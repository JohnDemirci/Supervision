//
//  Board.swift
//  Supervision
//
//  Created by John on 11/28/25.
//

import Foundation

@Observable
@MainActor
public final class Board<Dependency> {
    private var supervisors: NSMapTable<ReferenceIdentifier, AnyObject>
    private let dependency: Dependency
    
    public init(dependency: Dependency) {
        self.dependency = dependency
        self.supervisors = .weakToWeakObjects()
    }
    
    public var numberOfSupervisors: Int {
        supervisors.count
    }
}

extension Board {
    public func supervisor<Feature: FeatureProtocol>(
        state: Feature.State,
        _ dependencyClosure: @Sendable @escaping (Dependency) -> Feature.Dependency
    ) -> Supervisor<Feature> where Feature.State: Identifiable {
        let id = ReferenceIdentifier(id: state.id as AnyHashable)
        
        if let existingSupervisor = supervisors.object(forKey: id) {
            return unsafeDowncast(existingSupervisor, to: Supervisor<Feature>.self)
        } else {
            let newSupervisor = Supervisor<Feature>(
                state: state,
                dependency: dependencyClosure(dependency)
            )
            
            supervisors.setObject(newSupervisor, forKey: newSupervisor.id)
            return newSupervisor
        }
    }
    
    public func supervisor<Feature: FeatureProtocol>(
        type: Feature.Type = Feature.self,
        state: Feature.State,
        _ dependencyClosure: @escaping (Dependency) -> Feature.Dependency
    ) -> Supervisor<Feature> {
        let id = ReferenceIdentifier(id: ObjectIdentifier(Supervisor<Feature>.self) as AnyHashable)
        if let existingSupervisor = supervisors.object(forKey: id) {
            return unsafeDowncast(existingSupervisor, to: Supervisor<Feature>.self)
        } else {
            let newSupervisor = Supervisor<Feature>(
                state: state,
                dependency: dependencyClosure(dependency)
            )
            
            supervisors.setObject(newSupervisor, forKey: newSupervisor.id)
            return newSupervisor
        }
    }
    
    public func supervisor<Feature: FeatureProtocol>(
        type: Feature.Type = Feature.self,
        state: Feature.State
    ) -> Supervisor<Feature> where Feature.Dependency == Void {
        let id = ReferenceIdentifier(id: ObjectIdentifier(Supervisor<Feature>.self) as AnyHashable)
        if let existingSupervisor = supervisors.object(forKey: id) {
            return unsafeDowncast(existingSupervisor, to: Supervisor<Feature>.self)
        } else {
            let newSupervisor = Supervisor<Feature>(
                state: state,
                dependency: ()
            )
            
            supervisors.setObject(newSupervisor, forKey: newSupervisor.id)
            return newSupervisor
        }
    }
    
    public func supervisor<Feature: FeatureProtocol>(
        state: Feature.State
    ) -> Supervisor<Feature> where Feature.Dependency == Void, Feature.State: Identifiable {
        let id = ReferenceIdentifier(id: state.id as AnyHashable)
        
        if let existingSupervisor = supervisors.object(forKey: id) {
            return unsafeDowncast(existingSupervisor, to: Supervisor<Feature>.self)
        } else {
            let newSupervisor = Supervisor<Feature>(
                state: state,
                dependency: ()
            )
            
            supervisors.setObject(newSupervisor, forKey: newSupervisor.id)
            return newSupervisor
        }
    }
}
