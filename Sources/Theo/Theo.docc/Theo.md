# ``Theo``

A Swift client library for Neo4j graph databases.

## Overview

Theo is a high-level Swift client for Neo4j that provides an intuitive API for working with graph data. It handles connection management, query execution, and result mapping to Swift objects.

### Key Features

- **Simple API**: Execute Cypher queries with minimal boilerplate
- **Connection Pooling**: ``BoltPoolClient`` provides efficient connection reuse
- **Type Safety**: Strong typing for nodes, relationships, and paths
- **Transaction Support**: ACID-compliant transaction handling
- **Async/Await**: Modern Swift concurrency support
- **TLS Support**: Secure connections with configurable certificate validation

### Quick Example

```swift
import Theo

// Create a client
let config = try JSONClientConfiguration(
    url: URL(string: "bolt://localhost:7687")!,
    username: "neo4j",
    password: "password"
)
let client = try BoltClient(configuration: config)

// Connect
try client.connectSync()

// Execute a query
let result = try client.executeCypherSync(
    "CREATE (n:Person {name: $name}) RETURN n",
    params: ["name": "Alice"]
)

// Process results
for node in result.nodes {
    print("Created: \(node.labels) - \(node.properties)")
}
```

## Topics

### Getting Started

- <doc:GettingStarted>
- <doc:WorkingWithGraphData>
- <doc:Transactions>

### Client Configuration

- ``ClientProtocol``
- ``BoltClient``
- ``BoltPoolClient``
- ``ClientConfigurationProtocol``
- ``JSONClientConfiguration``

### Graph Model

- ``Node``
- ``Relationship``
- ``Path``
- ``UnboundRelationship``

### Query Execution

- ``QueryWithParameters``
- ``Transaction``

### Result Handling

- ``QueryResult``
- ``ResponseItem``
