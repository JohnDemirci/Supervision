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

private struct FeatureStateViewModifier<F: FeatureBlueprint>: ViewModifier {
    @Binding private var state: FeatureState<F>
    private let feature: Feature<F>

    init(
        state: Binding<FeatureState<F>>,
        feature: Feature<F>
    ) {
        self._state = state
        self.feature = feature
    }

    public func body(content: Content) -> some View {
        content
            .viewDidLoad {
                switch state {
                case .idle:
                    state = .initialized(feature)
                case .initialized:
                    break
                }
            }
            .onChange(of: state, initial: false) { oldValue, newValue in
                guard case .idle = newValue else { return }

                // Idle is only valid before first load. If an already mounted
                // view receives an idle reset, keep the feature it already owns.
                switch oldValue {
                case .initialized(let feature):
                    state = .initialized(feature)
                case .idle:
                    state = .initialized(feature)
                }
            }
    }
}

public struct FeatureStateView<F: FeatureBlueprint, C: View>: View {
    @Binding private var state: FeatureState<F>
    private let content: (Feature<F>) -> C

    public init(
        state: Binding<FeatureState<F>>,
        content: @escaping (Feature<F>) -> C
    ) {
        self._state = state
        self.content = content
    }

    public var body: some View {
        switch state {
        case .idle:
            ProgressView()
        case .initialized(let feature):
            content(feature)
        }
    }
}

public extension FeatureStateView {
    /// Instantiates the view with a feature for this mounted view identity.
    ///
    /// After the first transition from ``FeatureState/idle`` to
    /// ``FeatureState/initialized(_:)``, later attempts to set the binding back
    /// to ``FeatureState/idle`` are treated as invalid resets and the existing
    /// feature remains attached.
    func instantiate(
        with f: Feature<F>
    ) -> some View {
        modifier(
            FeatureStateViewModifier(
                state: $state,
                feature: f
            )
        )
    }
}
