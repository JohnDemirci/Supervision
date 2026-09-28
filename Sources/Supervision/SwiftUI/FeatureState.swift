//
//  FeatureState.swift
//  Supervision
//
//  Created by John Demirci on 6/5/26.
//

import Foundation
import SwiftUI

/// The initialization lifecycle for a SwiftUI-hosted ``Feature``.
///
/// ``idle`` is a first-load placeholder. Once a mounted ``FeatureStateView`` is
/// instantiated, the state is expected to remain ``initialized(_:)`` for that
/// view identity.
public enum FeatureState<F: FeatureBlueprint>: Equatable {
    /// The feature has not been attached to the view yet.
    case idle

    /// The view is attached to a live feature instance.
    case initialized(Feature<F>)

    public static func == (lhs: FeatureState<F>, rhs: FeatureState<F>) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle):
            return true
        case (.initialized(let lhsFeature), .initialized(let rhsFeature)):
            return lhsFeature === rhsFeature
        default:
            return false
        }
    }
}

private struct FeatureStateSnapshot<each F: FeatureBlueprint>: Equatable {
    let state: (repeat FeatureState<each F>)

    init(_ state: repeat FeatureState<each F>) {
        self.state = (repeat each state)
    }

    static func == (
        lhs: FeatureStateSnapshot<repeat each F>,
        rhs: FeatureStateSnapshot<repeat each F>
    ) -> Bool {
        for (lhsState, rhsState) in repeat (each lhs.state, each rhs.state) {
            guard lhsState == rhsState else { return false }
        }
        return true
    }
}

private struct FeatureStateViewModifier<each F: FeatureBlueprint>: ViewModifier {
    private let state: (repeat Binding<FeatureState<each F>>)
    private let feature: (repeat Feature<each F>)

    init(
        state: repeat Binding<FeatureState<each F>>,
        feature: repeat Feature<each F>
    ) {
        self.state = (repeat each state)
        self.feature = (repeat each feature)
    }

    private var snapshot: FeatureStateSnapshot<repeat each F> {
        FeatureStateSnapshot(repeat value(of: each state))
    }

    private func value<B: FeatureBlueprint>(
        of state: Binding<FeatureState<B>>
    ) -> FeatureState<B> {
        state.wrappedValue
    }

    public func body(content: Content) -> some View {
        content
            .viewDidLoad {
                repeat initialize(each state, with: each feature)
            }
            .onChange(of: snapshot, initial: false) { oldValue, newValue in
                repeat restore(each state, from: each oldValue.state, with: each feature)
            }
    }

    private func initialize<B: FeatureBlueprint>(
        _ state: Binding<FeatureState<B>>,
        with feature: Feature<B>
    ) {
        guard case .idle = state.wrappedValue else { return }
        state.wrappedValue = .initialized(feature)
    }

    private func restore<B: FeatureBlueprint>(
        _ state: Binding<FeatureState<B>>,
        from oldValue: FeatureState<B>,
        with feature: Feature<B>
    ) {
        guard case .idle = state.wrappedValue else { return }

        switch oldValue {
        case .initialized(let oldFeature):
            state.wrappedValue = .initialized(oldFeature)
        case .idle:
            state.wrappedValue = .initialized(feature)
        }
    }
}

public struct FeatureStateView<each F: FeatureBlueprint, C: View>: View {
    private let state: (repeat Binding<FeatureState<each F>>)
    private let content: (repeat Feature<each F>) -> C

    public init(
        state: repeat Binding<FeatureState<each F>>,
        content: @escaping (repeat Feature<each F>) -> C
    ) {
        self.state = (repeat each state)
        self.content = content
    }

    public var body: some View {
        if let feature = try? (repeat initializedFeature(from: each state)) {
            content(repeat each feature)
        } else {
            ProgressView()
        }
    }

    private func initializedFeature<B: FeatureBlueprint>(
        from state: Binding<FeatureState<B>>
    ) throws -> Feature<B> {
        guard case .initialized(let feature) = state.wrappedValue else {
            throw UninitializedFeatureError()
        }
        return feature
    }
}

public extension FeatureStateView {
    /// Instantiates the view with features for this mounted view identity.
    ///
    /// After the first transition from ``FeatureState/idle`` to
    /// ``FeatureState/initialized(_:)``, later attempts to set a binding back
    /// to ``FeatureState/idle`` are treated as invalid resets and the existing
    /// feature remains attached.
    func instantiate(
        with feature: repeat Feature<each F>
    ) -> some View {
        modifier(
            FeatureStateViewModifier(
                state: repeat each state,
                feature: repeat each feature
            )
        )
    }
}

private struct UninitializedFeatureError: Error {}
