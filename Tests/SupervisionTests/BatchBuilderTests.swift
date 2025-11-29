//
//  BatchBuilderTests.swift
//  Supervision
//
//  Created by John on 11/29/25.
//

@testable import Supervision
import Testing

private final class User {
    struct State {
        var name: String = "John"
        var lastName: String = "Demirci"
    }
    
    var state: State = .init()
}

@MainActor
@Suite("BatchBuilder")
struct BatchBuilderTests {
    @Test
    func something() async throws {
        let user = User()
        
        withUnsafeMutablePointer(to: &user.state) { pointer in
            let builder = BatchBuilder<User.State>(
                mutateFn: {
                    $0.apply(&pointer.pointee)
                },
                statePointer: UnsafePointer(pointer)
            )
            
            #expect(builder.name.wrappedValue == "John")
            #expect(builder.lastName.wrappedValue == "Demirci")
        }
    }
}
