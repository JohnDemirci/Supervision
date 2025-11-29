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
                statePointer: UnsafePointer(pointer),
                enableBatchingFn: {  },
                flushBatchFn: {  }
            )
            
            #expect(context.currentState == 0)
            
            context.mutate(\.self, to: 5)
            
            #expect(context.currentState == 5)
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
                statePointer: UnsafePointer(pointer),
                enableBatchingFn: {  },
                flushBatchFn: {  }
            )
            
            #expect(context.currentState == 0)
            
            context.transform(\.self) { _ in
                return 5
            }
            
            #expect(context.currentState == 5)
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
                statePointer: UnsafePointer(pointer),
                enableBatchingFn: {  },
                flushBatchFn: {  }
            )
            
            #expect(context.age == 0)
            
            context.transform(\.age) { _ in
                return 18
            }
            
            #expect(context.age == 18)
        }
    }
    
    @Test("Batching mutations should modify all at once")
    func batch() async throws {
        let user = User()

        withUnsafeMutablePointer(to: &user.state) { pointer in
            let context = Context<User.State>(
                mutateFn: { mutation in
                    mutation.apply(&pointer.pointee)
                },
                statePointer: UnsafePointer(pointer),
                enableBatchingFn: {  },
                flushBatchFn: {  }
            )

            context.batch {
                $0.age.wrappedValue = 30
                $0.name.wrappedValue = "John"
                $0.lastName.wrappedValue = "Demirci"
            }
            
            #expect(context.age == 30)
            #expect(context.name == "John")
            #expect(context.lastName == "Demirci")
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
                statePointer: UnsafePointer(pointer),
                enableBatchingFn: {  },
                flushBatchFn: {  }
            )

            context.batch {
                $0.age.wrappedValue = 30
                $0.name.wrappedValue = "John"
                $0.lastName.wrappedValue = "Demirci"
            }
            
            #expect(context.read(\.age) == 30)
            #expect(context.read(\.name) == "John")
            #expect(context.read(\.lastName) == "Demirci")
        }
    }
}
