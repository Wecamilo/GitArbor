import Foundation
import GitArborCore

/// Tudo o que o app mostra, guardado em disco para abrir na hora; a atualização vem em segundo plano.
nonisolated struct AppCache: Codable, Sendable {
    var login: String
    var credentialID: String? = nil
    var savedAt: Date
    var user: GHUser
    var repos: [GHRepo]
    var events: [GHEvent]
    var notifications: [GHNotification]
    var calendar: ContributionCalendar?
    /// Versões antigas guardavam uma pasta só.
    var localFolder: URL? = nil
    var localFolders: [URL]? = nil
    var localRepos: [LocalRepoStatus]
    var foldersWithoutGit: [URL]
    /// Gráficos do Panorama que demoram para vir do GitHub: abrem na hora com o último valor.
    var codeWeeks: [CodeWeek]? = nil
    var languageBytes: [String: Int]? = nil
    var languageRepositoryCount: Int? = nil
}

/// Lê e grava o cache em ~/Library/Application Support/Git Arbor/cache.json (só o seu usuário lê).
/// Fica fora do iCloud e é apagado ao desconectar a conta.
enum CacheStore {
    private static let queue = DispatchQueue(label: "GitArbor.CacheStore", qos: .utility)

    static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Git Arbor/cache.json")
    }

    static func load() async -> AppCache? {
        let url = url
        return await withCheckedContinuation { continuation in
            queue.async {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let cache = (try? Data(contentsOf: url)).flatMap { try? decoder.decode(AppCache.self, from: $0) }
                continuation.resume(returning: cache)
            }
        }
    }

    static func save(_ cache: AppCache) {
        let url = url
        queue.async {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(cache) else { return }
            let fm = FileManager.default
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
            try? data.write(to: url, options: .atomic)
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }

    static func delete() {
        let url = url
        queue.sync { try? FileManager.default.removeItem(at: url) }
    }
}

/// Histórico de alcance (visitas e clones por dia) de cada repositório, guardado em
/// ~/Library/Application Support/Git Arbor/reach.json. O GitHub só mostra 14 dias; aqui eles se acumulam.
/// A chave é o número do repositório, que não muda quando ele é renomeado.
enum ReachStore {
    private static let queue = DispatchQueue(label: "GitArbor.ReachStore", qos: .utility)

    static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Git Arbor/reach.json")
    }

    private static func readAll(_ url: URL) -> [String: ReachHistory] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? Data(contentsOf: url)).flatMap { try? decoder.decode([String: ReachHistory].self, from: $0) } ?? [:]
    }

    static func load(repoID: Int) async -> ReachHistory? {
        let url = url
        return await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: readAll(url)[String(repoID)]) }
        }
    }

    static func save(_ history: ReachHistory, repoID: Int) {
        let url = url
        queue.async {
            var all = readAll(url)
            all[String(repoID)] = history
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(all) else { return }
            let fm = FileManager.default
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
            try? data.write(to: url, options: .atomic)
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }

    static func delete() {
        let url = url
        queue.sync { try? FileManager.default.removeItem(at: url) }
    }
}
