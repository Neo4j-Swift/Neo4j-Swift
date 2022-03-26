import Foundation
import PackStream
import Bolt
import NIO

private class ClientInstanceWithProperties {
    let client: ClientProtocol
    var inUse: Bool
    
    init(client: ClientProtocol) {
        self.client = client
        self.inUse = false
    }
}

private struct InMemoryClientConfiguration: ClientConfigurationProtocol {
    let hostname: String
    let port: Int
    let username: String
    let password: String
    let encrypted: Bool
}

public class BoltPoolClient: ClientProtocol {
    
    
    private var clients: [ClientInstanceWithProperties]
    private let clientSemaphore: DispatchSemaphore
    
    private let configuration: ClientConfigurationProtocol
    
    private var hostname: String { return configuration.hostname }
    private var port: Int { return configuration.port }
    private var username: String { return configuration.username }
    private var password: String { return configuration.password }
    private var encrypted: Encryption { return configuration.encryption }
    
    required public init(_ configuration: ClientConfigurationProtocol, poolSize: ClosedRange<UInt>) throws {
        
        self.configuration = configuration
        self.clientSemaphore = DispatchSemaphore(value: Int(poolSize.upperBound))
        self.clients = try (0..<poolSize.lowerBound).map { _ in
            let client = try BoltClient(configuration)
            _ = client.connectSync()
            return ClientInstanceWithProperties(client: client)
        }
    }
    
    required public convenience init(hostname: String = "localhost", port: Int = 7687, username: String = "neo4j", password: String = "neo4j", encrypted: Bool = true, poolSize: ClosedRange<UInt>) throws {
        let configuration = InMemoryClientConfiguration(
            hostname: hostname,
            port: port,
            username: username,
            password: password,
            encrypted: encrypted)
        try self.init(configuration, poolSize: poolSize)
        
    }
    
    private let clientsMutationSemaphore = DispatchSemaphore(value: 1)
    
    public func getClient() -> ClientProtocol {
        self.clientSemaphore.wait()
        clientsMutationSemaphore.wait()
        var client: ClientProtocol? = nil
        var i = 0
        for alt in self.clients {
            if alt.inUse == false {
                alt.inUse = true
                client = alt.client
                self.clients[i] = alt
                break
            }
            
            i = i + 1
        }
        
        if client == nil {
            
            let boltClient = try! BoltClient(configuration) // TODO: !!! !
            let clientWithProps = ClientInstanceWithProperties(client: boltClient)
            clientWithProps.inUse = true
            self.clients.append(clientWithProps)
            client = clientWithProps.client
        }
        
        clientsMutationSemaphore.signal()
        
        return client! // TODO: !!! !
        
    }
    
    public func release(_ client: ClientProtocol) {
        clientsMutationSemaphore.wait()
        var i = 0
        for alt in self.clients {
            if alt.client === client {
                alt.inUse = false
                self.clients[i] = alt
                break
            }
            i = i + 1
        }
        clientsMutationSemaphore.signal()
        self.clientSemaphore.signal()
    }
}

extension BoltPoolClient {
    public func all() -> [ClientProtocol] {
        return clients.map { $0.client }
    }
}

extension BoltPoolClient {
    public func connect(completionBlock: ((Result<Bool, Error>) -> ())?) {
        let client = self.getClient()
        defer { release(client) }
        client.connect(completionBlock: completionBlock)
    }
    
    public func connectSync() -> Result<Bool, Error> {
        let client = self.getClient()
        defer { release(client) }
        return client.connectSync()
    }
    
    public func disconnect() {
        let client = self.getClient()
        
        defer { release(client) }
        client.disconnect()
    }
    
    public func execute(request: Request) -> EventLoopFuture<QueryResult> {
        let client = self.getClient()
        
        defer { release(client) }
        return client.execute(request: request)
    }
    
    public func executeWithResult(request: Request) -> EventLoopFuture<QueryResult> {
        let client = self.getClient()
        
        defer { release(client) }
        return client.executeWithResult(request: request)
    }
    
    public func executeWithResultSync(request: Request) -> Result<QueryResult, Error> {
        let client = self.getClient()
        
        defer { release(client) }
        return client.executeWithResultSync(request: request)
    }
    
    public func executeCypher(_ query: String, params: Dictionary<String, PackProtocol>?) -> EventLoopFuture<QueryResult> {
        let client = self.getClient()
        defer { release(client) }
        return client.executeCypher(query, params: params)
    }
    
    public func executeCypher(_ query: String, params: [String:PackProtocol] = [:]) -> EventLoopFuture<QueryResult>  {
        let client = self.getClient()
        defer { release(client) }
        return client.executeCypher(query, params: params)
    }
    
    public func executeCypherSync(_ query: String, params: Dictionary<String, PackProtocol>?) -> (Result<QueryResult, Error>) {
        let client = self.getClient()
        defer { release(client) }
        return client.executeCypherSync(query, params: params)
    }
    
    public func executeAsTransaction(mode: Request.TransactionMode = .readonly, bookmark: String?, transactionBlock: @escaping (Transaction) throws -> (), transactionCompleteBlock: ((Bool) -> ())? = nil) throws {
        let client = self.getClient()
        defer { release(client) }
        try client.executeAsTransaction(mode: mode, bookmark: bookmark, transactionBlock: transactionBlock, transactionCompleteBlock: transactionCompleteBlock)
    }

    public func reset(completionBlock: (() -> ())?) throws {
        let client = self.getClient() // TODO: How can we ensure we get the old client
        defer { release(client) }
        try client.reset(completionBlock: completionBlock)
    }
    public func resetSync() throws {
        let client = self.getClient() // TODO: How can we ensure we get the old client
        defer { release(client) }
        try client.resetSync()
    }
    
    public func rollback(transaction: Transaction, rollbackCompleteBlock: (() -> ())?) throws {
        let client = self.getClient() // TODO: How can we ensure we get the same client that is currently processing that transaction?
        defer { release(client) }
        try client.rollback(transaction: transaction, rollbackCompleteBlock: rollbackCompleteBlock)
    }
    
    public func getBookmark() -> String? {
        let client = self.getClient()
        defer { release(client) }
        return client.getBookmark()
    }
    
    // MARK: Create
    
    public func createAndReturnNode(node: Node) -> EventLoopFuture<Node> {
        let client = self.getClient()
        defer { release(client) }
        return client.createAndReturnNode(node: node)
    }
    
    public func createAndReturnNodeSync(node: Node) -> Result<Node, Error> {
        let client = self.getClient()
        defer { release(client) }
        return client.createAndReturnNodeSync(node: node)
    }
    
    public func createNode(node: Node) -> EventLoopFuture<Void> {
        let client = self.getClient()
        defer { release(client) }
        return client.createNode(node: node)
    }
    
    public func createNodeSync(node: Node) -> Result<Bool, Error> {
        let client = self.getClient()
        defer { release(client) }
        return client.createNodeSync(node: node)
    }
    
    public func createAndReturnNodes(nodes: [Node]) -> EventLoopFuture<[Node]> {
        let client = self.getClient()
        defer { release(client) }
        return client.createAndReturnNodes(nodes: nodes)
    }
    
    public func createAndReturnNodesSync(nodes: [Node]) -> Result<[Node], Error> {
        let client = self.getClient()
        defer { release(client) }
        let res = client.createAndReturnNodesSync(nodes: nodes)
        return res
    }
    
    public func createNodes(nodes: [Node]) -> EventLoopFuture<Void> {
        let client = self.getClient()
        defer { release(client) }
        return client.createNodes(nodes: nodes)
    }
    
    public func createNodesSync(nodes: [Node]) -> Result<Bool, Error> {
        let client = self.getClient()
        defer { release(client) }
        return client.createNodesSync(nodes: nodes)
    }
    
    // MARK: Update
    
    public func updateAndReturnNode(node: Node) -> EventLoopFuture<Node> {
        let client = self.getClient()
        defer { release(client) }
        return client.updateAndReturnNode(node: node)
    }
    
    public func updateAndReturnNodeSync(node: Node) -> Result<Node, Error> {
        let client = self.getClient()
        defer { release(client) }
        return client.updateAndReturnNodeSync(node: node)
    }
    
    public func updateNode(node: Node) -> EventLoopFuture<Void> {
        let client = self.getClient()
        defer { release(client) }
        return client.updateNode(node: node)
    }
    
    public func updateNodeSync(node: Node) -> Result<Bool, Error> {
        let client = self.getClient()
        defer { release(client) }
        return client.updateNodeSync(node: node)
    }
    
    public func updateAndReturnNodes(nodes: [Node]) -> EventLoopFuture<[Node]> {
        let client = self.getClient()
        defer { release(client) }
        return client.updateAndReturnNodes(nodes: nodes)
    }
    
    public func updateAndReturnNodesSync(nodes: [Node]) -> Result<[Node], Error> {
        let client = self.getClient()
        defer { release(client) }
        return client.updateAndReturnNodesSync(nodes: nodes)
    }
    
    public func updateNodes(nodes: [Node]) -> EventLoopFuture<Void> {
        let client = self.getClient()
        defer { release(client) }
        return client.updateNodes(nodes: nodes)
    }
    
    public func updateNodesSync(nodes: [Node]) -> Result<Bool, Error> {
        let client = self.getClient()
        defer { release(client) }
        return client.updateNodesSync(nodes: nodes)
    }
    
    // MARK: Delete
    
    public func deleteNode(node: Node) -> EventLoopFuture<Void> {
        let client = self.getClient()
        defer { release(client) }
        return client.deleteNode(node: node)
    }
    
    public func deleteNodeSync(node: Node) -> Result<Bool, Error> {
        let client = self.getClient()
        defer { release(client) }
        return client.deleteNodeSync(node: node)
    }
    
    public func deleteNodes(nodes: [Node]) -> EventLoopFuture<Void> {
        let client = self.getClient()
        defer { release(client) }
        return client.deleteNodes(nodes: nodes)
    }
    
    public func deleteNodesSync(nodes: [Node]) -> Result<Bool, Error> {
        let client = self.getClient()
        defer { release(client) }
        return client.deleteNodesSync(nodes: nodes)
    }
    
    // MARK: Nodes
    
    public func nodeBy(id: UInt64) -> EventLoopFuture<Node> {
        let client = self.getClient()
        defer { release(client) }
        return client.nodeBy(id: id)
    }
    
    public func nodeBySync(id: UInt64) -> Result<Node, Error> {
        let client = self.getClient()
        defer { release(client) }
        return client.nodeBySync(id: id)
    }
    
    public func nodesWith(labels: [String], andProperties properties: [String : PackProtocol], skip: UInt64, limit: UInt64) -> EventLoopFuture<[Node]> {
        let client = self.getClient()
        defer { release(client) }
        return client.nodesWith(labels: labels, andProperties: properties, skip: skip, limit: limit)
    }
    
    public func nodesWithSync(labels: [String], andProperties properties: [String : PackProtocol], skip: UInt64, limit: UInt64) ->Result<[Node], Error> {
        let client = self.getClient()
        defer { release(client) }
        return client.nodesWithSync(labels: labels, andProperties: properties, skip: skip, limit: limit)
    }
    
    public func nodesWith(properties: [String : PackProtocol], skip: UInt64, limit: UInt64) -> EventLoopFuture<[Node]> {
        let client = self.getClient()
        defer { release(client) }
        return client.nodesWith(properties: properties, skip: skip, limit: limit)
    }
    
    public func nodesWithSync(properties: [String : PackProtocol], skip: UInt64, limit: UInt64) -> Result<[Node], Error> {
        let client = self.getClient()
        defer { release(client) }
        return client.nodesWithSync(properties: properties, skip: skip, limit: limit)
    }
    
    public func nodesWith(label: String, andProperties properties: [String : PackProtocol], skip: UInt64, limit: UInt64) -> EventLoopFuture<[Node]> {
        let client = self.getClient()
        defer { release(client) }
        return client.nodesWith(label: label, andProperties: properties, skip: skip, limit: limit)
    }
    
    public func nodesWithSync(label: String, andProperties properties: [String : PackProtocol], skip: UInt64, limit: UInt64) -> Result<[Node], Error> {
        let client = self.getClient()
        defer { release(client) }
        return client.nodesWithSync(label: label, andProperties: properties, skip: skip, limit: limit)
    }
    
    // MARK: Relate
    
    public func relate(node: Node, to: Node, type: String, properties: [String : PackProtocol]) -> EventLoopFuture<Relationship> {
        let client = self.getClient()
        defer { release(client) }
        return client.relate(node: node, to: to, type: type, properties: properties)
    }
    
    public func relateSync(node: Node, to: Node, type: String, properties: [String : PackProtocol]) -> Result<Relationship, Error> {
        let client = self.getClient()
        defer { release(client) }
        return client.relateSync(node: node, to: to, type: type, properties: properties)
    }
    
    // MARK: Relationships
    
    public func createAndReturnRelationships(relationships: [Relationship]) -> EventLoopFuture<[Relationship]> {
        let client = self.getClient()
        defer { release(client) }
        return client.createAndReturnRelationships(relationships: relationships)
    }
    
    public func createAndReturnRelationshipsSync(relationships: [Relationship]) -> Result<[Relationship], Error> {
        let client = self.getClient()
        defer { release(client) }
        return client.createAndReturnRelationshipsSync(relationships: relationships)
    }
    
    public func createAndReturnRelationship(relationship: Relationship) -> EventLoopFuture<Relationship> {
        let client = self.getClient()
        defer { release(client) }
        return client.createAndReturnRelationship(relationship: relationship)
    }
    
    public func createAndReturnRelationshipSync(relationship: Relationship) -> Result<Relationship, Error> {
        let client = self.getClient()
        defer { release(client) }
        return client.createAndReturnRelationshipSync(relationship: relationship)
    }
    
    public func updateAndReturnRelationship(relationship: Relationship) -> EventLoopFuture<Relationship> {
        let client = self.getClient()
        defer { release(client) }
        return client.updateAndReturnRelationship(relationship: relationship)
    }
    
    public func updateAndReturnRelationshipSync(relationship: Relationship) -> Result<Relationship, Error> {
        let client = self.getClient()
        defer { release(client) }
        return client.updateAndReturnRelationshipSync(relationship: relationship)
    }
    
    public func updateRelationship(relationship: Relationship) -> EventLoopFuture<Void> {
        let client = self.getClient()
        defer { release(client) }
        return client.updateRelationship(relationship: relationship)
    }
    
    public func updateRelationshipSync(relationship: Relationship) -> Result<Bool, Error> {
        let client = self.getClient()
        defer { release(client) }
        return client.updateRelationshipSync(relationship: relationship)
    }
    
    public func deleteRelationship(relationship: Relationship) -> EventLoopFuture<Void> {
        let client = self.getClient()
        defer { release(client) }
        return client.deleteRelationship(relationship: relationship)
    }
    
    public func deleteRelationshipSync(relationship: Relationship) -> Result<Bool, Error> {
        let client = self.getClient()
        defer { release(client) }
        return client.deleteRelationshipSync(relationship: relationship)
    }
    
    public func relationshipsWith(type: String, andProperties properties: [String : PackProtocol], skip: UInt64, limit: UInt64) -> EventLoopFuture<[Relationship]> {
        let client = self.getClient()
        defer { release(client) }
        return client.relationshipsWith(type: type, andProperties: properties, skip: skip, limit: limit)
    }
    
    public func relationshipsWithSync(type: String, andProperties properties: [String:PackProtocol] = [:], skip: UInt64 = 0, limit: UInt64 = 25) -> Result<[Relationship], Error> {
        let client = self.getClient()
        defer { release(client) }
        return client.relationshipsWithSync(type: type, andProperties: properties, skip: skip, limit: limit)
    }
}
