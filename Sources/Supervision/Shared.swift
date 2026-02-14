//
//  Shared.swift
//  Supervision
//
//  Created by John Demirci on 2/5/26.
//

import Foundation

@MainActor
public final class Shared<Blueprint: FeatureBlueprint, Value, MappedValue>: Observable {
    let feature: Feature<Blueprint>
    let keypath: KeyPath<Feature<Blueprint>.State, Value>
    let map: (Value) -> MappedValue

    public var value: MappedValue {
        observationRegistar.access(self, keyPath: \.value)
        return map(feature.state[keyPath: keypath])
    }

    private let observationRegistar = ObservationRegistrar()

    public init(
        feature: Feature<Blueprint>,
        keypath: KeyPath<Feature<Blueprint>.State, Value>,
        map: @escaping (Value) -> MappedValue
    ) {
        self.feature = feature
        self.keypath = keypath
        self.map = map
        observe()
    }

    private func observe() {
        withObservationTracking {
            let _ = feature._state[keyPath: keypath]
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self else { return }
                observationRegistar.withMutation(of: self, keyPath: \.value, {})
                observe()
            }
        }
    }
}

extension Shared where Value == MappedValue {
    public convenience init(
        feature: Feature<Blueprint>,
        keypath: KeyPath<Feature<Blueprint>.State, Value>
    ) {
        self.init(
            feature: feature,
            keypath: keypath,
            map: \.self
        )
    }
}

extension Shared: @MainActor Equatable where MappedValue: Equatable {
    public static func == (
        lhs: Shared<Blueprint, Value, MappedValue>,
        rhs: Shared<Blueprint, Value, MappedValue>
    ) -> Bool {
        lhs === rhs
    }
}

extension Shared: @MainActor Hashable where MappedValue: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}
