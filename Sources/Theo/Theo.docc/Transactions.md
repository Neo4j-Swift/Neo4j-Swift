# Working with Transactions

Use transactions to ensure data consistency in Neo4j.

## Overview

Transactions group multiple operations into an atomic unit. Either all operations succeed (commit) or all are rolled back on failure.

### Basic Transaction Usage

Use the ``Transaction`` class to execute multiple queries atomically:

```swift
import Theo

let client = try BoltClient(configuration: config)
try client.connectSync()

// Begin a transaction
client.beginTransaction { result in
    switch result {
    case .success(let transaction):
        // Execute queries within the transaction
        transaction.run("CREATE (n:Person {name: $name})", params: ["name": "Alice"]) { _ in
            transaction.run("CREATE (n:Person {name: $name})", params: ["name": "Bob"]) { _ in
                // Commit the transaction
                transaction.commit { commitResult in
                    switch commitResult {
                    case .success:
                        print("Transaction committed!")
                    case .failure(let error):
                        print("Commit failed: \(error)")
                    }
                }
            }
        }
    case .failure(let error):
        print("Failed to begin transaction: \(error)")
    }
}
```

### Rolling Back

If an error occurs, roll back to undo all changes:

```swift
transaction.run("CREATE (n:Person {name: $name})", params: ["name": "Alice"]) { result in
    switch result {
    case .success:
        // Continue with more operations...
        break
    case .failure(let error):
        // Roll back on error
        transaction.rollback { _ in
            print("Transaction rolled back due to: \(error)")
        }
    }
}
```

### Transaction Isolation

Transactions provide isolation from concurrent operations. Changes made within a transaction are not visible to other transactions until committed.

```swift
// Transaction 1: Creates data
client.beginTransaction { result in
    guard case .success(let tx1) = result else { return }

    tx1.run("CREATE (n:Person {name: 'Alice'})") { _ in
        // At this point, 'Alice' exists only within tx1
        // Other transactions cannot see her yet

        tx1.commit { _ in
            // Now 'Alice' is visible to everyone
        }
    }
}
```

### Best Practices

1. **Keep transactions short**: Long-running transactions can cause lock contention
2. **Handle errors**: Always handle failures and roll back when necessary
3. **Use parameters**: Prevent injection attacks by using parameterized queries
4. **Close connections**: Ensure connections are properly closed when done

```swift
// Good: Using parameters
transaction.run(
    "CREATE (n:Person {name: $name})",
    params: ["name": userInput]
)

// Bad: String interpolation (vulnerable to injection)
// transaction.run("CREATE (n:Person {name: '\(userInput)'})")
```

## Topics

### Transaction Management

- ``Transaction``
- ``ClientProtocol``
