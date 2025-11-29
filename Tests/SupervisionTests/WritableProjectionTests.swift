//
//  WritableProjectionTests.swift
//  Supervision
//
//  Created by John on 11/29/25.
//

@testable import Supervision
import Testing

private final class User {
    struct State {
        var text: String = ""
        var number: Number = .init()
    }
    
    struct Number {
        var num: Int = 0
    }
    
    var state: State = .init()
}

@Suite("WritableProjectionTests")
struct WritableProjectionTests {
    @Test
    func writableProjection() async throws {
        let user = User()
        
        withUnsafeMutablePointer(to: &user.state) { pointer in
            let projection = WritableProjection<User.State, String>(
                keyPath: \.text,
                mutateFn: {
                    $0.apply(&pointer.pointee)
                },
                statePointer: pointer
            )
            
            projection.wrappedValue = "Hello, World!"
            
            #expect(projection.wrappedValue == "Hello, World!")
        }
    }
    
    @Test
    func projectionWithNested() async throws {
        let user = User()
        
        withUnsafeMutablePointer(to: &user.state) { pointer in
            let projection = WritableProjection<User.State, User.Number>(
                keyPath: \.number,
                mutateFn: {
                    $0.apply(&pointer.pointee)
                },
                statePointer: pointer
            )
            
            projection.num.wrappedValue = 42
            
            #expect(projection.num.wrappedValue == 42)
        }
    }
}
