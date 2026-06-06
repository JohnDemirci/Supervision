//
//  OnViewDidLoad.swift
//  Supervision
//
//  Created by John Demirci on 6/5/26.
//

import SwiftUI

private struct ViewDidLoadModifier: ViewModifier {
    @State private var didLoad: Bool
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.didLoad = false
        self.action = action
    }

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard !didLoad else { return }
                didLoad = true
                action()
            }
    }
}

public extension View {
    func viewDidLoad(_ action: @escaping () -> Void) -> some View {
        modifier(ViewDidLoadModifier(action: action))
    }
}
