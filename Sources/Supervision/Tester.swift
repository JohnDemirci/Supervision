//
//  Tester.swift
//  Supervision
//
//  Created by John Demirci on 1/9/26.
//

import Foundation
import OSLog

// TODO: - change precodnitionFailure with test failure using swift-issue-reporting

@dynamicMemberLookup
public final class Tester<Feature: FeatureProtocol> {
    public typealias Action = Feature.Action
    public typealias Dependency = Feature.Dependency
    public typealias State = Feature.State

    let feature: Feature
    private nonisolated let logger: Logger
    private var _state: State
    
    private var pending: [PendingAssertion<Action, Dependency>] = []
    
    deinit {
        guard pending.isEmpty else {
            preconditionFailure("you have \(pending.count) pending assertions that have not been fulfilled")
        }
    }

    public init(state: State) {
        self.feature = .init()
        self.logger = Logger(subsystem: "Test", category: "Tester<\(Feature.self)>")
        self._state = state
    }

    public subscript<Subject>(
        dynamicMember keyPath: KeyPath<State, Subject>
    ) -> Subject {
        return _state[keyPath: keyPath]
    }

    @discardableResult
    public func send(
        _ action: Action,
        _ workAssertion: (State, WorkAssertion<Action, Dependency>) -> Void
    ) -> PendingAssertion<Action, Dependency>? {
        let work: Feature.FeatureWork = withUnsafeMutablePointer(
            to: &_state
        ) { [self] pointer in
            let context = Context<Feature.State>(
                mutateFn: { mutation in
                    mutation.apply(&pointer.pointee)
                },
                statePointer: UnsafePointer(pointer)
            )

            return self.feature.process(action: action, context: context)
        }
        
        let _workAssertion = WorkAssertion(work)

        workAssertion(_state, _workAssertion)
        
        guard _workAssertion.asserted else {
            preconditionFailure()
        }
        
        return record(work)
        
        /*
         some thoughts
         
         - if we are expecting a value to be provided then we should return a value type and when the user provides a value they should refer to the returned type when they provide the value
         
         - if they do not provide a value and the system is expecting a value then we should cause a test failure
         
         - this might be particularly difficult for merge and concatenate but we'll see
         */
    }
    
    func record(_ work: Work<Action, Dependency>) -> PendingAssertion<Action, Dependency>? {
        switch work.operation {
        case .done, .cancel:
            return nil
        case .run(let run):
            if run.configuration.fireAndForget == true {
                if run.testPlan == nil {
                    return nil
                }
            }
            
            guard let testPlan = run.testPlan else {
                preconditionFailure("the run does not have a test plan")
            }
            
            let pendingAssertion = PendingAssertion(testPlan: testPlan)
            self.pending.append(pendingAssertion)
            
            return pendingAssertion
            
        case .merge(let works):
            for work in works {
                _ = record(work)
            }
            
            return nil
            
        case .concatenate(let works):
            for work in works {
                _ = record(work)
            }
            
            return nil
        }
    }
}

public final class WorkAssertion<Action, Dependency> {
    let work: Work<Action, Dependency>
    var asserted: Bool = false
    
    var testPlan: Work<Action, Dependency>.TestPlan? {
        return run?.testPlan
    }
    
    public var run: Work<Action, Dependency>.Run? {
        guard case .run(let run) = work.operation else { return nil }
        return run
    }
    
    public var configuration: Work<Action, Dependency>.RunConfiguration? {
        run?.configuration
    }
    
    init(_ work: Work<Action, Dependency>) {
        self.work = work
    }
    
    public func assertDone() {
        precondition(work.operation == .done, "expected .done but received \(work.operation)")
        asserted = true
    }
    
    public func assertStream() {
        guard case .run(let run) = work.operation else {
            preconditionFailure("expected the operation to be .run but received \(work.operation)")
        }
        
        guard run.configuration.fireAndForget == true else {
            preconditionFailure()
        }
        
        guard testPlan?.kind == .stream else {
            preconditionFailure()
        }
        
        asserted = true
    }
    
    public func assertFireAndForget() {
        guard let run else {
            preconditionFailure("expected .run but received \(work.operation)")
        }
        
        guard run.configuration.fireAndForget == true else {
            preconditionFailure("the work does not contain a fireAndForget configuration")
        }
        
        if run.testPlan?.kind == .stream {
            preconditionFailure("the work is a stream not a true fire and forget")
        }
        
        asserted = true
    }
    
    public func assertCancellation(_ cancelID: some (Hashable & Sendable)) {
        guard case .cancel(let id) = work.operation else {
            preconditionFailure("expected work to be a cancellation work but it is \(work.operation)")
        }
        
        guard AnyHashableSendable(value: cancelID) == id else {
            preconditionFailure("expected the id to be \(cancelID) but it is \(id)")
        }
        
        asserted = true
    }
    
    public func assertRun() {
        guard case .run(let run) = work.operation else {
            preconditionFailure("expected the operation to be .run but received \(work.operation)")
        }
        
        guard run.configuration.fireAndForget == false else {
            preconditionFailure()
        }
        
        asserted = true
    }
    
    public func assertMerge(numberOfWorks: Int) {
        guard case .merge(let works) = work.operation else {
            preconditionFailure("expected the work to be .merge but received \(work.operation)")
        }
        
        guard numberOfWorks == works.count else {
            preconditionFailure("expected \(works.count) works but got \(numberOfWorks)")
        }
        
        asserted = true
    }
    
    public func assertConcatenate(numberOfWorks: Int) {
        guard case .concatenate(let works) = work.operation else {
            preconditionFailure("expected the work to be .concatenate but received \(work.operation)")
        }
        
        guard numberOfWorks == works.count else {
            preconditionFailure("expected \(works.count) works but got \(numberOfWorks)")
        }
        
        // maybe we should do something with the number of works here
        asserted = true
    }
}

public final class PendingAssertion<Action, Dependency> {
    let id = UUID()
    let testPlan: Work<Action, Dependency>.TestPlan
    
    init(testPlan: Work<Action, Dependency>.TestPlan) {
        self.testPlan = testPlan
    }
}
