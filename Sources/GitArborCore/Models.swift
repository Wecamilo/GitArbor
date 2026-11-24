import Foundation

// Modelos da API REST do GitHub (só os campos que o app usa).
// A decodificação usa `convertFromSnakeCase`: `html_url` vira `htmlUrl`.

public struct GHOwner: Codable, Sendable, Hashable {
    public let login: String
    public let avatarUrl: URL?
    public let type: String?
}

public struct GHUser: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let login: String
    public let name: String?
    public let avatarUrl: URL?
    public let bio: String?
    public let publicRepos: Int?
    public let totalPrivateRepos: Int?
    public let followers: Int?
    public let following: Int?
    public let htmlUrl: URL?
    public let createdAt: Date?

    /// Primeiro nome para cumprimentar ("Boa tarde, Ana").
    public var firstName: String {
        let full = (name?.isEmpty == false ? name! : login)
        return full.split(separator: " ").first.map(String.init) ?? login
    }
}

public struct GHRepo: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let name: String
    public let fullName: String
    public let owner: GHOwner
    public let isPrivate: Bool
    public let description: String?
    public let fork: Bool
    public let htmlUrl: URL
    public let cloneUrl: String?
    public let sshUrl: String?
    public let defaultBranch: String?
    public let language: String?
    public let stargazersCount: Int
    public let forksCount: Int
    public let openIssuesCount: Int
    public let watchersCount: Int?
    public let size: Int?
    public let archived: Bool?
    public let hasIssues: Bool?
    public let homepage: String?
    public let topics: [String]?
    public let pushedAt: Date?
    public let updatedAt: Date?
    public let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, fullName, owner, description, fork, htmlUrl, cloneUrl, sshUrl, defaultBranch, language,
             stargazersCount, forksCount, openIssuesCount, watchersCount, size, archived, hasIssues, homepage,
             topics, pushedAt, updatedAt, createdAt
        case isPrivate = "private"
    }

    public var branch: String { defaultBranch ?? "main" }
    public var isArchived: Bool { archived ?? false }
    /// Data mais recente de mudança (envio de código ou edição).
    public var lastActivity: Date? { [pushedAt, updatedAt].compactMap { $0 }.max() }
}

public struct GHCommit: Codable, Sendable, Hashable, Identifiable {
    public struct Person: Codable, Sendable, Hashable {
        public let name: String?
        public let date: Date?
    }
    public struct Inner: Codable, Sendable, Hashable {
        public let message: String
        public let author: Person?
    }
    public struct Stats: Codable, Sendable, Hashable {
        public let additions: Int
        public let deletions: Int
        public let total: Int
    }
    public struct File: Codable, Sendable, Hashable, Identifiable {
        public let filename: String
        public let status: String
        public let additions: Int
        public let deletions: Int
        public let patch: String?
        public var id: String { filename }
    }

    public let sha: String
    public let commit: Inner
    public let author: GHOwner?
    public let htmlUrl: URL?
    public let stats: Stats?
    public let files: [File]?

    public var id: String { sha }
    public var shortSHA: String { String(sha.prefix(7)) }
    public var title: String { commit.message.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? "" }
    public var details: String {
        let lines = commit.message.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    public var authorName: String { author?.login ?? commit.author?.name ?? "Alguém" }
    public var date: Date? { commit.author?.date }
}

public struct GHBranch: Codable, Sendable, Hashable, Identifiable {
    public struct Ref: Codable, Sendable, Hashable { public let sha: String }
    public let name: String
    public let commit: Ref
    public let protected: Bool?
    public var id: String { name }
}

public struct GHCompare: Codable, Sendable, Hashable {
    public let aheadBy: Int
    public let behindBy: Int
    public let status: String
}

public struct GHLabel: Codable, Sendable, Hashable {
    public let name: String
    public let color: String?
}

public struct GHIssue: Codable, Sendable, Hashable, Identifiable {
    public struct PRRef: Codable, Sendable, Hashable { public let url: URL? }
    public let id: Int
    public let number: Int
    public let title: String
    public let body: String?
    public let state: String
    public let user: GHOwner?
    public let labels: [GHLabel]
    public let comments: Int
    public let createdAt: Date
    public let updatedAt: Date?
    public let closedAt: Date?
    public let htmlUrl: URL
    public let pullRequest: PRRef?

    public var isOpen: Bool { state == "open" }
    public var isPullRequest: Bool { pullRequest != nil }
}

public struct GHComment: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let body: String?
    public let user: GHOwner?
    public let createdAt: Date
}

public struct GHPull: Codable, Sendable, Hashable, Identifiable {
    public struct Side: Codable, Sendable, Hashable {
        public let ref: String
        public let label: String?
    }
    public let id: Int
    public let number: Int
    public let title: String
    public let body: String?
    public let state: String
    public let user: GHOwner?
    public let createdAt: Date
    public let mergedAt: Date?
    public let draft: Bool?
    public let head: Side
    public let base: Side
    public let htmlUrl: URL
    // Só vêm no detalhe de um pedido:
    public let mergeable: Bool?
    public let additions: Int?
    public let deletions: Int?
    public let changedFiles: Int?
    public let commits: Int?

    public var isOpen: Bool { state == "open" }
    public var isMerged: Bool { mergedAt != nil }
}

public struct GHMergeResult: Codable, Sendable { public let merged: Bool; public let message: String? }

public struct GHRelease: Codable, Sendable, Hashable, Identifiable {
    public struct Asset: Codable, Sendable, Hashable, Identifiable {
        public let id: Int
        public let name: String
        public let size: Int
        public let downloadCount: Int
        public let browserDownloadUrl: URL?
    }
    public let id: Int
    public let tagName: String
    public let name: String?
    public let body: String?
    public let draft: Bool
    public let prerelease: Bool
    public let publishedAt: Date?
    public let createdAt: Date?
    public let htmlUrl: URL
    public let assets: [Asset]

    public var displayName: String { (name?.isEmpty == false ? name! : tagName) }
}

public struct GHRunList: Codable, Sendable { public let totalCount: Int; public let workflowRuns: [GHRun] }

public struct GHRun: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let name: String?
    public let displayTitle: String?
    public let status: String?
    public let conclusion: String?
    public let headBranch: String?
    public let event: String?
    public let runNumber: Int?
    public let createdAt: Date
    public let htmlUrl: URL

    public enum Outcome: Sendable { case running, success, failure, cancelled, skipped, other }
    public var outcome: Outcome {
        if status != "completed" { return .running }
        switch conclusion {
        case "success": return .success
        case "failure", "timed_out", "startup_failure": return .failure
        case "cancelled": return .cancelled
        case "skipped", "neutral": return .skipped
        default: return .other
        }
    }
}

public struct GHContent: Codable, Sendable, Hashable, Identifiable {
    public let name: String
    public let path: String
    public let type: String
    public let size: Int
    public let sha: String
    public let downloadUrl: URL?
    public let htmlUrl: URL?
    public let content: String?
    public let encoding: String?

    public var id: String { path }
    public var isDirectory: Bool { type == "dir" }

    /// Texto do arquivo (a API manda em base64).
    public var decodedText: String? {
        guard let content, encoding == "base64" else { return nil }
        let cleaned = content.replacingOccurrences(of: "\n", with: "")
        guard let data = Data(base64Encoded: cleaned) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public var decodedData: Data? {
        guard let content, encoding == "base64" else { return nil }
        return Data(base64Encoded: content.replacingOccurrences(of: "\n", with: ""))
    }
}

public struct GHNotification: Codable, Sendable, Hashable, Identifiable {
    public struct Subject: Codable, Sendable, Hashable {
        public let title: String
        public let type: String
        public let url: URL?
    }
    public struct Repo: Codable, Sendable, Hashable {
        public let fullName: String
        public let htmlUrl: URL?
    }
    public let id: String
    public let unread: Bool
    public let reason: String
    public let updatedAt: Date
    public let subject: Subject
    public let repository: Repo

    /// Endereço da página no site (a API devolve o endereço da API).
    public var webURL: URL? {
        guard let url = subject.url else { return repository.htmlUrl }
        var s = url.absoluteString.replacingOccurrences(of: "https://api.github.com/repos/", with: "https://github.com/")
        s = s.replacingOccurrences(of: "/pulls/", with: "/pull/")
        s = s.replacingOccurrences(of: "/commits/", with: "/commit/")
        return URL(string: s)
    }
}

public struct GHEvent: Codable, Sendable, Hashable, Identifiable {
    public struct Repo: Codable, Sendable, Hashable { public let name: String }
    public struct Payload: Codable, Sendable, Hashable {
        public struct PushCommit: Codable, Sendable, Hashable { public let message: String }
        public struct Titled: Codable, Sendable, Hashable { public let title: String?; public let number: Int? }
        public struct Rel: Codable, Sendable, Hashable { public let tagName: String?; public let name: String? }
        public let action: String?
        public let ref: String?
        public let refType: String?
        public let size: Int?
        public let commits: [PushCommit]?
        public let pullRequest: Titled?
        public let issue: Titled?
        public let release: Rel?
    }
    public let id: String
    public let type: String
    public let repo: Repo
    public let createdAt: Date
    public let payload: Payload
}

/// Quadradinhos de atividade do último ano (vem da API GraphQL).
public struct ContributionCalendar: Codable, Sendable, Hashable {
    public struct Day: Codable, Sendable, Hashable {
        public let date: String
        public let contributionCount: Int
        public let weekday: Int
    }
    public struct Week: Codable, Sendable, Hashable { public let contributionDays: [Day] }
    public let totalContributions: Int
    public let weeks: [Week]

    public var maxCount: Int { weeks.flatMap(\.contributionDays).map(\.contributionCount).max() ?? 0 }
    /// Dias seguidos com atividade até hoje (ou ontem).
    public var currentStreak: Int {
        var days = weeks.flatMap(\.contributionDays)
        if let last = days.last, last.contributionCount == 0 { days.removeLast() }
        var streak = 0
        for day in days.reversed() {
            if day.contributionCount > 0 { streak += 1 } else { break }
        }
        return streak
    }
}

public enum Languages {
    /// Cores oficiais do GitHub para as linguagens mais comuns.
    public static func hex(_ name: String?) -> String {
        switch name {
        case "Swift": "F05138"
        case "JavaScript": "F1E05A"
        case "TypeScript": "3178C6"
        case "Python": "3572A5"
        case "HTML": "E34C26"
        case "CSS": "663399"
        case "Shell": "89E051"
        case "Ruby": "701516"
        case "Go": "00ADD8"
        case "Java": "B07219"
        case "Kotlin": "A97BFF"
        case "C": "555555"
        case "C++": "F34B7D"
        case "C#": "178600"
        case "PHP": "4F5D95"
        case "Rust": "DEA584"
        case "Dart": "00B4AB"
        case "Vue": "41B883"
        case "Objective-C": "438EFF"
        case "Jupyter Notebook": "DA5B0B"
        case "Dockerfile": "384D54"
        case "SCSS": "C6538C"
        case "Lua": "000080"
        case "Makefile": "427819"
        case "PowerShell": "012456"
        case "Astro": "FF5A03"
        case "Svelte": "FF3E00"
        case "MDX": "FCB32C"
        default: "8E8E93"
        }
    }
}

// MARK: - Segurança

public struct GHDependabotAlert: Codable, Sendable, Hashable, Identifiable {
    public struct Dependency: Codable, Sendable, Hashable {
        public struct Package: Codable, Sendable, Hashable {
            public let ecosystem: String?
            public let name: String
        }
        public let package: Package?
        public let manifestPath: String?
    }
    public struct Advisory: Codable, Sendable, Hashable {
        public let summary: String
        public let severity: String?
        public let ghsaId: String?
    }
    public struct Vulnerability: Codable, Sendable, Hashable {
        public struct Patched: Codable, Sendable, Hashable { public let identifier: String? }
        public let firstPatchedVersion: Patched?
        public let vulnerableVersionRange: String?
    }
    public let number: Int
    public let state: String
    public let dependency: Dependency?
    public let securityAdvisory: Advisory?
    public let securityVulnerability: Vulnerability?
    public let htmlUrl: URL?
    public let createdAt: Date?
    public var id: Int { number }

    /// Gravidade em português.
    public var severityLabel: String {
        switch securityAdvisory?.severity ?? "" {
        case "critical": "Crítica"
        case "high": "Alta"
        case "medium", "moderate": "Média"
        case "low": "Baixa"
        default: "Desconhecida"
        }
    }
}

public struct GHSecretAlert: Codable, Sendable, Hashable, Identifiable {
    public let number: Int
    public let state: String
    public let secretTypeDisplayName: String?
    public let htmlUrl: URL?
    public let createdAt: Date?
    public var id: Int { number }
}

// MARK: - Pessoas

public struct GHCollaborator: Codable, Sendable, Hashable, Identifiable {
    public struct Permissions: Codable, Sendable, Hashable {
        public let admin: Bool?
        public let maintain: Bool?
        public let push: Bool?
        public let triage: Bool?
        public let pull: Bool?
    }
    public let id: Int
    public let login: String
    public let avatarUrl: URL?
    public let htmlUrl: URL?
    public let permissions: Permissions?
    public let roleName: String?

    /// O que a pessoa pode fazer, em português.
    public var roleLabel: String {
        switch roleName ?? "" {
        case "admin": "Administra"
        case "maintain": "Mantém"
        case "write", "push": "Pode mudar"
        case "triage": "Organiza tarefas"
        case "read", "pull": "Só vê"
        default:
            if permissions?.admin == true { "Administra" }
            else if permissions?.push == true { "Pode mudar" }
            else { "Só vê" }
        }
    }
}

public struct GHInvitation: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let invitee: GHOwner?
    public let permissions: String?
    public let createdAt: Date?
}

// MARK: - Busca

public struct GHSearchResult<Item: Codable & Sendable & Hashable>: Codable, Sendable, Hashable {
    public let totalCount: Int
    public let items: [Item]
}

public struct GHIssueSearchItem: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let number: Int
    public let title: String
    public let state: String
    public let htmlUrl: URL
    public let repositoryUrl: URL?
    public let pullRequest: GHIssue.PRRef?
    public let updatedAt: Date?

    public var isPullRequest: Bool { pullRequest != nil }
    /// "dono/nome" a partir do endereço da API.
    public var repositoryFullName: String? {
        guard let parts = repositoryUrl?.pathComponents, parts.count >= 2 else { return nil }
        return parts.suffix(2).joined(separator: "/")
    }
}
