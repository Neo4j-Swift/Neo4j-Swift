import Foundation
import PackStream
import Bolt
import NIOCore

#if os(Linux)
import Dispatch
#endif

typealias BoltRequest = Bolt.Request

// MARK: - Sendable Box for sync methods
// Helper class to safely capture mutable state across concurrency boundaries
private final class SendableBox<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

open class BoltClient: ClientProtocol, @unchecked Sendable {
    private let hostname: String
    private let port: Int
    private let username: String
    private let password: String
    private let encrypted: Bool
    private let connection: Connection

    private var currentTransaction: Transaction?

    public enum BoltClientError: Error {
        case missingNodeResponse
        case missingRelationshipResponse
        case queryUnsuccessful
        case unexpectedNumberOfResponses
        case fetchingRecordsUnsuccessful
        case couldNotCreateRelationship
        case unknownError
    }

    required public init(_ configuration: ClientConfigurationProtocol) throws {

        self.hostname = configuration.hostname
        self.port = configuration.port
        self.username = configuration.username
        self.password = configuration.password
        self.encrypted = configuration.encrypted

        let settings = ConnectionSettings(username: self.username, password: self.password, userAgent: "Theo 5.2.0")

        let socket = try EncryptedSocket(hostname: hostname, port: port)
        socket.certificateValidator = UnsecureCertificateValidator(hostname: self.hostname, port: UInt(self.port))
        self.connection = Connection(
            socket: socket,
            settings: settings)
    }

    required public init(hostname: String = "localhost", port: Int = 7687, username: String = "neo4j", password: String = "neo4j", encrypted: Bool = true) throws {

        self.hostname = hostname
        self.port = port
        self.username = username
        self.password = password
        self.encrypted = encrypted

        let settings = ConnectionSettings(username: username, password: password, userAgent: "Theo 5.2.0")

        let socket = try EncryptedSocket(hostname: hostname, port: port)
        socket.certificateValidator = UnsecureCertificateValidator(hostname: self.hostname, port: UInt(self.port))
        self.connection = Connection(
            socket: socket,
            settings: settings)
    }

    /**
     Connects to Neo4j given the connection settings BoltClient was initialized with.

     Asynchronous, so the function returns straight away. It is not defined what thread the completionblock will run on,
     so if you need it to run on main thread or another thread, make sure to dispatch to this that thread

     - parameter completionBlock: Completion result-block that provides a Bool to indicate success, or an Error to explain what went wrong
     */
    public func connect(completionBlock: ((Result<Bool, Error>) -> ())? = nil) {
        // Wrap completion block for Sendable compatibility
        let callbackBox = SendableBox<((Result<Bool, Error>) -> ())?>(completionBlock)

        do {
            try self.connection.connect { (error) in
                if let error = error {
                    callbackBox.value?(.failure(error))
                } else {
                    callbackBox.value?(.success(true))
                }
            }
        } catch let error as BoltError {
            completionBlock?(.failure(error))
        } catch let error {
            print("Unknown error while connecting: \(error.localizedDescription)")
            completionBlock?(.failure(error))
        }
    }

    /**
     Connects to Neo4j given the connection settings BoltClient was initialized with.

     Synchronous, so the function will return only when the connection attempt has been made.

     - returns: Result that provides a Bool to indicate success, or an Error to explain what went wrong
     */
    public func connectSync() -> Result<Bool, Error> {

        var theResult: Result<Bool, Error>! = nil
        let dispatchGroup = DispatchGroup()
        dispatchGroup.enter()
        connect() { result in
            theResult = result
            dispatchGroup.leave()
        }
        dispatchGroup.wait()
        return theResult
    }

    /**
     Disconnects from Neo4j.
     */
    public func disconnect() {
        connection.disconnect()
    }

    /**
     Executes a given request on Neo4j

     Requires an established connection

     Asynchronous, so the function returns straight away. It is not defined what thread the completionblock will run on,
     so if you need it to run on main thread or another thread, make sure to dispatch to this that thread

     - warning: This function only performs a single request, and that request can lead Neo4j to expect a certain follow-up request, or disconnect with a failure if it receives an unexpected request following this request.

     - parameter request: The Bolt Request that will be sent to Neo4j
     - parameter completionBlock: Completion result-block that provides a partial QueryResult, or an Error to explain what went wrong
     */
    public func execute(request: Request, completionBlock: ((Result<(Bool, QueryResult), Error>) -> ())? = nil) {
        
        do {
            guard let promise = try connection.request(request) else {
                completionBlock?(.failure(BoltClientError.unknownError))
                return
            }

            promise.whenSuccess { responses in
                #if THEO_DEBUG
                print("execute -> success")
                #endif
                let queryResponse = self.parseResponses(responses: responses)
                completionBlock?(.success((true, queryResponse)))
            }
            
            promise.whenFailure { error in
                #if THEO_DEBUG
                print("execute -> failure")
                #endif
                completionBlock?(.failure((error)))
            }
            

        } catch let error as BoltError {
            completionBlock?(.failure(error))
        } catch let error {
            print("Unhandled error while executing cypher: \(error.localizedDescription)")
        }

    }

    /**
     Executes a given query on Neo4j, and pulls the respons data

     Requires an established connection

     Asynchronous, so the function returns straight away. It is not defined what thread the completionblock will run on,
     so if you need it to run on main thread or another thread, make sure to dispatch to this that thread

     - warning: This function should only be used with requests that expect data to be pulled after they run. Other requests can make Neo4j disconnect with a failure when it is subsequent asked for the result data

     - parameter query: The query that will be sent to Neo4j
     - parameter params: The parameters that go with the query
     - parameter completionBlock: Completion result-block that provides a complete QueryResult, or an Error to explain what went wrong
     */
    public func executeCypherWithResult(_ query: String, params: [String:PackProtocol] = [:], completionBlock: ((Result<(Bool, QueryResult), Error>) -> ())? = nil) {
        let request = Bolt.Request.run(statement: query, parameters: Map(dictionary: params))
        self.executeWithResult(request: request, completionBlock: completionBlock)
    }
    
    /**
     Executes a given request on Neo4j, and pulls the respons data

     Requires an established connection

     Asynchronous, so the function returns straight away. It is not defined what thread the completionblock will run on,
     so if you need it to run on main thread or another thread, make sure to dispatch to this that thread

     - warning: This function should only be used with requests that expect data to be pulled after they run. Other requests can make Neo4j disconnect with a failure when it is subsequent asked for the result data

     - parameter request: The Bolt Request that will be sent to Neo4j
     - parameter completionBlock: Completion result-block that provides a complete QueryResult, or an Error to explain what went wrong
     */
    public func executeWithResult(request: Request, completionBlock: ((Result<(Bool, QueryResult), Error>) -> ())? = nil) {
        do {
            guard let promise = try connection.request(request) else {
                completionBlock?(.failure(BoltClientError.unknownError))
                return
            }
            
            promise.whenSuccess{ responses in
                let queryResponse = self.parseResponses(responses: responses)
                self.pullAll(partialQueryResult: queryResponse) { result in
                    switch result {
                    case let .failure(error):
                        completionBlock?(.failure(error))
                    case let .success((successResponse, queryResponse)):
                        if successResponse == false {
                            completionBlock?(.failure(BoltClientError.queryUnsuccessful))
                        } else {
                            completionBlock?(.success((successResponse, queryResponse)))
                        }
                    }
                }
            }
            
            promise.whenFailure { (error) in
                completionBlock?(.failure(BoltClientError.queryUnsuccessful))
            }
        } catch let error as BoltError {
            completionBlock?(.failure(error))
        } catch let error {
            print("Unhandled error while executing cypher: \(error.localizedDescription)")
        }
    }

    /**
     Executes a given cypher query on Neo4j

     Requires an established connection

     Asynchronous, so the function returns straight away. It is not defined what thread the completionblock will run on,
     so if you need it to run on main thread or another thread, make sure to dispatch to this that thread

     - warning: Executing a query should be followed by a data pull with the response from Neo4j. Not doing so can lead to Neo4j closing the client connection.

     - parameter query: The Cypher query to be executed
     - parameter params: The named parameters to be included in the query. All parameter values need to conform to PackProtocol, as this is how they are encoded when sent via Bolt to Neo4j
     - parameter completionBlock: Completion result-block that provides a partial QueryResult, or an Error to explain what went wrong
     */
    public func executeCypher(_ query: String, params: Dictionary<String,PackProtocol>? = nil, completionBlock: ((Result<(Bool, QueryResult), Error>) -> ())? = nil) {

        let cypherRequest = BoltRequest.run(statement: query, parameters: Map(dictionary: params ?? [:]))

        execute(request: cypherRequest) { [weak self] result in
            let isSuccess = (try? result.get().0) ?? false
            if !isSuccess {
                if let completionBlock = completionBlock {
                    completionBlock(result)
                }
            } else {
                if let partialResult = try? result.get().1 {
                    self?.pullAll(partialQueryResult: partialResult, completionBlock: completionBlock)
                }
                /*
                let request = Request.pullAll()
                self?.execute(request: request, completionBlock: completionBlock)
                 */
            }
        }

    }

    /**
     Executes a given cypher query on Neo4j

     Requires an established connection

     Synchronous, so the function will return only when the query result is ready

     - parameter query: The Cypher query to be executed
     - parameter params: The named parameters to be included in the query. All parameter values need to conform to PackProtocol, as this is how they are encoded when sent via Bolt to Neo4j
     - returns: Result that provides a complete QueryResult, or an Error to explain what went wrong
     */
    @discardableResult
    public func executeCypherSync(_ query: String, params: Dictionary<String,PackProtocol>? = nil) -> (Result<QueryResult, Error>) {

        let resultBox = SendableBox<Result<QueryResult, Error>?>(nil)
        let partialResultBox = SendableBox<QueryResult>(QueryResult())
        let dispatchGroup = DispatchGroup()

        // Perform query
        dispatchGroup.enter()
        DispatchQueue.global(qos: .background).async {
            self.executeCypher(query, params: params) { result in
                switch result {
                case let .failure(error):
                    print("Error: \(error)")
                    resultBox.value = .failure(error)
                case let .success((isSuccess, _partialResult)):
                    if isSuccess == false {
                        let error = BoltClientError.queryUnsuccessful
                        resultBox.value = .failure(error)
                    } else {
                        resultBox.value = .success(_partialResult)
                        partialResultBox.value = _partialResult
                    }
                }
                dispatchGroup.leave()
            }
        }
        dispatchGroup.wait()
        if let result = resultBox.value {
            return result
        }

        // Stream and parse results
        dispatchGroup.enter()
        DispatchQueue.global(qos: .background).async {
            self.pullAll(partialQueryResult: partialResultBox.value) { result in
                switch result {
                case let .failure(error):
                    print("Error: \(error)")
                    resultBox.value = .failure(error)
                case let .success(isSuccess, parsedResponses):
                    if isSuccess == false {
                        let error = BoltClientError.queryUnsuccessful
                        resultBox.value = .failure(error)
                    } else {
                        resultBox.value = .success(parsedResponses)
                    }
                }
                dispatchGroup.leave()
            }
        }

        dispatchGroup.wait()
        return resultBox.value ?? .failure(BoltClientError.unknownError)
    }



    private func parseResponses(responses: [Response], result: QueryResult = QueryResult()) -> QueryResult {
        let fields = (responses.flatMap { $0.items } .compactMap { ($0 as? Map)?.dictionary["fields"] }.first as? List)?.items.compactMap { $0 as? String }
        if let fields = fields {
            result.fields = fields
        }

        let stats = responses.flatMap { $0.items.compactMap { $0 as? Map }.compactMap { QueryStats(data: $0) } }.first
        if let stats = stats {
            result.stats = stats
        }

        if let resultAvailableAfter = (responses.flatMap { $0.items } .compactMap { ($0 as? Map)?.dictionary["result_available_after"] }.first?.uintValue()) {
            result.stats.resultAvailableAfter = resultAvailableAfter
        }

        if let resultConsumedAfter = (responses.flatMap { $0.items } .compactMap { $0 as? Map }.first?.dictionary["result_consumed_after"]?.uintValue()) {
            result.stats.resultConsumedAfter = resultConsumedAfter
        }

        if let type = (responses.flatMap { $0.items } .compactMap { $0 as? Map }.first?.dictionary["type"] as? String) {
            result.stats.type = type
        }



        let candidateList = responses.flatMap { $0.items.compactMap { ($0 as? List)?.items } }.reduce( [], +)
        var nodes = [UInt64:Node]()
        var relationships = [UInt64:Relationship]()
        var paths = [Path]()
        var rows = [[String:ResponseItem]]()
        var row = [String:ResponseItem]()

        for i in 0..<candidateList.count {
            if result.fields.count > 0, // there must be a field
               i > 0, // skip the first, because the  first row is already set
               i % result.fields.count == 0 { // then we need to break into the next row
                rows.append(row)
                row = [String:ResponseItem]()
            }

            let field = result.fields.count > 0 ? result.fields[i % result.fields.count] : nil
            let candidate = candidateList[i]

            if let node = Node(data: candidate) {
                if let nodeId = node.id {
                    nodes[nodeId] = node
                }

                if let field = field {
                    row[field] = node
                }
            }

            else if let relationship = Relationship(data: candidate) {
                if let relationshipId = relationship.id {
                    relationships[relationshipId] = relationship
                }

                if let field = field {
                    row[field] = relationship
                }
            }

            else if let path = Path(data: candidate) {
                paths.append(path)

                if let field = field {
                    row[field] = path
                }
            }

            else if let record = candidate.uintValue() {
                if let field = field {
                    row[field] = record
                }
            }

            else if let record = candidate.intValue() {
                if let field = field {
                    row[field] = record
                }
            }

            else if let record = candidate as? ResponseItem {
                if let field = field {
                    row[field] = record
                }
            }

            else {
                let record = Record(entry: candidate)
                if let field = field {
                    row[field] = record
                }
            }
        }

        if row.count > 0 {
            rows.append(row)
        }

        result.nodes.merge(nodes) { (n, _) -> Node in return n }

        let mapper: (UInt64, Relationship) -> (UInt64, Relationship)? = { (key: UInt64, rel: Relationship) in
            guard let fromNodeId = rel.fromNodeId, let toNodeId = rel.toNodeId else {
                print("Relationship was missing id in response. This is most unusual! Please report a bug!")
                return nil
            }
            rel.fromNode = nodes[fromNodeId]
            rel.toNode = nodes[toNodeId]
            return (key, rel)
        }

        let updatedRelationships = Dictionary(uniqueKeysWithValues: relationships.compactMap(mapper))
        result.relationships.merge(updatedRelationships) { (r, _) -> Relationship in return r }

        result.paths += paths
        result.rows += rows

        return result

    }


    /**
     Executes a given block, usually containing multiple cypher queries run and results processed, as a transaction

     Requires an established connection

     Synchronous, so the function will return only when the query result is ready

     - parameter bookamrk: If a transaction bookmark has been given, the Neo4j node will wait until it has received a transaction with that bookmark before this transaction is run. This ensures that in a multi-node setup, the expected queries have been run before this set is.
     - parameter transactionBlock: The block of queries and result processing that make up the transaction. The Transaction object is available to it, so that it can mark it as failed, disable autocommit (on by default), or, after the transaction has been completed, get the transaction bookmark.
     */
    public func executeAsTransaction(mode: TransactionMode = .readonly, bookmark: String? = nil, transactionBlock: @escaping (_ tx: Transaction) throws -> (), transactionCompleteBlock: ((Bool) -> ())? = nil) throws {

        let transaction = Transaction()
        transaction.commitBlock = { succeed in
            if succeed {
                // self.pullSynchronouslyAndIgnore()

                let commitRequest = BoltRequest.commit()
                guard let promise = try self.connection.request(commitRequest) else {
                    let error = BoltClientError.unknownError
                    throw error
                    // return
                }

                promise.whenSuccess { responses in
                    self.currentTransaction = nil
                    transactionCompleteBlock?(true)
                    // self.pullSynchronouslyAndIgnore()
                }

                promise.whenFailure { error in
                    let error = BoltClientError.queryUnsuccessful
                    // throw error
                }
                
            } else {

                let rollbackRequest = BoltRequest.rollback()
                guard let promise = try self.connection.request(rollbackRequest) else {
                    let error = BoltClientError.unknownError
                    throw error
                    // return
                }
                
                promise.whenSuccess { responses in
                    self.currentTransaction = nil
                    transactionCompleteBlock?(false)
                    // self.pullSynchronouslyAndIgnore()
                }
                
                promise.whenFailure { error in
                    print("Error rolling back transaction: \(error)")
                    transactionCompleteBlock?(false)
                    /*
                    let error = BoltClientError.queryUnsuccessful
                    throw error
                     */
                }
            }
        }

        currentTransaction = transaction

        let beginRequest = BoltRequest.begin(mode: mode)
        guard let promise = try self.connection.request(beginRequest) else {
            let error = BoltClientError.unknownError
            throw error
            // return
        }

        promise.whenSuccess { responses in
            
            try? transactionBlock(transaction)
            #if THEO_DEBUG
            print("done transaction block??")
            #endif
            if transaction.autocommit == true {
                try? transaction.commitBlock(transaction.succeed)
                transaction.commitBlock = { _ in }
            }
        }
        
        promise.whenFailure { error in
            print("Error beginning transaction: \(error)")
            // let error = BoltClientError.queryUnsuccessful
            transaction.commitBlock = { _ in }
            // throw error
        }
    }
    
    public func reset(completionBlock: (() -> ())?) throws {
        let req = BoltRequest.reset()
        guard let promise = try self.connection.request(req) else {
            let error = BoltClientError.unknownError
            throw error
        }
        
        promise.whenSuccess { responses in
            if(responses.first?.category != .success) {
                print("No success rolling back, calling completionblock anyway")
            }
            completionBlock?()
        }
        
        promise.whenFailure { error in
            print("Error resetting connection: \(error)")
            completionBlock?()
        }

    }
    
    public func resetSync() throws {
        let group = DispatchGroup()
        group.enter()
        try self.reset {
            group.leave()
        }
        group.wait()
    }
    
    public func rollback(transaction: Transaction, rollbackCompleteBlock: (() -> ())?) throws {
        let rollbackRequest = BoltRequest.rollback()
        guard let promise = try self.connection.request(rollbackRequest) else {
            let error = BoltClientError.unknownError
            throw error
            // return
        }
        
        promise.whenSuccess { responses in
            self.currentTransaction = nil
            if(responses.first?.category != .success) {
                print("No success rolling back, calling completionblock anyway")
            }
            rollbackCompleteBlock?()
        }
        
        promise.whenFailure { error in
            print("Error rolling back transaction: \(error)")
            rollbackCompleteBlock?()
        }

    }

    public func pullSynchronouslyAndIgnore() {
        let pullRequest = BoltRequest.pullAll()

        let dispatchGroup = DispatchGroup()
        dispatchGroup.enter()
        let q = DispatchQueue(label: "pullSynchronouslyAndIgnore")
        q.async {
            guard let promise = try? self.connection.request(pullRequest) else {
                // let error = BoltClientError.unknownError
                // throw error
                dispatchGroup.leave()
                return
            }

            #if THEO_DEBUG
            print("Incoming promise: \(String(describing: promise))")
            #endif
            
            /*promise.whenSuccess { respone in
                print("yay.....1")
                dispatchGroup.leave()
            }
            
            promise.whenFailure { error in
                print("yay.....2")
                dispatchGroup.leave()
            }*/
            
            promise.whenComplete { result in
                #if THEO_DEBUG
                print("yay.....3")
                #endif
                dispatchGroup.leave()
            }

            /*
            _ = promise.map { result in
                print("yay.....4")
                dispatchGroup.leave()
            }*/
            /*_ = promise.map { response in
            // promise.whenSuccess { responses in

                if let bookmark = self.getBookmark() {
                    self.currentTransaction?.bookmark = bookmark
                }
                
                dispatchGroup.leave()
            }*/
        }
        
        dispatchGroup.wait()
    }

    /**
     Pull all data, for use after executing a query that puts the Neo4j bolt server in streaming mode

     Requires an established connection

     Asynchronous, so the function returns straight away. It is not defined what thread the completionblock will run on,
     so if you need it to run on main thread or another thread, make sure to dispatch to this that thread

     - parameter partialQueryResult: If, for instance when executing the Cypher query, a partial QueryResult was given, pass it in here to have it fully populated in the completion result block
     - parameter completionBlock: Completion result-block that provides either a fully update QueryResult if a QueryResult was given, or a partial QueryResult if no prior QueryResult as given. If a failure has occurred, the Result contains an Error to explain what went wrong
     */
    public func pullAll(partialQueryResult: QueryResult = QueryResult(), completionBlock: ((Result<(Bool, QueryResult), Error>) -> ())? = nil) {
        
        let pullRequest = BoltRequest.pullAll()
        guard let promise = try? self.connection.request(pullRequest) else {
            // let error = BoltClientError.unknownError
            // throw error
            return
        }

        promise.whenSuccess { responses in

            let result = self.parseResponses(responses: responses, result: partialQueryResult)
            completionBlock?(.success((true, result)))
        }
        
        promise.whenFailure { error in
            completionBlock?(.failure(error))
        }

    }

    /// Get the current transaction bookmark
    public func getBookmark() -> String? {
        return connection.currentTransactionBookmark
    }

}

extension BoltClient { // Node functions

    //MARK: Create

    public func createAndReturnNode(node: Node, completionBlock: ((Result<Node, Error>) -> ())?) {
        let request = node.createRequest()
        performRequestWithReturnNode(request: request, completionBlock: completionBlock)
    }

    public func createAndReturnNodeSync(node: Node) -> Result<Node, Error> {

        let group = DispatchGroup()
        group.enter()

        var theResult: Result<Node, Error> = .failure(BoltClientError.unknownError)
        createAndReturnNode(node: node) { result in
            theResult = result
            group.leave()
        }

        group.wait()
        return theResult
    }

    public func createNode(node: Node, completionBlock: ((Result<Bool, Error>) -> ())?) {
        let request = node.createRequest(withReturnStatement: false)
        performRequestWithNoReturnNode(request: request, completionBlock: completionBlock)
    }

    public func createNodeSync(node: Node) -> Result<Bool, Error> {

        let group = DispatchGroup()
        group.enter()

        var theResult: Result<Bool, Error> = .failure(BoltClientError.unknownError)
        createNode(node: node) { result in
            theResult = result
            self.pullSynchronouslyAndIgnore()
            group.leave()
        }

        group.wait()
        return theResult
    }

    public func createAndReturnNodes(nodes: [Node], completionBlock: ((Result<[Node], Error>) -> ())?) {
        let request = nodes.createRequest()
        execute(request: request) { response in
            switch response {
            case let .failure(error):
                completionBlock?(.failure(error))
            case let .success((isSuccess, partialQueryResult)):
                if !isSuccess {
                    let error = BoltClientError.queryUnsuccessful
                    completionBlock?(.failure(error))
                } else {
                    self.pullAll(partialQueryResult: partialQueryResult) { response in
                        switch response {
                        case let .failure(error):
                            completionBlock?(.failure(error))
                        case let .success((isSuccess, queryResult)):
                            if !isSuccess {
                                let error = BoltClientError.fetchingRecordsUnsuccessful
                                completionBlock?(.failure(error))
                            } else {
                                let nodes: [Node] = queryResult.nodes.map { $0.value }
                                completionBlock?(.success(nodes))
                            }
                        }
                    }
                }
            }
        }
    }

    public func createAndReturnNodesSync(nodes: [Node]) -> Result<[Node], Error> {

        let group = DispatchGroup()
        group.enter()

        var theResult: Result<[Node], Error> = .failure(BoltClientError.unknownError)
        createAndReturnNodes(nodes: nodes) { result in
            theResult = result
            if(nodes.count != nodes.count) {
                print("Expected nodes in and nodes out to be equal")
            }
            group.leave()
        }

        group.wait()
        return theResult
    }

    public func createNodes(nodes: [Node], completionBlock: ((Result<Bool, Error>) -> ())?) {
        let request = nodes.createRequest(withReturnStatement: false)
        execute(request: request) { response in
            switch response {
            case let .failure(error):
                completionBlock?(.failure(error))
            case let .success((isSuccess, _)):
                completionBlock?(.success(isSuccess))
            }
        }
    }

    public func createNodesSync(nodes: [Node]) -> Result<Bool, Error> {

        let group = DispatchGroup()
        group.enter()

        var theResult: Result<Bool, Error> = .failure(BoltClientError.unknownError)
        createNodes(nodes: nodes) { creationResult in
            self.pullAll(partialQueryResult: QueryResult()) { queryResult in
                theResult = creationResult
                group.leave()
            }
        }

        
        
        group.wait()
        return theResult
    }

    //MARK: Update
    public func updateAndReturnNode(node: Node, completionBlock: ((Result<Node, Error>) -> ())?) {

        let request = node.updateRequest()
        performRequestWithReturnNode(request: request, completionBlock: completionBlock)
    }

    private func performRequestWithReturnNode(request: Request, completionBlock: ((Result<Node, Error>) -> ())?) {
        execute(request: request) { response in
            switch response {
            case let .failure(error):
                completionBlock?(.failure(error))
            case let .success((isSuccess, partialQueryResult)):
                if !isSuccess {
                    let error = BoltClientError.queryUnsuccessful
                    completionBlock?(.failure(error))
                } else {
                    self.pullAll(partialQueryResult: partialQueryResult) { response in
                        switch response {
                        case let .failure(error):
                            completionBlock?(.failure(error))
                        case let .success((isSuccess, queryResult)):
                            if !isSuccess {
                                let error = BoltClientError.fetchingRecordsUnsuccessful
                                completionBlock?(.failure(error))
                            } else {
                                if let (_, node) = queryResult.nodes.first {
                                    completionBlock?(.success(node))
                                } else {
                                    let error = BoltClientError.missingNodeResponse
                                    completionBlock?(.failure(error))
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    public func updateAndReturnNodeSync(node: Node) -> Result<Node, Error> {

        let group = DispatchGroup()
        group.enter()

        var theResult: Result<Node, Error> = .failure(BoltClientError.unknownError)
        updateAndReturnNode(node: node) { result in
            theResult = result
            group.leave()
        }

        group.wait()
        return theResult
    }

    public func updateNode(node: Node, completionBlock: ((Result<Bool, Error>) -> ())?) {

        let request = node.updateRequest()
        performRequestWithNoReturnNode(request: request, completionBlock: completionBlock)
    }

    public func performRequestWithNoReturnNode(request: Request, completionBlock: ((Result<Bool, Error>) -> ())?) {

        execute(request: request) { response in
            switch response {
            case let .failure(error):
                completionBlock?(.failure(error))
            case let .success((isSuccess, _)):
                completionBlock?(.success(isSuccess))
            }
        }
    }

    public func updateNodeSync(node: Node) -> Result<Bool, Error> {

        let group = DispatchGroup()
        group.enter()

        var theResult: Result<Bool, Error> = .failure(BoltClientError.unknownError)
        updateNode(node: node) { result in
            theResult = result
            group.leave()
        }

        group.wait()
        self.pullSynchronouslyAndIgnore()
        return theResult
    }

    public func updateAndReturnNodes(nodes: [Node], completionBlock: ((Result<[Node], Error>) -> ())?) {
        let request = nodes.updateRequest()
        execute(request: request) { response in
            switch response {
            case let .failure(error):
                completionBlock?(.failure(error))
            case let .success((isSuccess, partialQueryResult)):
                if !isSuccess {
                    let error = BoltClientError.queryUnsuccessful
                    completionBlock?(.failure(error))
                } else {
                    self.pullAll(partialQueryResult: partialQueryResult) { response in
                        switch response {
                        case let .failure(error):
                            completionBlock?(.failure(error))
                        case let .success((isSuccess, queryResult)):
                            if !isSuccess {
                                let error = BoltClientError.fetchingRecordsUnsuccessful
                                completionBlock?(.failure(error))
                            } else {
                                let nodes: [Node] = queryResult.nodes.map { $0.value }
                                completionBlock?(.success(nodes))
                            }
                        }
                    }
                }
            }
        }
    }

    public func updateAndReturnNodesSync(nodes: [Node]) -> Result<[Node], Error> {

        let group = DispatchGroup()
        group.enter()

        var theResult: Result<[Node], Error> = .failure(BoltClientError.unknownError)
        updateAndReturnNodes(nodes: nodes) { result in
            theResult = result
            group.leave()
        }

        group.wait()
        return theResult
    }

    public func updateNodes(nodes: [Node], completionBlock: ((Result<Bool, Error>) -> ())?) {
        let request = nodes.updateRequest(withReturnStatement: false)
        execute(request: request) { response in
            switch response {
            case let .failure(error):
                completionBlock?(.failure(error))
            case let .success((isSuccess, _)):
                completionBlock?(.success(isSuccess))
            }
        }
    }

    public func updateNodesSync(nodes: [Node]) -> Result<Bool, Error> {

        let group = DispatchGroup()
        group.enter()

        let resultBox = SendableBox<Result<Bool, Error>>(.failure(BoltClientError.unknownError))
        DispatchQueue.global(qos: .background).async {
            self.updateNodes(nodes: nodes) { result in
                resultBox.value = result
                self.pullSynchronouslyAndIgnore()
                group.leave()
            }
        }

        group.wait()
        return resultBox.value
    }

    //MARK: Delete
    public func deleteNode(node: Node, completionBlock: ((Result<Bool, Error>) -> ())?) {
        let request = node.deleteRequest()
        performRequestWithNoReturnNode(request: request, completionBlock: completionBlock)
    }

    public func deleteNodeSync(node: Node) -> Result<Bool, Error> {

        let group = DispatchGroup()
        group.enter()

        var theResult: Result<Bool, Error> = .failure(BoltClientError.unknownError)
        deleteNode(node: node) { result in
            theResult = result
            self.pullSynchronouslyAndIgnore()
            group.leave()
        }

        group.wait()
        return theResult

    }

    public func deleteNodes(nodes: [Node], completionBlock: ((Result<Bool, Error>) -> ())?) {
        let request = nodes.deleteRequest()
        performRequestWithNoReturnNode(request: request, completionBlock: completionBlock)
    }

    public func deleteNodesSync(nodes: [Node]) -> Result<Bool, Error> {

        let group = DispatchGroup()
        group.enter()

        var theResult: Result<Bool, Error> = .failure(BoltClientError.unknownError)
        deleteNodes(nodes: nodes) { result in
            theResult = result
            self.pullSynchronouslyAndIgnore()
            group.leave()
        }

        group.wait()
        return theResult
    }

    public func nodeBy(id: UInt64, completionBlock: ((Result<Node?, Error>) -> ())?) {
        let query = "MATCH (n) WHERE id(n) = $id RETURN n"
        let params = ["id": Int64(id)]

        // Perform query
        executeCypher(query, params: params) { result in
            switch result {
            case let .failure(error):
                print("Error: \(error)")
                completionBlock?(.failure(error))
            case let .success((isSuccess, parsedResponses)):
                if isSuccess == false {
                    let error = BoltClientError.queryUnsuccessful
                    completionBlock?(.failure(error))
                } else {
                    let nodes = parsedResponses.nodes.values
                    if nodes.count > 1 {
                        let error = BoltClientError.unexpectedNumberOfResponses
                        completionBlock?(.failure(error))
                    } else {
                        completionBlock?(.success(nodes.first))
                    }
                }
            }
        }
    }

    private func queryResultToNodesResult(result: ((Result<(Bool, QueryResult), Error>))) -> (Result<[Node], Error>) {
        switch(result) {
        case let .success(value):
            let (isSuccess, queryResult) = value
            if isSuccess == false {
                let error = BoltClientError.queryUnsuccessful
                return .failure(error)
            } else {
                let nodes: [Node] = Array<Node>(queryResult.nodes.values)
                return .success(nodes)
            }
        case let .failure(error):
            return .failure(error)
        }
    }

    public func nodesWith(labels: [String] = [], andProperties properties: [String:PackProtocol] = [:], skip: UInt64 = 0, limit: UInt64 = 25, completionBlock: ((Result<[Node], Error>) -> ())?) {
        let request = Node.queryFor(labels: labels, andProperties: properties, skip: skip, limit: limit)
        executeWithResult(request: request) { result in
            let transformedResult = self.queryResultToNodesResult(result: result)
            completionBlock?(transformedResult)
        }
    }

    public func nodesWith(properties: [String:PackProtocol] = [:], skip: UInt64 = 0, limit: UInt64 = 25, completionBlock: ((Result<[Node], Error>) -> ())?) {
        let request = Node.queryFor(labels: [], andProperties: properties, skip: skip, limit: limit)
        executeWithResult(request: request) { result in
            let transformedResult = self.queryResultToNodesResult(result: result)
            completionBlock?(transformedResult)
        }
    }

    public func nodesWith(label: String, andProperties properties: [String:PackProtocol] = [:], skip: UInt64 = 0, limit: UInt64 = 25, completionBlock: ((Result<[Node], Error>) -> ())?) {
        let request = Node.queryFor(labels: [label], andProperties: properties, skip: skip, limit: limit)
        executeWithResult(request: request) { result in
            let transformedResult = self.queryResultToNodesResult(result: result)
            completionBlock?(transformedResult)
        }
    }

}

extension BoltClient { // Relationship functions

    // Create

    public func relate(node: Node, to: Node, type: String, properties: [String:PackProtocol] = [:], completionBlock: ((Result<Relationship, Error>) -> ())?) {
        let relationship = Relationship(fromNode: node, toNode: to, type: type, direction: .from, properties: properties)
        let request = relationship.createRequest()
        performRequestWithReturnRelationship(request: request, completionBlock: completionBlock)
    }

    public func relateSync(node: Node, to: Node, type: String, properties: [String:PackProtocol] = [:]) -> Result<Relationship, Error> {
        let group = DispatchGroup()
        group.enter()

        var theResult: Result<Relationship, Error> = .failure(BoltClientError.unknownError)
        relate(node: node, to: to, type: type, properties: properties) { result in
            theResult = result
            group.leave()
        }

        group.wait()
        return theResult
    }

    public func createAndReturnRelationshipsSync(relationships: [Relationship]) -> Result<[Relationship], Error> {
        let request = relationships.createRequest(withReturnStatement: true)
        let group = DispatchGroup()
        group.enter()
        var theResult: Result<[Relationship], Error> = .failure(BoltClientError.unknownError)
        executeWithResult(request: request) { result in
            switch result {
            case let .failure(error):
                theResult = .failure(error)
            case let .success((isSuccess, queryResult)):
                if isSuccess == false {
                    let error = BoltClientError.queryUnsuccessful
                    theResult = .failure(error)
                } else {
                    let relationships: [Relationship] = Array<Relationship>(queryResult.relationships.values)
                    theResult = .success(relationships)
                }
            }
            group.leave()
        }
        group.wait()

        return theResult
    }

    public func createAndReturnRelationships(relationships: [Relationship], completionBlock: ((Result<[Relationship], Error>) -> ())?) {
        let request = relationships.createRequest(withReturnStatement: true)
        executeWithResult(request: request) { result in
            switch result {
            case let .failure(error):
                completionBlock?(.failure(error))
            case let .success((isSuccess, queryResult)):
                if isSuccess == false {
                    let error = BoltClientError.queryUnsuccessful
                    completionBlock?(.failure(error))
                } else {
                    let relationships: [Relationship] = Array<Relationship>(queryResult.relationships.values)
                    completionBlock?(.success(relationships))
                }
            }
        }
    }

    public func createAndReturnRelationshipSync(relationship: Relationship) -> Result<Relationship, Error> {
        let request = relationship.createRequest(withReturnStatement: true)
        let group = DispatchGroup()
        group.enter()
        var theResult: Result<Relationship, Error> = .failure(BoltClientError.unknownError)
        executeWithResult(request: request) { result in
            switch result {
            case let .failure(error):
                theResult = .failure(error)
            case let .success((isSuccess, queryResult)):
                if isSuccess == false {
                    let error = BoltClientError.queryUnsuccessful
                    theResult = .failure(error)
                } else {
                    if queryResult.relationships.count == 0 {
                        let error = BoltClientError.unknownError
                        theResult = .failure(error)
                    } else if queryResult.relationships.count > 1 {
                        print("createAndReturnRelationshipSync() unexpectantly returned more than one relationship, returning first")
                        let relationship = queryResult.relationships.values.first!
                        theResult = .success(relationship)
                    } else {
                        let relationship = queryResult.relationships.values.first!
                        theResult = .success(relationship)
                    }
                }
            }
            group.leave()
        }
        group.wait()

        return theResult
    }

    public func createAndReturnRelationship(relationship: Relationship, completionBlock: ((Result<Relationship, Error>) -> ())?) {
        let request = relationship.createRequest(withReturnStatement: true)
        executeWithResult(request: request) { result in
            switch result {
            case let .failure(error):
                completionBlock?(.failure(error))
            case let .success((isSuccess, queryResult)):
                if isSuccess == false {
                    let error = BoltClientError.queryUnsuccessful
                    completionBlock?(.failure(error))
                } else {
                    if queryResult.relationships.count == 0 {
                        let error = BoltClientError.unknownError
                        completionBlock?(.failure(error))
                    } else if queryResult.relationships.count > 1 {
                        print("createAndReturnRelationship() unexpectantly returned more than one relationship, returning first")
                        let relationship = queryResult.relationships.values.first!
                        completionBlock?(.success(relationship))
                    } else {
                        let relationship = queryResult.relationships.values.first!
                        completionBlock?(.success(relationship))
                    }
                }
            }
        }
    }


    //MARK: Update
    public func updateAndReturnRelationship(relationship: Relationship, completionBlock: ((Result<Relationship, Error>) -> ())?) {

        let request = relationship.updateRequest()
        performRequestWithReturnRelationship(request: request, completionBlock: completionBlock)
    }

    private func performRequestWithReturnRelationship(request: Request, completionBlock: ((Result<Relationship, Error>) -> ())?) {
        execute(request: request) { response in
            switch response {
            case let .failure(error):
                completionBlock?(.failure(error))
            case let .success((isSuccess, partialQueryResult)):
                if !isSuccess {
                    let error = BoltClientError.queryUnsuccessful
                    completionBlock?(.failure(error))
                } else {
                    self.pullAll(partialQueryResult: partialQueryResult) { response in
                        switch response {
                        case let .failure(error):
                            completionBlock?(.failure(error))
                        case let .success((isSuccess, queryResult)):
                            if !isSuccess {
                                let error = BoltClientError.fetchingRecordsUnsuccessful
                                completionBlock?(.failure(error))
                            } else {
                                if let (_, relationship) = queryResult.relationships.first {
                                    completionBlock?(.success(relationship))
                                } else {
                                    let error = BoltClientError.missingRelationshipResponse
                                    completionBlock?(.failure(error))
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    public func updateAndReturnRelationshipSync(relationship: Relationship) -> Result<Relationship, Error> {

        let group = DispatchGroup()
        group.enter()

        var theResult: Result<Relationship, Error> = .failure(BoltClientError.unknownError)
        updateAndReturnRelationship(relationship: relationship) { result in
            theResult = result
            group.leave()
        }

        group.wait()
        return theResult
    }

    public func updateRelationship(relationship: Relationship, completionBlock: ((Result<Bool, Error>) -> ())?) {

        let request = relationship.updateRequest()
        performRequestWithNoReturnRelationship(request: request, completionBlock: completionBlock)
    }

    public func performRequestWithNoReturnRelationship(request: Request, completionBlock: ((Result<Bool, Error>) -> ())?) {

        execute(request: request) { response in
            switch response {
            case let .failure(error):
                completionBlock?(.failure(error))
            case let .success((isSuccess, _)):
                self.pullSynchronouslyAndIgnore()
                completionBlock?(.success(isSuccess))
            }
        }
    }

    public func updateRelationshipSync(relationship: Relationship) -> Result<Bool, Error> {

        let group = DispatchGroup()
        group.enter()

        var theResult: Result<Bool, Error> = .failure(BoltClientError.unknownError)
        updateRelationship(relationship: relationship) { result in
            theResult = result
            group.leave()
        }

        group.wait()
        return theResult
    }

    /*
    public func updateAndReturnRelationships(relationships: [Relationship], completionBlock: ((Result<[Relationship], Error>) -> ())?) {
        let request = relationships.updateRequest()
        execute(request: request) { response in
            switch response {
            case let .failure(error):
                completionBlock?(.failure(error))
            case let .success((isSuccess, partialQueryResult)):
                if !isSuccess {
                    let error = BoltClientError.queryUnsuccessful
                    completionBlock?(.failure(error))
                } else {
                    self.pullAll(partialQueryResult: partialQueryResult) { response in
                        switch response {
                        case let .failure(error):
                            completionBlock?(.failure(error))
                        case let .success((isSuccess, queryResult)):
                            if !isSuccess {
                                let error = Error(BoltClientError.fetchingRecordsUnsuccessful)
                                completionBlock?(.failure(error))
                            } else {
                                let relationships: [Relationship] = queryResult.relationships.map { $0.value }
                                completionBlock?(.success(relationships))
                            }
                        }
                    }
                }
            }
        }
    }

    public func updateAndReturnRelationshipsSync(relationships: [Relationship]) -> Result<[Relationship], Error> {

        let group = DispatchGroup()
        group.enter()

        var theResult: Result<[Relationship], Error> = .failure(BoltClientError.unknownError)
        updateAndReturnRelationships(relationships: relationships) { result in
            theResult = result
            group.leave()
        }

        group.wait()
        return theResult
    }

    public func updateRelationships(relationships: [Relationship], completionBlock: ((Result<Bool, Error>) -> ())?) {
        let request = relationships.updateRequest(withReturnStatement: false)
        execute(request: request) { response in
            switch response {
            case let .failure(error):
                completionBlock?(.failure(error))
            case let .success((isSuccess, _)):
                completionBlock?(.success(isSuccess))
            }
        }
    }

    public func updateRelationshipsSync(relationships: [Relationship]) -> Result<Bool, Error> {

        let group = DispatchGroup()
        group.enter()

        var theResult: Result<Bool, Error> = .failure(BoltClientError.unknownError)
        updateRelationships(relationships: relationships) { result in
            theResult = result
            group.leave()
        }

        group.wait()
        return theResult
    }*/

    //MARK: Delete
    public func deleteRelationship(relationship: Relationship, completionBlock: ((Result<Bool, Error>) -> ())?) {
        let request = relationship.deleteRequest()
        performRequestWithNoReturnRelationship(request: request, completionBlock: completionBlock)
    }

    public func deleteRelationshipSync(relationship: Relationship) -> Result<Bool, Error> {

        let group = DispatchGroup()
        group.enter()

        var theResult: Result<Bool, Error> = .failure(BoltClientError.unknownError)
        deleteRelationship(relationship: relationship) { result in
            theResult = result
            group.leave()
        }

        group.wait()
        return theResult

    }

    /*
    public func deleteRelationships(relationships: [Relationship], completionBlock: ((Result<[Bool], Error>) -> ())?) {
        let request = relationships.deleteRequest()
        performRequestWithNoReturnRelationship(request: request, completionBlock: completionBlock)
    }

    public func deleteRelationshipsSync(relationships: [Relationship]) -> Result<[Bool], Error> {

        let group = DispatchGroup()
        group.enter()

        var theResult: Result<Bool, Error> = .failure(BoltClientError.unknownError)
        deleteRelationships(relationships: relationships) { result in
            theResult = result
            group.leave()
        }

        group.wait()
        return theResult
    }*/

    private func queryResultToRelationshipResult(result: ((Result<(Bool, QueryResult), Error>))) -> (Result<[Relationship], Error>) {
        switch(result) {
        case let .success(value):
            let (isSuccess, queryResult) = value
            if isSuccess == false {
                let error = BoltClientError.queryUnsuccessful
                return .failure(error)
            } else {
                let nodes: [Relationship] = Array<Relationship>(queryResult.relationships.values)
                return .success(nodes)
            }
        case let .failure(error):
            return .failure(error)
        }
    }

    public func relationshipsWith(type: String, andProperties properties: [String:PackProtocol] = [:], skip: UInt64 = 0, limit: UInt64 = 25, completionBlock: ((Result<[Relationship], Error>) -> ())?) {
        let request = Relationship.queryFor(type: type, andProperties: properties, skip: skip, limit: limit)
        executeWithResult(request: request) { result in
            let transformedResult = self.queryResultToRelationshipResult(result: result)
            completionBlock?(transformedResult)
        }
    }

}
