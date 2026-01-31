import Foundation
import XCTest
@testable import Theo

class Theo_003_BoltPoolClientTests: Theo_000_BoltClientTests {

    nonisolated(unsafe) static var pool: BoltPoolClient!
    var clientForSuperclass: ClientProtocol!
    
    override static func setUp() {
        super.setUp()
        pool = try! BoltPoolClient(super.configuration, poolSize: 1...5)
    }
    
    override func setUp() {
        super.setUp()
        clientForSuperclass = Theo_003_BoltPoolClientTests.pool.getClient()
        
    }
    
    override func tearDown() {
        super.tearDown()
        Theo_003_BoltPoolClientTests.pool.release(clientForSuperclass)
    }
    
    override func makeClient(mode: ClientConfigMode = .any) throws -> ClientProtocol {
        return clientForSuperclass
    }
}
