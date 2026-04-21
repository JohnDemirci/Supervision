//
//  Todo.swift
//  Supervision
//
//  Created by John Demirci on 4/19/26.
//

import Supervision

struct TodoFeature: FeatureBlueprint {
    @ObservableValue
    struct State {
        var todos: [String] = []
    }

    enum Action {
        case fetch
        case fetchResult(Result<[String], Error>)
        case add(String)
        case addResult(Result<String, Error>)
        case remove(String)
        case removeResult(Result<String, Error>)
    }

    struct Dependency: Sendable {
        let client: TodoClient
    }

    func process(action: Action, context: borrowing Context<State>) -> FeatureWork {
        switch action {
        case .add(let todo):
            return .run { dependency in
                await dependency.client.add(todo)
            } map: { result in
                .addResult(result)
            }

        case .addResult(let result):
            guard case .success(let success) = result else {
                return .done
            }

            context.todos.append(success)
            return .done

        case .fetch:
            return .run { dependency in
                try await dependency.client.fetch()
            } map: { result in
                .fetchResult(result)
            }

        case .fetchResult(let result):
            guard case .success(let success) = result else {
                return .done
            }

            context.todos = success
            return .done

        case .remove(let todo):
            return .run { dependency in
                try await dependency.client.remove(todo)
            } map: { result in
                .removeResult(result)
            }

        case .removeResult(let result):
            guard case .success(let success) = result else {
                return .done
            }

            context.todos.removeAll(where: { $0 == success })

            return .done
        }
    }
}

actor TodoClient {
    var currentList = ["wash the dishes", "do the laundry", "go for a walk"]
    func fetch() async throws -> [String] {
        return currentList
    }

    func add(_ todo: String) async -> String {
        currentList.append(todo)
        return todo
    }

    func remove(_ todo: String) async throws -> String {
        let count = currentList.count
        currentList.removeAll(where: { $0 == todo })
        if currentList.count == count {
            throw NSError(domain: "com.example.todolist", code: 1, userInfo: nil)
        }
        return todo
    }
}
