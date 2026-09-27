//
//  ParentFeature.swift
//  Supervision
//
//  Created by John Demirci on 4/20/26.
//

@MainActor
public protocol ParentFeaturesProtocol: Sendable {
    associatedtype Actions

    var id: ReferenceIdentifier { get }
    
    func send(_ actions: Actions)
}

public struct ParentFeatures<each Blueprint: FeatureBlueprint>: ParentFeaturesProtocol, Sendable {
    public typealias Actions = (repeat ((each Blueprint).Action?))

    @usableFromInline
    let features: (repeat Feature<each Blueprint>)
    
    public init<C: Composed>(
        features: repeat Feature<each Blueprint>,
        composedBy: C.Type = C.self
    ) {
        self.features = (repeat each features)
        
        var ids: [ReferenceIdentifier] = []
        for feature in repeat each features {
            ids.append(feature.id)
        }
        ids.append(ReferenceIdentifier(id: ObjectIdentifier(composedBy)))
        
        self.id = ReferenceIdentifier(ids)
    }
    
    public let id: ReferenceIdentifier

    public func withFeatures<Result>(
        _ body: (repeat Feature<each Blueprint>) -> Result
    ) -> Result {
        body(repeat each features)
    }

    public func send(_ actions: Actions) {
        repeat route((each actions), to: (each features))
    }

    private func route<F: FeatureBlueprint>(
        _ action: F.Action?,
        to feature: Feature<F>
    ) {
        guard let action else { return }
        feature.send(action)
    }
}
