# Getting Started with Theo

Learn how to connect to Neo4j and execute your first queries.

## Overview

Theo provides a simple interface for working with Neo4j graph databases from Swift. This guide covers the basics of establishing a connection and running queries.

### Installation

Add Theo to your Swift package:

```swift
dependencies: [
    .package(url: "https://github.com/Neo4j-Swift/Neo4j-Swift.git", from: "6.0.0")
]
```

### Creating a Client

Use ``JSONClientConfiguration`` to configure your connection:

```swift
import Theo

let config = try JSONClientConfiguration(
    url: URL(string: "bolt://localhost:7687")!,
    username: "neo4j",
    password: "your-password"
)

let client = try BoltClient(configuration: config)
```

For TLS connections (recommended for production):

```swift
let config = try JSONClientConfiguration(
    url: URL(string: "bolt+s://neo4j.example.com:7687")!,
    username: "neo4j",
    password: "your-password"
)
```

### Connecting

Connect synchronously:

```swift
let result = client.connectSync()
switch result {
case .success:
    print("Connected!")
case .failure(let error):
    print("Connection failed: \(error)")
}
```

Or asynchronously:

```swift
client.connect { result in
    switch result {
    case .success:
        print("Connected!")
    case .failure(let error):
        print("Connection failed: \(error)")
    }
}
```

### Executing Queries

Run Cypher queries using `executeCypher`:

```swift
// Create a node
try client.executeCypherSync(
    "CREATE (n:Person {name: $name, age: $age}) RETURN n",
    params: ["name": "Alice", "age": 30]
)

// Query nodes
let result = try client.executeCypherSync(
    "MATCH (n:Person) WHERE n.age > $minAge RETURN n",
    params: ["minAge": 25]
)

// Process results
for node in result.nodes {
    if let name = node.properties["name"] as? String {
        print("Found: \(name)")
    }
}
```

### Using Connection Pools

For applications with concurrent queries, use ``BoltPoolClient``:

```swift
let pool = try BoltPoolClient(
    hostname: "localhost",
    port: 7687,
    username: "neo4j",
    password: "password",
    encrypted: true,
    poolSize: 10
)

// Connections are automatically managed
try pool.executeCypherSync("MATCH (n) RETURN count(n)")
```

## Topics

### Client Types

- ``BoltClient``
- ``BoltPoolClient``
- ``ClientProtocol``

### Configuration

- ``JSONClientConfiguration``
- ``ClientConfigurationProtocol``
