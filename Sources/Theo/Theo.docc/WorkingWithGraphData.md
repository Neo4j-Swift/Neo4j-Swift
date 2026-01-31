# Working with Graph Data

Learn how to work with nodes, relationships, and paths in Theo.

## Overview

Neo4j stores data as a graph consisting of nodes (entities) connected by relationships (edges). Theo provides Swift types to represent this data model.

### Nodes

Nodes represent entities in your graph. Each node can have:
- One or more **labels** (like types or categories)
- A set of **properties** (key-value pairs)

```swift
import Theo

// Query nodes
let result = try client.executeCypherSync(
    "MATCH (p:Person)-[:WORKS_AT]->(c:Company) RETURN p, c"
)

// Access nodes from results
for node in result.nodes {
    print("Labels: \(node.labels)")
    print("Properties: \(node.properties)")

    // Access specific properties
    if let name = node.properties["name"] as? String {
        print("Name: \(name)")
    }
}
```

### Relationships

Relationships connect nodes and have:
- A **type** (like "KNOWS", "WORKS_AT")
- A **direction** (from source to target node)
- **Properties** (optional key-value pairs)

```swift
let result = try client.executeCypherSync(
    "MATCH (a:Person)-[r:KNOWS]->(b:Person) RETURN a, r, b"
)

for relationship in result.relationships {
    print("Type: \(relationship.type)")
    print("From: \(relationship.fromNodeId)")
    print("To: \(relationship.toNodeId)")
    print("Properties: \(relationship.properties)")
}
```

### Paths

Paths represent a sequence of nodes and relationships:

```swift
let result = try client.executeCypherSync(
    "MATCH path = (a:Person)-[*1..3]-(b:Person) " +
    "WHERE a.name = 'Alice' AND b.name = 'Bob' " +
    "RETURN path"
)

for path in result.paths {
    print("Path length: \(path.segments.count)")

    // Iterate through segments
    for segment in path.segments {
        print("Node: \(segment.fromNode?.labels ?? [])")
        print("  -[\(segment.type)]->")
    }
}
```

### Creating Data

Create nodes and relationships with Cypher:

```swift
// Create a person
try client.executeCypherSync(
    "CREATE (p:Person {name: $name, email: $email})",
    params: [
        "name": "Alice",
        "email": "alice@example.com"
    ]
)

// Create a relationship
try client.executeCypherSync(
    """
    MATCH (a:Person {name: $person1}), (b:Person {name: $person2})
    CREATE (a)-[:KNOWS {since: $year}]->(b)
    """,
    params: [
        "person1": "Alice",
        "person2": "Bob",
        "year": 2020
    ]
)
```

### Updating Data

Update properties with SET:

```swift
try client.executeCypherSync(
    "MATCH (p:Person {name: $name}) SET p.age = $age",
    params: ["name": "Alice", "age": 31]
)
```

### Deleting Data

Remove nodes and relationships:

```swift
// Delete a relationship
try client.executeCypherSync(
    "MATCH (a:Person)-[r:KNOWS]->(b:Person) DELETE r"
)

// Delete a node (and its relationships)
try client.executeCypherSync(
    "MATCH (p:Person {name: $name}) DETACH DELETE p",
    params: ["name": "Alice"]
)
```

## Topics

### Model Types

- ``Node``
- ``Relationship``
- ``Path``
- ``UnboundRelationship``

### Results

- ``QueryResult``
- ``ResponseItem``
