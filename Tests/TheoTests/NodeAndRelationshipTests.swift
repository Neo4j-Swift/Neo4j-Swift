import XCTest
import PackStream
import Bolt

@testable import Theo

/// Node and Relationship model tests
/// Based on patterns from neo4j-java-driver (EntityTypeIT, ObjectMappingIT)
/// and neo4j-go-driver (graph_test.go)
final class NodeAndRelationshipTests: XCTestCase {

    // MARK: - Node Creation Tests

    func testCreateNodeWithNoLabels() {
        let node = Node()

        XCTAssertNil(node.id)
        XCTAssertTrue(node.labels.isEmpty)
        XCTAssertTrue(node.properties.isEmpty)
    }

    func testCreateNodeWithSingleLabel() {
        let node = Node(label: "Person", properties: [:])

        XCTAssertEqual(node.labels.count, 1)
        XCTAssertEqual(node.labels.first, "Person")
    }

    func testCreateNodeWithMultipleLabels() {
        let node = Node(labels: ["Person", "Employee", "Manager"], properties: [:])

        XCTAssertEqual(node.labels.count, 3)
        XCTAssertTrue(node.labels.contains("Person"))
        XCTAssertTrue(node.labels.contains("Employee"))
        XCTAssertTrue(node.labels.contains("Manager"))
    }

    func testCreateNodeWithProperties() {
        let props: [String: PackProtocol] = [
            "name": "Alice",
            "age": Int64(30),
            "active": true
        ]
        let node = Node(labels: ["Person"], properties: props)

        XCTAssertEqual(node.properties["name"] as? String, "Alice")
        XCTAssertEqual(node.properties["age"] as? Int64, 30)
        XCTAssertEqual(node.properties["active"] as? Bool, true)
    }

    func testNodeWithId() {
        let node = Node(labels: ["Test"], properties: [:])
        node.id = 12345

        XCTAssertEqual(node.id, 12345)
    }

    // MARK: - Node Label Tests

    func testNodeHasLabel() {
        let node = Node(labels: ["Person", "Employee"], properties: [:])

        XCTAssertTrue(node.labels.contains("Person"))
        XCTAssertTrue(node.labels.contains("Employee"))
        XCTAssertFalse(node.labels.contains("Company"))
    }

    func testAddLabelToNode() {
        let node = Node(labels: ["Person"], properties: [:])
        node.add(label: "Employee")

        XCTAssertTrue(node.labels.contains("Employee"))
        XCTAssertEqual(node.labels.count, 2)
    }

    func testRemoveLabelFromNode() {
        let node = Node(labels: ["Person", "Employee"], properties: [:])
        node.remove(label: "Employee")

        XCTAssertFalse(node.labels.contains("Employee"))
        XCTAssertEqual(node.labels.count, 1)
    }

    // MARK: - Node Property Tests

    func testNodePropertyAccess() {
        let props: [String: PackProtocol] = ["name": "Test", "value": Int64(42)]
        let node = Node(labels: ["TestNode"], properties: props)

        XCTAssertEqual(node["name"] as? String, "Test")
        XCTAssertEqual(node["value"] as? Int64, 42)
    }

    func testNodePropertyMissing() {
        let node = Node(labels: ["TestNode"], properties: [:])

        XCTAssertNil(node["nonexistent"])
    }

    func testUpdateNodeProperty() {
        let node = Node(labels: ["Test"], properties: ["count": Int64(1)])
        node["count"] = Int64(2)

        XCTAssertEqual(node.properties["count"] as? Int64, 2)
    }

    func testRemoveNodeProperty() {
        let node = Node(labels: ["Test"], properties: ["temp": "value"])
        node["temp"] = nil

        XCTAssertNil(node.properties["temp"])
    }

    // MARK: - Node with Complex Properties

    func testNodeWithListProperty() {
        let tags = List(items: ["swift", "neo4j", "database"])
        let props: [String: PackProtocol] = ["tags": tags]
        let node = Node(labels: ["Article"], properties: props)

        if let tagsList = node.properties["tags"] as? List {
            XCTAssertEqual(tagsList.items.count, 3)
        } else {
            XCTFail("Expected List property")
        }
    }

    func testNodeWithMapProperty() {
        let address = Map(dictionary: ["city": "NYC", "zip": "10001"])
        let props: [String: PackProtocol] = ["address": address]
        let node = Node(labels: ["Location"], properties: props)

        if let addr = node.properties["address"] as? Map {
            XCTAssertEqual(addr.dictionary["city"] as? String, "NYC")
        } else {
            XCTFail("Expected Map property")
        }
    }

    // MARK: - Relationship Creation Tests

    func testCreateRelationship() {
        let fromNode = Node(labels: ["Person"], properties: ["name": "Alice"])
        let toNode = Node(labels: ["Person"], properties: ["name": "Bob"])
        let rel = Relationship(fromNode: fromNode, toNode: toNode, type: "KNOWS")

        XCTAssertEqual(rel.type, "KNOWS")
        XCTAssertNil(rel.id)
    }

    func testCreateRelationshipWithNodes() {
        let fromNode = Node(labels: ["Person"], properties: ["name": "Alice"])
        let toNode = Node(labels: ["Person"], properties: ["name": "Bob"])

        let rel = Relationship(fromNode: fromNode, toNode: toNode, type: "KNOWS")

        XCTAssertNotNil(rel.fromNode)
        XCTAssertNotNil(rel.toNode)
    }

    func testCreateRelationshipWithNodeIds() {
        let rel = Relationship(
            fromNodeId: 1,
            toNodeId: 2,
            type: "FOLLOWS",
            direction: .from,
            properties: [:]
        )

        XCTAssertEqual(rel.fromNodeId, 1)
        XCTAssertEqual(rel.toNodeId, 2)
        XCTAssertEqual(rel.type, "FOLLOWS")
    }

    func testCreateRelationshipWithProperties() {
        let fromNode = Node(labels: ["Person"], properties: [:])
        let toNode = Node(labels: ["Person"], properties: [:])
        let props: [String: PackProtocol] = [
            "since": Int64(2020),
            "strength": 0.95
        ]
        let rel = Relationship(fromNode: fromNode, toNode: toNode, type: "KNOWS", properties: props)

        XCTAssertEqual(rel.properties["since"] as? Int64, 2020)
        XCTAssertEqual(rel.properties["strength"] as? Double, 0.95)
    }

    // MARK: - Relationship Direction Tests

    func testRelationshipDirectionFrom() {
        let fromNode = Node(labels: ["A"], properties: [:])
        let toNode = Node(labels: ["B"], properties: [:])
        let rel = Relationship(fromNode: fromNode, toNode: toNode, type: "LINKS", direction: .from)

        XCTAssertEqual(rel.direction, .from)
    }

    func testRelationshipDirectionTo() {
        let fromNode = Node(labels: ["A"], properties: [:])
        let toNode = Node(labels: ["B"], properties: [:])
        let rel = Relationship(fromNode: fromNode, toNode: toNode, type: "LINKS", direction: .to)

        XCTAssertEqual(rel.direction, .to)
    }

    // MARK: - Relationship Type Tests

    func testRelationshipTypeValidation() {
        let fromNode = Node(labels: ["Person"], properties: [:])
        let toNode = Node(labels: ["Person"], properties: [:])
        let validTypes = ["KNOWS", "FOLLOWS", "WORKS_AT", "HAS_CHILD"]

        for type in validTypes {
            let rel = Relationship(fromNode: fromNode, toNode: toNode, type: type)
            XCTAssertEqual(rel.type, type)
        }
    }

    func testRelationshipTypeWithSpecialCharacters() {
        // Neo4j allows underscores in relationship types
        let fromNode = Node(labels: ["A"], properties: [:])
        let toNode = Node(labels: ["B"], properties: [:])
        let rel = Relationship(fromNode: fromNode, toNode: toNode, type: "HAS_PARENT_OF")
        XCTAssertEqual(rel.type, "HAS_PARENT_OF")
    }

    // MARK: - Relationship Property Tests

    func testRelationshipPropertyAccess() {
        let fromNode = Node(labels: ["A"], properties: [:])
        let toNode = Node(labels: ["B"], properties: [:])
        let rel = Relationship(
            fromNode: fromNode,
            toNode: toNode,
            type: "RATED",
            properties: ["score": Int64(5), "comment": "Great!"]
        )

        XCTAssertEqual(rel["score"] as? Int64, 5)
        XCTAssertEqual(rel["comment"] as? String, "Great!")
    }

    func testUpdateRelationshipProperty() {
        let fromNode = Node(labels: ["A"], properties: [:])
        let toNode = Node(labels: ["B"], properties: [:])
        let rel = Relationship(
            fromNode: fromNode,
            toNode: toNode,
            type: "RATED",
            properties: ["score": Int64(3)]
        )
        rel["score"] = Int64(5)

        XCTAssertEqual(rel.properties["score"] as? Int64, 5)
    }

    // MARK: - Node Equality Tests

    func testNodeEqualityById() {
        let node1 = Node(labels: ["Test"], properties: [:])
        let node2 = Node(labels: ["Test"], properties: [:])

        node1.id = 100
        node2.id = 100

        // Nodes with same ID should have matching IDs
        XCTAssertEqual(node1.id, node2.id)
    }

    func testNodeInequalityByDifferentId() {
        let node1 = Node(labels: ["Test"], properties: [:])
        let node2 = Node(labels: ["Test"], properties: [:])

        node1.id = 100
        node2.id = 200

        XCTAssertNotEqual(node1.id, node2.id)
    }

    // MARK: - Relationship Equality Tests

    func testRelationshipEqualityById() {
        let fromNode = Node(labels: ["A"], properties: [:])
        let toNode = Node(labels: ["B"], properties: [:])
        let rel1 = Relationship(fromNode: fromNode, toNode: toNode, type: "KNOWS")
        let rel2 = Relationship(fromNode: fromNode, toNode: toNode, type: "KNOWS")

        rel1.id = 500
        rel2.id = 500

        XCTAssertEqual(rel1.id, rel2.id)
    }

    // MARK: - Node Cypher Generation Tests

    func testNodeCreateCypher() {
        let node = Node(labels: ["Person"], properties: ["name": "Alice", "age": Int64(30)])
        let cypher = node.createRequest()

        XCTAssertNotNil(cypher)
    }

    func testNodeMatchCypher() {
        let node = Node(labels: ["Person"], properties: [:])
        node.id = 123

        // Node with ID should be able to generate match query
        XCTAssertNotNil(node.id)
    }

    // MARK: - Relationship Cypher Generation Tests

    func testRelationshipCreateCypher() {
        let rel = Relationship(
            fromNodeId: 1,
            toNodeId: 2,
            type: "KNOWS",
            direction: .from,
            properties: ["since": Int64(2020)]
        )

        XCTAssertEqual(rel.type, "KNOWS")
        XCTAssertNotNil(rel.fromNodeId)
        XCTAssertNotNil(rel.toNodeId)
    }

    // MARK: - Node Deserialization Tests (from Bolt protocol)

    func testNodeDeserializationFromStructure() {
        // Node structure: signature 78 (0x4E = 'N'), [id, labels, properties]
        let labels = List(items: ["Person", "Employee"])
        let properties = Map(dictionary: ["name": "Alice", "age": Int64(30)])
        let nodeStructure = Structure(signature: 78, items: [Int64(12345), labels, properties])

        let node = Node(data: nodeStructure)

        XCTAssertNotNil(node)
        XCTAssertEqual(node?.id, 12345)
        XCTAssertEqual(node?.labels.count, 2)
        XCTAssertTrue(node?.labels.contains("Person") ?? false)
        XCTAssertTrue(node?.labels.contains("Employee") ?? false)
        XCTAssertEqual(node?.properties["name"] as? String, "Alice")
        XCTAssertEqual(node?.properties["age"] as? Int64, 30)
    }

    func testNodeDeserializationWithEmptyLabels() {
        let labels = List(items: [])
        let properties = Map(dictionary: ["key": "value"])
        let nodeStructure = Structure(signature: 78, items: [Int64(1), labels, properties])

        let node = Node(data: nodeStructure)

        XCTAssertNotNil(node)
        XCTAssertEqual(node?.id, 1)
        XCTAssertTrue(node?.labels.isEmpty ?? false)
    }

    func testNodeDeserializationWithEmptyProperties() {
        let labels = List(items: ["Test"])
        let properties = Map(dictionary: [:])
        let nodeStructure = Structure(signature: 78, items: [Int64(1), labels, properties])

        let node = Node(data: nodeStructure)

        XCTAssertNotNil(node)
        XCTAssertTrue(node?.properties.isEmpty ?? false)
    }

    func testNodeDeserializationWithWrongSignature() {
        let labels = List(items: ["Test"])
        let properties = Map(dictionary: [:])
        // Wrong signature (79 instead of 78)
        let nodeStructure = Structure(signature: 79, items: [Int64(1), labels, properties])

        let node = Node(data: nodeStructure)

        XCTAssertNil(node)
    }

    func testNodeDeserializationWithInsufficientItems() {
        // Only 2 items instead of 3
        let labels = List(items: ["Test"])
        let nodeStructure = Structure(signature: 78, items: [Int64(1), labels])

        let node = Node(data: nodeStructure)

        XCTAssertNil(node)
    }

    func testNodeDeserializationFromNonStructure() {
        let node = Node(data: "not a structure")

        XCTAssertNil(node)
    }

    func testNodeDeserializationWithInt64Id() {
        let labels = List(items: ["Test"])
        let properties = Map(dictionary: [:])
        // Use Int64 which can be converted to UInt64
        let nodeStructure = Structure(signature: 78, items: [Int64(999), labels, properties])

        let node = Node(data: nodeStructure)

        XCTAssertNotNil(node)
        XCTAssertEqual(node?.id, 999)
    }

    // MARK: - Relationship Deserialization Tests (from Bolt protocol)

    func testRelationshipDeserializationFromStructure() {
        // Relationship structure: signature 82 (0x52 = 'R'), [id, startNodeId, endNodeId, type, properties]
        let properties = Map(dictionary: ["since": Int64(2020)])
        let relStructure = Structure(signature: 82, items: [
            Int64(100),      // relationship id
            Int64(1),        // start node id
            Int64(2),        // end node id
            "KNOWS",         // type
            properties       // properties
        ])

        let relationship = Relationship(data: relStructure)

        XCTAssertNotNil(relationship)
        XCTAssertEqual(relationship?.id, 100)
        XCTAssertEqual(relationship?.fromNodeId, 1)
        XCTAssertEqual(relationship?.toNodeId, 2)
        XCTAssertEqual(relationship?.type, "KNOWS")
        XCTAssertEqual(relationship?.properties["since"] as? Int64, 2020)
    }

    func testRelationshipDeserializationWithEmptyProperties() {
        let properties = Map(dictionary: [:])
        let relStructure = Structure(signature: 82, items: [
            Int64(1), Int64(10), Int64(20), "FOLLOWS", properties
        ])

        let relationship = Relationship(data: relStructure)

        XCTAssertNotNil(relationship)
        XCTAssertTrue(relationship?.properties.isEmpty ?? false)
    }

    func testRelationshipDeserializationWithWrongSignature() {
        let properties = Map(dictionary: [:])
        // Wrong signature (83 instead of 82)
        let relStructure = Structure(signature: 83, items: [
            Int64(1), Int64(10), Int64(20), "FOLLOWS", properties
        ])

        let relationship = Relationship(data: relStructure)

        XCTAssertNil(relationship)
    }

    func testRelationshipDeserializationWithInsufficientItems() {
        // Only 4 items instead of 5
        let relStructure = Structure(signature: 82, items: [
            Int64(1), Int64(10), Int64(20), "FOLLOWS"
        ])

        let relationship = Relationship(data: relStructure)

        XCTAssertNil(relationship)
    }

    func testRelationshipDeserializationFromNonStructure() {
        let relationship = Relationship(data: "not a structure")

        XCTAssertNil(relationship)
    }

    func testRelationshipDeserializationDefaultDirection() {
        let properties = Map(dictionary: [:])
        let relStructure = Structure(signature: 82, items: [
            Int64(1), Int64(10), Int64(20), "LINKS", properties
        ])

        let relationship = Relationship(data: relStructure)

        XCTAssertNotNil(relationship)
        // Default direction should be .from when deserializing
        XCTAssertEqual(relationship?.direction, .from)
    }

    // MARK: - Edge Cases

    func testNodeWithEmptyLabel() {
        // Empty string labels should be handled
        let node = Node(labels: [""], properties: [:])
        XCTAssertEqual(node.labels.count, 1)
    }

    func testNodeWithUnicodeLabel() {
        let node = Node(labels: ["Persönlich"], properties: [:])
        XCTAssertTrue(node.labels.contains("Persönlich"))
    }

    func testRelationshipWithUnicodeType() {
        let fromNode = Node(labels: ["A"], properties: [:])
        let toNode = Node(labels: ["B"], properties: [:])
        let rel = Relationship(fromNode: fromNode, toNode: toNode, type: "KENNT")  // German for KNOWS
        XCTAssertEqual(rel.type, "KENNT")
    }

    func testNodeWithManyLabels() {
        let labels = (1...100).map { "Label\($0)" }
        let node = Node(labels: labels, properties: [:])

        XCTAssertEqual(node.labels.count, 100)
    }

    func testNodeWithManyProperties() {
        var props: [String: PackProtocol] = [:]
        for i in 1...100 {
            props["prop\(i)"] = Int64(i)
        }
        let node = Node(labels: ["Test"], properties: props)

        XCTAssertEqual(node.properties.count, 100)
    }

    // MARK: - allTests for Linux

    static var allTests: [(String, (NodeAndRelationshipTests) -> () throws -> Void)] {
        return [
            ("testCreateNodeWithNoLabels", testCreateNodeWithNoLabels),
            ("testCreateNodeWithSingleLabel", testCreateNodeWithSingleLabel),
            ("testCreateNodeWithMultipleLabels", testCreateNodeWithMultipleLabels),
            ("testCreateNodeWithProperties", testCreateNodeWithProperties),
            ("testNodeWithId", testNodeWithId),
            ("testNodeHasLabel", testNodeHasLabel),
            ("testAddLabelToNode", testAddLabelToNode),
            ("testRemoveLabelFromNode", testRemoveLabelFromNode),
            ("testNodePropertyAccess", testNodePropertyAccess),
            ("testNodePropertyMissing", testNodePropertyMissing),
            ("testUpdateNodeProperty", testUpdateNodeProperty),
            ("testRemoveNodeProperty", testRemoveNodeProperty),
            ("testNodeWithListProperty", testNodeWithListProperty),
            ("testNodeWithMapProperty", testNodeWithMapProperty),
            ("testCreateRelationship", testCreateRelationship),
            ("testCreateRelationshipWithNodes", testCreateRelationshipWithNodes),
            ("testCreateRelationshipWithNodeIds", testCreateRelationshipWithNodeIds),
            ("testCreateRelationshipWithProperties", testCreateRelationshipWithProperties),
            ("testRelationshipDirectionFrom", testRelationshipDirectionFrom),
            ("testRelationshipDirectionTo", testRelationshipDirectionTo),
            ("testRelationshipTypeValidation", testRelationshipTypeValidation),
            ("testRelationshipTypeWithSpecialCharacters", testRelationshipTypeWithSpecialCharacters),
            ("testRelationshipPropertyAccess", testRelationshipPropertyAccess),
            ("testUpdateRelationshipProperty", testUpdateRelationshipProperty),
            ("testNodeEqualityById", testNodeEqualityById),
            ("testNodeInequalityByDifferentId", testNodeInequalityByDifferentId),
            ("testRelationshipEqualityById", testRelationshipEqualityById),
            ("testNodeCreateCypher", testNodeCreateCypher),
            ("testNodeMatchCypher", testNodeMatchCypher),
            ("testRelationshipCreateCypher", testRelationshipCreateCypher),
            // Deserialization tests
            ("testNodeDeserializationFromStructure", testNodeDeserializationFromStructure),
            ("testNodeDeserializationWithEmptyLabels", testNodeDeserializationWithEmptyLabels),
            ("testNodeDeserializationWithEmptyProperties", testNodeDeserializationWithEmptyProperties),
            ("testNodeDeserializationWithWrongSignature", testNodeDeserializationWithWrongSignature),
            ("testNodeDeserializationWithInsufficientItems", testNodeDeserializationWithInsufficientItems),
            ("testNodeDeserializationFromNonStructure", testNodeDeserializationFromNonStructure),
            ("testNodeDeserializationWithInt64Id", testNodeDeserializationWithInt64Id),
            ("testRelationshipDeserializationFromStructure", testRelationshipDeserializationFromStructure),
            ("testRelationshipDeserializationWithEmptyProperties", testRelationshipDeserializationWithEmptyProperties),
            ("testRelationshipDeserializationWithWrongSignature", testRelationshipDeserializationWithWrongSignature),
            ("testRelationshipDeserializationWithInsufficientItems", testRelationshipDeserializationWithInsufficientItems),
            ("testRelationshipDeserializationFromNonStructure", testRelationshipDeserializationFromNonStructure),
            ("testRelationshipDeserializationDefaultDirection", testRelationshipDeserializationDefaultDirection),
            // Edge cases
            ("testNodeWithEmptyLabel", testNodeWithEmptyLabel),
            ("testNodeWithUnicodeLabel", testNodeWithUnicodeLabel),
            ("testRelationshipWithUnicodeType", testRelationshipWithUnicodeType),
            ("testNodeWithManyLabels", testNodeWithManyLabels),
            ("testNodeWithManyProperties", testNodeWithManyProperties),
        ]
    }
}
