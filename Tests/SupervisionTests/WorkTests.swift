//
//  WorkTests.swift
//  Supervision
//
//  Created by John on 1/14/26.
//

import Testing
@testable import Supervision

@Suite("Work")
struct WorkTests {
    @Test
    func initializer() {
        let work = Work<Int, Void>(
            operation: .done
        )
        
        #expect(work.operation == .done)
    }
}
