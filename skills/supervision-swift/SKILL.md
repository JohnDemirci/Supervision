---
name: supervision-swift
description: Build, integrate, and test Swift and SwiftUI features with the Supervision library. Use when a project imports Supervision or requests work with FeatureBlueprint, Work, FeatureContainer, Composed, or Tester. Do not use for generic process supervision or unrelated state-management libraries.
license: 0BSD
---

# Supervision for Swift

Use Supervision as the project's feature-oriented state-management system. Preserve
the application's existing feature boundaries and conventions unless the user asks
for an architectural change.

## Establish compatibility

Before writing code:

1. Inspect `Package.swift`, `Package.resolved`, existing `import Supervision` sites,
   and nearby features and tests.
2. Determine the resolved Supervision version. These references describe v3.3.0.
3. Prefer checked-out package source and compiler-visible interfaces over these
   references when the resolved version differs.
4. If source for a different version is unavailable, consult matching release
   documentation or explain the version uncertainty instead of guessing an API.

The v3.3.0 baseline requires Swift 6.2 and Apple platform version 26 or later.
Confirm compatibility before adding Supervision to a project that targets older
toolchains or platforms.

## Load only the relevant guidance

- Read [feature-modeling.md](references/feature-modeling.md) when defining or
  changing state, actions, dependencies, `Context` mutations, or `Work` effects.
- Read [app-integration.md](references/app-integration.md) for feature ownership,
  containers, SwiftUI, previews, composition, shared values, or broadcasting.
- Read [testing.md](references/testing.md) when adding or updating feature tests.

Read more than one reference when the request crosses those concerns.

## Preserve the architecture

- Define feature state as a nested `@ObservableValue struct State` unless an
  established feature deliberately uses another compatible shape.
- Keep actions and dependencies `Sendable`; keep dependency capabilities explicit
  and injectable.
- Perform immediate state changes only through the borrowed `Context` passed to
  `process`. Never retain or escape that context.
- Return asynchronous behavior as `Work` and map results back into actions. Do not
  start untracked `Task` values inside `process` as a substitute for `Work`.
- Prefer action-driven SwiftUI bindings. Use direct bindings only for UI-local or
  high-frequency values that intentionally bypass feature logic.
- Preserve feature identity and ownership. Do not recreate a feature on each view
  evaluation or assume a container strongly retains it.

## Complete the task

Implement the smallest change that matches the surrounding project. Add or update
tests for state transitions and returned work, then run the repository's Swift test
command. If the package has no custom command, use `swift test`.
