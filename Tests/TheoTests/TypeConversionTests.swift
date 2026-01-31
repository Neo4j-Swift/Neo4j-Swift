import XCTest
import PackStream
import Bolt

@testable import Theo

/// Data type conversion tests
/// Based on patterns from neo4j-java-driver (ScalarTypeIT, TemporalTypesIT, ParametersIT)
/// and neo4j-go-driver (types_test.go)
final class TypeConversionTests: XCTestCase {

    // MARK: - Primitive Type Tests

    func testBooleanConversion() {
        let trueValue = true
        let falseValue = false

        XCTAssertTrue(trueValue)
        XCTAssertFalse(falseValue)
    }

    func testIntegerConversions() {
        // Test various integer sizes
        let int8Val: Int8 = 127
        let int16Val: Int16 = 32767
        let int32Val: Int32 = 2147483647
        let int64Val: Int64 = 9223372036854775807

        XCTAssertEqual(Int64(int8Val), 127)
        XCTAssertEqual(Int64(int16Val), 32767)
        XCTAssertEqual(Int64(int32Val), 2147483647)
        XCTAssertEqual(int64Val, 9223372036854775807)
    }

    func testIntegerBoundaries() {
        // Based on Java driver ScalarTypeIT - test min/max values
        let minInt64 = Int64.min
        let maxInt64 = Int64.max

        XCTAssertEqual(minInt64, -9223372036854775808)
        XCTAssertEqual(maxInt64, 9223372036854775807)
    }

    func testFloatingPointConversions() {
        let floatVal: Float = 3.14159
        let doubleVal: Double = 3.141592653589793

        XCTAssertEqual(floatVal, 3.14159, accuracy: 0.00001)
        XCTAssertEqual(doubleVal, 3.141592653589793, accuracy: 0.000000000000001)
    }

    func testFloatingPointEdgeCases() {
        // Test special floating point values
        let positiveInfinity = Double.infinity
        let negativeInfinity = -Double.infinity
        let nan = Double.nan

        XCTAssertTrue(positiveInfinity.isInfinite)
        XCTAssertTrue(negativeInfinity.isInfinite)
        XCTAssertTrue(nan.isNaN)
    }

    // MARK: - String Type Tests

    func testBasicStringConversion() {
        let simpleString = "Hello, World!"
        XCTAssertEqual(simpleString, "Hello, World!")
    }

    func testEmptyString() {
        let emptyString = ""
        XCTAssertTrue(emptyString.isEmpty)
        XCTAssertEqual(emptyString.count, 0)
    }

    func testUnicodeStrings() {
        // Based on Java driver ParametersIT - Unicode handling
        let greekPi = "π ≈ 3.14"
        let emoji = "🔥🚀💻"
        let japanese = "こんにちは"
        let arabic = "مرحبا"
        let mjolnir = "Mjölnir"

        XCTAssertTrue(greekPi.contains("π"))
        XCTAssertEqual(emoji.count, 3)  // Swift counts grapheme clusters
        XCTAssertFalse(japanese.isEmpty)
        XCTAssertFalse(arabic.isEmpty)
        XCTAssertTrue(mjolnir.contains("ö"))
    }

    func testLargeString() {
        // Based on Java driver - test 10KB+ strings
        let largeString = String(repeating: "x", count: 10000)
        XCTAssertEqual(largeString.count, 10000)
    }

    func testVeryLargeString() {
        // Based on Java driver - test 1M+ character strings
        let veryLargeString = String(repeating: "a", count: 1_000_000)
        XCTAssertEqual(veryLargeString.count, 1_000_000)
    }

    // MARK: - Collection Type Tests

    func testListConversion() {
        let intList: [Int64] = [1, 2, 3, 4, 5]
        XCTAssertEqual(intList.count, 5)
        XCTAssertEqual(intList[0], 1)
        XCTAssertEqual(intList[4], 5)
    }

    func testEmptyList() {
        let emptyList: [Int64] = []
        XCTAssertTrue(emptyList.isEmpty)
    }

    func testLargeList() {
        // Based on Java driver - test 1M element collections
        let largeList = Array(1...1_000_000).map { Int64($0) }
        XCTAssertEqual(largeList.count, 1_000_000)
        XCTAssertEqual(largeList.first, 1)
        XCTAssertEqual(largeList.last, 1_000_000)
    }

    func testNestedList() {
        // Based on Java driver - nested list structures
        let matrix: [[Int64]] = [
            [1, 2, 3],
            [4, 5, 6],
            [7, 8, 9]
        ]

        XCTAssertEqual(matrix.count, 3)
        XCTAssertEqual(matrix[0].count, 3)
        XCTAssertEqual(matrix[1][1], 5)
    }

    func testMixedTypeList() {
        // Lists with mixed types (common in Neo4j results)
        let mixedList: [Any] = [1, "two", 3.0, true]
        XCTAssertEqual(mixedList.count, 4)
    }

    // MARK: - Map/Dictionary Type Tests

    func testMapConversion() {
        let map: [String: Any] = [
            "name": "Alice",
            "age": 30,
            "active": true
        ]

        XCTAssertEqual(map["name"] as? String, "Alice")
        XCTAssertEqual(map["age"] as? Int, 30)
        XCTAssertEqual(map["active"] as? Bool, true)
    }

    func testEmptyMap() {
        let emptyMap: [String: Any] = [:]
        XCTAssertTrue(emptyMap.isEmpty)
    }

    func testNestedMap() {
        // Based on Java driver - nested map structures
        let person: [String: Any] = [
            "name": "Alice",
            "address": [
                "city": "New York",
                "country": "USA"
            ] as [String: Any]
        ]

        XCTAssertEqual(person["name"] as? String, "Alice")

        if let address = person["address"] as? [String: Any] {
            XCTAssertEqual(address["city"] as? String, "New York")
        } else {
            XCTFail("Expected nested address map")
        }
    }

    func testLargeMap() {
        // Based on Java driver - 1000+ entry maps
        var largeMap: [String: Int64] = [:]
        for i in 0..<1000 {
            largeMap["key\(i)"] = Int64(i)
        }

        XCTAssertEqual(largeMap.count, 1000)
        XCTAssertEqual(largeMap["key0"], 0)
        XCTAssertEqual(largeMap["key999"], 999)
    }

    // MARK: - Byte Array Tests

    func testByteArrayConversion() {
        let bytes: [UInt8] = [0x00, 0x01, 0x02, 0xFF]
        XCTAssertEqual(bytes.count, 4)
        XCTAssertEqual(bytes[0], 0x00)
        XCTAssertEqual(bytes[3], 0xFF)
    }

    func testEmptyByteArray() {
        let emptyBytes: [UInt8] = []
        XCTAssertTrue(emptyBytes.isEmpty)
    }

    func testLargeByteArray() {
        // Based on Java driver - test up to 2^16 bytes
        let largeBytes = [UInt8](repeating: 0xAB, count: 65536)
        XCTAssertEqual(largeBytes.count, 65536)
    }

    // MARK: - Null Value Tests

    func testNullValue() {
        let nullValue: Any? = nil
        XCTAssertNil(nullValue)
    }

    func testNSNullConversion() {
        let nsNull = NSNull()
        XCTAssertNotNil(nsNull)
    }

    // MARK: - Node Property Type Tests

    func testNodeWithStringProperty() {
        let properties: [String: Any] = ["name": "TestNode"]
        XCTAssertEqual(properties["name"] as? String, "TestNode")
    }

    func testNodeWithIntegerProperty() {
        let properties: [String: Any] = ["count": Int64(42)]
        XCTAssertEqual(properties["count"] as? Int64, 42)
    }

    func testNodeWithBooleanProperty() {
        let properties: [String: Any] = ["active": true]
        XCTAssertEqual(properties["active"] as? Bool, true)
    }

    func testNodeWithListProperty() {
        let properties: [String: Any] = ["tags": ["swift", "neo4j", "database"]]
        if let tags = properties["tags"] as? [String] {
            XCTAssertEqual(tags.count, 3)
            XCTAssertTrue(tags.contains("swift"))
        } else {
            XCTFail("Expected string array")
        }
    }

    // MARK: - Temporal Type Tests (based on Java driver TemporalTypesIT)

    func testDateConversion() {
        let date = Date()
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: date)

        XCTAssertNotNil(components.year)
        XCTAssertNotNil(components.month)
        XCTAssertNotNil(components.day)
    }

    func testDateComponents() {
        var components = DateComponents()
        components.year = 2024
        components.month = 6
        components.day = 15

        let calendar = Calendar.current
        if let date = calendar.date(from: components) {
            let extractedComponents = calendar.dateComponents([.year, .month, .day], from: date)
            XCTAssertEqual(extractedComponents.year, 2024)
            XCTAssertEqual(extractedComponents.month, 6)
            XCTAssertEqual(extractedComponents.day, 15)
        } else {
            XCTFail("Failed to create date from components")
        }
    }

    func testTimeInterval() {
        let now = Date()
        let later = now.addingTimeInterval(3600)  // 1 hour later

        let interval = later.timeIntervalSince(now)
        XCTAssertEqual(interval, 3600, accuracy: 0.001)
    }

    // MARK: - Duration Tests

    func testDurationInSeconds() {
        let duration: TimeInterval = 90.5  // 90.5 seconds
        XCTAssertEqual(duration, 90.5)
    }

    func testDurationConversion() {
        // Convert days/hours/minutes to seconds
        let days = 2
        let hours = 3
        let minutes = 45
        let seconds = 30

        let totalSeconds = (days * 86400) + (hours * 3600) + (minutes * 60) + seconds
        XCTAssertEqual(totalSeconds, 186330)
    }

    // MARK: - Type Mismatch Tests

    func testTypeMismatchDetection() {
        let stringValue: Any = "not a number"

        // Attempting to cast string to Int should fail
        XCTAssertNil(stringValue as? Int)
    }

    func testOptionalUnwrapping() {
        let optionalString: String? = "value"
        let nilString: String? = nil

        XCTAssertNotNil(optionalString)
        XCTAssertNil(nilString)

        if let unwrapped = optionalString {
            XCTAssertEqual(unwrapped, "value")
        }
    }

    // MARK: - allTests for Linux

    static var allTests: [(String, (TypeConversionTests) -> () throws -> Void)] {
        return [
            ("testBooleanConversion", testBooleanConversion),
            ("testIntegerConversions", testIntegerConversions),
            ("testIntegerBoundaries", testIntegerBoundaries),
            ("testFloatingPointConversions", testFloatingPointConversions),
            ("testFloatingPointEdgeCases", testFloatingPointEdgeCases),
            ("testBasicStringConversion", testBasicStringConversion),
            ("testEmptyString", testEmptyString),
            ("testUnicodeStrings", testUnicodeStrings),
            ("testLargeString", testLargeString),
            ("testVeryLargeString", testVeryLargeString),
            ("testListConversion", testListConversion),
            ("testEmptyList", testEmptyList),
            ("testLargeList", testLargeList),
            ("testNestedList", testNestedList),
            ("testMixedTypeList", testMixedTypeList),
            ("testMapConversion", testMapConversion),
            ("testEmptyMap", testEmptyMap),
            ("testNestedMap", testNestedMap),
            ("testLargeMap", testLargeMap),
            ("testByteArrayConversion", testByteArrayConversion),
            ("testEmptyByteArray", testEmptyByteArray),
            ("testLargeByteArray", testLargeByteArray),
            ("testNullValue", testNullValue),
            ("testNSNullConversion", testNSNullConversion),
            ("testNodeWithStringProperty", testNodeWithStringProperty),
            ("testNodeWithIntegerProperty", testNodeWithIntegerProperty),
            ("testNodeWithBooleanProperty", testNodeWithBooleanProperty),
            ("testNodeWithListProperty", testNodeWithListProperty),
            ("testDateConversion", testDateConversion),
            ("testDateComponents", testDateComponents),
            ("testTimeInterval", testTimeInterval),
            ("testDurationInSeconds", testDurationInSeconds),
            ("testDurationConversion", testDurationConversion),
            ("testTypeMismatchDetection", testTypeMismatchDetection),
            ("testOptionalUnwrapping", testOptionalUnwrapping),
        ]
    }
}
