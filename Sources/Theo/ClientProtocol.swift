import Foundation
import Bolt
import PackStream
import NIO

public protocol ClientProtocol: AnyObject {
    func connect(completionBlock: ((Result<Bool, Error>) -> ())?)
    func connectSync() -> Result<Bool, Error>
    func disconnect()
    
    func execute(request: Request) -> EventLoopFuture<QueryResult>
    func executeWithResult(request: Request) -> EventLoopFuture<QueryResult>
    func executeWithResultSync(request: Request) -> Result<QueryResult, Error>
    
    func executeCypher(_ query: String, params: Dictionary<String,PackProtocol>?) -> EventLoopFuture<QueryResult>
    func executeCypher(_ query: String, params: [String:PackProtocol]) -> EventLoopFuture<QueryResult>
    func executeCypherSync(_ query: String, params: Dictionary<String,PackProtocol>?) -> Result<QueryResult, Error>
    
    func executeAsTransaction(mode: Request.TransactionMode, bookmark: String?, transactionBlock: @escaping (_ tx: Transaction) throws -> (), transactionCompleteBlock: ((Bool) -> ())?) throws
    func reset(completionBlock: (() -> ())?) throws
    func resetSync() throws
    func rollback(transaction: Transaction, rollbackCompleteBlock: (() -> ())?) throws
    
    func getBookmark() -> String?
    
    // MARK: - Create
    
    func createAndReturnNode(node: Node) -> EventLoopFuture<Node>
    func createAndReturnNodeSync(node: Node) -> Result<Node, Error>
    func createNode(node: Node) -> EventLoopFuture<Void>
    func createNodeSync(node: Node) -> Result<Bool, Error>
    func createAndReturnNodes(nodes: [Node]) -> EventLoopFuture<[Node]>
    func createAndReturnNodesSync(nodes: [Node]) -> Result<[Node], Error>
    func createNodes(nodes: [Node]) -> EventLoopFuture<Void>
    func createNodesSync(nodes: [Node]) -> Result<Bool, Error>
    
    // MARK: Update
    
    func updateAndReturnNode(node: Node) -> EventLoopFuture<Node>
    func updateAndReturnNodeSync(node: Node) -> Result<Node, Error>
    func updateNode(node: Node) -> EventLoopFuture<Void>
    func updateNodeSync(node: Node) -> Result<Bool, Error>
    func updateAndReturnNodes(nodes: [Node]) -> EventLoopFuture<[Node]>
    func updateAndReturnNodesSync(nodes: [Node]) -> Result<[Node], Error>
    func updateNodes(nodes: [Node]) -> EventLoopFuture<Void>
    func updateNodesSync(nodes: [Node]) -> Result<Bool, Error>
    
    // MARK: Delete
    
    func deleteNode(node: Node) -> EventLoopFuture<Void>
    func deleteNodeSync(node: Node) -> Result<Bool, Error>
    func deleteNodes(nodes: [Node]) -> EventLoopFuture<Void>
    func deleteNodesSync(nodes: [Node]) -> Result<Bool, Error>
    
    // MARK: Nodes
    
    func nodeBy(id: UInt64) -> EventLoopFuture<Node>
    func nodeBySync(id: UInt64) -> Result<Node, Error>
    func nodesWith(labels: [String], andProperties properties: [String:PackProtocol], skip: UInt64, limit: UInt64) -> EventLoopFuture<[Node]>
    func nodesWithSync(labels: [String], andProperties properties: [String:PackProtocol], skip: UInt64, limit: UInt64) -> Result<[Node], Error>
    func nodesWith(properties: [String:PackProtocol], skip: UInt64, limit: UInt64) -> EventLoopFuture<[Node]>
    func nodesWithSync(properties: [String:PackProtocol], skip: UInt64, limit: UInt64) -> Result<[Node], Error>
    func nodesWith(label: String, andProperties properties: [String:PackProtocol], skip: UInt64, limit: UInt64) -> EventLoopFuture<[Node]>
    func nodesWithSync(label: String, andProperties properties: [String:PackProtocol], skip: UInt64, limit: UInt64) ->Result<[Node], Error>
    
    // MARK: Relate
    
    func relate(node: Node, to: Node, type: String, properties: [String:PackProtocol]) -> EventLoopFuture<Relationship>
    func relateSync(node: Node, to: Node, type: String, properties: [String:PackProtocol]) -> Result<Relationship, Error>
    
    // MARK: Relationships
    
    func createAndReturnRelationships(relationships: [Relationship]) -> EventLoopFuture<[Relationship]>
    func createAndReturnRelationshipsSync(relationships: [Relationship]) -> Result<[Relationship], Error>
    
    func createAndReturnRelationship(relationship: Relationship) -> EventLoopFuture<Relationship>
    func createAndReturnRelationshipSync(relationship: Relationship) -> Result<Relationship, Error>
    
    func updateAndReturnRelationship(relationship: Relationship) -> EventLoopFuture<Relationship>
    func updateAndReturnRelationshipSync(relationship: Relationship) -> Result<Relationship, Error>
    
    func updateRelationship(relationship: Relationship) -> EventLoopFuture<Void>
    func updateRelationshipSync(relationship: Relationship) -> Result<Bool, Error>
    
    func deleteRelationship(relationship: Relationship) -> EventLoopFuture<Void>
    func deleteRelationshipSync(relationship: Relationship) -> Result<Bool, Error>

    func relationshipsWith(type: String, andProperties properties: [String:PackProtocol], skip: UInt64, limit: UInt64) -> EventLoopFuture<[Relationship]>
    func relationshipsWithSync(type: String, andProperties properties: [String:PackProtocol], skip: UInt64, limit: UInt64) -> Result<[Relationship], Error>
    
}
