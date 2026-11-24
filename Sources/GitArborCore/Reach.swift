import Foundation

// MARK: - Respostas do GitHub (Insights → Traffic)

/// Um dia de visitas ou de clones. O GitHub marca o dia com a meia-noite em UTC.
public struct GHTrafficDay: Codable, Sendable, Hashable {
    public let timestamp: Date
    public let count: Int
    public let uniques: Int

    public init(timestamp: Date, count: Int, uniques: Int) {
        self.timestamp = timestamp
        self.count = count
        self.uniques = uniques
    }
}

/// Visitas à página do repositório nos últimos 14 dias.
public struct GHTrafficViews: Codable, Sendable, Hashable {
    public let count: Int
    public let uniques: Int
    public let views: [GHTrafficDay]
}

/// Cópias (clones) do repositório nos últimos 14 dias.
public struct GHTrafficClones: Codable, Sendable, Hashable {
    public let count: Int
    public let uniques: Int
    public let clones: [GHTrafficDay]
}

/// Site de onde as pessoas vieram (Google, um blog, o próprio GitHub…).
public struct GHReferrer: Codable, Sendable, Hashable, Identifiable {
    public let referrer: String
    public let count: Int
    public let uniques: Int
    public var id: String { referrer }
}

/// Página do repositório mais vista.
public struct GHPopularPath: Codable, Sendable, Hashable, Identifiable {
    public let path: String
    public let title: String
    public let count: Int
    public let uniques: Int
    public var id: String { path }

    /// Caminho sem o “/dono/repositório” do começo: “/blob/main/README.md” vira “blob/main/README.md”.
    public func shortPath(repoFullName: String) -> String {
        let prefix = "/" + repoFullName
        var p = path
        if p.lowercased().hasPrefix(prefix.lowercased()) { p.removeFirst(prefix.count) }
        p = p.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return p.isEmpty ? "Página inicial" : p
    }
}

// MARK: - Histórico guardado no Mac

/// Números de um dia.
public struct ReachDay: Codable, Sendable, Hashable {
    public var views = 0
    public var viewUniques = 0
    public var clones = 0
    public var cloneUniques = 0

    public init(views: Int = 0, viewUniques: Int = 0, clones: Int = 0, cloneUniques: Int = 0) {
        self.views = views
        self.viewUniques = viewUniques
        self.clones = clones
        self.cloneUniques = cloneUniques
    }
}

/// O GitHub só mostra os últimos 14 dias. O histórico junta, dia a dia, tudo o que o app já viu,
/// para o alcance poder ser acompanhado por meses.
public struct ReachHistory: Codable, Sendable, Hashable {
    /// Dia no formato “2026-11-24” (UTC, como o GitHub) → números do dia.
    public var days: [String: ReachDay] = [:]
    public var updatedAt: Date?

    public init(days: [String: ReachDay] = [:], updatedAt: Date? = nil) {
        self.days = days
        self.updatedAt = updatedAt
    }

    static let dayKey: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    public static func key(_ date: Date) -> String { dayKey.string(from: date) }
    public static func date(_ key: String) -> Date? { dayKey.date(from: key) }

    /// Junta o que o GitHub devolveu agora. Para os dias que vieram, o número novo vale
    /// (o dia de hoje ainda está crescendo); os dias antigos continuam guardados.
    public mutating func merge(views: [GHTrafficDay], clones: [GHTrafficDay], at now: Date = Date()) {
        for d in views {
            let k = Self.key(d.timestamp)
            var day = days[k] ?? ReachDay()
            day.views = d.count
            day.viewUniques = d.uniques
            days[k] = day
        }
        for d in clones {
            let k = Self.key(d.timestamp)
            var day = days[k] ?? ReachDay()
            day.clones = d.count
            day.cloneUniques = d.uniques
            days[k] = day
        }
        updatedAt = now
    }

    /// Primeiro dia guardado.
    public var firstDay: Date? { days.keys.min().flatMap(Self.date) }

    public var totalViews: Int { days.values.reduce(0) { $0 + $1.views } }
    public var totalClones: Int { days.values.reduce(0) { $0 + $1.clones } }

    /// Série contínua (dias sem nada viram zero) dos últimos `limit` dias até `end`.
    public func series(lastDays limit: Int, until end: Date = Date()) -> [(date: Date, day: ReachDay)] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let last = calendar.startOfDay(for: end)
        let start: Date = {
            let earliest = calendar.date(byAdding: .day, value: -(limit - 1), to: last)!
            guard let first = firstDay else { return earliest }
            return max(earliest, calendar.startOfDay(for: first))
        }()
        var out: [(Date, ReachDay)] = []
        var d = start
        while d <= last {
            out.append((d, days[Self.key(d)] ?? ReachDay()))
            d = calendar.date(byAdding: .day, value: 1, to: d)!
        }
        return out
    }
}

public enum Reach {
    /// Soma dos downloads de todos os arquivos de todas as versões publicadas.
    public static func totalDownloads(_ releases: [GHRelease]) -> Int {
        releases.reduce(0) { sum, r in sum + r.assets.reduce(0) { $0 + $1.downloadCount } }
    }

    /// Nome amigável do site de origem.
    public static func referrerName(_ referrer: String) -> String {
        switch referrer.lowercased() {
        case "github.com": "GitHub"
        case "google", "google.com": "Google"
        case "bing.com": "Bing"
        case "duckduckgo.com": "DuckDuckGo"
        case "t.co", "twitter.com", "x.com": "X (Twitter)"
        case "linkedin.com", "lnkd.in": "LinkedIn"
        case "reddit.com", "old.reddit.com": "Reddit"
        case "news.ycombinator.com": "Hacker News"
        case "facebook.com", "m.facebook.com", "l.facebook.com": "Facebook"
        case "instagram.com", "l.instagram.com": "Instagram"
        case "youtube.com": "YouTube"
        default: referrer
        }
    }
}
