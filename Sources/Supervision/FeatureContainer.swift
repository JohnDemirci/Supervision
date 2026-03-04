//
//  Board.swift
//  Supervision
//
//  Created by John on 11/28/25.
//

import Foundation

///
/// A lightweight, observable registry that creates, caches, and hands out Feature instances scoped by a dependency context.
///
/// FeatureContainer is responsible for:
/// - Holding a shared dependency object (of generic type `Dependency`) used to construct features.
/// - Lazily creating Feature instances on demand and returning cached instances for the same identity.
/// - Managing a weak-to-weak map of features, allowing automatic cleanup when no strong references remain.
/// - Operating on the main actor and participating in SwiftUI-style observation via `@Observable`.
///
/// Key behaviors:
/// - Caching: Features are stored in a weak-to-weak NSMapTable keyed by a ReferenceIdentifier. If a Feature
///   is deallocated (no remaining strong references), it will be recreated upon the next request.
/// - Identity: When requesting a feature with identifiable state, the identity is derived from `state.id`,
///   ensuring that the same state identity returns the same Feature instance.
/// - Dependency scoping: A closure can transform the container’s shared `Dependency` into the specific
///   dependency required by the requested Feature, enabling modular composition.
///
/// Concurrency & Observation:
/// - Annotated with `@MainActor`, meaning all interactions occur on the main actor.
///
/// Type Parameters:
/// - Dependency: The shared dependency type held by the container and used to derive per-feature dependencies.
///
/// Memory Semantics:
/// - Uses a weak-to-weak map for features: features are not strongly retained by the container.
///   If a feature is no longer referenced elsewhere, it may be deallocated and recreated on demand.
@Observable
@MainActor
public final class FeatureContainer<Dependency> {
    private var features: NSMapTable<ReferenceIdentifier, AnyObject>
    private let dependency: Dependency

    public init(dependency: Dependency) {
        self.dependency = dependency
        features = .weakToWeakObjects()
    }

    private func getOrCreate<F: FeatureBlueprint>(
        id: ReferenceIdentifier,
        create: @MainActor () -> Feature<F>
    ) -> Feature<F> {
        if let existing = features.object(forKey: id) {
            return unsafeDowncast(existing, to: Feature<F>.self)
        }
        let feature = create()
        features.setObject(feature, forKey: feature.id)
        return feature
    }
}

extension FeatureContainer {
    /// Provides a Feature
    ///
    /// ## Behavior ##
    /// - If a Feature instance for the computed identifier already exists in the container, it is returned.
    /// - Otherwise, a new Feature is created, stored in the container, and returned.
    /// - The identifier is derived from `state.id`, so the same identifiable state yields the same Feature instance.
    ///
    /// - Parameters:
    ///    - state: The initial state for the feature. Its `id` is used to compute the feature’s identity.
    ///    - dependencyClosure: A closure that transforms the container’s `Dependency` into the specific
    ///   dependency required by the feature `F`.
    ///
    /// - Returns:
    ///    - ``Feature``: A `Feature<F>` bound to the provided state and dependency.
    public func feature<F: FeatureBlueprint>(
        state: F.State,
        _ dependencyClosure: @MainActor @escaping (Dependency) -> F.Dependency
    ) -> Feature<F> where F.State: Identifiable {
        getOrCreate(id: Feature<F>.makeID(from: state.id)) {
            Feature<F>(state: state, dependency: dependencyClosure(dependency))
        }
    }

    /// Returns a Feature instance for the specified feature type and state, using a dependency derived from the container.
    ///
    /// ## Behavior ##
    /// - If a Feature instance for the given feature type already exists in the container, it is returned.
    /// - Otherwise, a new Feature is created with the provided state and a dependency produced by `dependencyClosure`,
    ///   stored in the container’s cache, and returned.
    /// - The identifier used for caching is scoped to the feature type (not the state), ensuring a single instance
    ///   per feature type within this container.
    ///
    /// - Parameters:
    ///    - type: The concrete Feature type `F` to create or retrieve. Defaults to `F.self`.
    ///    - state: The initial state for the feature.
    ///    - dependencyClosure: A closure that transforms the container’s `Dependency` into the specific dependency
    ///   required by the feature `F`.
    ///
    /// - Returns:
    ///    - ``Feature``: A `Feature<F>` bound to the provided state and derived dependency.
    ///
    /// - Note: Use this overload when feature identity should be scoped by type rather than by state identity.
    ///   If you want identity based on `state.id`, prefer the overload where `F.State: Identifiable`.
    public func feature<F: FeatureBlueprint>(
        type _: F.Type = F.self,
        state: F.State,
        _ dependencyClosure: @MainActor @escaping (Dependency) -> F.Dependency
    ) -> Feature<F> {
        getOrCreate(id: ReferenceIdentifier(id: ObjectIdentifier(Feature<F>.self))) {
            Feature<F>(state: state, dependency: dependencyClosure(dependency))
        }
    }

    public func feature<F: FeatureBlueprint>(
        type _: F.Type = F.self,
        state: F.State
    ) -> Feature<F> where F.Dependency == Void {
        getOrCreate(id: ReferenceIdentifier(id: ObjectIdentifier(Feature<F>.self))) {
            Feature<F>(state: state, dependency: ())
        }
    }

    public func feature<F: FeatureBlueprint>(
        state: F.State
    ) -> Feature<F> where F.Dependency == Void, F.State: Identifiable {
        getOrCreate(id: Feature<F>.makeID(from: state.id)) {
            Feature<F>(state: state, dependency: ())
        }
    }
}
