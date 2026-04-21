//
//  Shared.swift
//  Supervision
//
//  Created by John Demirci on 2/5/26.
//

import Foundation

@MainActor
public final class Shared<Blueprint: FeatureBlueprint, Value>: Observable {
    let feature: Feature<Blueprint>
    let keypath: KeyPath<Feature<Blueprint>.State, Value>

    public var value: Value {
        observationRegistar.access(self, keyPath: \.value)
        return feature.state[keyPath: keypath]
    }

    private let observationRegistar = ObservationRegistrar()

    public init(
        feature: Feature<Blueprint>,
        keypath: KeyPath<Feature<Blueprint>.State, Value>,
    ) {
        self.feature = feature
        self.keypath = keypath
        observe()
    }

    private func observe() {
        withObservationTracking {
            let _ = feature._state[keyPath: keypath]
        } onChange: { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                observationRegistar.withMutation(of: self, keyPath: \.value, {})
                observe()
            }
        }
    }
}

extension Shared: @MainActor Equatable {
    public static func == (
        lhs: Shared<Blueprint, Value>,
        rhs: Shared<Blueprint, Value>
    ) -> Bool {
        lhs === rhs
    }
}

extension Shared: @MainActor Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}
