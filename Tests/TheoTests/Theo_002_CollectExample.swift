import Foundation
import XCTest
import PackStream

import Bolt
//import SwiftRandom

@testable import Theo

class Theo_002_CollectExample: TheoTestCase {
    
    override func setUp() {
        super.setUp()
        self.continueAfterFailure = false
    }

    func testCollect() throws {
        let client = try makeClient()

        // grabbed query from https://markhneedham.com/blog/2014/09/26/neo4j-collecting-multiple-values-too-many-parameters-for-function-collect/
        let createQueries =
        """
        create (p:Person {name: "Mark"})
        create (e1:Event {name: "Event1", timestamp: 1234})
        create (e2:Event {name: "Event2", timestamp: 4567})

        create (p)-[:EVENT]->(e1)
        create (p)-[:EVENT]->(e2)
        """
        
        let query = """
                    MATCH (p:Person)-[:EVENT]->(e)
                    RETURN p, COLLECT(e.name)
                    """
        
        try client.executeAsTransaction(mode: .readwrite, bookmark: nil, transactionBlock: { tx in
            let createResult = client.executeCypherSync(createQueries, params: [:])
            XCTAssertTrue(createResult.isSuccess)
            
            let queryResult = client.executeCypherSync(query, params: [:])
            XCTAssertTrue(queryResult.isSuccess)
            
            print(queryResult)
            
            tx.markAsFailed()
        }, transactionCompleteBlock: nil)
    }
    
    func testLukesSample() throws {
        
        let client = try makeClient()
        try client.executeAsTransaction(mode: .readwrite, bookmark: nil, transactionBlock: { tx in

            let createQuery = (0..<500).map { i in
                return "CREATE (t\(i):TestNode{value: \(Int.random(0, 150))})"
            }.joined(separator: "\n")
            let createResult = client.executeCypherSync(createQuery, params: [:])
            XCTAssert(createResult.isSuccess)
        
            let matchResult = client.executeCypherSync("MATCH (t:TestNode) RETURN COLLECT (t.value)", params: [:])
            XCTAssert(matchResult.isSuccess)
            guard case let Result.success(queryResult) = matchResult else {
                XCTFail("Got no result")
                return
            }
            
            let array = queryResult.rows
            let values = array
                .map{$0.values}
                .reduce([], +)
            
            print(values)

            tx.markAsFailed()
        }, transactionCompleteBlock: nil)
    }

}

