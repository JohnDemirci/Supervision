//
//  Board.swift
//  Supervision
//
//  Created by John on 11/28/25.
//

import Foundation

/// Board oversees the lifecycle of Supervisors. When a Supervisor is in the memory, it will be returned upon request.
/// If the supervisor is not in the memory, it will be created and then returned.
///
/// - Important: You must have only **ONE** Board within the entire application for the intended use case. Otherwise you may risk multiple identical Supervisors being present in the memory.
///
/// - Note: You should initialize the board when you launch your application where you instantiate all the dependencies of your application at the root level. The Dependency generic is used to create Supervisors and that should be the Application's entire dependencies that will be used when requesting a Supervisor.
@Observable
@MainActor
public final class Board<Dependency> {
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

    private func getOrCreate<Feature: FeatureProtocol>(
        id: ReferenceIdentifier,
        create: () -> Supervisor<Feature>
    ) -> Supervisor<Feature> {
        if let existing = supervisors.object(forKey: id) {
            return unsafeDowncast(existing, to: Supervisor<Feature>.self)
        }
        let supervisor = create()
        supervisors.setObject(supervisor, forKey: supervisor.id)
        return supervisor
    }
}

extension Board {
    /// Provides a **Supervisor** which has a generic over the given Feature.
    /// If the supervisor exists within the memory, it will be returned, otherwise a new instance is created
    ///
    /// - Parameters:
    ///    - state: Feature.State
    ///    - dependencyClosure: Closure capturing the Application's Dependency and returns Feature's Dependency
    ///
    /// - Returns: ``Supervisor<Feature>``
    public func supervisor<Feature: FeatureProtocol>(
        state: Feature.State,
        _ dependencyClosure: @Sendable @escaping (Dependency) -> Feature.Dependency
    ) -> Supervisor<Feature> where Feature.State: Identifiable {
        getOrCreate(id: ReferenceIdentifier(id: state.id as AnyHashable)) {
            Supervisor<Feature>(state: state, dependency: dependencyClosure(dependency))
        }
    }

    /// Provides a **Supervisor** which has a generic over the given Feature.
    /// If the supervisor exists within the memory, it will be returned, otherwise a new instance is created
    ///
    /// - Parameters:
    ///    - type: Feature.self
    ///    - state: Feature.State
    ///    - dependencyClosure: Closure capturing the Application's Dependency and returns Feature's Dependency
    ///
    /// - Returns: ``Supervisor<Feature>``
    public func supervisor<Feature: FeatureProtocol>(
        type _: Feature.Type = Feature.self,
        state: Feature.State,
        _ dependencyClosure: @Sendable @escaping (Dependency) -> Feature.Dependency
    ) -> Supervisor<Feature> {
        getOrCreate(id: ReferenceIdentifier(id: ObjectIdentifier(Supervisor<Feature>.self) as AnyHashable)) {
            Supervisor<Feature>(state: state, dependency: dependencyClosure(dependency))
        }
    }

    /// Provides a **Supervisor** which has a generic over the given Feature.
    /// If the supervisor exists within the memory, it will be returned, otherwise a new instance is created
    ///
    /// - Parameters:
    ///    - type: Feature.self
    ///    - state: Feature.State
    ///
    /// - Returns: ``Supervisor<Feature>``
    public func supervisor<Feature: FeatureProtocol>(
        type _: Feature.Type = Feature.self,
        state: Feature.State
    ) -> Supervisor<Feature> where Feature.Dependency == Void {
        getOrCreate(id: ReferenceIdentifier(id: ObjectIdentifier(Supervisor<Feature>.self) as AnyHashable)) {
            Supervisor<Feature>(state: state, dependency: ())
        }
    }

    /// Provides a **Supervisor** which has a generic over the given Feature.
    /// If the supervisor exists within the memory, it will be returned, otherwise a new instance is created
    ///
    /// - Parameters:
    ///    - state: Feature.State
    ///
    /// - Returns: ``Supervisor<Feature>``
    public func supervisor<Feature: FeatureProtocol>(
        state: Feature.State
    ) -> Supervisor<Feature> where Feature.Dependency == Void, Feature.State: Identifiable {
        getOrCreate(id: ReferenceIdentifier(id: state.id as AnyHashable)) {
            Supervisor<Feature>(state: state, dependency: ())
        }
    }
}
