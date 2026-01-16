//
//  ContextTests.swift
//  Supervision
//
//  Created by John on 11/29/25.
//

@testable import Supervision
import Testing
import Observation

@Observable
private final class User: @unchecked Sendable {
    struct State: Sendable {
        var name: String = ""
        var lastName: String = ""
        var age: Int = 0
    }
    
    var state: State = .init()
}

@MainActor
@Suite("Context")
struct ContextTests {
    @Test
    func contextMutation() async throws {
        var state: Int = 0
        
        withUnsafeMutablePointer(to: &state) { pointer in
            let context = Context<Int>(
                mutateFn: { mutation in
                    mutation.apply(&pointer.pointee)
                },
                statePointer: UnsafeMutablePointer(pointer)
            )
            
            #expect(context.state == 0)
            
            context.modify(\.self, to: 5)
            
            #expect(context.state == 5)
        }
    }
    
    @Test
    func transform() async throws {
        var state: Int = 0
        
        withUnsafeMutablePointer(to: &state) { pointer in
            let context = Context<Int>(
                mutateFn: { mutation in
                    mutation.apply(&pointer.pointee)
                },
                statePointer: UnsafeMutablePointer(pointer)
            )
            
            #expect(context.state == 0)
            
            context.modify(\.self) {
                $0 = 5
            }
            
            #expect(context.state == 5)
        }
    }
    
    @Test("dynamicMemberLookups should show the correct value")
    func dynamicMemberLookup() async throws {
        let user = User()
        
        withUnsafeMutablePointer(to: &user.state) { pointer in
            let context = Context<User.State>(
                mutateFn: { mutation in
                    mutation.apply(&pointer.pointee)
                },
                statePointer: UnsafeMutablePointer(pointer)
            )
            
            #expect(context.age == 0)
            
            context.modify(\.age) {
                $0 = 18
            }
            
            #expect(context.age == 18)
        }
    }

    @Test("read function call")
    func read() async throws {
        let user = User()

        withUnsafeMutablePointer(to: &user.state) { pointer in
            let context = Context<User.State>(
                mutateFn: { mutation in
                    mutation.apply(&pointer.pointee)
                },
                statePointer: UnsafeMutablePointer(pointer)
            )

            context.modify {
                $0.set(\.age, to: 30)
                $0.set(\.name, to: "John")
                $0.set(\.lastName, to: "Demirci")
            }

            #expect(context.age == 30)
            #expect(context.name == "John")
            #expect(context.lastName == "Demirci")
        }
    }
}
