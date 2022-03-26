import Foundation
import PackStream
import Bolt
import NIO

#if os(Linux)
import Dispatch
#endif

typealias BoltRequest = Bolt.Request

open class BoltClient: ClientProtocol {
    
    
    private let hostname: String
    private let port: Int
    private let username: String
    private let password: String
    // private let encryption: Encryption
    private let connection: Connection

    private var currentTransaction: Transaction?
    
    // QoS for all *Sync functions
    private let dispatchQoS: DispatchQoS.QoSClass = .userInitiated

    public enum BoltClientError: Error {
        case missingNodeResponse
        case missingRelationshipResponse
        case queryUnsuccessful
        case unexpectedNumberOfResponses
        case fetchingRecordsUnsuccessful
        case couldNotCreateRelationship
        case unknownError
    }

    required public init(hostname: String = "localhost", port: Int = 7687, username: String = "neo4j", password: String = "neo4j", encryption: Encryption) throws {

        self.hostname = hostname
        self.port = port
        self.username = username
        self.password = password
        // self.encryption = encryption

        let settings = ConnectionSettings(username: username, password: password, userAgent: "Theo 5.2.1")

        let socket: SocketProtocol
        switch encryption {
        case .unencrypted:
            socket = try UnencryptedSocket(hostname: hostname, port: port)
        case .certificateIsSelfSigned, .certificateTrusted(certificatePath: _), .certificateTrustedByAuthority:
            let encSocket = try EncryptedSocket(hostname: hostname, port: port)
            let port = UInt(self.port)

            switch encryption {
            case .unencrypted:
                break
            case .certificateIsSelfSigned:
                encSocket.certificateValidator = UnsecureCertificateValidator(hostname: self.hostname, port: port)
            case let .certificateTrusted(certificatePath: certPath):
                encSocket.certificateValidator = TrustSpecificOrRootCertificateValidator(hostname: self.hostname, port: port, trustedCertificateAtPath: certPath)
            case .certificateTrustedByAuthority:
                encSocket.certificateValidator = TrustRootOnlyCertificateValidator(hostname: self.hostname, port: port)
                
            }
            socket = encSocket
        }

        self.connection = Connection(
            socket: socket,
            settings: settings)
    }
    
    public convenience init(_ configuration: ClientConfigurationProtocol) throws {

        try self.init(
            hostname: configuration.hostname,
            port: configuration.port,
            username: configuration.username,
            password: configuration.password,
            encryption: configuration.encryption
        )
    }



    /**
     Connects to Neo4j given the connection settings BoltClient was initialized with.

     Asynchronous, so the function returns straight away. It is not defined what thread the completionblock will run on,
     so if you need it to run on main thread or another thread, make sure to dispatch to this that thread

     - parameter completionBlock: Completion result-block that provides a Bool to indicate success, or an Error to explain what went wrong
     */
    public func connect(completionBlock: ((Result<Bool, Error>) -> ())? = nil) {

        do {
            try self.connection.connect { (error) in
                if let error = error {
                    completionBlock?(.failure(error))
                } else {
                    completionBlock?(.success(true))
                }
            }
        } catch let error as Connection.ConnectionError {
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
    public func execute(request: Request) -> EventLoopFuture<QueryResult> {
        let future = connection.request(request)
        
        return future.flatMap { responses -> EventLoopFuture<QueryResult> in
            let queryResponse = self.parseResponses(responses: responses)
            return future.eventLoop.makeSucceededFuture(queryResponse)
        }
    }
    
    public func executeSync(request: Request) -> Result<QueryResult, Error> {
        let group = DispatchGroup()
        group.enter()

        var theResult: Result<QueryResult, Error> = .failure(BoltClientError.unknownError)
        DispatchQueue.global(qos: dispatchQoS).async {
            let future = self.execute(request: request)
            do {
                let result = try future.wait()
                theResult = .success(result)
            } catch (let error) {
                theResult = .failure(error)
            }
            group.leave()
        }
        
        group.wait()
        return theResult
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
    public func executeWithResult(request: Request) -> EventLoopFuture<QueryResult> {
        
        let promise = connection.request(request)
        
        return promise.map { responses -> QueryResult in
            let queryResponse = self.parseResponses(responses: responses)
            return queryResponse
        }
        .flatMap { queryResult -> EventLoopFuture<QueryResult> in
            return self.pullAll(partialQueryResult: queryResult)
        }
    }
    
    public func executeWithResultSync(request: Request) -> Result<QueryResult, Error> {
        
        let group = DispatchGroup()
        group.enter()

        var theResult: Result<QueryResult, Error> = .failure(BoltClientError.unknownError)
        DispatchQueue.global(qos: dispatchQoS).async {
            let future = self.executeWithResult(request: request)
            do {
                let result = try future.wait()
                theResult = .success(result)
            } catch (let error) {
                theResult = .failure(error)
            }
            group.leave()
        }
        
        group.wait()
        return theResult
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
    public func executeCypher(_ query: String, params: Dictionary<String,PackProtocol>? = nil) -> EventLoopFuture<QueryResult> {

        let cypherRequest = BoltRequest.run(statement: query, parameters: Map(dictionary: params ?? [:]))

        return execute(request: cypherRequest)
            .flatMap { queryResult -> EventLoopFuture<QueryResult> in
                return self.pullAll(partialQueryResult: queryResult)
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
    public func executeCypher(_ query: String, params: [String:PackProtocol] = [:]) -> EventLoopFuture<QueryResult> {
        let request = Bolt.Request.run(statement: query, parameters: Map(dictionary: params))
        return self.executeWithResult(request: request)
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

        var theResult: Result<QueryResult, Error>! = nil
        let dispatchGroup = DispatchGroup()

        // Perform query
        dispatchGroup.enter()
        var partialResult = QueryResult()
        DispatchQueue.global(qos: dispatchQoS).async {
            let future = self.executeCypher(query, params: params)
            do {
                let _partialResult = try future.wait()
                theResult = .success(_partialResult) // TODO: hack for now
                partialResult = _partialResult
            } catch (let error) {
                theResult = .failure(error)
            }
            dispatchGroup.leave()
        }
        dispatchGroup.wait()
        if theResult != nil {
            return theResult
        }

        // Stream and parse results
        dispatchGroup.enter()
        DispatchQueue.global(qos: dispatchQoS).async {
            let future = self.pullAll(partialQueryResult: partialResult)
            do {
                let parsedResponses = try future.wait()
                theResult = .success(parsedResponses)
            } catch (let error) {
                theResult = .failure(error)
            }
            dispatchGroup.leave()
        }

        dispatchGroup.wait()
        return theResult
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
    public func executeAsTransaction(mode: Request.TransactionMode = .readonly, bookmark: String? = nil, transactionBlock: @escaping (_ tx: Transaction) throws -> (), transactionCompleteBlock: ((Bool) -> ())? = nil) throws {

        let transaction = Transaction()
        transaction.commitBlock = { succeed in
            if succeed {

                let commitRequest = BoltRequest.commit()
                
                // run commit future
                #if THEO_DEBUG
                print("executeAsTransaction - starting transaction commit")
                #endif
                let result = self.executeSync(request: commitRequest)
                switch result {
                case let .failure(error):
                    #if THEO_DEBUG
                    print("executeAsTransaction - commit error: \(error)")
                    #endif
                    // let error = BoltClientError.queryUnsuccessful
                    
                case .success:
                    #if THEO_DEBUG
                    print("executeAsTransaction - commit success")
                    #endif
                    self.currentTransaction = nil
                    transactionCompleteBlock?(true)
                }
                
            } else {

                let rollbackRequest = BoltRequest.rollback()
                
                // run rollback future
                #if THEO_DEBUG
                print("executeAsTransaction - starting transaction rollback")
                #endif
                let result = self.executeSync(request: rollbackRequest)
                switch result {
                case let .failure(error):
                    #if THEO_DEBUG
                    print("executeAsTransaction - rollback error: \(error)")
                    #endif
                    transactionCompleteBlock?(false)
                    
                case .success:
                    #if THEO_DEBUG
                    print("executeAsTransaction - rollback success")
                    #endif
                    self.currentTransaction = nil
                    transactionCompleteBlock?(false)
                }
            }
        }

        currentTransaction = transaction

        let beginRequest = BoltRequest.begin(mode: mode)
        
        #if THEO_DEBUG
        print("executeAsTransaction - starting transaction begin")
        #endif
        let result = executeSync(request: beginRequest)
        switch result {
        case let .failure(error):
            #if THEO_DEBUG
            print("executeAsTransaction - transaction begin error: \(error)")
            #endif
            // let error = BoltClientError.queryUnsuccessful
            transaction.commitBlock = { _ in }
            
        case .success:
            #if THEO_DEBUG
            print("executeAsTransaction - transaction begin success")
            #endif
            try? transactionBlock(transaction)
            #if THEO_DEBUG
            print("executeAsTransaction - done transaction block")
            #endif
            if transaction.autocommit == true {
                try? transaction.commitBlock(transaction.succeed)
                transaction.commitBlock = { _ in }
            }
        }
    }
    
    public func reset(completionBlock: (() -> ())?) throws {
        let req = BoltRequest.reset()
        let promise = self.connection.request(req)
        
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
        
        let group = DispatchGroup()
        group.enter()
        var theResult: Result<[Response], Error> = .failure(BoltClientError.unknownError)
        DispatchQueue.global(qos: self.dispatchQoS).async {
            do {
                let response = try promise.wait()
                theResult = .success(response)
            } catch (let error) {
                theResult = .failure(error)
            }
            group.leave()
        }
        group.wait()
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
        let promise = self.connection.request(rollbackRequest)
        
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
        
        let group = DispatchGroup()
        group.enter()
        var theResult: Result<[Response], Error> = .failure(BoltClientError.unknownError)
        DispatchQueue.global(qos: self.dispatchQoS).async {
            do {
                let response = try promise.wait()
                theResult = .success(response)
            } catch (let error) {
                theResult = .failure(error)
            }
            group.leave()
        }
        group.wait()

    }
    
    /// Get the current transaction bookmark
    public func getBookmark() -> String? {
        return connection.currentTransactionBookmark
    }

    /**
     Pull all data, for use after executing a query that puts the Neo4j bolt server in streaming mode

     Requires an established connection

     Asynchronous, so the function returns straight away. It is not defined what thread the completionblock will run on,
     so if you need it to run on main thread or another thread, make sure to dispatch to this that thread

     - parameter partialQueryResult: If, for instance when executing the Cypher query, a partial QueryResult was given, pass it in here to have it fully populated in the completion result block
     - parameter completionBlock: Completion result-block that provides either a fully update QueryResult if a QueryResult was given, or a partial QueryResult if no prior QueryResult as given. If a failure has occurred, the Result contains an Error to explain what went wrong
     */
    private func pullAll(partialQueryResult: QueryResult = QueryResult()) -> EventLoopFuture<QueryResult> {
        
        let pullRequest = BoltRequest.pullAll()
        let future = self.connection.request(pullRequest)

        return future.flatMap { responses -> EventLoopFuture<QueryResult> in
            let result = self.parseResponses(responses: responses, result: partialQueryResult)
            return future.eventLoop.makeSucceededFuture(result)
        }
    }
    
    private func pullAllAndIgnore() -> EventLoopFuture<Void> {
        
        let pullRequest = BoltRequest.pullAll()
        let future = self.connection.request(pullRequest)

        return future.flatMap { responses -> EventLoopFuture<Void> in
            return future.eventLoop.makeSucceededVoidFuture()
        }
    }
}

extension BoltClient { // Node functions
    
    private func performRequestWithNoReturnNode(request: Request) -> EventLoopFuture<Void> {
        let future = execute(request: request)
        return future.flatMap { queryResult -> EventLoopFuture<Void> in
            return future.eventLoop.makeSucceededVoidFuture()
        }
    }
    
    private func performRequestWithReturnNode(request: Request) -> EventLoopFuture<Node> {
        
        let future = execute(request: request)
        return future.flatMap { queryResult -> EventLoopFuture<Node> in
            return self.pullAll(partialQueryResult: queryResult)
                .flatMap { queryResult -> EventLoopFuture<Node> in
                    if let (_, value) = queryResult.nodes.first {
                        return future.eventLoop.makeSucceededFuture(value)
                    } else {
                        return future.eventLoop.makeFailedFuture(BoltClientError.missingNodeResponse)
                    }
            }
        }
    }

    // MARK: Create

    public func createAndReturnNode(node: Node) -> EventLoopFuture<Node> {
        let request = node.createRequest()
        return performRequestWithReturnNode(request: request)
    }

    public func createAndReturnNodeSync(node: Node) -> Result<Node, Error> {
        
        let group = DispatchGroup()
        group.enter()
        
        var theResult: Result<Node, Error> = .failure(BoltClientError.unknownError)
        DispatchQueue.global(qos: dispatchQoS).async {
            let future = self.createAndReturnNode(node: node)
            do {
                let node = try future.wait()
                theResult = .success(node)
            } catch (let error) {
                theResult = .failure(error)
            }
            group.leave()
        }

        group.wait()
        return theResult
    }

    public func createNode(node: Node) -> EventLoopFuture<Void> {
        let request = node.createRequest(withReturnStatement: false)
        let future = performRequestWithNoReturnNode(request: request)
        return future.flatMap { _ in
            return self.pullAllAndIgnore()
        }
    }

    public func createNodeSync(node: Node) -> Result<Bool, Error> {

        let group = DispatchGroup()
        group.enter()

        var theResult: Result<Bool, Error> = .failure(BoltClientError.unknownError)
        DispatchQueue.global(qos: dispatchQoS).async {
            let future = self.createNode(node: node)
            do {
                let _ = try future.wait()
                theResult = .success(true)
            } catch (let error) {
                theResult = .failure(error)
            }
            group.leave()
        }
        
        group.wait()
        return theResult
        
    }

    public func createAndReturnNodes(nodes: [Node]) -> EventLoopFuture<[Node]> {
        let request = nodes.createRequest()
        let future = execute(request: request)
        return future.flatMap { partialQueryResult -> EventLoopFuture<[Node]> in
            return self.pullAll(partialQueryResult: partialQueryResult)
                .flatMap { queryResult -> EventLoopFuture<[Node]> in
                    let nodes: [Node] = queryResult.nodes.map { $0.value }
                    return future.eventLoop.makeSucceededFuture(nodes)
            }
        }
    }

    public func createAndReturnNodesSync(nodes: [Node]) -> Result<[Node], Error> {

        let group = DispatchGroup()
        group.enter()

        var theResult: Result<[Node], Error> = .failure(BoltClientError.unknownError)
        DispatchQueue.global(qos: dispatchQoS).async {
            let future = self.createAndReturnNodes(nodes: nodes)
            do {
                let nodes = try future.wait()
                theResult = .success(nodes)
            } catch (let error) {
                theResult = .failure(error)
            }
            group.leave()
        }

        group.wait()
        return theResult
    }

    public func createNodes(nodes: [Node]) -> EventLoopFuture<Void> {
        let request = nodes.createRequest(withReturnStatement: false)
        let future = execute(request: request)
        return future.flatMap { queryResult -> EventLoopFuture<Void> in
            return future.eventLoop.makeSucceededVoidFuture()
        }
    }

    public func createNodesSync(nodes: [Node]) -> Result<Bool, Error> {

        let group = DispatchGroup()
        group.enter()

        var theResult: Result<Bool, Error> = .failure(BoltClientError.unknownError)
        DispatchQueue.global(qos: dispatchQoS).async {
            let future = self.createNodes(nodes: nodes)
            do {
                let _ = try future.wait()
                theResult = .success(true)
            } catch (let error) {
                theResult = .failure(error)
            }
            group.leave()
        }
        
        group.wait()
        return theResult
    }

    // MARK: Update
    
    public func updateAndReturnNode(node: Node) -> EventLoopFuture<Node> {

        let request = node.updateRequest()
        return performRequestWithReturnNode(request: request)
    }

    public func updateAndReturnNodeSync(node: Node) -> Result<Node, Error> {

        let group = DispatchGroup()
        group.enter()

        var theResult: Result<Node, Error> = .failure(BoltClientError.unknownError)
        DispatchQueue.global(qos: dispatchQoS).async {
            let future = self.updateAndReturnNode(node: node)
            do {
                let node = try future.wait()
                theResult = .success(node)
            } catch (let error) {
                theResult = .failure(error)
            }
            group.leave()
        }

        group.wait()
        return theResult
    }

    public func updateNode(node: Node) -> EventLoopFuture<Void> {

        let request = node.updateRequest()
        return performRequestWithNoReturnNode(request: request).flatMap { _ in
            return self.pullAllAndIgnore()
        }
    }

    public func updateNodeSync(node: Node) -> Result<Bool, Error> {

        let group = DispatchGroup()
        group.enter()

        var theResult: Result<Bool, Error> = .failure(BoltClientError.unknownError)
        DispatchQueue.global(qos: dispatchQoS).async {
            let future = self.updateNode(node: node)
            do {
                let _ = try future.wait()
                theResult = .success(true)
            } catch (let error) {
                theResult = .failure(error)
            }
            group.leave()
        }
        
        group.wait()
        return theResult
    }

    public func updateAndReturnNodes(nodes: [Node]) -> EventLoopFuture<[Node]> {
        let request = nodes.updateRequest()
        let future = execute(request: request)
        return future.flatMap { partialQueryResult -> EventLoopFuture<[Node]> in
            return self.pullAll(partialQueryResult: partialQueryResult)
                .flatMap { queryResult -> EventLoopFuture<[Node]> in
                    let nodes: [Node] = queryResult.nodes.map { $0.value }
                    return future.eventLoop.makeSucceededFuture(nodes)
            }
        }
    }

    public func updateAndReturnNodesSync(nodes: [Node]) -> Result<[Node], Error> {

        let group = DispatchGroup()
        group.enter()

        var theResult: Result<[Node], Error> = .failure(BoltClientError.unknownError)
        DispatchQueue.global(qos: dispatchQoS).async {
            let future = self.updateAndReturnNodes(nodes: nodes)
            do {
                let nodes = try future.wait()
                theResult = .success(nodes)
            } catch (let error) {
                theResult = .failure(error)
            }
            group.leave()
        }

        group.wait()
        return theResult
    }

    public func updateNodes(nodes: [Node]) -> EventLoopFuture<Void> {
        let request = nodes.updateRequest(withReturnStatement: false)
        let future = execute(request: request)
        return future.flatMap { queryResult -> EventLoopFuture<Void> in
            return future.eventLoop.makeSucceededVoidFuture().flatMap { _ in
                return self.pullAllAndIgnore()
            }
        }
    }

    public func updateNodesSync(nodes: [Node]) -> Result<Bool, Error> {

        let group = DispatchGroup()
        group.enter()

        var theResult: Result<Bool, Error> = .failure(BoltClientError.unknownError)
        DispatchQueue.global(qos: dispatchQoS).async {
            let future = self.updateNodes(nodes: nodes)
            do {
                let _ = try future.wait()
                theResult = .success(true)
            } catch (let error) {
                theResult = .failure(error)
            }
            group.leave()
        }
        
        group.wait()
        return theResult
    }

    // MARK: Delete
    
    public func deleteNode(node: Node) -> EventLoopFuture<Void> {
        let request = node.deleteRequest()
        return performRequestWithNoReturnNode(request: request).flatMap { _ in
            return self.pullAllAndIgnore()
        }
    }

    public func deleteNodeSync(node: Node) -> Result<Bool, Error> {

        let group = DispatchGroup()
        group.enter()

        var theResult: Result<Bool, Error> = .failure(BoltClientError.unknownError)
        DispatchQueue.global(qos: dispatchQoS).async {
            let future = self.deleteNode(node: node)
            do {
                let _ = try future.wait()
                theResult = .success(true)
            } catch (let error) {
                theResult = .failure(error)
            }
            group.leave()
        }

        group.wait()
        return theResult
    }

    public func deleteNodes(nodes: [Node]) -> EventLoopFuture<Void> {
        let request = nodes.deleteRequest()
        return performRequestWithNoReturnNode(request: request).flatMap { _ in
            return self.pullAllAndIgnore()
        }
    }

    public func deleteNodesSync(nodes: [Node]) -> Result<Bool, Error> {

        let group = DispatchGroup()
        group.enter()

        var theResult: Result<Bool, Error> = .failure(BoltClientError.unknownError)
        DispatchQueue.global(qos: dispatchQoS).async {
            let future = self.deleteNodes(nodes: nodes)
            do {
                let _ = try future.wait()
                theResult = .success(true)
            } catch (let error) {
                theResult = .failure(error)
            }
            group.leave()
        }

        group.wait()
        return theResult
    }
    
    // MARK: Nodes
    
    public func nodeBy(id: UInt64) -> EventLoopFuture<Node> {
        let query = "MATCH (n) WHERE id(n) = $id RETURN n"
        let params = ["id": Int64(id)]
        
        let future = executeCypher(query, params: params)
        return future.flatMap { queryResult -> EventLoopFuture<Node> in
            let nodes = queryResult.nodes.values
            if nodes.count > 1 {
                return future.eventLoop.makeFailedFuture(BoltClientError.unexpectedNumberOfResponses)
            } else if let node = nodes.first {
                return future.eventLoop.makeSucceededFuture(node)
            } else {
                return future.eventLoop.makeFailedFuture(BoltClientError.unexpectedNumberOfResponses)
            }
        }
    }
        
    public func nodeBySync(id: UInt64) -> Result<Node, Error> {
        let group = DispatchGroup()
        group.enter()

        var theResult: Result<Node, Error> = .failure(BoltClientError.unknownError)
        DispatchQueue.global(qos: dispatchQoS).async {
            let future = self.nodeBy(id: id)
            do {
                let node = try future.wait()
                theResult = .success(node)
            } catch {
                theResult = .failure(BoltClientError.unknownError)
            }
            group.leave()
        }
        
        group.wait()
        return theResult
    }

    public func nodesWith(labels: [String] = [], andProperties properties: [String:PackProtocol] = [:], skip: UInt64 = 0, limit: UInt64 = 25) -> EventLoopFuture<[Node]> {
        let request = Node.queryFor(labels: labels, andProperties: properties, skip: skip, limit: limit)
        let future = executeWithResult(request: request)
        return future.flatMap { queryResult -> EventLoopFuture<[Node]> in
            let nodes: [Node] = Array<Node>(queryResult.nodes.values)
            return future.eventLoop.makeSucceededFuture(nodes)
        }
    }
    
    public func nodesWithSync(labels: [String] = [], andProperties properties: [String:PackProtocol] = [:], skip: UInt64 = 0, limit: UInt64 = 25) -> Result<[Node], Error> {
        let group = DispatchGroup()
        group.enter()

        var theResult: Result<[Node], Error> = .failure(BoltClientError.unknownError)
        DispatchQueue.global(qos: dispatchQoS).async {
            let future = self.nodesWith(labels: labels, andProperties: properties, skip: skip, limit: limit)
            do {
                let nodes = try future.wait()
                theResult = .success(nodes)
            } catch {
                theResult = .failure(BoltClientError.unknownError)
            }
            group.leave()
        }
        
        group.wait()
        return theResult
    }
    
    public func nodesWith(properties: [String:PackProtocol] = [:], skip: UInt64 = 0, limit: UInt64 = 25) -> EventLoopFuture<[Node]> {
        let request = Node.queryFor(labels: [], andProperties: properties, skip: skip, limit: limit)
        let future = executeWithResult(request: request)
        return future.flatMap { queryResult -> EventLoopFuture<[Node]> in
            let nodes: [Node] = Array<Node>(queryResult.nodes.values)
            return future.eventLoop.makeSucceededFuture(nodes)
        }
    }
    
    public func nodesWithSync(properties: [String:PackProtocol] = [:], skip: UInt64 = 0, limit: UInt64 = 25) -> Result<[Node], Error> {
        let group = DispatchGroup()
        group.enter()

        var theResult: Result<[Node], Error> = .failure(BoltClientError.unknownError)
        DispatchQueue.global(qos: dispatchQoS).async {
            let future = self.nodesWith(properties: properties, skip: skip, limit: limit)
            do {
                let nodes = try future.wait()
                theResult = .success(nodes)
            } catch {
                theResult = .failure(BoltClientError.unknownError)
            }
            group.leave()
        }
        
        group.wait()
        return theResult
    }
    
    public func nodesWith(label: String, andProperties properties: [String:PackProtocol] = [:], skip: UInt64 = 0, limit: UInt64 = 25) -> EventLoopFuture<[Node]> {
        let request = Node.queryFor(labels: [label], andProperties: properties, skip: skip, limit: limit)
        let future = executeWithResult(request: request)
        return future.flatMap { queryResult -> EventLoopFuture<[Node]> in
            let nodes: [Node] = Array<Node>(queryResult.nodes.values)
            return future.eventLoop.makeSucceededFuture(nodes)
        }
    }
    
    public func nodesWithSync(label: String, andProperties properties: [String:PackProtocol] = [:], skip: UInt64 = 0, limit: UInt64 = 25) -> Result<[Node], Error> {
        let group = DispatchGroup()
        group.enter()

        var theResult: Result<[Node], Error> = .failure(BoltClientError.unknownError)
        DispatchQueue.global(qos: dispatchQoS).async {
            let future = self.nodesWith(label: label, andProperties: properties, skip: skip, limit: limit)
            do {
                let nodes = try future.wait()
                theResult = .success(nodes)
            } catch {
                theResult = .failure(BoltClientError.unknownError)
            }
            group.leave()
        }
        
        group.wait()
        return theResult
    }

}

extension BoltClient { // Relationship functions
    
    private func performRequestWithReturnRelationship(request: Request) -> EventLoopFuture<Relationship> {
        
        let future = execute(request: request)
        return future.flatMap { partialQueryResult -> EventLoopFuture<Relationship> in
            self.pullAll(partialQueryResult: partialQueryResult)
                .flatMap { queryResult -> EventLoopFuture<Relationship> in
                    if let (_, relationship) = queryResult.relationships.first {
                        return future.eventLoop.makeSucceededFuture(relationship)
                    } else {
                        return future.eventLoop.makeFailedFuture(BoltClientError.missingRelationshipResponse)
                    }
            }
        }
    }
    
    private func performRequestWithNoReturnRelationship(request: Request) -> EventLoopFuture<Void> {
        let future = execute(request: request)
        return future.flatMap { queryResult -> EventLoopFuture<Void> in
            return future.eventLoop.makeSucceededVoidFuture()
        }
    }

    // MARK: Relate

    public func relate(node: Node, to: Node, type: String, properties: [String:PackProtocol] = [:]) -> EventLoopFuture<Relationship> {
        let relationship = Relationship(fromNode: node, toNode: to, type: type, direction: .from, properties: properties)
        let request = relationship.createRequest()
        return performRequestWithReturnRelationship(request: request)
    }

    public func relateSync(node: Node, to: Node, type: String, properties: [String:PackProtocol] = [:]) -> Result<Relationship, Error> {
        let group = DispatchGroup()
        group.enter()

        var theResult: Result<Relationship, Error> = .failure(BoltClientError.unknownError)
        DispatchQueue.global(qos: dispatchQoS).async {
            let future = self.relate(node: node, to: to, type: type, properties: properties)
            do {
                let relationship = try future.wait()
                theResult = .success(relationship)
            } catch {
                theResult = .failure(BoltClientError.unknownError)
            }
            group.leave()
        }

        group.wait()
        return theResult
    }
    
    // MARK: Relationships
    
    public func createAndReturnRelationships(relationships: [Relationship]) -> EventLoopFuture<[Relationship]> {
        let request = relationships.createRequest(withReturnStatement: true)
        let future = executeWithResult(request: request)
        return future.flatMap { queryResult -> EventLoopFuture<[Relationship]> in
            let relationships: [Relationship] = Array<Relationship>(queryResult.relationships.values)
            return future.eventLoop.makeSucceededFuture(relationships)
        }
    }

    public func createAndReturnRelationshipsSync(relationships: [Relationship]) -> Result<[Relationship], Error> {
        let group = DispatchGroup()
        group.enter()
        
        var theResult: Result<[Relationship], Error> = .failure(BoltClientError.unknownError)
        DispatchQueue.global(qos: dispatchQoS).async {
            let future = self.createAndReturnRelationships(relationships: relationships)
            do {
                let relationship = try future.wait()
                theResult = .success(relationship)
            } catch {
                theResult = .failure(BoltClientError.unknownError)
            }
            group.leave()
        }

        group.wait()
        return theResult
    }
    
    public func createAndReturnRelationship(relationship: Relationship) -> EventLoopFuture<Relationship> {
        let request = relationship.createRequest(withReturnStatement: true)
        let future = executeWithResult(request: request)
        return future.flatMap { queryResult -> EventLoopFuture<Relationship> in
            if queryResult.relationships.count == 0 {
                return future.eventLoop.makeFailedFuture(BoltClientError.unknownError)
            } else if queryResult.relationships.count == 1, let first = queryResult.relationships.values.first {
                return future.eventLoop.makeSucceededFuture(first)
            } else {
                print("createAndReturnRelationship() unexpectantly returned more than one relationship, returning first")
                return future.eventLoop.makeFailedFuture(BoltClientError.unknownError)
            }
        }
    }

    public func createAndReturnRelationshipSync(relationship: Relationship) -> Result<Relationship, Error> {
        let group = DispatchGroup()
        group.enter()
        
        var theResult: Result<Relationship, Error> = .failure(BoltClientError.unknownError)
        DispatchQueue.global(qos: dispatchQoS).async {
            let future = self.createAndReturnRelationship(relationship: relationship)
            do {
                let relationship = try future.wait()
                theResult = .success(relationship)
            } catch {
                theResult = .failure(BoltClientError.unknownError)
            }
            group.leave()
        }
        
        group.wait()
        return theResult
    }

    public func updateAndReturnRelationship(relationship: Relationship) -> EventLoopFuture<Relationship> {
        let request = relationship.updateRequest()
        return performRequestWithReturnRelationship(request: request)
    }

    public func updateAndReturnRelationshipSync(relationship: Relationship) -> Result<Relationship, Error> {
        let group = DispatchGroup()
        group.enter()

        var theResult: Result<Relationship, Error> = .failure(BoltClientError.unknownError)
        DispatchQueue.global(qos: dispatchQoS).async {
            let future = self.updateAndReturnRelationship(relationship: relationship)
            do {
                let relationship = try future.wait()
                theResult = .success(relationship)
            } catch {
                theResult = .failure(BoltClientError.unknownError)
            }
            group.leave()
        }

        group.wait()
        return theResult
    }

    public func updateRelationship(relationship: Relationship) -> EventLoopFuture<Void> {
        let request = relationship.updateRequest()
        return performRequestWithNoReturnRelationship(request: request).flatMap { _ in
            return self.pullAllAndIgnore()
        }
    }

    public func updateRelationshipSync(relationship: Relationship) -> Result<Bool, Error> {

        let group = DispatchGroup()
        group.enter()

        var theResult: Result<Bool, Error> = .failure(BoltClientError.unknownError)
        DispatchQueue.global(qos: dispatchQoS).async {
            let future = self.updateRelationship(relationship: relationship)
            do {
                let _ = try future.wait()
                theResult = .success(true)
            } catch {
                theResult = .failure(BoltClientError.unknownError)
            }
            group.leave()
        }

        group.wait()
        return theResult
    }

    // TODO: Determine if these are needed going forward
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

    public func deleteRelationship(relationship: Relationship) -> EventLoopFuture<Void> {
        let request = relationship.deleteRequest()
        return performRequestWithNoReturnRelationship(request: request)
    }

    public func deleteRelationshipSync(relationship: Relationship) -> Result<Bool, Error> {
        let group = DispatchGroup()
        group.enter()

        var theResult: Result<Bool, Error> = .failure(BoltClientError.unknownError)
        DispatchQueue.global(qos: dispatchQoS).async {
            let future = self.deleteRelationship(relationship: relationship)
            do {
                let _ = try future.wait()
                theResult = .success(true)
            } catch {
                theResult = .failure(BoltClientError.unknownError)
            }
            group.leave()
        }

        group.wait()
        return theResult
    }

    // TODO: Determine if these are needed going forward
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
    
    public func relationshipsWith(type: String, andProperties properties: [String:PackProtocol] = [:], skip: UInt64 = 0, limit: UInt64 = 25) -> EventLoopFuture<[Relationship]> {
        let request = Relationship.queryFor(type: type, andProperties: properties, skip: skip, limit: limit)
        let future = executeWithResult(request: request)
        return future.flatMap { queryResult -> EventLoopFuture<[Relationship]> in
            let nodes: [Relationship] = Array<Relationship>(queryResult.relationships.values)
            return future.eventLoop.makeSucceededFuture(nodes)
        }
    }
    
    public func relationshipsWithSync(type: String, andProperties properties: [String:PackProtocol] = [:], skip: UInt64 = 0, limit: UInt64 = 25) -> Result<[Relationship], Error> {
        let group = DispatchGroup()
        group.enter()

        var theResult: Result<[Relationship], Error> = .failure(BoltClientError.unknownError)
        DispatchQueue.global(qos: dispatchQoS).async {
            let future = self.relationshipsWith(type: type, andProperties: properties, skip: skip, limit: limit)
            do {
                let relationships = try future.wait()
                theResult = .success(relationships)
            } catch {
                theResult = .failure(BoltClientError.unknownError)
            }
            group.leave()
        }

        group.wait()
        return theResult
        
    }

}
