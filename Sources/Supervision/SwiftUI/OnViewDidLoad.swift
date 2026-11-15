//
//  OnViewDidLoad.swift
//  Supervision
//
//  Created by John Demirci on 6/5/26.
//

import SwiftUI

private struct ViewDidLoadModifier: ViewModifier {
    @State private var didLoad: Bool
    private let action: nonisolated(nonsending) () async -> Void

    init(action: nonisolated(nonsending) @escaping () async -> Void) {
        self.didLoad = false
        self.action = action
    }

    func body(content: Content) -> some View {
        content
            .task {
                guard !didLoad else { return }
                didLoad = true
                await action()
            }
    }
}

public extension View {
    func viewDidLoad(_ action: @escaping () -> Void) -> some View {
        modifier(ViewDidLoadModifier(action: action))
    }

    func viewDidLoad(_ action: @escaping () async -> Void) -> some View {
        modifier(ViewDidLoadModifier(action: action))
    }
}
