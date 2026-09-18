//
//  Board.swift
//  Supervision
//
//  Created by John on 11/28/25.
//

import Foundation
import Observation
import SwiftUI

// MARK: - ContainerManagement

public protocol ContainerManagement<Dependency>: Observable {

    associatedtype Dependency

    @MainActor
    func composedFeature<C: Composed>(
        composed: C
    ) -> ComposedFeature<C>

    @MainActor
    func feature<F: FeatureBlueprint>(
        state: F.State,
        _ dependencyClosure: @MainActor @escaping (Dependency) -> F.Dependency
    ) -> Feature<F>
    where F.State: Identifiable

    @MainActor
    func feature<F: FeatureBlueprint>(
        type: F.Type,
        state: F.State,
        _ dependencyClosure: @MainActor @escaping (Dependency) -> F.Dependency
    ) -> Feature<F>

    @MainActor
    func feature<F: FeatureBlueprint>(
        type: F.Type,
        state: F.State
    ) -> Feature<F>
    where F.Dependency == Void

    @MainActor
    func feature<F: FeatureBlueprint>(
        state: F.State
    ) -> Feature<F>
    where F.Dependency == Void, F.State: Identifiable
}


// MARK: - ContainerFeature

/// Type-erased access to a feature that can be injected into a testing container.
@MainActor
public protocol ContainerFeature: AnyObject {

    var id: ReferenceIdentifier { get }
}

extension Feature: ContainerFeature {}


// MARK: - FeatureContainer

/// A lightweight, observable registry that creates, caches, and hands out
/// Feature instances scoped by a dependency context.
@Observable
@MainActor
public final class FeatureContainer<Dependency>: ContainerManagement {

    private var features: NSMapTable<ReferenceIdentifier, AnyObject>

    private let dependency: Dependency

    public init(dependency: Dependency) {
        self.dependency = dependency
        self.features = .weakToWeakObjects()
    }

    var count: Int {
        features.count
    }

    private func getOrCreate<F: FeatureBlueprint>(
        id: ReferenceIdentifier,
        create: @MainActor () -> Feature<F>
    ) -> Feature<F> {

        if let existing = features.object(forKey: id) {
            return unsafeDowncast(
                existing,
                to: Feature<F>.self
            )
        }

        let feature = create()

        features.setObject(
            feature,
            forKey: feature.id
        )

        return feature
    }

    private func getOrCreate<C: Composed>(
        id: ReferenceIdentifier,
        create: @MainActor () -> ComposedFeature<C>
    ) -> ComposedFeature<C> {

        if let existing = features.object(forKey: id) {
            return unsafeDowncast(
                existing,
                to: ComposedFeature<C>.self
            )
        }

        let composed = create()

        features.setObject(
            composed,
            forKey: id
        )

        return composed
    }
}


// MARK: Feature creation

extension FeatureContainer {

    public func composedFeature<C: Composed>(
        composed: C
    ) -> ComposedFeature<C> {
        getOrCreate(
            id: composed.parents.id
        ) {
            ComposedFeature(
                composed: composed
            )
        }
    }

    /// Provides a feature whose identity is derived from its state.
    public func feature<F: FeatureBlueprint>(
        state: F.State,
        _ dependencyClosure: @MainActor @escaping (Dependency) -> F.Dependency
    ) -> Feature<F>
    where F.State: Identifiable {
        getOrCreate(
            id: Feature<F>.makeID(
                from: state.id
            )
        ) {
            Feature<F>(
                state: state,
                dependency: dependencyClosure(dependency)
            )
        }
    }

    /// Provides a feature whose identity is derived from its feature type.
    public func feature<F: FeatureBlueprint>(
        type _: F.Type = F.self,
        state: F.State,
        _ dependencyClosure: @MainActor @escaping (Dependency) -> F.Dependency
    ) -> Feature<F> {
        getOrCreate(
            id: ReferenceIdentifier(
                id: ObjectIdentifier(
                    Feature<F>.self
                )
            )
        ) {
            Feature<F>(
                state: state,
                dependency: dependencyClosure(dependency)
            )
        }
    }

    public func feature<F: FeatureBlueprint>(
        type _: F.Type = F.self,
        state: F.State
    ) -> Feature<F>
    where F.Dependency == Void {

        getOrCreate(
            id: ReferenceIdentifier(
                id: ObjectIdentifier(
                    Feature<F>.self
                )
            )
        ) {
            Feature<F>(
                state: state,
                dependency: ()
            )
        }
    }

    public func feature<F: FeatureBlueprint>(
        state: F.State
    ) -> Feature<F>
    where F.Dependency == Void, F.State: Identifiable {

        getOrCreate(
            id: Feature<F>.makeID(
                from: state.id
            )
        ) {
            Feature<F>(
                state: state,
                dependency: ()
            )
        }
    }
}


// MARK: - TestingFeatureContainer

@Observable
@MainActor
public final class TestingFeatureContainer<Dependency>: ContainerManagement {
    private var features: [ReferenceIdentifier: AnyObject] = [:]

    public init(
        features: [any ContainerFeature]
    ) {
        for feature in features {
            self.features[feature.id] = feature
        }
    }

    public func feature<F: FeatureBlueprint>(
        type _: F.Type = F.self,
        state _: F.State,
        _ dependencyClosure: @MainActor @escaping (Dependency) -> F.Dependency
    ) -> Feature<F> {
        injectedFeature(
            id: Feature<F>.makeID()
        )
    }

    public func feature<F: FeatureBlueprint>(
        state: F.State,
        _ dependencyClosure: @MainActor @escaping (Dependency) -> F.Dependency
    ) -> Feature<F>
    where F.State: Identifiable {
        injectedFeature(
            id: Feature<F>.makeID(
                from: state.id
            )
        )
    }

    public func feature<F: FeatureBlueprint>(
        type _: F.Type = F.self,
        state _: F.State
    ) -> Feature<F>
    where F.Dependency == Void {
        injectedFeature(
            id: Feature<F>.makeID()
        )
    }

    public func feature<F: FeatureBlueprint>(
        state: F.State
    ) -> Feature<F>
    where F.Dependency == Void, F.State: Identifiable {
        injectedFeature(
            id: Feature<F>.makeID(
                from: state.id
            )
        )
    }

    public func composedFeature<C: Composed>(
        composed: C
    ) -> ComposedFeature<C> {
        let id = composed.parents.id

        if let existing = features[id] {

            guard let feature = existing as? ComposedFeature<C> else {
                preconditionFailure(
                    "An injected value for \(id) has an unexpected type."
                )
            }

            return feature
        }

        let feature = ComposedFeature(
            composed: composed
        )

        features[id] = feature

        return feature
    }

    private func injectedFeature<F: FeatureBlueprint>(
        id: ReferenceIdentifier
    ) -> Feature<F> {
        guard let existing = features[id] else {
            preconditionFailure(
                "No \(F.self) was supplied to the testing container for \(id)."
            )
        }

        guard let feature = existing as? Feature<F> else {
            preconditionFailure(
                "An injected value for \(id) has an unexpected type."
            )
        }

        return feature
    }
}


// MARK: - Container factories

extension ContainerManagement {
    @MainActor
    public static func live<D>(
        dependency: D
    ) -> some ContainerManagement<D> {
        FeatureContainer(
            dependency: dependency
        )
    }

    @MainActor
    public static func test<D>(
        features: [any ContainerFeature]
    ) -> some ContainerManagement<D> {
        TestingFeatureContainer<D>(
            features: features
        )
    }
}


// MARK: - Type-erased container

/// Type-erases the concrete dependency specialization of a
/// `ContainerManagement`.
///
/// This exists specifically so a container can cross boundaries that require
/// one concrete type, such as SwiftUI's Environment.
///
/// The dependency type is recovered when the container is consumed.
public struct AnyContainerManagement {
    private let storage: Any

    public init<D>(
        _ container: any ContainerManagement<D>
    ) {
        self.storage = container
    }

    public func resolve<D>(
        as dependencyType: D.Type = D.self
    ) -> any ContainerManagement<D> {
        guard let container = storage as? any ContainerManagement<D> else {
            preconditionFailure(
                """
                Container dependency mismatch.

                The container stored in the SwiftUI environment cannot be \
                resolved as ContainerManagement<\(D.self)>.

                Make sure the dependency type supplied to \
                @ContainerEnvironment matches the dependency type used when \
                the FeatureContainer was created.
                """
            )
        }

        return container
    }
}


// MARK: Convenience factories

extension AnyContainerManagement {
    @MainActor
    public static func live<D>(
        dependency: D
    ) -> AnyContainerManagement {
        AnyContainerManagement(
            FeatureContainer(
                dependency: dependency
            )
        )
    }

    @MainActor
    public static func test<D>(
        dependency _: D.Type = D.self,
        features: [any ContainerFeature]
    ) -> AnyContainerManagement {
        AnyContainerManagement(
            TestingFeatureContainer<D>(
                features: features
            )
        )
    }
}


// MARK: - SwiftUI Environment

private struct ContainerManagementEnvironmentKey: @MainActor EnvironmentKey {
    @MainActor static var defaultValue: AnyContainerManagement? = nil
}

public extension EnvironmentValues {

    /// The dependency-erased Supervision container.
    @MainActor
    var containerManagement: AnyContainerManagement? {
        get {
            self[ContainerManagementEnvironmentKey.self]
        }
        set {
            self[ContainerManagementEnvironmentKey.self] = newValue
        }
    }
}


// MARK: - Typed Environment accessor

/// Reads the dependency-erased container from SwiftUI's Environment and
/// restores its dependency type.
///
/// Example:
///
/// ```swift
/// @ContainerEnvironment<AppDependencies>
/// private var container
/// ```
@MainActor
@propertyWrapper
public struct ContainerEnvironment<Dependency>: DynamicProperty {

    @Environment(\.containerManagement)
    private var container

    public init() {}

    public var wrappedValue: any ContainerManagement<Dependency> {

        guard let container else {
            preconditionFailure(
                """
                No Supervision container was found in the SwiftUI environment.

                Inject one with:

                    .containerManagement(
                        FeatureContainer(dependency: dependencies)
                    )
                """
            )
        }

        return container.resolve(
            as: Dependency.self
        )
    }
}


// MARK: - View convenience

public extension View {

    /// Injects a strongly typed container into SwiftUI while erasing its
    /// dependency specialization only at the Environment boundary.
    func containerManagement<D>(
        _ container: some ContainerManagement<D>
    ) -> some View {

        environment(
            \.containerManagement,
            AnyContainerManagement(container)
        )
    }

    /// Injects an already type-erased container.
    func containerManagement(
        _ container: AnyContainerManagement
    ) -> some View {

        environment(
            \.containerManagement,
            container
        )
    }
}
