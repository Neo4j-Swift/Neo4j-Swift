## Theo
*Thomas Anderson is a computer programmer who maintains a double life as "Neo" the hacker. - Combination of Neo and Thomas*

## Summary

**Theo** is an open-source [Neo4j](http://neo4j.com/) Swift interface.

## Features

* CRUD operations for Nodes and Relationships
* Transaction statement execution
* Supports iOS, tvOS, macOS, watchOS and Linux

## Requirements

* macOS 14+ / iOS 17+ / tvOS 17+ / watchOS 10+ / Linux
* Swift 6.0+

## Feedback

Because this framework is open source it is best for most situations to post on Stack Overflow and tag it **[Theo](http://stackoverflow.com/questions/tagged/neo4j-swift)**. If you do
find a bug please file an issue or issue a PR for any features or fixes.
You are also most welcome to join the conversation in the #neo4j-swift channel in the [neo4j-users Slack](http://neo4j-users-slack-invite.herokuapp.com)

## Installation

### Swift Package Manager
Add the following line to your Package dependencies array:

```swift
.package(url: "https://github.com/Neo4j-Swift/Neo4j-Swift.git", from: "6.0.0")
```
Run `swift build` to build your project, now with Theo included and ready to be used from your source

## Usage
If you prefer just code-examples to get started, check out [theo-example](https://github.com/Neo4j-Swift/theo-example) that is updated to match the current version of Theo.

### Initalization

To get started, you need to set up a BoltClient with the connection information to your Neo4j instance. You could for instance load a JSON into a dictionary, and then pass any values that should overrid the defaults, like this:

```swift
let config = ["password": "<passcode>"]
let client = try BoltClient(JSONClientConfiguration(json: config))
```

Or you can provide your on ClientConfiguration-based class, or even set them all manually:

```swift
let client = try BoltClient(hostname: "localhost",
                                port: 6787,
                            username: "neo4j",
                            password: "<passcode>",
                           encrypted: true)
```


### Create and save a node

```swift
// Create the node
let node = Node(label: "Character", properties: ["name": "Thomas Anderson", "alias": "Neo" ])

// Save the node
do {
    try await client.createNode(node: node)
    print("Node saved successfully")
} catch {
    print(error.localizedDescription)
}
```

There's also `createAndReturnNode()` if you need the created node back, and `createNodes()` / `createAndReturnNodes()` for creating multiple nodes at once. Sync variants are available for all methods (e.g., `createNodeSync()`).

### Fetch a node via id

```swift
do {
    if let foundNode = try await client.nodeBy(id: 42) {
        print("Successfully found node \(foundNode)")
    } else {
        print("There was no node with id 42")
    }
} catch {
    print(error.localizedDescription)
}
```

### Updating a node
Given the variable 'node' with an existing node, we might want to update it. Let's add a label:

```swift
node.add(label: "AnotherLabel")
```

or add a few properties:
```swift
node["age"] = 42
node["color"] = "white"
```

and then


```swift
do {
    try await client.updateNode(node: node)
    print("Node updated successfully")
} catch {
    print(error.localizedDescription)
}
```

### Deleting a node

Likewise, given the variable 'node' with an existing node, when we no longer want the data,
we might want to delete it all together:

```swift
do {
    try await client.deleteNode(node: node)
    print("Node deleted successfully")
} catch {
    print(error.localizedDescription)
}
```

Note that in Neo4j, to delete a node all relationships this node participates in should be deleted first. However, you can force a delete by calling "DETACH DELETE", and it will then remove all the relationships the node participates in as well. Since this is an exception to the rule, there is no helper function for this. But with Theo, running an arbitrary Cypher statement is easy:

```swift
guard let id = node.id else { return }
let query = """
            MATCH (n) WHERE id(n) = $id DETACH DELETE n
            """
do {
    try await client.executeCypher(query, params: ["id": Int64(id)])
    print("Node deleted successfully")
} catch {
    print("Something went wrong while deleting the node")
}
```

### Fetch nodes matching labels and property values

```swift
let labels = ["Father", "Husband"]
let properties: [String:PackProtocol] = [
    "firstName": "Niklas",
    "age": 38
]

let nodes = try await client.nodesWith(labels: labels, andProperties: properties)
print("Found \(nodes.count) nodes")
```

### Create a relationship
Given two nodes reader and writer, making a relationship with the type "follows" is easy:

```swift
try await client.relate(node: reader, to: writer, type: "follows")
print("Relationship successfully created")
```

You can also create a relationship object directly:

```swift
let relationship = Relationship(fromNode: from, toNode: to, type: "Married to")
let created = try await client.createAndReturnRelationship(relationship: relationship)
print("Successfully created relationship \(created)")
```

Note that if one or both of the nodes in a relationship have not been created in advance, they will be created together with the relationship.

### Updating properties on a relationship

Having fetched a relationship as part of a query, you can edit properties on that relationship:

```swift
relationship["someKey"] = "someValue"
relationship["otherKey"] = 42
let updated = try await client.updateAndReturnRelationship(relationship: relationship)
print("Successfully updated relationship \(updated)")
```

### Deleting a relationship

And finally, you can remove the relationship altogether:

```swift
try await client.deleteRelationship(relationship: relationship)
print("Successfully deleted the relationship")
```

### Execute a transaction
Transactions allow you to run multiple operations atomically and roll back if something goes wrong:

```swift
try await client.executeAsTransaction { tx in
    try await client.executeCypher("MATCH (n) SET n.abra = 'kadabra'")
    try await client.executeCypher("MATCH (n:Person) WHERE n.name = 'Guy' SET n.likeable = true")
    let result = try await client.executeCypher("MATCH (n:Person) WHERE n.name = 'Guy' AND n.abra='kadabra' SET n.starRating = 5")
    if (result.stats.propertiesSetCount) == 0 {
        tx.markAsFailed()
    }
}
```

### Execute a cypher query
In the example above, we already executed a few cypher queries. In the following example, we execute a longer cypher example with named parameters, where we'll supply the parameters along side the query:

```swift
let query = """
            MATCH (u:User {username: $user }) WITH u
            MATCH (u)-[:FOLLOWS*0..1]->(f) WITH DISTINCT f,u
            MATCH (f)-[:LASTPOST]-(lp)-[:NEXTPOST*0..3]-(p)
            RETURN p.contentId as contentId, p.title as title, p.tagstr as tagstr, p.timestamp as timestamp, p.url as url, f.username as username, f=u as owner
            """
let params: [String:PackProtocol] = ["user": "ajordan"]
do {
    let result = try await client.executeCypher(query, params: params)
    print("Successfully ran query with \(result.rows.count) rows")
} catch {
    print("Got an error: \(error)")
}
```

## Integration Tests

### Setup

There is a file called, `TheoBoltConfig.json.example` which you should copy to `TheoBoltConfig.json`. You can edit this configuration with connection settings to your Neo4j instance, and the test classes using these instead of having to modify any *actual* class files. `TheoBoltConfig.json` is in the `.gitignore` so you don't have to worry about creds being committed.

### Execution

* Select the unit test target
* Hit `CMD-U`

## Authors

* [Niklas Saers](http://niklas.saers.com/) ([@niklassaers](https://twitter.com/niklassaers)) (Theo v3-v6)
* [Cory Wiles](http://www.corywiles.com/) ([@kwylez](https://twitter.com/kwylez)) (Theo v1-v3)

## Special thanks to
* [Cory Benfield](https://lukasa.co.uk) for all the help with with SwiftNIO and Transport Services
* [Nigel Small](https://nige.tech) for all the Bolt-related help
* [Michael Hunger](http://www.jexp.de) for help navigating the Neo4j community
