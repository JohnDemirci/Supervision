//
//  Board.swift
//  Supervision
//
//  Created by John on 11/28/25.
//

import Foundation

@Observable
@MainActor
public final class FeatureContainer<Dependency> {
    private var supervisors: NSMapTable<ReferenceIdentifier, AnyObject>
    private let dependency: Dependency

    public init(dependency: Dependency) {
        self.dependency = dependency
        supervisors = .weakToWeakObjects()
    }

    #if DEBUG
        public var numberOfSupervisors: Int {
            supervisors.count
        }
    #endif

    private func getOrCreate<F: FeatureProtocol>(
        id: ReferenceIdentifier,
        create: () -> Feature<F>
    ) -> Feature<F> {
        if let existing = supervisors.object(forKey: id) {
            return unsafeDowncast(existing, to: Feature<F>.self)
        }
        let supervisor = create()
        supervisors.setObject(supervisor, forKey: supervisor.id)
        return supervisor
    }
}

extension FeatureContainer {
    public func supervisor<F: FeatureProtocol>(
        state: F.State,
        _ dependencyClosure: @Sendable @escaping (Dependency) -> F.Dependency
    ) -> Feature<F> where F.State: Identifiable {
        getOrCreate(id: Feature<F>.makeID(from: state.id)) {
            Feature<F>(state: state, dependency: dependencyClosure(dependency))
        }
    }

    public func supervisor<F: FeatureProtocol>(
        type _: F.Type = F.self,
        state: F.State,
        _ dependencyClosure: @Sendable @escaping (Dependency) -> F.Dependency
    ) -> Feature<F> {
        getOrCreate(id: ReferenceIdentifier(id: ObjectIdentifier(Feature<F>.self))) {
            Feature<F>(state: state, dependency: dependencyClosure(dependency))
        }
    }

    public func supervisor<F: FeatureProtocol>(
        type _: F.Type = F.self,
        state: F.State
    ) -> Feature<F> where F.Dependency == Void {
        getOrCreate(id: ReferenceIdentifier(id: ObjectIdentifier(Feature<F>.self))) {
            Feature<F>(state: state, dependency: ())
        }
    }

    public func supervisor<F: FeatureProtocol>(
        state: F.State
    ) -> Feature<F> where F.Dependency == Void, F.State: Identifiable {
        getOrCreate(id: Feature<F>.makeID(from: state.id)) {
            Feature<F>(state: state, dependency: ())
        }
    }
}
