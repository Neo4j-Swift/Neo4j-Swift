import Foundation
import Bolt
import PackStream

public protocol ClientProtocol: AnyObject {
    func connect(completionBlock: ((Result<Bool, Error>) -> ())?)
    func connectSync() -> Result<Bool, Error>
    func disconnect()
    func execute(request: Request, completionBlock: ((Result<(Bool, QueryResult), Error>) -> ())?)
    func executeWithResult(request: Request, completionBlock: ((Result<(Bool, QueryResult), Error>) -> ())?)
    func executeCypherWithResult(_ query: String, params: [String:PackProtocol], completionBlock: ((Result<(Bool, QueryResult), Error>) -> ())?)

    func executeCypher(_ query: String, params: Dictionary<String,PackProtocol>?, completionBlock: ((Result<(Bool, QueryResult), Error>) -> ())?)
    func executeCypherSync(_ query: String, params: Dictionary<String,PackProtocol>?) -> (Result<QueryResult, Error>)

    func executeAsTransaction(mode: TransactionMode, bookmark: String?, transactionBlock: @escaping (_ tx: Transaction) throws -> (), transactionCompleteBlock: ((Bool) -> ())?) throws
    func reset(completionBlock: (() -> ())?) throws
    func resetSync() throws
    func rollback(transaction: Transaction, rollbackCompleteBlock: (() -> ())?) throws
    func pullAll(partialQueryResult: QueryResult, completionBlock: ((Result<(Bool, QueryResult), Error>) -> ())?)
    func getBookmark() -> String?
    func createAndReturnNode(node: Node, completionBlock: ((Result<Node, Error>) -> ())?)
    func createAndReturnNodeSync(node: Node) -> Result<Node, Error>
    func createNode(node: Node, completionBlock: ((Result<Bool, Error>) -> ())?)
    func createNodeSync(node: Node) -> Result<Bool, Error>
    func createAndReturnNodes(nodes: [Node], completionBlock: ((Result<[Node], Error>) -> ())?)
    func createAndReturnNodesSync(nodes: [Node]) -> Result<[Node], Error>
    func createNodes(nodes: [Node], completionBlock: ((Result<Bool, Error>) -> ())?)
    func createNodesSync(nodes: [Node]) -> Result<Bool, Error>
    func updateAndReturnNode(node: Node, completionBlock: ((Result<Node, Error>) -> ())?)
    func updateAndReturnNodeSync(node: Node) -> Result<Node, Error>
    func updateNode(node: Node, completionBlock: ((Result<Bool, Error>) -> ())?)
    func performRequestWithNoReturnNode(request: Request, completionBlock: ((Result<Bool, Error>) -> ())?)
    func updateNodeSync(node: Node) -> Result<Bool, Error>
    func updateAndReturnNodes(nodes: [Node], completionBlock: ((Result<[Node], Error>) -> ())?)
    func updateAndReturnNodesSync(nodes: [Node]) -> Result<[Node], Error>
    func updateNodes(nodes: [Node], completionBlock: ((Result<Bool, Error>) -> ())?)
    func updateNodesSync(nodes: [Node]) -> Result<Bool, Error>
    func deleteNode(node: Node, completionBlock: ((Result<Bool, Error>) -> ())?)
    func deleteNodeSync(node: Node) -> Result<Bool, Error>
    func deleteNodes(nodes: [Node], completionBlock: ((Result<Bool, Error>) -> ())?)
    func deleteNodesSync(nodes: [Node]) -> Result<Bool, Error>
    func nodeBy(id: UInt64, completionBlock: ((Result<Node?, Error>) -> ())?)
    func nodesWith(labels: [String], andProperties properties: [String:PackProtocol], skip: UInt64, limit: UInt64, completionBlock: ((Result<[Node], Error>) -> ())?)
    func nodesWith(properties: [String:PackProtocol], skip: UInt64, limit: UInt64, completionBlock: ((Result<[Node], Error>) -> ())?)
    func nodesWith(label: String, andProperties properties: [String:PackProtocol], skip: UInt64, limit: UInt64, completionBlock: ((Result<[Node], Error>) -> ())?)
    
    func relate(node: Node, to: Node, type: String, properties: [String:PackProtocol], completionBlock: ((Result<Relationship, Error>) -> ())?)
    func relateSync(node: Node, to: Node, type: String, properties: [String:PackProtocol]) -> Result<Relationship, Error>
    
    func createAndReturnRelationshipsSync(relationships: [Relationship]) -> Result<[Relationship], Error>
    func createAndReturnRelationships(relationships: [Relationship], completionBlock: ((Result<[Relationship], Error>) -> ())?)
    func createAndReturnRelationshipSync(relationship: Relationship) -> Result<Relationship, Error>
    func createAndReturnRelationship(relationship: Relationship, completionBlock: ((Result<Relationship, Error>) -> ())?)
    func updateAndReturnRelationship(relationship: Relationship, completionBlock: ((Result<Relationship, Error>) -> ())?)
    func updateAndReturnRelationshipSync(relationship: Relationship) -> Result<Relationship, Error>
    func updateRelationship(relationship: Relationship, completionBlock: ((Result<Bool, Error>) -> ())?)
    func performRequestWithNoReturnRelationship(request: Request, completionBlock: ((Result<Bool, Error>) -> ())?)
    func updateRelationshipSync(relationship: Relationship) -> Result<Bool, Error>
    /*
    func updateAndReturnRelationships(relationships: [Relationship], completionBlock: ((Result<[Relationship], Error>) -> ())?)
    func updateAndReturnRelationshipsSync(relationships: [Relationship]) -> Result<[Relationship], Error>
    func updateRelationships(relationships: [Relationship], completionBlock: ((Result<Bool, Error>) -> ())?)
    func updateRelationshipsSync(relationships: [Relationship]) -> Result<Bool, Error>
     */
    func deleteRelationship(relationship: Relationship, completionBlock: ((Result<Bool, Error>) -> ())?)
    func deleteRelationshipSync(relationship: Relationship) -> Result<Bool, Error>
    /*
    func deleteRelationships(relationships: [Relationship], completionBlock: ((Result<[Bool], Error>) -> ())?)
    func deleteRelationshipsSync(relationships: [Relationship]) -> Result<[Bool], Error>
     */
    func relationshipsWith(type: String, andProperties properties: [String:PackProtocol], skip: UInt64, limit: UInt64, completionBlock: ((Result<[Relationship], Error>) -> ())?)
    func pullSynchronouslyAndIgnore()
    
    
}
