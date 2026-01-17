//
//  AnyHashableSendableTests.swift
//  Supervision
//
//  Created by John Demirci on 1/19/26.
//

import Testing
@testable import Supervision

@Suite("AnyHashableSendable")
struct AnyHashableSendableTests {
    enum First: Hashable & Sendable {
        case one
    }

    enum Second: Hashable & Sendable {
        case one
    }

    @Test
    func example() async {
        let one = AnyHashableSendable(value: 1)

        #expect(AnyHashableSendable(value: 1) == one)
    }

    @Test
    func equalityCheck() async {
        let firstOne = AnyHashableSendable(value: First.one)
        let secondOne = AnyHashableSendable(value: Second.one)

        #expect(firstOne != secondOne)
    }
}
