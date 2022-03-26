import Foundation
import XCTest
import PackStream

import Bolt
//import LoremSwiftum

@testable import Theo

class TheoTestCase: XCTestCase {
    
    enum ClientConfigMode {
        case any
        case `default`
        case json
        case custom
    }
    
    func makeAndConnectClient(mode: ClientConfigMode = .any, completion: @escaping ((Result<Bool, Error>, ClientProtocol) -> ())) throws {
        let client = try _makeClient(mode: mode)
        client.connect { result in
            completion(result, client)
        }
    }
    
    enum ConnectionErrors: Error {
        case couldNotConnect
    }
    
    func makeClient(mode: ClientConfigMode = .any) throws -> ClientProtocol {
        let client = try _makeClient()
        let result = client.connectSync()
        if try result.get() == false {
            throw ConnectionErrors.couldNotConnect
        }
        return client
    }
    
    private func _makeClient(mode: ClientConfigMode = .any) throws -> ClientProtocol {
        let client: BoltClient
        let configuration = Theo_000_BoltClientTests.configuration
        
        if mode == .default || (mode == .any && Theo_000_BoltClientTests.runCount % 3 == 0) {
            client = try BoltClient(hostname: configuration.hostname,
                                    port: configuration.port,
                                    username: configuration.username,
                                    password: configuration.password,
                                    encryption: configuration.encryption)
        } else if mode == .custom || (mode == .any && Theo_000_BoltClientTests.runCount % 3 == 1) {
            class CustomConfig: ClientConfigurationProtocol {
                let hostname: String
                let username: String
                let password: String
                let port: Int
                let encryption: Encryption
                
                init(configuration: ClientConfigurationProtocol) {
                    hostname = configuration.hostname
                    password = configuration.password
                    username = configuration.username
                    port = configuration.port
                    encryption = configuration.encryption
                }
            }
            client = try BoltClient(CustomConfig(configuration: configuration))
        } else { // .json || .any && %3 == 2
            let testPath = URL(fileURLWithPath: #file)
                .deletingLastPathComponent().path
            let filePath = "\(testPath)/TheoBoltConfig.json"
            let data = try Data(contentsOf: URL.init(fileURLWithPath: filePath))
            
            let json = try JSONSerialization.jsonObject(with: data) as! [String:Any]
            let jsonConfig = JSONClientConfiguration(json: json)
            client = try BoltClient(jsonConfig)
        }
        
        return client
    }
    
    func performConnectSync(client: BoltClient, completionBlock: ((Bool) -> ())? = nil) {
        
        let result = client.connectSync()
        switch result {
        case let .failure(error):
            XCTFail("Failed connecting with error: \(error)")
            completionBlock?(false)
        case let .success(isSuccess):
            XCTAssertTrue(isSuccess)
            completionBlock?(true)
        }
    }
    
    func performConnect(client: BoltClient, completionBlock: ((Bool) -> ())? = nil) {
        client.connect() { connectionResult in
            switch connectionResult {
            case let .failure(error):
                XCTFail("Failed connecting with error: \(error)")
                completionBlock?(false)
            case let .success(isConnected):
                if !isConnected {
                    print("Error, could not connect!")
                }
                completionBlock?(isConnected)
            }
        }
    }
}

class Theo_001_LotsOfDataScenario: TheoTestCase {
    
    let label = Lorem.word
    
    override func setUp() {
        super.setUp()
        self.continueAfterFailure = false
    }
    
    
    func testScenario() throws {
        let client = try makeClient()
        
        print("Test with '\(label)'")
        
        measure {
            do {
                try self.buildData(client: client)
                try? client.resetSync()
                try self.findData(client: client)
                try? client.resetSync()
            } catch {
                XCTFail("Hmm....")
            }
        }
    }
    
    

    let data = Lorem.sentences(30).split(separator: ".")
    private var pos = 0
    private var sentence: String {
        pos = pos + 1
        return String(data[pos % data.count])
    }
    
    private var word: String {
        pos = pos + 1
        let words = self.sentence.split(separator: " ")
        return String(words[pos % words.count])
    }
    
    func buildData(client: ClientProtocol) throws {
        
        print("...-> buildData")
        var nodes = [Node]()
        
        let cypherCreateResult = client.executeCypherSync("CREATE (n:\(label) {created_at: TIMESTAMP()}) RETURN n", params: [:])
        XCTAssertTrue(cypherCreateResult.isSuccess)
        guard case let Result.success(cypherCreateResultValue) = cypherCreateResult else {
            XCTFail()
            return
        }

        XCTAssertEqual(1, cypherCreateResultValue.nodes.count)
        let nodeWithTimestamp = cypherCreateResultValue.nodes.values.first!
        let timestamp: TimeInterval = Double(nodeWithTimestamp["created_at"] as? Int64 ?? 0) / 1000.0
        let diff = Date().timeIntervalSince1970 - timestamp
        XCTAssertLessThan(diff, 60.0)
        
        let emptyParameterResult = client.executeCypherSync("CREATE (n:\(label) {param: \"\"}) RETURN n", params: [:])
        XCTAssertTrue(cypherCreateResult.isSuccess)
        guard case let Result.success(emptyParameterResultValue) = emptyParameterResult else {
            XCTFail()
            return
        }

        XCTAssertTrue(emptyParameterResult.isSuccess)
        XCTAssertEqual(1, emptyParameterResultValue.nodes.count)
        let nodeWithEmptyParameter = emptyParameterResultValue.nodes.values.first!
        let param = nodeWithEmptyParameter["param"] as? String
        XCTAssertEqual(param, "")

        for _ in 0..<100 {
            let node = Node()
            node.add(label: label)
            for _ in 0..<15 {
                let key = self.word
                let value = self.sentence
                node[key] = value
            }
            nodes.append(node)
        }
        let result = client.createNodesSync(nodes: nodes)
        XCTAssertTrue(result.isSuccess)
    }
    
    func findData(client: ClientProtocol) throws {
        let result = client.nodesWithSync(label: label, andProperties: [:], skip: 0, limit: 0)
        switch result {
        case .failure(let error):
            XCTFail("Failure during query: \(error.localizedDescription)")
        case .success(let nodes):
            XCTAssertEqual(nodes.count, 102)
            let deleteResult = client.deleteNodesSync(nodes: nodes)
            XCTAssertTrue(deleteResult.isSuccess)
        }
        
    }
}
