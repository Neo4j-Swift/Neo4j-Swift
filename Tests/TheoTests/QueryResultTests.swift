import XCTest
import PackStream
import Bolt

@testable import Theo

/// Query result handling tests
/// Based on patterns from neo4j-java-driver (ResultStreamIT, QueryIT)
/// and neo4j-go-driver (result_test.go)
final class QueryResultTests: XCTestCase {

    // MARK: - QueryResult Structure Tests

    func testEmptyQueryResult() {
        let result = QueryResult()

        XCTAssertTrue(result.fields.isEmpty)
        XCTAssertTrue(result.rows.isEmpty)
        XCTAssertTrue(result.nodes.isEmpty)
        XCTAssertTrue(result.relationships.isEmpty)
        XCTAssertTrue(result.paths.isEmpty)
    }

    func testQueryResultWithFields() {
        let result = QueryResult(fields: ["name", "age", "active"])

        XCTAssertEqual(result.fields.count, 3)
        XCTAssertEqual(result.fields[0], "name")
        XCTAssertEqual(result.fields[1], "age")
        XCTAssertEqual(result.fields[2], "active")
    }

    func testQueryResultFieldOrder() {
        // Based on Go driver - fields should maintain order
        let result = QueryResult(fields: ["a", "b", "c", "d", "e"])

        XCTAssertEqual(result.fields.first, "a")
        XCTAssertEqual(result.fields.last, "e")
    }

    // MARK: - Row Access Tests

    func testMultipleRows() {
        let result = QueryResult(fields: ["id", "name"])

        // Add rows manually
        let node1 = Node(labels: ["Person"], properties: ["name": "Alice"])
        let node2 = Node(labels: ["Person"], properties: ["name": "Bob"])

        result.rows.append(["n": node1])
        result.rows.append(["n": node2])

        XCTAssertEqual(result.rows.count, 2)
    }

    // MARK: - Node Result Tests

    func testQueryResultWithNodes() {
        let node = Node(labels: ["Person"], properties: ["name": "Alice", "age": Int64(30)])
        node.id = 1

        let result = QueryResult(nodes: [1: node])

        XCTAssertEqual(result.nodes.count, 1)
        XCTAssertEqual(result.nodes[1]?.id, 1)
        XCTAssertEqual(result.nodes[1]?.labels.first, "Person")
    }

    func testQueryResultWithMultipleNodes() {
        var nodes: [UInt64: Node] = [:]
        for i: UInt64 in 1...10 {
            let node = Node(labels: ["TestNode"], properties: ["index": Int64(i)])
            node.id = i
            nodes[i] = node
        }

        let result = QueryResult(nodes: nodes)

        XCTAssertEqual(result.nodes.count, 10)
    }

    // MARK: - Relationship Result Tests

    func testQueryResultWithRelationships() {
        let fromNode = Node(labels: ["Person"], properties: [:])
        let toNode = Node(labels: ["Person"], properties: [:])
        let rel = Relationship(fromNode: fromNode, toNode: toNode, type: "KNOWS", properties: ["since": Int64(2020)])
        rel.id = 100

        let result = QueryResult(relationships: [100: rel])

        XCTAssertEqual(result.relationships.count, 1)
        XCTAssertEqual(result.relationships[100]?.type, "KNOWS")
    }

    // MARK: - QueryStats Tests

    func testQueryStatsNodesCreated() {
        let stats = QueryStats(nodesCreatedCount: 5)

        XCTAssertEqual(stats.nodesCreatedCount, 5)
    }

    func testQueryStatsPropertiesSet() {
        let stats = QueryStats(propertiesSetCount: 15)

        XCTAssertEqual(stats.propertiesSetCount, 15)
    }

    func testQueryStatsLabelsAdded() {
        let stats = QueryStats(labelsAddedCount: 4)

        XCTAssertEqual(stats.labelsAddedCount, 4)
    }

    func testQueryStatsType() {
        let stats = QueryStats(type: "r")  // read-only
        XCTAssertEqual(stats.type, "r")
    }

    func testQueryStatsResultTiming() {
        let stats = QueryStats(resultAvailableAfter: 100, resultConsumedAfter: 150)

        XCTAssertEqual(stats.resultAvailableAfter, 100)
        XCTAssertEqual(stats.resultConsumedAfter, 150)
    }

    // MARK: - Result Iteration Tests

    func testIterateOverEmptyResult() {
        let result = QueryResult()

        var count = 0
        for _ in result.rows {
            count += 1
        }

        XCTAssertEqual(count, 0)
    }

    func testIterateOverRows() {
        let result = QueryResult(fields: ["value"])

        for i in 1...100 {
            let node = Node(labels: ["N"], properties: ["value": Int64(i)])
            result.rows.append(["n": node])
        }

        XCTAssertEqual(result.rows.count, 100)
    }

    // MARK: - Large Result Tests (based on Java driver)

    func testLargeResultSet() {
        let result = QueryResult(fields: ["id"])

        // Simulate large result set (10,000 rows)
        for i in 1...10_000 {
            let node = Node(labels: ["N"], properties: ["id": Int64(i)])
            result.rows.append(["n": node])
        }

        XCTAssertEqual(result.rows.count, 10_000)
    }

    // MARK: - Result with All Components

    func testCompleteQueryResult() {
        // Set up nodes
        let node1 = Node(labels: ["Person"], properties: ["name": "Alice"])
        node1.id = 1
        let node2 = Node(labels: ["Person"], properties: ["name": "Bob"])
        node2.id = 2
        let nodes: [UInt64: Node] = [1: node1, 2: node2]

        // Set up relationship
        let rel = Relationship(fromNode: node1, toNode: node2, type: "KNOWS")
        rel.id = 100
        let relationships: [UInt64: Relationship] = [100: rel]

        // Set up stats
        let stats = QueryStats(
            propertiesSetCount: 2,
            labelsAddedCount: 2,
            nodesCreatedCount: 2,
            type: "w"
        )

        // Create complete result
        let result = QueryResult(
            fields: ["n", "r", "m"],
            stats: stats,
            nodes: nodes,
            relationships: relationships
        )

        // Verify all components
        XCTAssertEqual(result.fields.count, 3)
        XCTAssertEqual(result.nodes.count, 2)
        XCTAssertEqual(result.relationships.count, 1)
        XCTAssertEqual(result.stats.nodesCreatedCount, 2)
        XCTAssertEqual(result.stats.type, "w")
    }

    // MARK: - Node Access Tests

    func testAccessNodeById() {
        let node = Node(labels: ["Test"], properties: ["value": Int64(42)])
        node.id = 123

        let result = QueryResult(nodes: [123: node])

        XCTAssertNotNil(result.nodes[123])
        XCTAssertEqual(result.nodes[123]?.properties["value"] as? Int64, 42)
    }

    func testAccessNonExistentNode() {
        let result = QueryResult()

        XCTAssertNil(result.nodes[999])
    }

    // MARK: - Relationship Access Tests

    func testAccessRelationshipById() {
        let fromNode = Node(labels: ["A"], properties: [:])
        let toNode = Node(labels: ["B"], properties: [:])
        let rel = Relationship(fromNode: fromNode, toNode: toNode, type: "LINKS")
        rel.id = 456

        let result = QueryResult(relationships: [456: rel])

        XCTAssertNotNil(result.relationships[456])
        XCTAssertEqual(result.relationships[456]?.type, "LINKS")
    }

    // MARK: - allTests for Linux

    static var allTests: [(String, (QueryResultTests) -> () throws -> Void)] {
        return [
            ("testEmptyQueryResult", testEmptyQueryResult),
            ("testQueryResultWithFields", testQueryResultWithFields),
            ("testQueryResultFieldOrder", testQueryResultFieldOrder),
            ("testMultipleRows", testMultipleRows),
            ("testQueryResultWithNodes", testQueryResultWithNodes),
            ("testQueryResultWithMultipleNodes", testQueryResultWithMultipleNodes),
            ("testQueryResultWithRelationships", testQueryResultWithRelationships),
            ("testQueryStatsNodesCreated", testQueryStatsNodesCreated),
            ("testQueryStatsPropertiesSet", testQueryStatsPropertiesSet),
            ("testQueryStatsLabelsAdded", testQueryStatsLabelsAdded),
            ("testQueryStatsType", testQueryStatsType),
            ("testQueryStatsResultTiming", testQueryStatsResultTiming),
            ("testIterateOverEmptyResult", testIterateOverEmptyResult),
            ("testIterateOverRows", testIterateOverRows),
            ("testLargeResultSet", testLargeResultSet),
            ("testCompleteQueryResult", testCompleteQueryResult),
            ("testAccessNodeById", testAccessNodeById),
            ("testAccessNonExistentNode", testAccessNonExistentNode),
            ("testAccessRelationshipById", testAccessRelationshipById),
        ]
    }
}
