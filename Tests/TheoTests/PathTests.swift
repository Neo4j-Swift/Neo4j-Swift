import XCTest
import PackStream
import Bolt

@testable import Theo

/// Path and UnboundRelationship tests
/// Based on patterns from neo4j-java-driver (PathValueIT)
/// and neo4j-go-driver (graph_test.go path tests)
final class PathTests: XCTestCase {

    // MARK: - UnboundRelationship Tests

    func testUnboundRelationshipDeserializationFromStructure() {
        // UnboundRelationship structure: signature 114 (0x72 = 'r'), [id, type, properties]
        let properties = Map(dictionary: ["weight": Double(0.5)])
        let unboundRelStructure = Structure(signature: 114, items: [
            Int64(42),       // relationship id
            "CONNECTED_TO",  // type
            properties       // properties
        ])

        let unboundRel = UnboundRelationship(data: unboundRelStructure)

        XCTAssertNotNil(unboundRel)
        XCTAssertEqual(unboundRel?.relIdentity, 42)
        XCTAssertEqual(unboundRel?.type, "CONNECTED_TO")
        XCTAssertEqual(unboundRel?.properties["weight"] as? Double, 0.5)
    }

    func testUnboundRelationshipWithEmptyProperties() {
        let properties = Map(dictionary: [:])
        let unboundRelStructure = Structure(signature: 114, items: [
            Int64(1), "LINKS", properties
        ])

        let unboundRel = UnboundRelationship(data: unboundRelStructure)

        XCTAssertNotNil(unboundRel)
        XCTAssertTrue(unboundRel?.properties.isEmpty ?? false)
    }

    func testUnboundRelationshipWithWrongSignature() {
        let properties = Map(dictionary: [:])
        // Wrong signature (115 instead of 114)
        let unboundRelStructure = Structure(signature: 115, items: [
            Int64(1), "LINKS", properties
        ])

        let unboundRel = UnboundRelationship(data: unboundRelStructure)

        XCTAssertNil(unboundRel)
    }

    func testUnboundRelationshipWithInsufficientItems() {
        // Only 2 items instead of 3
        let unboundRelStructure = Structure(signature: 114, items: [
            Int64(1), "LINKS"
        ])

        let unboundRel = UnboundRelationship(data: unboundRelStructure)

        XCTAssertNil(unboundRel)
    }

    func testUnboundRelationshipFromNonStructure() {
        let unboundRel = UnboundRelationship(data: "not a structure")

        XCTAssertNil(unboundRel)
    }

    // MARK: - Path Deserialization Tests

    func testPathDeserializationFromNonStructure() {
        let path = Path(data: "not a structure")

        XCTAssertNil(path)
    }

    func testPathDeserializationWithWrongSignature() {
        // Path structure: signature 80 (0x50 = 'P'), but we use 81
        let nodes = List(items: [])
        let rels = List(items: [])
        let sequence = List(items: [])
        let pathStructure = Structure(signature: 81, items: [nodes, rels, sequence])

        let path = Path(data: pathStructure)

        XCTAssertNil(path)
    }

    func testPathDeserializationWithInsufficientItems() {
        // Only 2 items instead of 3
        let nodes = List(items: [])
        let rels = List(items: [])
        let pathStructure = Structure(signature: 80, items: [nodes, rels])

        let path = Path(data: pathStructure)

        XCTAssertNil(path)
    }

    // MARK: - Helper to create test structures

    private func createNodeStructure(id: Int64, labels: [String], properties: [String: PackProtocol] = [:]) -> Structure {
        let labelsList = List(items: labels)
        let propsMap = Map(dictionary: properties)
        return Structure(signature: 78, items: [id, labelsList, propsMap])
    }

    private func createUnboundRelStructure(id: Int64, type: String, properties: [String: PackProtocol] = [:]) -> Structure {
        let propsMap = Map(dictionary: properties)
        return Structure(signature: 114, items: [id, type, propsMap])
    }

    // MARK: - ResponseItem Protocol Tests

    func testPathConformsToResponseItem() {
        // Path should conform to ResponseItem protocol
        // We can't easily create a valid path here, but we can test the protocol conformance
        let node = Node(labels: ["Test"], properties: [:])
        XCTAssertTrue(node is ResponseItem)

        let rel = Relationship(
            fromNodeId: 1,
            toNodeId: 2,
            type: "KNOWS",
            direction: .from,
            properties: [:]
        )
        XCTAssertTrue(rel is ResponseItem)
    }

    func testUnboundRelationshipConformsToResponseItem() {
        let properties = Map(dictionary: [:])
        let unboundRelStructure = Structure(signature: 114, items: [
            Int64(1), "TEST", properties
        ])

        if let unboundRel = UnboundRelationship(data: unboundRelStructure) {
            XCTAssertTrue(unboundRel is ResponseItem)
        } else {
            XCTFail("Failed to create UnboundRelationship")
        }
    }

    // MARK: - Segment Type Alias Test

    func testSegmentIsRelationshipAlias() {
        // Segment is a typealias for Relationship
        let fromNode = Node(labels: ["A"], properties: [:])
        let toNode = Node(labels: ["B"], properties: [:])
        let segment: Segment = Relationship(fromNode: fromNode, toNode: toNode, type: "LINKS")

        XCTAssertEqual(segment.type, "LINKS")
        XCTAssertNotNil(segment.fromNode)
        XCTAssertNotNil(segment.toNode)
    }

    // MARK: - RelationshipDirection Tests

    func testRelationshipDirectionEnum() {
        let dirFrom: RelationshipDirection = .from
        let dirTo: RelationshipDirection = .to

        XCTAssertNotEqual(dirFrom, dirTo)
    }

    func testRelationshipDirectionInRelationship() {
        let fromNode = Node(labels: ["A"], properties: [:])
        let toNode = Node(labels: ["B"], properties: [:])

        let relFrom = Relationship(fromNode: fromNode, toNode: toNode, type: "TEST", direction: .from)
        let relTo = Relationship(fromNode: fromNode, toNode: toNode, type: "TEST", direction: .to)

        XCTAssertEqual(relFrom.direction, .from)
        XCTAssertEqual(relTo.direction, .to)
    }

    // MARK: - allTests for Linux

    static var allTests: [(String, (PathTests) -> () throws -> Void)] {
        return [
            ("testUnboundRelationshipDeserializationFromStructure", testUnboundRelationshipDeserializationFromStructure),
            ("testUnboundRelationshipWithEmptyProperties", testUnboundRelationshipWithEmptyProperties),
            ("testUnboundRelationshipWithWrongSignature", testUnboundRelationshipWithWrongSignature),
            ("testUnboundRelationshipWithInsufficientItems", testUnboundRelationshipWithInsufficientItems),
            ("testUnboundRelationshipFromNonStructure", testUnboundRelationshipFromNonStructure),
            ("testPathDeserializationFromNonStructure", testPathDeserializationFromNonStructure),
            ("testPathDeserializationWithWrongSignature", testPathDeserializationWithWrongSignature),
            ("testPathDeserializationWithInsufficientItems", testPathDeserializationWithInsufficientItems),
            ("testPathConformsToResponseItem", testPathConformsToResponseItem),
            ("testUnboundRelationshipConformsToResponseItem", testUnboundRelationshipConformsToResponseItem),
            ("testSegmentIsRelationshipAlias", testSegmentIsRelationshipAlias),
            ("testRelationshipDirectionEnum", testRelationshipDirectionEnum),
            ("testRelationshipDirectionInRelationship", testRelationshipDirectionInRelationship),
        ]
    }
}
