//
//  isTesting.swift
//  Supervision
//
//  Created by John Demirci on 1/13/26.
//

import Foundation

extension ProcessInfo {
    var isTesting: Bool {
        if environment.keys.contains("XCTestBundlePath") { return true }
        if environment.keys.contains("XCTestBundleInjectPath") { return true }
        if environment.keys.contains("XCTestConfigurationFilePath") { return true }
        if environment.keys.contains("XCTestSessionIdentifier") { return true }

        return arguments.contains { argument in
            let path = URL(fileURLWithPath: argument)
            if path.lastPathComponent == "swiftpm-testing-helper" { return true }
            if argument == "--testing-library" { return true }
            if path.lastPathComponent == "xctest" { return true }
            if path.pathExtension == "xctest" { return true }

            return false
        }
    }
}

@inline(__always)
func isTesting() -> Bool {
    #if DEBUG
    return ProcessInfo.processInfo.isTesting
    #else
    return false
    #endif
}
