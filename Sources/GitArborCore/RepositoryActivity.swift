import Foundation

public struct RepositoryActivity: Sendable, Equatable {
    public let commits: Int
    public let estimatedMinutes: Int?
}

extension GitHubClient {
    /// Conta todos os commits do ramo principal e estima a duração das sessões do autor conectado.
    /// Agrupa repositórios em lotes e continua apenas os históricos que ainda têm páginas.
    public func repositoryActivity(_ names: [String], from start: Date, through end: Date) async throws -> [String: RepositoryActivity] {
        guard !names.isEmpty else { return [:] }
        struct Viewer: Decodable { struct User: Decodable { let id: String }; let viewer: User }
        let author = try await graphQL("query { viewer { id } }", as: Viewer.self).viewer.id
        let formatter = ISO8601DateFormatter()
        let range = ["author": author, "since": formatter.string(from: start), "until": formatter.string(from: end)]
        var results: [String: RepositoryActivity] = [:]

        for offset in stride(from: 0, to: names.count, by: 8) {
            let batch = names.dropFirst(offset).prefix(8).map { ActivityQuery(name: $0, cursor: nil) }
            let initial = try await activityPages(batch, range: range)
            var dates: [String: [Date]] = [:]
            var counts: [String: Int] = [:]
            var pending: [ActivityQuery] = []
            for item in batch {
                guard let repository = initial[item.name] else { continue }
                guard let branch = repository.defaultBranchRef else {
                    results[item.name] = RepositoryActivity(commits: 0, estimatedMinutes: 0)
                    continue
                }
                guard let target = branch.target, let history = target.total else { continue }
                counts[item.name] = history.totalCount
                if let page = target.recent {
                    dates[item.name] = page.nodes.compactMap { $0?.committedDate }
                    if page.pageInfo.hasNextPage {
                        if let cursor = page.pageInfo.endCursor { pending.append(ActivityQuery(name: item.name, cursor: cursor)) }
                        else { dates.removeValue(forKey: item.name) }
                    }
                }
            }
            while !pending.isEmpty {
                let pages = try await activityPages(pending, range: range)
                pending = pending.compactMap { item in
                    guard let page = pages[item.name]?.defaultBranchRef?.target?.recent else {
                        dates.removeValue(forKey: item.name)
                        return nil
                    }
                    dates[item.name, default: []].append(contentsOf: page.nodes.compactMap { $0?.committedDate })
                    guard page.pageInfo.hasNextPage else { return nil }
                    guard let cursor = page.pageInfo.endCursor, cursor != item.cursor else {
                        dates.removeValue(forKey: item.name)
                        return nil
                    }
                    return ActivityQuery(name: item.name, cursor: cursor)
                }
            }
            for (name, count) in counts {
                let minutes = dates[name].map { Self.estimatedActivityMinutes($0.filter { $0 >= start && $0 <= end }) }
                results[name] = RepositoryActivity(commits: count, estimatedMinutes: minutes)
            }
        }
        return results
    }

    /// 15 minutos para o primeiro commit de cada sessão, mais os intervalos de até uma hora.
    static func estimatedActivityMinutes(_ timestamps: [Date]) -> Int {
        let dates = timestamps.sorted()
        guard let first = dates.first else { return 0 }
        var previous = first
        var seconds: TimeInterval = 15 * 60
        for date in dates.dropFirst() {
            let gap = date.timeIntervalSince(previous)
            seconds += gap <= 3600 ? gap : 15 * 60
            previous = date
        }
        return Int((seconds / 60).rounded())
    }

    private struct ActivityQuery {
        let name: String
        let cursor: String?
    }

    private struct ActivityRepository: Decodable {
        struct Ref: Decodable {
            struct Commit: Decodable {
                struct Count: Decodable { let totalCount: Int }
                struct Recent: Decodable {
                    struct Node: Decodable { let committedDate: Date }
                    struct Page: Decodable { let hasNextPage: Bool; let endCursor: String? }
                    let nodes: [Node?]
                    let pageInfo: Page
                }
                let total: Count?
                let recent: Recent?
            }
            let target: Commit?
        }
        let defaultBranchRef: Ref?
    }

    private func activityPages(_ items: [ActivityQuery], range: [String: String]) async throws -> [String: ActivityRepository] {
        try Task.checkCancellation()
        var variables = range
        var parameters = ["$author: ID!", "$since: GitTimestamp!", "$until: GitTimestamp!"]
        var fields: [String] = []
        var names: [String: String] = [:]

        for (i, item) in items.enumerated() {
            let parts = item.name.split(separator: "/")
            guard parts.count == 2 else { continue }
            let alias = "repo\(i)"
            names[alias] = item.name
            variables["owner\(i)"] = String(parts[0])
            variables["name\(i)"] = String(parts[1])
            parameters += ["$owner\(i): String!", "$name\(i): String!"]
            var pagination = ""
            if let cursor = item.cursor {
                parameters.append("$cursor\(i): String!")
                variables["cursor\(i)"] = cursor
                pagination = ", after: $cursor\(i)"
            }
            let total = item.cursor == nil ? "total: history(first: 1) { totalCount }" : ""
            fields.append("""
            \(alias): repository(owner: $owner\(i), name: $name\(i)) {
              defaultBranchRef {
                target { ... on Commit {
                  \(total)
                  recent: history(first: 100, author: {id: $author}, since: $since, until: $until\(pagination)) {
                    nodes { committedDate }
                    pageInfo { hasNextPage endCursor }
                  }
                } }
              }
            }
            """)
        }
        guard !fields.isEmpty else { return [:] }
        let query = "query RepositoryActivity(\(parameters.joined(separator: ", "))) { \(fields.joined(separator: "\n")) }"
        let response = try await graphQL(query, variables: variables, as: [String: ActivityRepository?].self)
        return Dictionary(uniqueKeysWithValues: names.compactMap { alias, name in
            guard let repository = response[alias] ?? nil else { return nil }
            return (name, repository)
        })
    }
}
