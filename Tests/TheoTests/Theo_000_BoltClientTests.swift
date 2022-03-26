import Foundation
import XCTest
import PackStream
import NIO

@testable import Theo

#if os(Linux)
    import Dispatch
#endif

let TheoTimeoutInterval: TimeInterval = 10

class ConfigLoader: NSObject {

    class func loadBoltConfig() -> BoltConfig {

        let testPath = URL(fileURLWithPath: #file)
            .deletingLastPathComponent().path

        let filePath = "\(testPath)/TheoBoltConfig.json"

        return BoltConfig(pathToFile: filePath)
    }

}

class Theo_000_BoltClientTests: TheoTestCase {
    
    static let configuration: ClientConfigurationProtocol = ConfigLoader.loadBoltConfig()
    static var runCount: Int = 0

    var eventLoopGroup: MultiThreadedEventLoopGroup! = nil

    override func setUp() {
        super.setUp()
        eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        continueAfterFailure = false
        Theo_000_BoltClientTests.runCount = Theo_000_BoltClientTests.runCount + 1
    }

    /*
    private func performConnectSync(client: BoltClient, completionBlock: ((Bool) -> ())? = nil) {

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


    private func performConnect(client: BoltClient, completionBlock: ((Bool) -> ())? = nil) {
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

    internal func makeClient() throws -> ClientProtocol {
        let client: BoltClient
        let configuration = Theo_000_BoltClientTests.configuration
        
        if Theo_000_BoltClientTests.runCount % 3 == 0 {
            client = try BoltClient(hostname: configuration.hostname,
                                    port: configuration.port,
                                    username: configuration.username,
                                    password: configuration.password,
                                    encrypted: configuration.encrypted)
        } else if Theo_000_BoltClientTests.runCount % 3 == 1 {
            class CustomConfig: ClientConfigurationProtocol {
                let hostname: String
                let username: String
                let password: String
                let port: Int
                let encrypted: Bool
                
                init(configuration: ClientConfigurationProtocol) {
                    hostname = configuration.hostname
                    password = configuration.password
                    username = configuration.username
                    port = configuration.port
                    encrypted = configuration.encrypted
                }
            }
            client = try BoltClient(CustomConfig(configuration: configuration))
        } else {
            let testPath = URL(fileURLWithPath: #file)
                .deletingLastPathComponent().path
            let filePath = "\(testPath)/TheoBoltConfig.json"
            let data = try Data(contentsOf: URL.init(fileURLWithPath: filePath))

            let json = try JSONSerialization.jsonObject(with: data) as! [String:Any]
            let jsonConfig = JSONClientConfiguration(json: json)
            client = try BoltClient(jsonConfig)
        }


        if Theo_000_BoltClientTests.runCount % 2 == 0 {
            let group = DispatchGroup()
            group.enter()
            performConnect(client: client) { connectionSuccessful in
                XCTAssertTrue(connectionSuccessful)
                group.leave()
            }
            group.wait()
        } else {
            performConnectSync(client: client) { connectionSuccessful in
                XCTAssertTrue(connectionSuccessful)
            }
        }

        return client
    }*/
    
    func testMeasureUnwinds() {
        measure {
            try? testUnwinds()
        }
    }
    
    func testUnwinds() throws {
        
        let exp = expectation(description: "testUnwinds")
        
        try makeAndConnectClient() { (result, client) in
            XCTAssert(result.isSuccess)
            
            let n = 10
            let max = 2250
            for i in (max-n)...max {
                let cypher: String = "UNWIND range(1, \(i)) AS n RETURN n"
                let result = client.executeCypherSync(cypher, params: [:])
                    
                XCTAssert(result.isSuccess)
                guard case let Result.success(value) = result else {
                    XCTFail()
                    return
                }
                XCTAssertEqual(i, value.rows.count)
                
                if i == max {
                    exp.fulfill()
                }
            }
        }
        
        
        waitForExpectations(timeout: 1000.0) { _ in
            print("Test complete")
        }
    }
    
    func testUnwind() throws {
        let exp = expectation(description: "testUnwind")
        
        try makeAndConnectClient() { (connectionResult, client) in
            XCTAssert(connectionResult.isSuccess)
            let i = 1000
            let result = client.executeCypherSync("UNWIND range(1, \(i)) AS n RETURN n", params: [:])
            XCTAssert(result.isSuccess)
            guard case let Result.success(value) = result
            else {
                XCTFail()
                return
            }

            XCTAssertEqual(1, value.fields.count)
            XCTAssertEqual(i, value.rows.count)
            exp.fulfill()
        }
        
        
        waitForExpectations(timeout: 10.0) { _ in
            print("Test complete")
        }
        
    }

    func testNodeResult() throws {
        let exp = self.expectation(description: "testNodeResult")
        try makeAndConnectClient() { (result, client) in
            
            XCTAssertTrue(client.executeCypherSync("CREATE (n:TheoTestNodeWithALongLabel { foo: \"bar\", baz: 3}) RETURN n", params: [:]).isSuccess)
            exp.fulfill()
        }
        
        self.waitForExpectations(timeout: 10, handler: { error in
            XCTAssertNil(error)
        })
    }

    func testRelationshipResult() throws {
        let client = try makeClient()
        let exp = self.expectation(description: "testNodeResult")

        let query = """
                    CREATE (b:Candidate {name:'Bala'})
                    CREATE (e:Employer {name:'Yahoo'})
                    CREATE (b)-[r:WORKED_IN]->(e)
                    RETURN b,r,e
                    """

        XCTAssertTrue(client.executeCypherSync(query, params: [:]).isSuccess)
        exp.fulfill()

        self.waitForExpectations(timeout: 10, handler: { error in
            XCTAssertNil(error)
        })
    }

    func testIntroToCypher() throws {

        let client = try makeClient()
        let exp = self.expectation(description: "testNodeResult")
        var queries = [String]()

        queries.append(
                   """
                     MATCH (n)
                     DETACH DELETE n
                   """)

        queries.append(
                   """
                      CREATE (you:Person {name:"You"})
                      RETURN you
                   """)

        queries.append(
                   """
                      MATCH  (you:Person {name:"You"})
                      CREATE (you)-[like:LIKE]->(neo:Database {name:"Neo4j" })
                      RETURN you,like,neo
                   """)

        queries.append(
                   """
                      MATCH (you:Person {name:"You"})
                      FOREACH (name in ["Johan","Rajesh","Anna","Julia","Andrew"] |
                      CREATE (you)-[:FRIEND]->(:Person {name:name}))
                   """)

        queries.append(
                   """
                      MATCH (you {name:"You"})-[:FRIEND]->(yourFriends)
                      RETURN you, yourFriends
                   """)

        queries.append(
                   """
                      MATCH (neo:Database {name:"Neo4j"})
                      MATCH (anna:Person {name:"Anna"})
                      CREATE (anna)-[:FRIEND]->(:Person:Expert {name:"Amanda"})-[:WORKED_WITH]->(neo)
                   """)

        queries.append(
                   """
                      MATCH (you {name:"You"})
                      MATCH (expert)-[w:WORKED_WITH]->(db:Database {name:"Neo4j"})
                      MATCH path = shortestPath( (you)-[:FRIEND*..5]-(expert) )
                      RETURN DISTINCT db,w,expert,path
                   """)

        for query in queries {
            XCTAssertTrue(client.executeCypherSync(query, params: [:]).isSuccess)

        }
        exp.fulfill()

        self.waitForExpectations(timeout: 10, handler: { error in
            XCTAssertNil(error)
        })
    }

    func testSetOfQueries() throws {

        let client = try makeClient()
        let exp = self.expectation(description: "testSetOfQueries")
        var queries = [String]()

        queries.append(
            """
              CREATE (you:Person {name:"You", weight: 80})
              RETURN you.name, sum(you.weight) as singleSum
            """)

        queries.append(
            """
              MATCH (you:Person {name:"You"})
              RETURN you.name, sum(you.weight) as allSum, you
            """)


        for query in queries {
            XCTAssertTrue(client.executeCypherSync(query, params: [:]).isSuccess)

        }
        exp.fulfill()

        self.waitForExpectations(timeout: 10, handler: { error in
            XCTAssertNil(error)
        })
    }


    func testSucceedingTransactionSync() throws {
        let client = try makeClient()
        let exp = self.expectation(description: "testSucceedingTransaction")

        do {
            try client.executeAsTransaction(mode: .readwrite, bookmark: nil, transactionBlock: { (tx) in
                XCTAssertTrue(client.executeCypherSync("CREATE (n:TheoTestNode { foo: \"bar\"})", params: [:]).isSuccess)
                XCTAssertTrue(client.executeCypherSync("MATCH (n:TheoTestNode { foo: \"bar\"}) RETURN n", params: [:]).isSuccess)
                XCTAssertTrue(client.executeCypherSync("MATCH (n:TheoTestNode { foo: \"bar\"}) DETACH DELETE n", params: [:]).isSuccess)
                exp.fulfill()
            }, transactionCompleteBlock: nil)
        } catch let error {
            print("Failed transaction with error \(error)")
            XCTFail()
        }

        self.waitForExpectations(timeout: 10, handler: { error in
            XCTAssertNil(error)
        })
    }

    func testMeasureFailingTransactionSync() throws {
        let client = try makeClient()
        
        measure {
            do {
                let exp = self.expectation(description: "testFailingTransaction")
                
                try client.executeAsTransaction(mode: .readwrite, bookmark: nil, transactionBlock: { (tx) in
                    XCTAssertTrue(client.executeCypherSync("CREATE (n:TheoTestNode { foo: \"bar\"})", params: [:]).isSuccess)
                    XCTAssertTrue(client.executeCypherSync("MATCH (n:TheoTestNode { foo: \"bar\"}) RETURN n", params: [:]).isSuccess)
                    XCTAssertFalse(client.executeCypherSync("MAXXXTCH (n:TheoTestNode { foo: \"bar\"}) DETACH DELETE n", params: [:]).isSuccess)
                    tx.markAsFailed()
                    
                    XCTAssertFalse(tx.succeed)
                    
                    client.connect { _ in // TODO: Ask Nigel what to do instead of reconnect. RESET?
                        exp.fulfill()
                    }
                }, transactionCompleteBlock: nil)
                
                self.waitForExpectations(timeout: 1000 /* TheoTimeoutInterval*/, handler: { error in
                    XCTAssertNil(error)
                })
                
            } catch {
                XCTFail()
            }
        }
    }
    
    func testFailingTransactionSync() throws {
        let client = try makeClient()
        let exp = self.expectation(description: "testFailingTransaction")

        try client.executeAsTransaction(mode: .readwrite, bookmark: nil, transactionBlock: { (tx) in
            XCTAssertTrue(client.executeCypherSync("CREATE (n:TheoTestNode { foo: \"bar\"})", params: [:]).isSuccess)
            XCTAssertTrue(client.executeCypherSync("MATCH (n:TheoTestNode { foo: \"bar\"}) RETURN n", params: [:]).isSuccess)
            XCTAssertFalse(client.executeCypherSync("MAXXXTCH (n:TheoTestNode { foo: \"bar\"}) DETACH DELETE n", params: [:]).isSuccess)
            tx.markAsFailed()

            XCTAssertFalse(tx.succeed)
            
            exp.fulfill()
        }, transactionCompleteBlock: nil)

        self.waitForExpectations(timeout: TheoTimeoutInterval, handler: { error in
            XCTAssertNil(error)
        })
        
        _ = client.connectSync() // TODO: Having to reconnect after a failed transaction isn't good. How can we improve on this?
    }

    func testCancellingTransaction() throws {
        let client = try self.makeClient()
        let exp = self.expectation(description: "testCancellingTransaction")
        
        try client.executeAsTransaction(mode: .readwrite, bookmark: nil, transactionBlock: { (tx) in
            tx.markAsFailed()
            exp.fulfill()
        }, transactionCompleteBlock: nil)
        
        self.waitForExpectations(timeout: TheoTimeoutInterval, handler: { error in
            XCTAssertNil(error)
        })
    }

    func testTransactionResultsInBookmark() throws {
        let client = try makeClient()
        let exp = self.expectation(description: "testTransactionResultsInBookmark")
        
        let group = DispatchGroup()
        group.enter()

        DispatchQueue.global(qos: .background).async {
            do {
                
                try client.executeAsTransaction(mode: .readwrite, bookmark: nil, transactionBlock: { (tx) in
                    let result = client.executeCypherSync("CREATE (n:TheoTestNode { foo: \"bar\"})", params: [:])
                    //                    client.executeCypher("CREATE (n:TheoTestNode { foo: \"bar\"})", params: [:]) { result in
                    
                    switch result {
                    case let .failure(error):
                        print("Error in cypher: \(error)")
                    // case let .success((success, partialQueryResult)):
                    case let .success(queryResult):
                        //client.pullAll(partialQueryResult: partialQueryResult) { result in
                        XCTAssertEqual(1, queryResult.stats.propertiesSetCount)
                        XCTAssertEqual(1, queryResult.stats.labelsAddedCount)
                        XCTAssertEqual(1, queryResult.stats.nodesCreatedCount)
                        XCTAssertEqual("w", queryResult.stats.type)
                        XCTAssertEqual(0, queryResult.fields.count)
                        XCTAssertEqual(0, queryResult.nodes.count)
                        XCTAssertEqual(0, queryResult.relationships.count)
                        XCTAssertEqual(0, queryResult.paths.count)
                        XCTAssertEqual(0, queryResult.rows.count)
                        
                    }
                    
                    XCTAssertTrue(result.isSuccess)
                    //}
                }, transactionCompleteBlock: { isSuccess in
                    XCTAssertTrue(isSuccess)
                    exp.fulfill()
                    group.leave()
                })
            } catch {
                XCTFail()
            }
        }

        group.wait()
        
        if let bookmark = client.getBookmark() {
            XCTAssertNotEqual("", bookmark)
            
            // TODO: Look into bookmark name changes
            // see: https://community.neo4j.com/t/supplied-bookmark-fb-kcwqcw6pr0ihr5szcd5sxayzawgq-does-not-conform-to-pattern-neo4jv1-tx/39540
            // let endIndex = bookmark.index(bookmark.startIndex, offsetBy: 17)
            // let substring = bookmark[..<endIndex]
            // XCTAssertEqual("neo4j:bookmark:v1", String(substring))
            
        } else {
            XCTFail("Bookmark should not be nil")
        }
        
        self.waitForExpectations(timeout: 10, handler: { error in
            XCTAssertNil(error)
        })
    }
    
    func testDeprecatedParameterSyntax() throws {

        let client = try makeClient()
        let exp = self.expectation(description: "testDeprecatedParameterSyntax")

        let result = client.executeCypherSync("MATCH (a:Person) WHERE a.name = {name} RETURN count(a) AS count", params: ["name": "Arthur"])
        XCTAssertFalse(result.isSuccess)
        exp.fulfill()

        self.waitForExpectations(timeout: 10, handler: { error in
            XCTAssertNil(error)
        })

    }
    
    func testGettingStartedExample() throws {
        
        let client = try makeClient()
        let exp = self.expectation(description: "testGettingStartedExample")

        // First, lets determine the number of existing King Arthurs. The test may have been run before

        let figureOutNumberOfKingArthurs = DispatchGroup()
        figureOutNumberOfKingArthurs.enter()
        var numberOfKingArthurs = -1

        DispatchQueue.global(qos: .background).async {
            let result = client.executeCypherSync("MATCH (a:Person) WHERE a.name = $name RETURN count(a) AS count", params: ["name": "Arthur"])
                
            XCTAssertTrue(result.isSuccess)
            guard case Result.success(_) = result else {
                XCTFail()
                figureOutNumberOfKingArthurs.leave()
                return
            }
            
            // ? XCTAssertTrue(value.0)
            
            switch result {
            case .failure:
                XCTFail("Failed to pull response data")
            case let .success(queryResult):
                XCTAssertEqual(1, queryResult.rows.count)
                XCTAssertEqual(1, queryResult.rows.first?.count ?? 0)
                XCTAssertEqual(0, queryResult.nodes.count)
                XCTAssertEqual(0, queryResult.relationships.count)
                XCTAssertEqual(0, queryResult.paths.count)
                XCTAssertEqual(1, queryResult.fields.count)
                
                if let numberOfKingArthursRI = queryResult.rows.first?["count"],
                    let numberOfKingArthurS64 = numberOfKingArthursRI as? UInt64 {
                    numberOfKingArthurs = Int(truncatingIfNeeded: numberOfKingArthurS64)
                } else {
                    XCTFail("Could not get count and make it an Int")
                }
                
                XCTAssertGreaterThanOrEqual(0, numberOfKingArthurs)
                
                figureOutNumberOfKingArthurs.leave()
            }
        }
        figureOutNumberOfKingArthurs.wait()
        XCTAssertNotEqual(-1, numberOfKingArthurs)

        // Now lets run the actual test

        try client.executeAsTransaction(mode: .readwrite, bookmark: nil, transactionBlock: { (tx) in
            tx.autocommit = false
            
            let result = client.executeCypherSync("CREATE (a:Person {name: $name, title: $title})",
                                                   params: ["name": "Arthur", "title": "King"])
            XCTAssertTrue(result.isSuccess)
            guard case let Result.success(value) = result else {
                XCTFail()
                return
            }
            let queryResult = value
            XCTAssertEqual(2, queryResult.stats.propertiesSetCount)
            XCTAssertEqual(1, queryResult.stats.labelsAddedCount)
            XCTAssertEqual(1, queryResult.stats.nodesCreatedCount)
            XCTAssertEqual("w", queryResult.stats.type)
            XCTAssertEqual(0, queryResult.fields.count)
            XCTAssertEqual(0, queryResult.nodes.count)
            XCTAssertEqual(0, queryResult.relationships.count)
            XCTAssertEqual(0, queryResult.paths.count)
            XCTAssertEqual(0, queryResult.rows.count)


            let result2 = client.executeCypherSync("MATCH (a:Person) WHERE a.name = $name " +
                                 "RETURN a.name AS name, a.title AS title",
                         params: ["name": "Arthur"])

            XCTAssertTrue(result2.isSuccess)
            guard case let Result.success(value) = result2 else {
                XCTFail()
                return
            }
            // XCTAssertTrue(value.0)
            let queryResult2 = value // .1

            XCTAssertEqual(2, queryResult2.fields.count)
            XCTAssertEqual(0, queryResult2.nodes.count)
            XCTAssertEqual(0, queryResult2.relationships.count)
            XCTAssertEqual(0, queryResult2.paths.count)
            XCTAssertEqual(1, queryResult2.rows.count)
            XCTAssertEqual("r", queryResult2.stats.type)

            let row = queryResult2.rows.first!
            XCTAssertEqual(2, row.count)
            XCTAssertEqual("King", row["title"] as! String)
            XCTAssertEqual("Arthur", row["name"] as! String)

            XCTAssertEqual(numberOfKingArthurs + 2, queryResult2.rows.first?.count ?? 0)

            tx.markAsFailed() // This should undo the beginning CREATE even though we have pulled it here
            try? tx.commitBlock(false)
            
        }, transactionCompleteBlock: { isSuccess in
            XCTAssertFalse(isSuccess, "Transaction was rolled back")
            exp.fulfill()
        })

        self.waitForExpectations(timeout: 10, handler: { error in
            XCTAssertNil(error)
        })
    }

    func testCreateAndRunCypherFromNode() throws {

        let node = Node(labels: ["Person","Husband","Father"], properties: [
            "firstName": "Niklas",
            "age": 40,
            "weight": 80.2,
            "favouriteWhiskys": List(items: ["Ardbeg", "Caol Ila", "Laphroaig"])
            ])

        let client = try makeClient()
        let result = client.createAndReturnNodeSync(node: node)
        switch result {
        case let .failure(error):
            XCTFail(error.localizedDescription)
        case let .success(resultNode):
            XCTAssertEqual(3, resultNode.labels.count)
            XCTAssertEqual(4, resultNode.properties.count)
            XCTAssertEqual("Niklas", resultNode.properties["firstName"] as! String)
            XCTAssertEqual(40 as Int64, resultNode.properties["age"]?.intValue())
        }
    }

    func makeSomeNodes() -> [Node] {
        let node1 = Node(labels: ["Person","Husband","Father"], properties: [
            "firstName": "Niklas",
            "age": 40,
            "weight": 80.2,
            "favouriteWhiskys": List(items: ["Ardbeg", "Caol Ila", "Laphroaig"])
            ])

        let node2 = Node(labels: ["Person","Wife","Mother"], properties: [
            "firstName": "Christina",
            "age": 37,
            "favouriteAnimals": List(items: ["Silver", "Oscar", "Simba"])
            ])

        return [node1, node2]
    }

    func testCreateAndRunCypherFromNodesWithResult() throws {

        let nodes = makeSomeNodes()

        let client = try makeClient()
        let result = client.createAndReturnNodesSync(nodes: nodes)
        switch result {
        case let .failure(error):
            XCTFail(error.localizedDescription)
        case let .success(resultNodes):
            XCTAssert(resultNodes.count > 0)
            let candidates = resultNodes.filter { $0.properties["firstName"] as! String == "Niklas" }
            var resultNode = candidates.first!
            XCTAssertEqual(3, resultNode.labels.count)
            XCTAssertTrue(resultNode.labels.contains("Father"))
            XCTAssertEqual(4, resultNode.properties.count)
            XCTAssertEqual("Niklas", resultNode.properties["firstName"] as! String)
            XCTAssertEqual(40 as Int64, resultNode.properties["age"]?.intValue())

            resultNode = resultNodes.filter { $0.properties["firstName"] as! String == "Christina" }.first!
            XCTAssertEqual(3, resultNode.labels.count)
            XCTAssertTrue(resultNode.labels.contains("Mother"))
            XCTAssertEqual(3, resultNode.properties.count)
            XCTAssertEqual("Christina", resultNode.properties["firstName"] as! String)
            XCTAssertEqual(37 as Int64, resultNode.properties["age"]?.intValue())
        }
    }

    func testUpdateAndRunCypherFromNodesWithResult() throws {
        
        let nodes = makeSomeNodes()

        let client = try makeClient()
        var result = client.createAndReturnNodesSync(nodes: nodes)
        switch result {
        case let .failure(error):
            XCTFail(error.localizedDescription)
        case var .success(resultNodes):
            let resultNode = resultNodes.filter { $0.properties["firstName"] as! String == "Niklas" }.first!
            let resultNode2 = resultNodes.filter { $0.properties["firstName"] as! String == "Christina" }.first!

            resultNode["instrument"] = "Recorder"
            resultNode["favouriteComposer"] = "CPE Bach"
            resultNode["weight"] = nil
            resultNode.add(label: "LabelledOne")

            resultNode2["instrument"] = "Piano"
            resultNode2.add(label: "LabelledOne")
            result = client.updateAndReturnNodesSync(nodes: [resultNode, resultNode2])
            guard case let Result.success(value) = result else {
                XCTFail()
                return
            }
            XCTAssertNotNil(value)
            resultNodes = value

            let resultNode3 = resultNodes.filter { $0.properties["firstName"] as! String == "Niklas" }.first!
            XCTAssertEqual(4, resultNode3.labels.count)
            XCTAssertTrue(resultNode3.labels.contains("Father"))
            XCTAssertTrue(resultNode3.labels.contains("LabelledOne"))
            XCTAssertEqual(5, resultNode3.properties.count)
            XCTAssertNil(resultNode3["weight"])
            XCTAssertEqual("Niklas", resultNode3.properties["firstName"] as! String)
            XCTAssertEqual(40 as Int64, resultNode3.properties["age"]?.intValue())

            let resultNode4 = resultNodes.filter { $0.properties["firstName"] as! String == "Christina" }.first!
            XCTAssertEqual(4, resultNode4.labels.count)
            XCTAssertTrue(resultNode4.labels.contains("Mother"))
            XCTAssertTrue(resultNode4.labels.contains("LabelledOne"))
            XCTAssertEqual(4, resultNode4.properties.count)
            XCTAssertEqual("Christina", resultNode4.properties["firstName"] as! String)
            XCTAssertEqual(37 as Int64, resultNode4.properties["age"]?.intValue())

        }
    }
    
    func testMeasureUpdateAsyncAndRunCypherFromNodesWithoutResult() {
        measure {
            try? testUpdateAsyncAndRunCypherFromNodesWithoutResult()
        }
    }
    
    func testUpdateAsyncAndRunCypherFromNodesWithoutResult() throws {

        let exp = expectation(description: "testUpdateAsyncAndRunCypherFromNodesWithoutResult")
        let nodes = makeSomeNodes()

        let client = try makeClient()
        let nodesCreatedResult = client.createAndReturnNodesSync(nodes: nodes)
        switch nodesCreatedResult {
        case let .failure(error):
            XCTFail(error.localizedDescription)
        case let .success(resultNodes):
            let resultNode = resultNodes.filter { $0.properties["firstName"] as! String == "Niklas" }.first!
            let resultNode2 = resultNodes.filter { $0.properties["firstName"] as! String == "Christina" }.first!

            resultNode["instrument"] = "Recorder"
            resultNode["favouriteComposer"] = "CPE Bach"
            resultNode["weight"] = nil
            resultNode.add(label: "LabelledOne")

            resultNode2["instrument"] = "Piano"
            resultNode2.add(label: "LabelledOne")
            let updateNodesResult = client.updateAndReturnNodesSync(nodes: [resultNode, resultNode2])
            guard case let Result.success(nodes) = updateNodesResult else {
                XCTFail()
                return
            }

            XCTAssertEqual(2, nodes.count)

            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10.0) { error in
            print("failed...")
        }
    }

    func testUpdateAndRunCypherFromNodesWithoutResult() throws {

        
        let nodes = makeSomeNodes()

        let client = try makeClient()
        let result = client.createAndReturnNodesSync(nodes: nodes)
        switch result {
        case let .failure(error):
            XCTFail(error.localizedDescription)
        case let .success(resultNodes):
            let resultNode = resultNodes.filter { $0.properties["firstName"] as! String == "Niklas" }.first!
            let resultNode2 = resultNodes.filter { $0.properties["firstName"] as! String == "Christina" }.first!

            resultNode["instrument"] = "Recorder"
            resultNode["favouriteComposer"] = "CPE Bach"
            resultNode["weight"] = nil
            resultNode.add(label: "LabelledOne")

            resultNode2["instrument"] = "Piano"
            resultNode2.add(label: "LabelledOne")
            let result = client.updateNodesSync(nodes: [resultNode, resultNode2])
            guard case let Result.success(value) = result else {
                XCTFail()
                return
            }
            XCTAssertNotNil(value)
            XCTAssertTrue(value)
        }
    }
    
    func testUpdateNode() throws {
        let client = try makeClient()

        var apple = Node(labels: ["Fruit"], properties: [:])
        apple["pits"] = 4
        apple["color"] = "green"
        apple["variety"] = "McIntosh"
        let createResult = client.createAndReturnNodeSync(node: apple)
        XCTAssertTrue(createResult.isSuccess)

        guard case let Result.success(newApple) = createResult else {
            XCTFail()
            return
        }
        apple = newApple
        
        apple.add(label: "Apple")
        apple["juicy"] = true
        apple["findMe"] = 42
        let updateResult = client.updateNodeSync(node: apple)
        XCTAssertTrue(updateResult.isSuccess)
        
        let prevId = apple.id!
        let exp = expectation(description: "Should get expected update back")
        let result = client.nodeBySync(id: prevId)
        XCTAssertTrue(result.isSuccess)
        guard case let Result.success(foundApple) = result else {
            XCTFail()
            return
        }
        let apple2 = foundApple
        
        XCTAssertNotNil(apple2.id)
        XCTAssertEqual(prevId, apple2.id!)
        XCTAssertEqual(42, apple2["findMe"]?.intValue() ?? -1)
        XCTAssertTrue(apple2["juicy"] as? Bool ?? false)
        XCTAssertTrue(apple2.labels.contains("Apple"))
        exp.fulfill()
        
        waitForExpectations(timeout: 5.0) { error in
            XCTAssertNil(error)
        }
        
    }
    
    func testUpdateAndReturnNode() throws {
        let client = try makeClient()
        
        var apple = Node(labels: ["Fruit"], properties: [:])
        apple["pits"] = 4
        apple["color"] = "green"
        apple["variety"] = "McIntosh"
        let createResult = client.createAndReturnNodeSync(node: apple)
        XCTAssertTrue(createResult.isSuccess)
        
        guard case let Result.success(newApple) = createResult else {
            XCTFail()
            return
        }
        apple = newApple

        apple.add(label: "Apple")
        apple["juicy"] = true
        apple["findMe"] = 42
        
         let updateResult = client.updateAndReturnNodeSync(node: apple)
         XCTAssertNotNil(apple.id)
         XCTAssertTrue(updateResult.isSuccess)
        guard case let Result.success(updatedApple) = createResult else {
            XCTFail()
            return
        }

         XCTAssertNotNil(updatedApple)
         apple = updatedApple
         XCTAssertEqual(42, apple["findMe"] as? Int ?? -1)
         XCTAssertTrue(apple["juicy"] as? Bool ?? false)
         XCTAssertTrue(apple.labels.contains("Apple"))
    }
    
    func testCypherMatching() throws {
        let client = try makeClient()
        let cypher =
          """
          MATCH (n)-->(m)
          RETURN n, count(1)
          """
        let cypherResult = client.executeCypherSync(cypher, params: [:])
        XCTAssertTrue(cypherResult.isSuccess)

    }

    func testCreateAndRunCypherFromNodesNoResult() throws {

        let nodes = makeSomeNodes()

        let client = try makeClient()
        let result = client.createNodesSync(nodes: nodes)
        switch result {
        case let .failure(error):
            XCTFail(error.localizedDescription)
        case let .success(isSuccess):
            XCTAssertTrue(isSuccess)
        }

    }
    
    func testCreatePropertylessNodeAsync() throws {
        
        let node = Node(label: "Juice", properties: [:])
        let exp = expectation(description: "testCreatePropertylessNodeAsync")
        
        let client = try makeClient()
        let result = client.createNodeSync(node: node)
        switch result {
        case let .failure(error):
            XCTFail(error.localizedDescription)
        case let .success(isSuccess):
            XCTAssertTrue(isSuccess)
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 5.0) { error in
            XCTAssertNil(error)
        }
    }

    func testCreateAndRunCypherFromNodeNoResult() throws {

        let nodes = makeSomeNodes()

        let client = try makeClient()
        let result = client.createNodeSync(node: nodes.first!)
        switch result {
        case let .failure(error):
            XCTFail(error.localizedDescription)
        case let .success(isSuccess):
            XCTAssertTrue(isSuccess)
        }
    }
    
    func testUpdateNodesWithResult() throws {

        let node = makeSomeNodes().first!
        let client = try makeClient()
        var result = client.createAndReturnNodeSync(node: node)
        guard case let Result.success(createdNode) = result else {
            XCTFail()
            return
        }

        createdNode["favouriteColor"] = "Blue"
        createdNode["luckyNumber"] = 24
        createdNode.add(label: "RecorderPlayer")

        result = client.updateAndReturnNodeSync(node: createdNode)
        guard case let Result.success(updatedNode) = result else {
            XCTFail()
            return
        }

        XCTAssertEqual(4, updatedNode.labels.count)
        XCTAssertEqual(Int64(24), updatedNode["luckyNumber"]!.intValue()!)
    }

    func testUpdateNodesWithNoResult() throws {

        let node = makeSomeNodes().first!
        let client = try makeClient()
        let result = client.createAndReturnNodeSync(node: node)
        guard case let Result.success(createdNode) = result else {
            XCTFail()
            return
        }

        createdNode["favouriteColor"] = "Blue"
        createdNode["luckyNumber"] = 24
        createdNode.add(label: "RecorderPlayer")

        let emptyResult = client.updateNodeSync(node: createdNode)
        guard case let Result.success(isSuccess) = emptyResult else {
            XCTFail()
            return
        }
        XCTAssertTrue(isSuccess)
    }

    func testCreateRelationshipWithoutCreateNodes() throws {
        
        let client = try makeClient()
        let nodes = makeSomeNodes()
        guard case let Result.success(createdNodes) = client.createAndReturnNodesSync(nodes: nodes) else {
            XCTFail()
            return
        }

        var (from, to) = (createdNodes[0], createdNodes[1])
        var result = client.relateSync(node: from, to: to, type: "Married to", properties: [:])
        if !result.isSuccess {
            XCTFail("Creating relationship failed!")
        }
        
        result = client.relateSync(node: from, to: to, type: "Married to", properties: [ "happily": true ])
        guard case let Result.success(createdRelationship) = result else {
            XCTFail()
            return
        }
        
        XCTAssertTrue(createdRelationship["happily"] as! Bool)
        XCTAssertEqual(from.id!, createdRelationship.fromNodeId)
        XCTAssertEqual(to.id!, createdRelationship.toNodeId)
        
        from = createdRelationship.fromNode!
        to = createdRelationship.toNode!
        XCTAssertEqual(from.id!, createdRelationship.fromNodeId)
        XCTAssertEqual(to.id!, createdRelationship.toNodeId)
    }
    
    func testCreateRelationshipWithCreateNodes() throws {
        
        let client = try makeClient()
        let madeNodes = makeSomeNodes()
        var (from, to) = (madeNodes[0], madeNodes[1])
        let result = client.relateSync(node: from, to: to, type: "Married to", properties: [ "happily": true ])
        guard case let Result.success(createdRelationship) = result else {
            XCTFail()
            return
        }
        
        XCTAssertTrue(createdRelationship["happily"] as! Bool)
        
        from = createdRelationship.fromNode!
        to = createdRelationship.toNode!
        XCTAssertEqual(from.id!, createdRelationship.fromNodeId)
        XCTAssertEqual(to.id!, createdRelationship.toNodeId)
    }
    
    func testCreateRelationshipWithCreateFromNode() throws {
        
        let client = try makeClient()
        let madeNodes = makeSomeNodes()
        var (from_, to) = (madeNodes[0], madeNodes[1])
        guard case let Result.success(createdNode) = client.createAndReturnNodeSync(node: from_) else {
            XCTFail()
            return
        }
        
        var from = createdNode
        let result = client.relateSync(node: from, to: to, type: "Married to", properties: [ "happily": true ])
        guard case let Result.success(createdRelationship) = result else {
            XCTFail()
            return
        }
        
        XCTAssertTrue(createdRelationship["happily"] as! Bool)
        XCTAssertEqual(from.id!, createdRelationship.fromNodeId)
        
        from = createdRelationship.fromNode!
        to = createdRelationship.toNode!
        XCTAssertEqual(from.id!, createdRelationship.fromNodeId)
        XCTAssertEqual(to.id!, createdRelationship.toNodeId)
    }
    
    func testCreateAndReturnRelationshipsSync() throws {
        
        let client = try makeClient()
        let madeNodes = makeSomeNodes()
        let (from, to) = (madeNodes[0], madeNodes[1])
        let relationship1 = Relationship(fromNode: from, toNode: to, type: "Married to")
        let relationship2 = Relationship(fromNode: to, toNode: from, type: "Married to")
        let createdRelationships = client.createAndReturnRelationshipsSync(relationships: [relationship1, relationship2])
        XCTAssertTrue(createdRelationships.isSuccess)
        guard case let Result.success(value) = createdRelationships else {
            XCTFail()
            return
        }
        XCTAssertEqual(2, value.count)
    }
    
    func testCreateAndReturnRelationships() throws {
        
        let exp = expectation(description: "testCreateAndReturnRelationships")
        let client = try makeClient()
        let madeNodes = makeSomeNodes()
        let (from, to) = (madeNodes[0], madeNodes[1])
        let relationship1 = Relationship(fromNode: from, toNode: to, type: "Married to")
        let relationship2 = Relationship(fromNode: to, toNode: from, type: "Married to")
        let createdRelationships = client.createAndReturnRelationshipsSync(relationships: [relationship1, relationship2])
        XCTAssertTrue(createdRelationships.isSuccess)
        guard case let Result.success(value) = createdRelationships else {
            XCTFail()
            return
        }

        XCTAssertEqual(2, value.count)
        exp.fulfill()
        
        waitForExpectations(timeout: 5.0) { error in
            XCTAssertNil(error)
        }
    }
    
    func testCreateAndReturnRelationship() throws {
        
        let exp = expectation(description: "testCreateAndReturnRelationships")
        let client = try makeClient()
        let madeNodes = makeSomeNodes()
        let (from, to) = (madeNodes[0], madeNodes[1])
        let relationship = Relationship(fromNode: from, toNode: to, type: "Married to")
        let createdRelationships = client.createAndReturnRelationshipSync(relationship: relationship)
        XCTAssertTrue(createdRelationships.isSuccess)
        guard case let Result.success(value) = createdRelationships else {
            XCTFail()
            return
        }
        XCTAssertEqual("Married to", value.type)
        exp.fulfill()
        
        waitForExpectations(timeout: 5.0) { error in
            XCTAssertNil(error)
        }
    }
    
    func testCreateAndReturnRelationshipByCreatingFromAndToNode() throws {
        
        let exp = expectation(description: "testCreateAndReturnRelationships")
        let client = try makeClient()
        let madeNodes = makeSomeNodes()
        let (from_, to_) = (madeNodes[0], madeNodes[1])
        
        guard case let Result.success(from) = client.createAndReturnNodeSync(node: from_),
              case let Result.success(to) = client.createAndReturnNodeSync(node: to_)
        else {
            XCTFail("Failed while creating nodes")
            return
        }

        let relationship = Relationship(fromNode: from, toNode: to, type: "Married to")
        let createdRelationships = client.createAndReturnRelationshipSync(relationship: relationship)
            
        if case Result.failure(let error) = createdRelationships {
            XCTFail("Did not expect creation of relationship to fail. Got error \(error)")
        }
        
        XCTAssertTrue(createdRelationships.isSuccess)
        guard case let Result.success(value) = createdRelationships else {
            XCTFail()
            return
        }
        XCTAssertEqual("Married to", value.type)
        exp.fulfill()
        
        waitForExpectations(timeout: 5.0) { error in
            XCTAssertNil(error)
        }
    }
    
    func testCreateAndReturnRelationshipByCreatingOnlyFromNode() throws {
        
        let exp = expectation(description: "testCreateAndReturnRelationships")
        let client = try makeClient()
        let madeNodes = makeSomeNodes()
        let (from_, to) = (madeNodes[0], madeNodes[1])
        
        guard
            case let Result.success(from) = client.createAndReturnNodeSync(node: from_)
            else {
                XCTFail("Failed while creating nodes")
                return
        }
        
        let relationship = Relationship(fromNode: from, toNode: to, type: "Married to")
        let createdRelationships = client.createAndReturnRelationshipSync(relationship: relationship)
            
        if case Result.failure(let error) = createdRelationships {
            XCTFail("Did not expect creation of relationship to fail. Got error \(error)")
        }
        
        XCTAssertTrue(createdRelationships.isSuccess)
        guard case let Result.success(value) = createdRelationships else {
            XCTFail()
            return
        }
        XCTAssertEqual("Married to", value.type)
        exp.fulfill()
        
        waitForExpectations(timeout: 5.0) { error in
            XCTAssertNil(error)
        }
    }

    func testCreateAndReturnRelationshipByCreatingOnlyToNode() throws {
        
        let exp = expectation(description: "testCreateAndReturnRelationships")
        let client = try makeClient()
        let madeNodes = makeSomeNodes()
        let (from, to_) = (madeNodes[0], madeNodes[1])
        
        guard
            case let Result.success(to) = client.createAndReturnNodeSync(node: to_)
            else {
                XCTFail("Failed while creating nodes")
                return
        }
        
        let relationship = Relationship(fromNode: from, toNode: to, type: "Married to")
        let createdRelationships = client.createAndReturnRelationshipSync(relationship: relationship)
            
        if case Result.failure(let error) = createdRelationships {
            XCTFail("Did not expect creation of relationship to fail. Got error \(error)")
        }
        
        XCTAssertTrue(createdRelationships.isSuccess)
        guard case let Result.success(value) = createdRelationships else {
            XCTFail()
            return
        }
        XCTAssertEqual("Married to", value.type)
        exp.fulfill()
        
        waitForExpectations(timeout: 5.0) { error in
            XCTAssertNil(error)
        }
    }
    
    
    func testCreateRelationshipWithCreateToNode() throws {
        
        let client = try makeClient()
        let madeNodes = makeSomeNodes()
        var (from, to_) = (madeNodes[0], madeNodes[1])
        guard case let Result.success(createdNode) = client.createAndReturnNodeSync(node: to_) else {
            XCTFail()
            return
        }
        var to = createdNode
        let result = client.relateSync(node: from, to: to, type: "Married to", properties: [ "happily": true ])
        guard case let Result.success(createdRelationship) = result else {
            XCTFail()
            return
        }
        
        if case Result.failure(let resultError) = result {
            XCTFail("Did not expect error \(resultError)")
        }

        XCTAssertTrue(createdRelationship["happily"] as! Bool)
        XCTAssertEqual(to.id!, createdRelationship.toNodeId)
        
        from = createdRelationship.fromNode!
        to = createdRelationship.toNode!
        XCTAssertEqual(from.id!, createdRelationship.fromNodeId)
        XCTAssertEqual(to.id!, createdRelationship.toNodeId)
    }
    
    func testCreateRelationshipSync() throws {
        let client = try makeClient()
        let nodes = makeSomeNodes()

        let reader: Node! = nodes[0]
        let writer: Node! = nodes[1]
        var relationship = Relationship(fromNode: reader, toNode: writer, type: "follows")
        let result = client.createAndReturnRelationshipSync(relationship: relationship)
        XCTAssertTrue(result.isSuccess)
        guard case let Result.success(theRelationship) = result else {
            XCTFail()
            return
        }
        relationship = theRelationship
        XCTAssertEqual("follows", relationship.type)
        //XCTAssertEqual(reader.labels, relationship.fromNode?.labels ?? [])
        //XCTAssertEqual(writer.labels, relationship.toNode?.labels ?? [])
    }

    func testCreateRelationshipsWithExistingNodesUsingId() throws {
        
        let client = try makeClient()
        let nodes = makeSomeNodes()
        let result = client.createAndReturnNodesSync(nodes: nodes)
        XCTAssertTrue(result.isSuccess)
        guard case let Result.success(createdNodes) = result else {
            XCTFail()
            return
        }
        XCTAssertTrue(createdNodes.count == 2)
        let (from, to) = (createdNodes[0], createdNodes[1])
        
        guard let fromId = from.id,
            let toId = to.id
            else {
                XCTFail()
                return
        }
        
        let rel1 = Relationship(fromNodeId: fromId, toNodeId: toId, type: "Married to", direction: .to, properties: [ "happily": true ])
        let rel2 = Relationship(fromNodeId: fromId, toNodeId: toId, type: "Married to", direction: .from, properties: [ "happily": true ])
        
        let request = [rel1, rel2].createRequest(withReturnStatement: true)
        var queryResult: QueryResult! = nil
        let result2 = client.executeWithResultSync(request: request)
        switch result2 {
        case let .failure(error):
            XCTFail(error.localizedDescription)
            return
        case let .success(theQueryResult):
            queryResult = theQueryResult
        }
        
        XCTAssertEqual(1, queryResult!.rows.count)
        XCTAssertEqual(4, queryResult!.fields.count)
        XCTAssertEqual(2, queryResult!.nodes.count)
        XCTAssertEqual(2, queryResult!.relationships.count)
        XCTAssertEqual("rw", queryResult!.stats.type)
    }

    func testCreateRelationshipsWithExistingNodesUsingNode() throws {

        let client = try makeClient()
        let nodes = makeSomeNodes()
        guard case let Result.success(createdNodes) = client.createAndReturnNodesSync(nodes: nodes) else {
            XCTFail()
            return
        }
        XCTAssert(createdNodes.count == 2)
        let (from, to) = (createdNodes[0], createdNodes[1])

        let rel1 = Relationship(fromNode: from, toNode: to, type: "Married to", direction: .to, properties: [ "happily": true ])
        let rel2 = Relationship(fromNode: from, toNode: to, type: "Married to", direction: .from, properties: [ "happily": true ])

        let request = [rel1, rel2].createRequest(withReturnStatement: true)
        var queryResult: QueryResult! = nil
        let result = client.executeWithResultSync(request: request)
        switch result {
        case let .failure(error):
            XCTFail(error.localizedDescription)
            return
        case let .success(theQueryResult):
            queryResult = theQueryResult
        }

        XCTAssertEqual(1, queryResult!.rows.count)
        XCTAssertEqual(4, queryResult!.fields.count)
        XCTAssertEqual(2, queryResult!.nodes.count)
        XCTAssertEqual(2, queryResult!.relationships.count)
        XCTAssertEqual("rw", queryResult!.stats.type)
    }
    
    func testCreateRelationshipsWithoutExistingNodes() throws {
        
        let client = try makeClient()
        let nodes = makeSomeNodes()
        let (from, to) = (nodes[0], nodes[1])
        
        let rel1 = Relationship(fromNode: from, toNode: to, type: "Married to", direction: .to, properties: [ "happily": true ])
        let rel2 = Relationship(fromNode: from, toNode: to, type: "Married to", direction: .from, properties: [ "happily": true ])
        
        let request = [rel1, rel2].createRequest(withReturnStatement: true)
        var queryResult: QueryResult! = nil
        let result = client.executeWithResultSync(request: request)
        switch result {
        case let .failure(error):
            XCTFail(error.localizedDescription)
            return
        case let .success(theQueryResult):
            queryResult = theQueryResult
        }

        XCTAssertEqual(1, queryResult!.rows.count)
        XCTAssertEqual(4, queryResult!.fields.count)
        XCTAssertEqual(2, queryResult!.nodes.count)
        XCTAssertEqual(2, queryResult!.relationships.count)
        XCTAssertEqual("rw", queryResult!.stats.type)
    }
    
    func testCreateRelationshipsWithMixedNodes() throws {
        
        let client = try makeClient()
        let nodes = makeSomeNodes()
        let (from_, to) = (nodes[0], nodes[1])
        guard case let Result.success(from) = client.createAndReturnNodeSync(node: from_) else {
            XCTFail()
            return
        }
        
        let rel1 = Relationship(fromNode: from, toNode: to, type: "Married to", direction: .to, properties: [ "happily": true ])
        let rel2 = Relationship(fromNode: from, toNode: to, type: "Married to", direction: .from, properties: [ "happily": true ])

        let request = [rel1, rel2].createRequest(withReturnStatement: true)
        var queryResult: QueryResult! = nil
        let result = client.executeWithResultSync(request: request)
        switch result {
        case let .failure(error):
            XCTFail(error.localizedDescription)
            return
        case let .success(theQueryResult):
            queryResult = theQueryResult
        }
        
        XCTAssertEqual(1, queryResult!.rows.count)
        XCTAssertEqual(4, queryResult!.fields.count)
        XCTAssertEqual(2, queryResult!.nodes.count)
        XCTAssertEqual(2, queryResult!.relationships.count)
        XCTAssertEqual("rw", queryResult!.stats.type)
    }

    func testUpdateRelationshipAlt() throws {
        
        let exp = expectation(description: "Finish transaction with updates to relationship")
        let client = try makeClient()
        try client.executeAsTransaction(mode: .readwrite, bookmark: nil, transactionBlock:  { tx in
            
            tx.autocommit = false
            let nodes = self.makeSomeNodes()
            let result = client.createAndReturnNodesSync(nodes: nodes)
            XCTAssertTrue(result.isSuccess)
            let createdNodes = try! result.get()
            
            let (from, to) = (createdNodes[0], createdNodes[1])
            let result2 = client.relateSync(node: from, to: to, type: "Married", properties: [ "happily": true ])
            XCTAssertTrue(result2.isSuccess)
            let createdRelationship = try! result2.get()
            
            XCTAssertTrue(createdRelationship["happily"] as! Bool)
            XCTAssertEqual(from.id!, createdRelationship.fromNodeId)
            XCTAssertEqual(to.id!, createdRelationship.toNodeId)
            
            createdRelationship["location"] = "church"
            createdRelationship["someProp"] = 42
            
            
            
            let result3 = client.updateAndReturnRelationshipSync(relationship: createdRelationship)
            XCTAssertTrue(result3.isSuccess)
            let updatedRelationship = try! result3.get()
            updatedRelationship["someProp"] = nil
            
            let result4 = client.updateAndReturnRelationshipSync(relationship: updatedRelationship)
            XCTAssertTrue(result4.isSuccess)
            let finalRelationship = try! result4.get()
            
            XCTAssertTrue(finalRelationship["happily"] as! Bool)
            XCTAssertEqual("church", finalRelationship["location"] as! String)
            XCTAssertNil(finalRelationship["someProp"])
            XCTAssertEqual(from.id!, finalRelationship.fromNodeId)
            XCTAssertEqual(to.id!, finalRelationship.toNodeId)
            
            tx.markAsFailed()
            try? client.rollback(transaction: tx) {
                exp.fulfill()
            }
            
        }, transactionCompleteBlock: nil)
        
        waitForExpectations(timeout: 20.0) { error in
            XCTAssertNil(error)
        }
    }
    
    func testUpdateRelationship() throws {

        let exp = expectation(description: "Finish transaction with updates to relationship")
        let client = try makeClient()
        try client.executeAsTransaction(mode: .readwrite, bookmark: nil, transactionBlock:  { tx in

            let nodes = self.makeSomeNodes()
            guard case let Result.success(createdNodes) = client.createAndReturnNodesSync(nodes: nodes) else {
                XCTFail()
                return
            }
            let (from, to) = (createdNodes[0], createdNodes[1])
            var result = client.relateSync(node: from, to: to, type: "Married", properties: [ "happily": true ])
            guard case let Result.success(createdRelationship) = result else {
                XCTFail()
                return
            }

            XCTAssertTrue(createdRelationship["happily"] as! Bool)
            XCTAssertEqual(from.id!, createdRelationship.fromNodeId)
            XCTAssertEqual(to.id!, createdRelationship.toNodeId)

            createdRelationship["location"] = "church"
            createdRelationship["someProp"] = 42
            result = client.updateAndReturnRelationshipSync(relationship: createdRelationship)
            guard case let Result.success(updatedRelationship) = result else {
                XCTFail()
                return
            }

            updatedRelationship["someProp"] = nil
            result = client.updateAndReturnRelationshipSync(relationship: updatedRelationship)
            guard case let Result.success(finalRelationship) = result else {
                XCTFail()
                return
            }

            XCTAssertTrue(finalRelationship["happily"] as! Bool)
            XCTAssertEqual("church", finalRelationship["location"] as! String)
            XCTAssertNil(finalRelationship["someProp"])
            XCTAssertEqual(from.id!, finalRelationship.fromNodeId)
            XCTAssertEqual(to.id!, finalRelationship.toNodeId)

            tx.markAsFailed()
        }, transactionCompleteBlock: { isSuccess in
            exp.fulfill()
        })

        waitForExpectations(timeout: 20.0) { error in
            XCTAssertNil(error)
        }
    }

    func testMeasureCreateAndDeleteNode() {
        measure {
            print("Iterate")
            try! testCreateAndDeleteNode()
        }
    }
    
    func testCreateAndDeleteNode() throws {

        let node = makeSomeNodes().first!

        let client = try makeClient()
        
        let result = client.createAndReturnNodeSync(node: node)
        switch result {
        case let .failure(error):
            XCTFail(error.localizedDescription)
        case let .success(resultNode):
            let result = client.deleteNodeSync(node: resultNode)
            switch result{
            case let .failure(error):
                XCTFail(error.localizedDescription)
            case let .success(isSuccess):
                XCTAssertTrue(isSuccess)
            }
        }
    }

    func testCreateAndDeleteNodes() throws {

        let nodes = makeSomeNodes()

        let client = try makeClient()
        let result = client.createAndReturnNodesSync(nodes: nodes)
        switch result {
        case let .failure(error):
            XCTFail(error.localizedDescription)
        case let .success(resultNodes):
            let result = client.deleteNodesSync(nodes: resultNodes)
            switch result{
            case let .failure(error):
                XCTFail(error.localizedDescription)
            case let .success(isSuccess):
                XCTAssertTrue(isSuccess)
            }
        }
    }

    func testUpdateRelationshipNoReturn() throws {

        var from = Node(labels: ["Candidate"], properties: ["name": "Bala"])
        var to = Node(labels: ["Employer"], properties: ["name": "Yahoo"])

        let client = try makeClient()
        let result = client.createAndReturnNodesSync(nodes: [from, to])
        XCTAssertTrue(result.isSuccess)
        guard case let Result.success(resultNodes) = result else {
            XCTFail()
            return
        }
        XCTAssertNotNil(resultNodes)
        from = resultNodes[0]
        to = resultNodes[1]

        let relResult = client.relateSync(node: from, to: to, type: "WORKED_IN", properties: [ "from": 2015, "to": 2017])
        XCTAssertTrue(relResult.isSuccess)
        guard case let Result.success(relationship) = relResult else {
            XCTFail()
            return
        }

        XCTAssertNotNil(relationship)
        relationship["to"] = 2016
        let updateRelResult = client.updateRelationshipSync(relationship: relationship)
        XCTAssertTrue(updateRelResult.isSuccess)
        guard case let Result.success(value) = updateRelResult else {
            XCTFail()
            return
        }
        XCTAssertNotNil(value)
        XCTAssertTrue(value)
        
        relationship["to"] = 2018
        let updateRelResult2 = client.updateRelationshipSync(relationship: relationship)
        XCTAssertTrue(updateRelResult2.isSuccess)
        guard case let Result.success(value2) = updateRelResult2 else {
            XCTFail()
            return
        }
        XCTAssertTrue(updateRelResult.isSuccess)
        XCTAssertNotNil(value2)
        XCTAssertTrue(value2)

    }

    func testDeleteRelationship() throws {

        var from = Node(labels: ["Candidate"], properties: ["name": "Bala"])
        var to = Node(labels: ["Employer"], properties: ["name": "Yahoo"])

        let client = try makeClient()
        let result = client.createAndReturnNodesSync(nodes: [from, to])
        XCTAssertTrue(result.isSuccess)
        guard case let Result.success(resultNodes) = result else {
            XCTFail()
            return
        }
        XCTAssertNotNil(resultNodes)
        from = resultNodes[0]
        to = resultNodes[1]

        let relResult = client.relateSync(node: from, to: to, type: "WORKED_IN", properties: [ "from": 2015, "to": 2017])
        XCTAssertTrue(relResult.isSuccess)
        guard case let Result.success(relationship) = relResult else {
            XCTFail()
            return
        }
        XCTAssertNotNil(relationship)

        let rmResult = client.deleteRelationshipSync(relationship: relationship)
        XCTAssertTrue(rmResult.isSuccess)

    }

    func testReturnPath() throws {

        try testIntroToCypher() // First make sure we have a result path

        let client = try makeClient()
        let query = "MATCH p = (a)-[*3..5]->(b)\nRETURN p LIMIT 5"
        let result = client.executeCypherSync(query, params: [:])
        guard case let Result.success(value) = result else {
            XCTFail()
            return
        }
        XCTAssertNotNil(value)
        XCTAssertEqual(1, value.paths.count)
        let path = value.paths.first!
        XCTAssertLessThan(0, path.segments.count)
    }

    func testBreweryDataset() throws {

        let exp = expectation(description: "testBreweryDataset")
        
        let indexQueries =
"""
CREATE INDEX ON :BeerBrand(name);
CREATE INDEX ON :Brewery(name);
CREATE INDEX ON :BeerType(name);
CREATE INDEX ON :AlcoholPercentage(value);
"""
        
        let queries =
"""
LOAD CSV WITH HEADERS FROM "https://docs.google.com/spreadsheets/d/1FwWxlgnOhOtrUELIzLupDFW7euqXfeh8x3BeiEY_sbI/export?format=csv&id=1FwWxlgnOhOtrUELIzLupDFW7euqXfeh8x3BeiEY_sbI&gid=0" AS CSV
WITH CSV AS beercsv
WHERE beercsv.BeerType IS not NULL
MERGE (b:BeerType {name: beercsv.BeerType})
WITH beercsv
WHERE beercsv.BeerBrand IS not NULL
MERGE (b:BeerBrand {name: beercsv.BeerBrand})
WITH beercsv
WHERE beercsv.Brewery IS not NULL
MERGE (b:Brewery {name: beercsv.Brewery})
WITH beercsv
WHERE beercsv.AlcoholPercentage IS not NULL
MERGE (b:AlcoholPercentage {value:
tofloat(replace(replace(beercsv.AlcoholPercentage,'%',''),',','.'))})
WITH beercsv
MATCH (ap:AlcoholPercentage {value:
tofloat(replace(replace(beercsv.AlcoholPercentage,'%',''),',','.'))}),
(br:Brewery {name: beercsv.Brewery}),
(bb:BeerBrand {name: beercsv.BeerBrand}),
(bt:BeerType {name: beercsv.BeerType})
CREATE (bb)-[:HAS_ALCOHOLPERCENTAGE]->(ap),
(bb)-[:IS_A]->(bt),
(bb)<-[:BREWS]-(br);
"""
        let client = try makeClient()
        for query in indexQueries.split(separator: ";") {
            let result = client.executeCypherSync(String(query), params: [:])
            XCTAssertTrue(result.isSuccess)
        }
        
        try client.resetSync()
        
        try client.executeAsTransaction(mode: .readwrite, bookmark: nil, transactionBlock: { tx in
            tx.autocommit = false
            
            for query in queries.split(separator: ";") {
                let result = client.executeCypherSync(String(query), params: [:])
                XCTAssertTrue(result.isSuccess)
            }
            
            tx.markAsFailed()
            try client.rollback(transaction: tx, rollbackCompleteBlock: {
                exp.fulfill()
            })
        }, transactionCompleteBlock: nil)
        
        waitForExpectations(timeout: 10.0) { error in
            XCTAssertNil(error)
        }
    }
    
    /*func testDisconnect() throws {
        let client = try makeClient()
        client.disconnect()
        let result = client.executeCypherSync("RETURN 1", params: [:])
        XCTAssertFalse(result.isSuccess)
         // Fair enough, but we should then decide how we reconnect
        _ = client.connectSync()
    }*/

    func testRecord() throws {
        let client = try makeClient()
        let result = client.executeCypherSync("RETURN 1,2,3", params: [:])
        XCTAssertTrue(result.isSuccess)
        guard case let Result.success(value) = result else {
            XCTFail()
            return
        }
        let row = value.rows[0]
        XCTAssertEqual(1 as UInt64, row["1"]! as! UInt64)
        XCTAssertEqual(2 as UInt64, row["2"]! as! UInt64)
        XCTAssertEqual(3 as UInt64, row["3"]! as! UInt64)
    }
    
    func testFindNodeById() throws {
        
        let exp = expectation(description: "testFindNodeById")
        
        let nodes = makeSomeNodes()
        
        let client = try makeClient()
        let createResult = client.createAndReturnNodeSync(node: nodes.first!)
        XCTAssertTrue(createResult.isSuccess)
        guard case let Result.success(createdNode) = createResult else {
            XCTFail()
            return
        }
        let createdNodeId = createdNode.id!

        let foundNodeResult = client.nodeBySync(id: createdNodeId)
        switch foundNodeResult {
        case let .failure(error):
            XCTFail(error.localizedDescription)
        case let .success(foundNode):
            XCTAssertNotNil(foundNode)
            XCTAssertEqual(createdNode.id, foundNode.id)
        }
        exp.fulfill()
        
        waitForExpectations(timeout: 10.0) { error in
            XCTAssertNil(error)
        }
    }
    
    func testFindNodeByLabels() throws {
        let client = try makeClient()
        let nodes = makeSomeNodes()
        let labels = Array<String>(nodes.flatMap { $0.labels }[1...2]) // Husband, Father
        
        var nodeCount: Int = -1
        let result = client.nodesWithSync(labels: labels, andProperties: [:], skip: 0, limit: 0)
        XCTAssertTrue(result.isSuccess)
        guard case let Result.success(value) = result else {
            XCTFail()
            return
        }
        XCTAssertNotNil(value)
        nodeCount = value.count
        
        let createResult = client.createNodeSync(node: nodes[0])
        XCTAssertTrue(createResult.isSuccess)
        
        let exp = expectation(description: "Node should be one more than on previous count")
        let result2 = client.nodesWithSync(labels: labels, andProperties: [:], skip: 0, limit: 0)
        XCTAssertTrue(result2.isSuccess)
        guard case let Result.success(values) = result2 else {
            XCTFail()
            return
        }
        XCTAssertNotNil(values)
        XCTAssertEqual(nodeCount + 1, values.count)
        exp.fulfill()
        
        waitForExpectations(timeout: 5.0) { error in
            XCTAssertNil(error)
        }
    }

    func testFindNodeByProperties() throws {
        let client = try makeClient()
        let properties: [String:PackProtocol] = [
            "firstName": "Niklas",
            "age": 40
        ]
        
        var nodeCount: Int = -1
        let result = client.nodesWithSync(properties: properties, skip: 0, limit: 0)
        XCTAssertTrue(result.isSuccess)
        guard case let Result.success(value) = result else {
            XCTFail()
            return
        }
        XCTAssertNotNil(value)
        nodeCount = value.count
        
        let nodes = makeSomeNodes()
        let createResult = client.createNodeSync(node: nodes[0])
        XCTAssertTrue(createResult.isSuccess)
        
        let exp = expectation(description: "Node should be one more than on previous count")
        let result2 = client.nodesWithSync(properties: properties, skip: 0, limit: 0)
        XCTAssertTrue(result2.isSuccess)
        guard case let Result.success(value2) = result2 else {
            XCTFail()
            return
        }
        XCTAssertNotNil(value2)
        XCTAssertEqual(nodeCount + 1, value2.count)
        exp.fulfill()
        
        waitForExpectations(timeout: 5.0) { error in
            XCTAssertNil(error)
        }
    }

    func testFindNodeByLabelsAndProperties() throws {
        let client = try makeClient()
        let labels = ["Father", "Husband"]
        let properties: [String:PackProtocol] = [
            "firstName": "Niklas",
            "age": 40
        ]
        
        let limit: UInt64 = UInt64(Int32.max)
        var nodeCount: Int = -1
        let result = client.nodesWithSync(labels: labels, andProperties: properties, skip: 0, limit: limit)
        XCTAssertTrue(result.isSuccess)
        guard case let Result.success(value) = result else {
            XCTFail()
            return
        }
        XCTAssertNotNil(value)
        nodeCount = value.count
        
        let nodes = makeSomeNodes()
        let createResult = client.createNodeSync(node: nodes[0])
        XCTAssertTrue(createResult.isSuccess)
        
        let exp = expectation(description: "Node should be one more than on previous count")
        let result2 = client.nodesWithSync(labels: labels, andProperties: properties, skip: 0, limit: limit)
        XCTAssertTrue(result2.isSuccess)
        guard case let Result.success(value2) = result2 else {
            XCTFail()
            return
        }
        XCTAssertNotNil(value2)
        XCTAssertEqual(nodeCount + 1, value2.count)
        exp.fulfill()
        
        waitForExpectations(timeout: 5.0) { error in
            XCTAssertNil(error)
        }
    }

    func testFindNodeByLabelAndProperties() throws {
        let client = try makeClient()
        let label = "Father"
        let properties: [String:PackProtocol] = [
            "firstName": "Niklas",
            "age": 40
        ]
        
        let limit: UInt64 = UInt64(Int32.max)
        var nodeCount: Int = -1
        let result = client.nodesWithSync(label: label, andProperties: properties, skip: 0, limit: limit)
        XCTAssertTrue(result.isSuccess)
        guard case let Result.success(value) = result else {
            XCTFail()
            return
        }
        XCTAssertNotNil(value)
        nodeCount = value.count
        
        let nodes = makeSomeNodes()
        let createResult = client.createNodeSync(node: nodes[0])
        XCTAssertTrue(createResult.isSuccess)
        
        let exp = expectation(description: "Node should be one more than on previous count")
        let result2 = client.nodesWithSync(label: label, andProperties: properties, skip: 0, limit: limit)
        XCTAssertTrue(result2.isSuccess)
        guard case let Result.success(value2) = result2 else {
            XCTFail()
            return
        }
        XCTAssertNotNil(value2)
        XCTAssertEqual(nodeCount + 1, value2.count)
        exp.fulfill()
        
        waitForExpectations(timeout: 5.0) { error in
            XCTAssertNil(error)
        }
    }
    
    func testFindNodeByLabelsAndProperty() throws {
        let client = try makeClient()
        let labels = ["Father", "Husband"]
        let property: [String:PackProtocol] = [
            "firstName": "Niklas"
        ]
        
        var nodeCount: Int = -1
        let result = client.nodesWithSync(labels: labels, andProperties: property, skip: 0, limit: 0)
        XCTAssertTrue(result.isSuccess)
        guard case let Result.success(value) = result else {
            XCTFail()
            return
        }

        XCTAssertNotNil(value)
        nodeCount = value.count
        
        let nodes = makeSomeNodes()
        let createResult = client.createNodeSync(node: nodes[0])
        XCTAssertTrue(createResult.isSuccess)
        
        let exp = expectation(description: "Node should be one more than on previous count")
        let result2 = client.nodesWithSync(labels: labels, andProperties: property, skip: 0, limit: 0)
        XCTAssertTrue(result2.isSuccess)
        guard case let Result.success(value2) = result2 else {
            XCTFail()
            return
        }
        XCTAssertNotNil(value2)
        XCTAssertEqual(nodeCount + 1, value2.count)
        exp.fulfill()
        
        waitForExpectations(timeout: 5.0) { error in
            XCTAssertNil(error)
        }
    }
    
    func testFindNodeByLabelAndProperty() throws {
        let client = try makeClient()
        let label = "Father"
        let property: [String:PackProtocol] = [
            "firstName": "Niklas"
        ]
        
        let limit: UInt64 = UInt64(Int32.max)
        var nodeCount: Int = -1
        let result = client.nodesWithSync(label: label, andProperties: property, skip: 0, limit: limit)
        XCTAssertTrue(result.isSuccess)
        guard case let Result.success(value) = result else {
            XCTFail()
            return
        }
        XCTAssertNotNil(value)
        nodeCount = value.count
        
        let nodes = makeSomeNodes()
        let createResult = client.createNodeSync(node: nodes[0])
        XCTAssertTrue(createResult.isSuccess)
        
        let exp = expectation(description: "Node should be one more than on previous count")
        let result2 = client.nodesWithSync(label: label, andProperties: property, skip: 0, limit: limit)
        XCTAssertTrue(result2.isSuccess)
        guard case let Result.success(value2) = result2 else {
            XCTFail()
            return
        }
        XCTAssertNotNil(value2)
        XCTAssertEqual(nodeCount + 1, value2.count)
        exp.fulfill()
        
        waitForExpectations(timeout: 5.0) { error in
            XCTAssertNil(error)
        }
    }
    
    func testFindRelationshipsByType() throws {
        
        let client = try makeClient()
        let nodes = makeSomeNodes()
        
        let type = "IS_MADLY_IN_LOVE_WITH"
        let result = client.relateSync(node: nodes[0], to: nodes[1], type: type, properties: [:])
        XCTAssertTrue(result.isSuccess)
        guard case let Result.success(relationship) = result else {
            XCTFail()
            return
        }
        XCTAssertNotNil(relationship)
        
        let exp = expectation(description: "Found relationship in result")
        let result2 = client.relationshipsWithSync(type: type, andProperties: [:], skip: 0, limit: 0)
        XCTAssertTrue(result.isSuccess)
        guard case let Result.success(relationships) = result2 else {
            XCTFail()
            return
        }
        XCTAssertNotNil(relationships)
        for rel in relationships {
            if let foundId = rel.id,
                let compareId = relationship.id,
                foundId == compareId {
                exp.fulfill()
                break
            }
            
        }
        
        waitForExpectations(timeout: 5.0) { error in
            XCTAssertNil(error)
        }
    }

    func testFindRelationshipsByTypeAndProperties() throws {
        let client = try makeClient()
        let nodes = makeSomeNodes()
        
        let type = "IS_MADLY_IN_LOVE_WITH"
        let props: [String: PackProtocol] = [ "propA": true, "propB": "another" ]
        let result = client.relateSync(node: nodes[0], to: nodes[1], type: type, properties: props )
        XCTAssertTrue(result.isSuccess)
        guard case let Result.success(relationship) = result else {
            XCTFail()
            return
        }
        XCTAssertNotNil(relationship)
        
        let exp = expectation(description: "Found relationship in result")
        let result2 = client.relationshipsWithSync(type: type, andProperties: props, skip: 0, limit: 0)
        XCTAssertTrue(result.isSuccess)
        guard case let Result.success(relationships) = result2 else {
            XCTFail()
            return
        }
        XCTAssertNotNil(relationships)
        for rel in relationships {
            if let foundId = rel.id,
                let compareId = relationship.id,
                foundId == compareId {
                exp.fulfill()
                break
            }
            
        }
        
        waitForExpectations(timeout: 5.0) { error in
            XCTAssertNil(error)
        }
    }
    
    func testFindRelationshipsByTypeAndProperty() throws {
        let client = try makeClient()
        let nodes = makeSomeNodes()
        
        let type = "IS_MADLY_IN_LOVE_WITH"
        let props: [String: PackProtocol] = [ "propA": true, "propB": "another" ]
        let result = client.relateSync(node: nodes[0], to: nodes[1], type: type, properties: props )
        XCTAssertTrue(result.isSuccess)
        guard case let Result.success(relationship) = result else {
            XCTFail()
            return
        }
        XCTAssertNotNil(relationship)
        
        let exp = expectation(description: "Found relationship in result")
        let result2 = client.relationshipsWithSync(type: type, andProperties: ["propA": true], skip: 0, limit: 0)
        XCTAssertTrue(result2.isSuccess)
        guard case let Result.success(relationships) = result2 else {
            XCTFail()
            return
        }
        XCTAssertNotNil(relationships)
        for rel in relationships {
            if let foundId = rel.id,
                let compareId = relationship.id,
                foundId == compareId {
                exp.fulfill()
                break
            }
            
        }
        
        waitForExpectations(timeout: 5.0) { error in
            XCTAssertNil(error)
        }
    }
    
    /// Expectation: nothing else runs on the database on the same time
    func testThatRelationshipsForExistingNodesDoNotCreateNewNodes() throws {

        let count: () throws -> (Int) = { [weak self] in
            guard let client = try self?.makeClient() else { return -3 }
            let query = "MATCH (n) RETURN count(n) AS count"
            let result = client.executeCypherSync(query, params: [:])
            let ret: Int
            switch result {
            case .failure:
                ret = -1
            case let .success(queryResult):
                if let row = queryResult.rows.first,
                    let countValue = row["count"] as? UInt64 {
                    let countIntValue = Int(countValue)
                    ret = countIntValue
                } else {
                    ret = -2
                }
            }
            return ret
        }
        
        let client = try makeClient()
        let nodes = makeSomeNodes()
        guard case let Result.success(createdNodes) = client.createAndReturnNodesSync(nodes: nodes) else {
            XCTFail()
            return
        }
        let (from, to) = (createdNodes[0], createdNodes[1])

        let before = try count()
        XCTAssertGreaterThan(before, -1)
        
        let rel1 = Relationship(fromNode: from, toNode: to, type: "Married to", direction: .to, properties: [ "happily": true ])
        let rel2 = Relationship(fromNode: from, toNode: to, type: "Married to", direction: .from, properties: [ "happily": true ])
        
        let request = [rel1, rel2].createRequest(withReturnStatement: true)
        var queryResult: QueryResult! = nil
        let result = client.executeWithResultSync(request: request)
        switch result {
        case let .failure(error):
            XCTFail(error.localizedDescription)
            return
        case let .success(theQueryResult):
            queryResult = theQueryResult
        }
        
        XCTAssertEqual(1, queryResult!.rows.count)
        XCTAssertEqual(4, queryResult!.fields.count)
        XCTAssertEqual(2, queryResult!.nodes.count)
        XCTAssertEqual(2, queryResult!.relationships.count)
        XCTAssertEqual("rw", queryResult!.stats.type)
        
        let after = try count()
    
        XCTAssertEqual(before, after)
    }
    
    func createBigNodes(num: Int) throws {
        let query = "UNWIND RANGE(1, 16, 1) AS i CREATE (n:BigNode { i: i, payload: $payload })"
        let payload = (0..<1024).map { _ in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz" } .joined(separator: "/0123456789/")
        
        let client = try makeClient()
        let result = client.executeCypherSync(query, params: ["payload": payload])
        switch result {
        case let .failure(error):
            XCTFail(error.localizedDescription)
        case .success(_):
            break
        }

    }
    
    func testMultiChunkResults() throws {
        try createBigNodes(num: 16)
        let exp = expectation(description: "Got lots of data back")

        let client = try makeClient()
        let result = client.nodesWithSync(labels: ["BigNode"], andProperties: [:], skip:0, limit: 0)
        switch result {
        case let .failure(error):
            XCTFail(error.localizedDescription)
        case let .success(nodes):
            XCTAssertGreaterThan(nodes.count, 0)
        }
        exp.fulfill()
        
        waitForExpectations(timeout: 15.0) { (error) in
            XCTAssertNil(error)
        }
    }
    
    func testMeasureTestNodeResult() {
        measure {
            try! testNodeResult()
        }
    }
    
    func testMeasureTestRelationshipResult() {
        measure {
            try! testRelationshipResult()
        }
    }
    
    func testMeasureTestIntroToCypher() {
        measure {
            try! testIntroToCypher()
        }
    }
    
    func testMeasureTestSetOfQueries() {
        measure {
            try! testSetOfQueries()
        }
    }
    
    func testMeasureTestSucceedingTransactionSync() {
        measure {
            try! testSucceedingTransactionSync()
        }
    }
    
    func testMeasureTestFailingTransactionSync() {
        measure {
            try! testFailingTransactionSync()
        }
    }
    
    func testMeasureTestCancellingTransaction() {
        measure {
            try! testCancellingTransaction()
        }
    }
    
    func testMeasureTestTransactionResultsInBookmark() {
        measure {
            try! testTransactionResultsInBookmark()
        }
    }
    
    func testMeasureTestGettingStartedExample() {
        measure {
            try! testGettingStartedExample()
        }
    }
    
    func testMeasureTestCreateAndRunCypherFromNode() {
        measure {
            try! testCreateAndRunCypherFromNode()
        }
    }
    
    func testMeasureTestCreateAndRunCypherFromNodesWithResult() {
        measure {
            try! testCreateAndRunCypherFromNodesWithResult()
        }
    }
    
    func testMeasureTestUpdateAndRunCypherFromNodesWithResult() {
        measure {
            try! testUpdateAndRunCypherFromNodesWithResult()
        }
    }
    
    func testMeasureTestUpdateAndRunCypherFromNodesWithoutResult() {
        measure {
            try! testUpdateAndRunCypherFromNodesWithoutResult()
        }
    }
    
    func testMeasureTestUpdateNode() {
        measure {
            try! testUpdateNode()
        }
    }
    
    func testMeasureTestUpdateAndReturnNode() {
        measure {
            try! testUpdateAndReturnNode()
        }
    }
    
    func testMeasureTestCypherMatching() {
        measure {
            try! testCypherMatching()
        }
    }
    
    func testMeasureTestCreateAndRunCypherFromNodesNoResult() {
        measure {
            try! testCreateAndRunCypherFromNodesNoResult()
        }
    }
    
    func testMeasureTestCreatePropertylessNodeAsync() {
        measure {
            try! testCreatePropertylessNodeAsync()
        }
    }
    
    func testMeasureTestCreateAndRunCypherFromNodeNoResult() {
        measure {
            try! testCreateAndRunCypherFromNodeNoResult()
        }
    }
    
    func testMeasureTestUpdateNodesWithResult() {
        measure {
            try! testUpdateNodesWithResult()
        }
    }
    
    func testMeasureTestUpdateNodesWithNoResult() {
        measure {
            try! testUpdateNodesWithNoResult()
        }
    }
    
    func testMeasureTestCreateRelationshipWithoutCreateNodes() {
        measure {
            try! testCreateRelationshipWithoutCreateNodes()
        }
    }
    
    func testMeasureTestCreateRelationshipWithCreateNodes() {
        measure {
            try! testCreateRelationshipWithCreateNodes()
        }
    }
    
    func testMeasureTestCreateRelationshipWithCreateFromNode() {
        measure {
            try! testCreateRelationshipWithCreateFromNode()
        }
    }
    
    func testMeasureTestCreateAndReturnRelationshipsSync() {
        measure {
            try! testCreateAndReturnRelationshipsSync()
        }
    }
    
    func testMeasureTestCreateAndReturnRelationships() {
        measure {
            try! testCreateAndReturnRelationships()
        }
    }
    
    func testMeasureTestCreateAndReturnRelationship() {
        measure {
            try! testCreateAndReturnRelationship()
        }
    }
    
    func testMeasureTestCreateAndReturnRelationshipByCreatingFromAndToNode() {
        measure {
            try! testCreateAndReturnRelationshipByCreatingFromAndToNode()
        }
    }
    
    func testMeasureTestCreateAndReturnRelationshipByCreatingOnlyFromNode() {
        measure {
            try! testCreateAndReturnRelationshipByCreatingOnlyFromNode()
        }
    }
    
    func testMeasureTestCreateAndReturnRelationshipByCreatingOnlyToNode() {
        measure {
            try! testCreateAndReturnRelationshipByCreatingOnlyToNode()
        }
    }
    
    func testMeasureTestCreateRelationshipWithCreateToNode() {
        measure {
            try! testCreateRelationshipWithCreateToNode()
        }
    }
    
    func testMeasureTestCreateRelationshipSync() {
        measure {
            try! testCreateRelationshipSync()
        }
    }
    
    func testMeasureTestCreateRelationshipsWithExistingNodesUsingId() {
        measure {
            try! testCreateRelationshipsWithExistingNodesUsingId()
        }
    }
    
    func testMeasureTestCreateRelationshipsWithExistingNodesUsingNode() {
        measure {
            try! testCreateRelationshipsWithExistingNodesUsingNode()
        }
    }
    
    func testMeasureTestCreateRelationshipsWithoutExistingNodes() {
        measure {
            try! testCreateRelationshipsWithoutExistingNodes()
        }
    }
    
    func testMeasureTestCreateRelationshipsWithMixedNodes() {
        measure {
            try! testCreateRelationshipsWithMixedNodes()
        }
    }
    
    func testMeasureTestUpdateRelationship() {
        measure {
            try! testUpdateRelationship()
        }
    }

    func testMeasureTestUpdateRelationshipAlt() {
        measure {
            try! testUpdateRelationshipAlt()
        }
    }

    func testMeasureTestCreateAndDeleteNode() {
        measure {
            try! testCreateAndDeleteNode()
        }
    }
    
    func testMeasureTestCreateAndDeleteNodes() {
        measure {
            try! testCreateAndDeleteNodes()
        }
    }
    
    func testMeasureTestUpdateRelationshipNoReturn() {
        measure {
            try! testUpdateRelationshipNoReturn()
        }
    }
    
    func testMeasureTestDeleteRelationship() {
        measure {
            try! testDeleteRelationship()
        }
    }
    
    func testMeasureTestReturnPath() {
        measure {
            try! testReturnPath()
        }
    }
    
    func testMeasureTestBreweryDataset() {
        measure {
            try! testBreweryDataset()
        }
    }
    
    /*func testMeasureTestDisconnect() {
        measure {
            try! testDisconnect()
        }
    }*/
    
    func testMeasureTestRecord() {
        measure {
            try! testRecord()
        }
    }
    
    func testMeasureTestFindNodeById() {
        measure {
            try! testFindNodeById()
        }
    }
    
    func testMeasureTestFindNodeByLabels() {
        measure {
            try! testFindNodeByLabels()
        }
    }
    
    func testMeasureTestFindNodeByProperties() {
        measure {
            try! testFindNodeByProperties()
        }
    }
    
    func testMeasureTestFindNodeByLabelsAndProperties() {
        measure {
            try! testFindNodeByLabelsAndProperties()
        }
    }
    
    func testMeasureTestFindNodeByLabelAndProperties() {
        measure {
            try! testFindNodeByLabelAndProperties()
        }
    }
    
    func testMeasureTestFindNodeByLabelsAndProperty() {
        measure {
            try! testFindNodeByLabelsAndProperty()
        }
    }
    
    func testMeasureTestFindNodeByLabelAndProperty() {
        measure {
            try! testFindNodeByLabelAndProperty()
        }
    }
    
    func testMeasureTestFindRelationshipsByType() {
        measure {
            try! testFindRelationshipsByType()
        }
    }
    
    func testMeasureTestFindRelationshipsByTypeAndProperties() {
        measure {
            try! testFindRelationshipsByTypeAndProperties()
        }
    }
    
    func testMeasureTestFindRelationshipsByTypeAndProperty() {
        measure {
            try! testFindRelationshipsByTypeAndProperty()
        }
    }
    
    func testMeasureTestThatRelationshipsForExistingNodesDoNotCreateNewNodes() {
        measure {
            try! testThatRelationshipsForExistingNodesDoNotCreateNewNodes()
        }
    }
    
    func testMeasureTestMultiChunkResults() {
        measure {
            try! testMultiChunkResults()
        }
    }

    static var allTests = [
        ("testBreweryDataset", testBreweryDataset),
        ("testCancellingTransaction", testCancellingTransaction),
        ("testCreateAndDeleteNode", testCreateAndDeleteNode),
        ("testCreateAndDeleteNodes", testCreateAndDeleteNodes),
        ("testCreateAndRunCypherFromNode", testCreateAndRunCypherFromNode),
        ("testCreateAndRunCypherFromNodeNoResult", testCreateAndRunCypherFromNodeNoResult),
        ("testCreateAndRunCypherFromNodesNoResult", testCreateAndRunCypherFromNodesNoResult),
        ("testCreateAndRunCypherFromNodesWithResult", testCreateAndRunCypherFromNodesWithResult),
        ("testCreateRelationshipWithCreateFromNode", testCreateRelationshipWithCreateFromNode),
        ("testCreateRelationshipWithCreateNodes", testCreateRelationshipWithCreateNodes),
        ("testCreateRelationshipWithCreateToNode", testCreateRelationshipWithCreateToNode),
        ("testCreateRelationshipWithoutCreateNodes", testCreateRelationshipWithoutCreateNodes),
        ("testCreateRelationshipsWithExistingNodesUsingId", testCreateRelationshipsWithExistingNodesUsingId),
        ("testCreateRelationshipsWithExistingNodesUsingNode", testCreateRelationshipsWithExistingNodesUsingNode),
        ("testCreateRelationshipsWithMixedNodes", testCreateRelationshipsWithMixedNodes),
        ("testCreateRelationshipsWithoutExistingNodes", testCreateRelationshipsWithoutExistingNodes),
        ("testCypherMatching", testCypherMatching),
        ("testDeleteRelationship", testDeleteRelationship),
        ("testFailingTransactionSync", testFailingTransactionSync),
        ("testGettingStartedExample", testGettingStartedExample),
        ("testIntroToCypher", testIntroToCypher),
        ("testNodeResult", testNodeResult),
        ("testRelationshipResult", testRelationshipResult),
        ("testReturnPath", testReturnPath),
        ("testSetOfQueries", testSetOfQueries),
        ("testSucceedingTransactionSync", testSucceedingTransactionSync),
        ("testTransactionResultsInBookmark", testTransactionResultsInBookmark),
        ("testUpdateAndRunCypherFromNodesWithResult", testUpdateAndRunCypherFromNodesWithResult),
        ("testUpdateAndRunCypherFromNodesWithoutResult", testUpdateAndRunCypherFromNodesWithoutResult),
        ("testUpdateNode", testUpdateNode),
        ("testUpdateNodesWithNoResult", testUpdateNodesWithNoResult),
        ("testUpdateNodesWithResult", testUpdateNodesWithResult),
        ("testUpdateRelationship", testUpdateRelationship),
        ("testUpdateRelationshipNoReturn", testUpdateRelationshipNoReturn),
        //("testDisconnect", testDisconnect),
        ("testRecord", testRecord),
        ("testFindNodeById", testFindNodeById),
        ("testFindNodeByLabels", testFindNodeByLabels),
        ("testFindNodeByLabelsAndProperties", testFindNodeByLabelsAndProperties),
        ("testFindNodeByLabelAndProperties", testFindNodeByLabelAndProperties),
        ("testFindNodeByLabelsAndProperty", testFindNodeByLabelsAndProperty),
        ("testFindNodeByLabelAndProperty", testFindNodeByLabelAndProperty),
        ("testCreateAndReturnRelationshipsSync", testCreateAndReturnRelationshipsSync),
        ("testCreateAndReturnRelationships", testCreateAndReturnRelationships),
        ("testCreateAndReturnRelationship", testCreateAndReturnRelationship),
        ("testUpdateAndReturnNode", testUpdateAndReturnNode),
        ("testFindRelationshipsByType", testFindRelationshipsByType),
        ("testFindRelationshipsByTypeAndProperties", testFindRelationshipsByTypeAndProperties),
        ("testFindRelationshipsByTypeAndProperty", testFindRelationshipsByTypeAndProperty),
    ]
 
}

extension Result {
    var isSuccess: Bool {
        get {
            switch self {
            case .failure(_):
                return false
            case .success(_):
                return true
            }
        }
    }
}
