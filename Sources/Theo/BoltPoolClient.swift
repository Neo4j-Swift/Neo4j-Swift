import Foundation
import PackStream
import Bolt

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
    private var encrypted: Bool { return configuration.encrypted }
    
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
    
    public func execute(request: Request, completionBlock: ((Result<(Bool, QueryResult), Error>) -> ())?) {
        let client = self.getClient()
        
        defer { release(client) }
        client.execute(request: request, completionBlock: completionBlock)
    }
    
    public func executeWithResult(request: Request, completionBlock: ((Result<(Bool, QueryResult), Error>) -> ())?) {
        let client = self.getClient()
        
        defer { release(client) }
        client.executeWithResult(request: request, completionBlock: completionBlock)
    }
    
    public func executeCypher(_ query: String, params: Dictionary<String, PackProtocol>?, completionBlock: ((Result<(Bool, QueryResult), Error>) -> ())?) {
        let client = self.getClient()
        defer { release(client) }
        client.executeCypher(query, params: params, completionBlock: completionBlock)
    }
    
    public func executeCypherWithResult(_ query: String, params: [String:PackProtocol] = [:], completionBlock: ((Result<(Bool, QueryResult), Error>) -> ())? = nil) {
        let client = self.getClient()
        
        client.executeCypherWithResult(query, params: params) { result in
            self.release(client)
            completionBlock?(result)
        }
    }
    
    public func executeCypherSync(_ query: String, params: Dictionary<String, PackProtocol>?) -> (Result<QueryResult, Error>) {
        let client = self.getClient()
        defer { release(client) }
        return client.executeCypherSync(query, params: params)
    }
    
    public func executeAsTransaction(mode: TransactionMode = .readonly, bookmark: String?, transactionBlock: @escaping (Transaction) throws -> (), transactionCompleteBlock: ((Bool) -> ())? = nil) throws {
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
    
    public func pullAll(partialQueryResult: QueryResult, completionBlock: ((Result<(Bool, QueryResult), Error>) -> ())?) {
        let client = self.getClient()
        defer { release(client) }
        client.pullAll(partialQueryResult: partialQueryResult, completionBlock: completionBlock)
    }
    
    public func getBookmark() -> String? {
        let client = self.getClient()
        defer { release(client) }
        return client.getBookmark()
    }
    
    public func createAndReturnNode(node: Node, completionBlock: ((Result<Node, Error>) -> ())?) {
        let client = self.getClient()
        defer { release(client) }
        client.createAndReturnNode(node: node, completionBlock: completionBlock)
    }
    
    public func createAndReturnNodeSync(node: Node) -> Result<Node, Error> {
        let client = self.getClient()
        defer { release(client) }
        return client.createAndReturnNodeSync(node: node)
    }
    
    public func createNode(node: Node, completionBlock: ((Result<Bool, Error>) -> ())?) {
        let client = self.getClient()
        defer { release(client) }
        client.createNode(node: node, completionBlock: completionBlock)
    }
    
    public func createNodeSync(node: Node) -> Result<Bool, Error> {
        let client = self.getClient()
        defer { release(client) }
        return client.createNodeSync(node: node)
    }
    
    public func createAndReturnNodes(nodes: [Node], completionBlock: ((Result<[Node], Error>) -> ())?) {
        let client = self.getClient()
        defer { release(client) }
        client.createAndReturnNodes(nodes: nodes, completionBlock: completionBlock)
    }
    
    public func createAndReturnNodesSync(nodes: [Node]) -> Result<[Node], Error> {
        let client = self.getClient()
        defer { release(client) }
        let res = client.createAndReturnNodesSync(nodes: nodes)
        return res
    }
    
    public func createNodes(nodes: [Node], completionBlock: ((Result<Bool, Error>) -> ())?) {
        let client = self.getClient()
        defer { release(client) }
        client.createNodes(nodes: nodes, completionBlock: completionBlock)
    }
    
    public func createNodesSync(nodes: [Node]) -> Result<Bool, Error> {
        let client = self.getClient()
        defer { release(client) }
        return client.createNodesSync(nodes: nodes)
    }
    
    public func updateAndReturnNode(node: Node, completionBlock: ((Result<Node, Error>) -> ())?) {
        let client = self.getClient()
        defer { release(client) }
        client.updateAndReturnNode(node: node, completionBlock: completionBlock)
    }
    
    public func updateAndReturnNodeSync(node: Node) -> Result<Node, Error> {
        let client = self.getClient()
        defer { release(client) }
        return client.updateAndReturnNodeSync(node: node)
    }
    
    public func updateNode(node: Node, completionBlock: ((Result<Bool, Error>) -> ())?) {
        let client = self.getClient()
        defer { release(client) }
        client.updateNode(node: node, completionBlock: completionBlock)
    }
    
    public func performRequestWithNoReturnNode(request: Request, completionBlock: ((Result<Bool, Error>) -> ())?) {
        let client = self.getClient()
        defer { release(client) }
        client.performRequestWithNoReturnNode(request: request, completionBlock: completionBlock)
    }
    
    public func updateNodeSync(node: Node) -> Result<Bool, Error> {
        let client = self.getClient()
        defer { release(client) }
        return client.updateNodeSync(node: node)
    }
    
    public func updateAndReturnNodes(nodes: [Node], completionBlock: ((Result<[Node], Error>) -> ())?) {
        let client = self.getClient()
        defer { release(client) }
        client.updateAndReturnNodes(nodes: nodes, completionBlock: completionBlock)
    }
    
    public func updateAndReturnNodesSync(nodes: [Node]) -> Result<[Node], Error> {
        let client = self.getClient()
        defer { release(client) }
        return client.updateAndReturnNodesSync(nodes: nodes)
    }
    
    public func updateNodes(nodes: [Node], completionBlock: ((Result<Bool, Error>) -> ())?) {
        let client = self.getClient()
        defer { release(client) }
        client.updateNodes(nodes: nodes, completionBlock: completionBlock)
    }
    
    public func updateNodesSync(nodes: [Node]) -> Result<Bool, Error> {
        let client = self.getClient()
        defer { release(client) }
        return client.updateNodesSync(nodes: nodes)
    }
    
    public func deleteNode(node: Node, completionBlock: ((Result<Bool, Error>) -> ())?) {
        let client = self.getClient()
        defer { release(client) }
        client.deleteNode(node: node, completionBlock: completionBlock)
    }
    
    public func deleteNodeSync(node: Node) -> Result<Bool, Error> {
        let client = self.getClient()
        defer { release(client) }
        return client.deleteNodeSync(node: node)
    }
    
    public func deleteNodes(nodes: [Node], completionBlock: ((Result<Bool, Error>) -> ())?) {
        let client = self.getClient()
        defer { release(client) }
        client.deleteNodes(nodes: nodes, completionBlock: completionBlock)
    }
    
    public func deleteNodesSync(nodes: [Node]) -> Result<Bool, Error> {
        let client = self.getClient()
        defer { release(client) }
        return client.deleteNodesSync(nodes: nodes)
    }
    
    public func nodeBy(id: UInt64, completionBlock: ((Result<Node?, Error>) -> ())?) {
        let client = self.getClient()
        defer { release(client) }
        client.nodeBy(id: id, completionBlock: completionBlock)
    }
    
    public func nodesWith(labels: [String], andProperties properties: [String : PackProtocol], skip: UInt64, limit: UInt64, completionBlock: ((Result<[Node], Error>) -> ())?) {
        let client = self.getClient()
        defer { release(client) }
        client.nodesWith(labels: labels, andProperties: properties, skip: skip, limit: limit, completionBlock: completionBlock)
    }
    
    public func nodesWith(properties: [String : PackProtocol], skip: UInt64, limit: UInt64, completionBlock: ((Result<[Node], Error>) -> ())?) {
        let client = self.getClient()
        defer { release(client) }
        client.nodesWith(properties: properties, skip: skip, limit: limit, completionBlock: completionBlock)
    }
    
    public func nodesWith(label: String, andProperties properties: [String : PackProtocol], skip: UInt64, limit: UInt64, completionBlock: ((Result<[Node], Error>) -> ())?) {
        let client = self.getClient()
        defer { release(client) }
        client.nodesWith(label: label, andProperties: properties, skip: skip, limit: limit, completionBlock: completionBlock)
    }
    
    public func relate(node: Node, to: Node, type: String, properties: [String : PackProtocol], completionBlock: ((Result<Relationship, Error>) -> ())?) {
        let client = self.getClient()
        defer { release(client) }
        client.relate(node: node, to: to, type: type, properties: properties, completionBlock: completionBlock)
    }
    
    public func relateSync(node: Node, to: Node, type: String, properties: [String : PackProtocol]) -> Result<Relationship, Error> {
        let client = self.getClient()
        defer { release(client) }
        return client.relateSync(node: node, to: to, type: type, properties: properties)
    }
    
    public func createAndReturnRelationshipsSync(relationships: [Relationship]) -> Result<[Relationship], Error> {
        let client = self.getClient()
        defer { release(client) }
        return client.createAndReturnRelationshipsSync(relationships: relationships)
    }
    
    public func createAndReturnRelationships(relationships: [Relationship], completionBlock: ((Result<[Relationship], Error>) -> ())?) {
        let client = self.getClient()
        defer { release(client) }
        client.createAndReturnRelationships(relationships: relationships, completionBlock: completionBlock)
    }
    
    public func createAndReturnRelationshipSync(relationship: Relationship) -> Result<Relationship, Error> {
        let client = self.getClient()
        defer { release(client) }
        return client.createAndReturnRelationshipSync(relationship: relationship)
    }
    
    public func createAndReturnRelationship(relationship: Relationship, completionBlock: ((Result<Relationship, Error>) -> ())?) {
        let client = self.getClient()
        defer { release(client) }
        client.createAndReturnRelationship(relationship: relationship, completionBlock: completionBlock)
    }
    
    public func updateAndReturnRelationship(relationship: Relationship, completionBlock: ((Result<Relationship, Error>) -> ())?) {
        let client = self.getClient()
        defer { release(client) }
        client.updateAndReturnRelationship(relationship: relationship, completionBlock: completionBlock)
    }
    
    public func updateAndReturnRelationshipSync(relationship: Relationship) -> Result<Relationship, Error> {
        let client = self.getClient()
        defer { release(client) }
        return client.updateAndReturnRelationshipSync(relationship: relationship)
    }
    
    public func updateRelationship(relationship: Relationship, completionBlock: ((Result<Bool, Error>) -> ())?) {
        let client = self.getClient()
        defer { release(client) }
        client.updateRelationship(relationship: relationship, completionBlock: completionBlock)
    }
    
    public func performRequestWithNoReturnRelationship(request: Request, completionBlock: ((Result<Bool, Error>) -> ())?) {
        let client = self.getClient()
        defer { release(client) }
        client.performRequestWithNoReturnRelationship(request: request, completionBlock: completionBlock)
    }
    
    public func updateRelationshipSync(relationship: Relationship) -> Result<Bool, Error> {
        let client = self.getClient()
        defer { release(client) }
        return client.updateRelationshipSync(relationship: relationship)
    }
    
    public func deleteRelationship(relationship: Relationship, completionBlock: ((Result<Bool, Error>) -> ())?) {
        let client = self.getClient()
        defer { release(client) }
        client.deleteRelationship(relationship: relationship, completionBlock: completionBlock)
    }
    
    public func deleteRelationshipSync(relationship: Relationship) -> Result<Bool, Error> {
        let client = self.getClient()
        defer { release(client) }
        return client.deleteRelationshipSync(relationship: relationship)
    }
    
    public func relationshipsWith(type: String, andProperties properties: [String : PackProtocol], skip: UInt64, limit: UInt64, completionBlock: ((Result<[Relationship], Error>) -> ())?) {
        let client = self.getClient()
        defer { release(client) }
        return client.relationshipsWith(type: type, andProperties: properties, skip: skip, limit: limit, completionBlock: completionBlock)
    }
    
    public func pullSynchronouslyAndIgnore() {
        let client = self.getClient()
        defer { release(client) }
        client.pullSynchronouslyAndIgnore()
    }
}
