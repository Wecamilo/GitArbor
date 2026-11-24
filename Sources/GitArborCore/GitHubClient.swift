import Foundation

/// Erros da conversa com o GitHub, já em linguagem simples.
public enum GitHubError: LocalizedError, Sendable, Equatable {
    case unauthorized
    case forbidden(String?)
    case notFound
    case invalid(String)
    case server(Int, String?)
    case offline

    public var errorDescription: String? {
        switch self {
        case .unauthorized:
            "O GitHub não aceitou a sua chave de acesso. Ela pode ter expirado: conecte a conta de novo em Conta."
        case .forbidden(let message):
            "O GitHub não deixou fazer isso. A sua chave de acesso pode não ter essa permissão."
                + (message.map { "\n\nDetalhe: \($0)" } ?? "")
        case .notFound:
            "Não encontrei isso no GitHub. Pode ter sido apagado ou você não tem acesso."
        case .invalid(let message):
            "O GitHub recusou o pedido: \(message)"
        case .server(let code, let message):
            "O GitHub respondeu com um erro (\(code))." + (message.map { " \($0)" } ?? "")
        case .offline:
            "Sem conexão com a internet. Confira o Wi-Fi e tente de novo."
        }
    }
}

/// Cliente da API do GitHub (REST + GraphQL) com a chave de acesso do usuário.
public struct GitHubClient: Sendable {
    public let token: String
    let base = URL(string: "https://api.github.com")!
    let session: URLSession
    /// Respostas guardadas com a etiqueta (ETag) do GitHub: perguntar de novo custa quase nada
    /// e, quando nada mudou, o GitHub responde 304 sem gastar o limite de pedidos.
    public let responses: ResponseCache

    public init(token: String, session: URLSession = .shared) {
        self.token = token
        self.session = session
        self.responses = ResponseCache()
    }

    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    // MARK: Transporte

    func request(_ method: String, _ path: String, query: [String: String] = [:], body: Data? = nil,
                 accept: String = "application/vnd.github+json") -> URLRequest {
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var req = URLRequest(url: components.url!)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(accept, forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        req.setValue("GitArbor", forHTTPHeaderField: "User-Agent")
        req.cachePolicy = .reloadIgnoringLocalCacheData
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return req
    }

    /// Faz o pedido e, se o GitHub redirecionou (repositório renomeado ou transferido),
    /// refaz no endereço novo com a chave de acesso: o sistema descarta o cabeçalho
    /// Authorization ao seguir o redirecionamento, e um repositório privado viraria “não encontrado”.
    func load(_ req: URLRequest) async throws -> (Data, URLResponse) {
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, [401, 403, 404].contains(http.statusCode),
              let final = http.url, let original = req.url, final != original,
              final.host == original.host else { return (data, response) }
        var retry = req
        retry.url = final
        return try await session.data(for: retry)
    }

    func send(_ req: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await load(req)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost].contains(error.code) {
            throw GitHubError.offline
        }
        guard let http = response as? HTTPURLResponse else { throw GitHubError.server(0, nil) }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.error(status: http.statusCode, data: data)
        }
        return (data, http)
    }

    static func error(status: Int, data: Data) -> GitHubError {
        struct Body: Decodable {
            struct Item: Decodable { let message: String?; let field: String?; let code: String? }
            let message: String?
            let errors: [Item]?
        }
        let body = try? JSONDecoder().decode(Body.self, from: data)
        let detail = body?.errors?.compactMap { $0.message ?? [$0.field, $0.code].compactMap { $0 }.joined(separator: " ") }.first
        let message = [body?.message, detail].compactMap { $0 }.joined(separator: " — ")
        switch status {
        case 401: return .unauthorized
        case 403: return .forbidden(message.isEmpty ? nil : message)
        case 404: return .notFound
        case 409, 405, 422: return .invalid(Self.translate(message))
        default: return .server(status, message.isEmpty ? nil : message)
        }
    }

    /// Mensagens comuns traduzidas para o português.
    static func translate(_ message: String) -> String {
        let lower = message.lowercased()
        if lower.contains("name already exists") { return "já existe um repositório com esse nome." }
        if lower.contains("reference already exists") { return "já existe um ramo com esse nome." }
        if lower.contains("no commits between") { return "não há diferenças entre os dois ramos." }
        if lower.contains("pull request already exists") { return "já existe um pedido de mudança aberto para esse ramo." }
        if lower.contains("not mergeable") || lower.contains("merge conflict") { return "há conflitos: as mesmas linhas foram mudadas nos dois ramos. Resolva no site do GitHub." }
        if lower.contains("already_exists") && lower.contains("tag_name") { return "já existe uma versão com essa etiqueta." }
        return message.isEmpty ? "pedido inválido." : message
    }

    /// GET condicional: manda a etiqueta da última resposta; se o GitHub disser 304 (nada mudou),
    /// usa a resposta guardada. `changed` diz se veio algo novo.
    func conditionalGet(_ path: String, query: [String: String] = [:]) async throws -> (data: Data, changed: Bool) {
        var req = request("GET", path, query: query)
        let key = req.url!
        let cached = await responses.entry(for: key)
        if let cached {
            if let etag = cached.etag { req.setValue(etag, forHTTPHeaderField: "If-None-Match") }
            if let modified = cached.lastModified { req.setValue(modified, forHTTPHeaderField: "If-Modified-Since") }
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await load(req)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost].contains(error.code) {
            throw GitHubError.offline
        }
        guard let http = response as? HTTPURLResponse else { throw GitHubError.server(0, nil) }
        if let poll = http.value(forHTTPHeaderField: "X-Poll-Interval").flatMap(TimeInterval.init) {
            await responses.setPollInterval(poll, for: path)
        }
        if http.statusCode == 304, let cached { return (cached.data, false) }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.error(status: http.statusCode, data: data)
        }
        let etag = http.value(forHTTPHeaderField: "ETag")
        let modified = http.value(forHTTPHeaderField: "Last-Modified")
        if etag != nil || modified != nil {
            await responses.store(ResponseCache.Entry(etag: etag, lastModified: modified, data: data), for: key)
        }
        return (data, cached?.data != data)
    }

    public func get<T: Decodable>(_ path: String, query: [String: String] = [:], as: T.Type = T.self) async throws -> T {
        let (data, _) = try await conditionalGet(path, query: query)
        return try Self.decoder.decode(T.self, from: data)
    }

    /// Como `get`, mas devolve nil quando nada mudou desde a última vez.
    public func getIfChanged<T: Decodable>(_ path: String, query: [String: String] = [:], as: T.Type = T.self) async throws -> T? {
        let (data, changed) = try await conditionalGet(path, query: query)
        return changed ? try Self.decoder.decode(T.self, from: data) : nil
    }

    /// Junta todas as páginas (até `maxPages`).
    public func getAll<T: Decodable>(_ path: String, query: [String: String] = [:], maxPages: Int = 10) async throws -> [T] {
        try await getAllTracked(path, query: query, maxPages: maxPages).items
    }

    func getAllTracked<T: Decodable>(_ path: String, query: [String: String] = [:], maxPages: Int = 10) async throws -> (items: [T], changed: Bool) {
        var results: [T] = []
        var changed = false
        var q = query
        q["per_page"] = q["per_page"] ?? "100"
        for page in 1...maxPages {
            q["page"] = String(page)
            let (data, pageChanged) = try await conditionalGet(path, query: q)
            changed = changed || pageChanged
            let items = try Self.decoder.decode([T].self, from: data)
            results += items
            if items.count < Int(q["per_page"]!)! { break }
        }
        return (results, changed)
    }

    @discardableResult
    public func send<T: Decodable>(_ method: String, _ path: String, json: [String: any Sendable]? = nil, as: T.Type = T.self) async throws -> T {
        let body = try json.map { try JSONSerialization.data(withJSONObject: $0) }
        let (data, _) = try await send(request(method, path, body: body))
        return try Self.decoder.decode(T.self, from: data)
    }

    /// Pedido sem resposta útil (ex.: 204 No Content).
    public func perform(_ method: String, _ path: String, json: [String: any Sendable]? = nil) async throws {
        let body = try json.map { try JSONSerialization.data(withJSONObject: $0) }
        _ = try await send(request(method, path, body: body))
    }

    public func raw(_ path: String, query: [String: String] = [:]) async throws -> String {
        let (data, _) = try await send(request("GET", path, query: query, accept: "application/vnd.github.raw+json"))
        return String(decoding: data, as: UTF8.self)
    }

    public func graphQL<T: Decodable>(_ query: String, variables: [String: String] = [:], as: T.Type = T.self) async throws -> T {
        let body = try JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])
        let (data, _) = try await send(request("POST", "graphql", body: body))
        guard let value = try Self.decoder.decode(GraphQLEnvelope<T>.self, from: data).data else {
            throw GitHubError.server(200, "Resposta vazia")
        }
        return value
    }

    // MARK: Conta

    public func currentUser() async throws -> GHUser { try await get("user") }

    public func repositories() async throws -> [GHRepo] {
        try await getAll("user/repos", query: ["sort": "pushed", "affiliation": "owner,collaborator,organization_member"])
    }

    public func repositoriesIfChanged() async throws -> [GHRepo]? {
        let result: (items: [GHRepo], changed: Bool) = try await getAllTracked(
            "user/repos", query: ["sort": "pushed", "affiliation": "owner,collaborator,organization_member"])
        return result.changed ? result.items : nil
    }

    public func events(login: String) async throws -> [GHEvent] {
        try await get("users/\(login)/events", query: ["per_page": "40"])
    }

    public func eventsIfChanged(login: String) async throws -> [GHEvent]? {
        try await getIfChanged("users/\(login)/events", query: ["per_page": "40"])
    }

    public func notifications(all: Bool = false) async throws -> [GHNotification] {
        try await get("notifications", query: ["all": all ? "true" : "false", "per_page": "50"])
    }

    public func notificationsIfChanged() async throws -> [GHNotification]? {
        try await getIfChanged("notifications", query: ["all": "false", "per_page": "50"])
    }

    public func markAllNotificationsRead() async throws {
        try await perform("PUT", "notifications", json: ["read": true])
    }

    public func markNotificationRead(_ id: String) async throws {
        try await perform("PATCH", "notifications/threads/\(id)")
    }

    public func contributionCalendar() async throws -> ContributionCalendar {
        struct D: Decodable {
            struct V: Decodable {
                struct C: Decodable { let contributionCalendar: ContributionCalendar }
                let contributionsCollection: C
            }
            let viewer: V
        }
        let q = "query { viewer { contributionsCollection { contributionCalendar { totalContributions weeks { contributionDays { date contributionCount weekday } } } } } }"
        return try await graphQL(q, as: D.self).viewer.contributionsCollection.contributionCalendar
    }

    // MARK: Repositório

    public func createRepository(name: String, description: String, isPrivate: Bool, withReadme: Bool) async throws -> GHRepo {
        try await send("POST", "user/repos", json: [
            "name": name, "description": description, "private": isPrivate, "auto_init": withReadme
        ])
    }

    public func updateRepository(_ fullName: String, fields: [String: any Sendable]) async throws -> GHRepo {
        try await send("PATCH", "repos/\(fullName)", json: fields)
    }

    public func deleteRepository(_ fullName: String) async throws {
        try await perform("DELETE", "repos/\(fullName)")
    }

    public func readme(_ fullName: String) async throws -> String {
        try await raw("repos/\(fullName)/readme")
    }

    public func languages(_ fullName: String) async throws -> [String: Int] {
        try await get("repos/\(fullName)/languages")
    }

    /// Linhas adicionadas e removidas por semana: [[segundos desde 1970, adições, remoções (negativo)]].
    /// nil = o GitHub ainda está calculando (resposta 202); vale perguntar de novo em instantes.
    public func codeFrequency(_ fullName: String) async throws -> [[Int]]? {
        let (data, http) = try await send(request("GET", "repos/\(fullName)/stats/code_frequency"))
        if http.statusCode == 202 { return nil }
        if http.statusCode == 204 || data.isEmpty { return [] }
        return try Self.decoder.decode([[Int]].self, from: data)
    }

    public func contents(_ fullName: String, path: String, ref: String?) async throws -> [GHContent] {
        let p = path.isEmpty ? "repos/\(fullName)/contents" : "repos/\(fullName)/contents/\(path)"
        return try await get(p, query: ref.map { ["ref": $0] } ?? [:])
    }

    public func file(_ fullName: String, path: String, ref: String?) async throws -> GHContent {
        try await get("repos/\(fullName)/contents/\(path)", query: ref.map { ["ref": $0] } ?? [:])
    }

    public func commits(_ fullName: String, branch: String?, page: Int = 1) async throws -> [GHCommit] {
        var q = ["per_page": "40", "page": String(page)]
        if let branch { q["sha"] = branch }
        return try await get("repos/\(fullName)/commits", query: q)
    }

    public func commit(_ fullName: String, sha: String) async throws -> GHCommit {
        try await get("repos/\(fullName)/commits/\(sha)")
    }

    public func branches(_ fullName: String) async throws -> [GHBranch] {
        try await getAll("repos/\(fullName)/branches", maxPages: 3)
    }

    public func compare(_ fullName: String, base: String, head: String) async throws -> GHCompare {
        try await get("repos/\(fullName)/compare/\(base)...\(head)")
    }

    public func createBranch(_ fullName: String, name: String, fromSHA sha: String) async throws {
        try await perform("POST", "repos/\(fullName)/git/refs", json: ["ref": "refs/heads/\(name)", "sha": sha])
    }

    public func deleteBranch(_ fullName: String, name: String) async throws {
        try await perform("DELETE", "repos/\(fullName)/git/refs/heads/\(name)")
    }

    public func issues(_ fullName: String, open: Bool) async throws -> [GHIssue] {
        let all: [GHIssue] = try await get("repos/\(fullName)/issues",
                                            query: ["state": open ? "open" : "closed", "per_page": "60"])
        return all.filter { !$0.isPullRequest }
    }

    public func createIssue(_ fullName: String, title: String, body: String) async throws -> GHIssue {
        try await send("POST", "repos/\(fullName)/issues", json: ["title": title, "body": body])
    }

    public func setIssue(_ fullName: String, number: Int, open: Bool) async throws -> GHIssue {
        try await send("PATCH", "repos/\(fullName)/issues/\(number)", json: ["state": open ? "open" : "closed"])
    }

    public func comments(_ fullName: String, number: Int) async throws -> [GHComment] {
        try await get("repos/\(fullName)/issues/\(number)/comments", query: ["per_page": "100"])
    }

    public func addComment(_ fullName: String, number: Int, body: String) async throws -> GHComment {
        try await send("POST", "repos/\(fullName)/issues/\(number)/comments", json: ["body": body])
    }

    public func pulls(_ fullName: String, open: Bool) async throws -> [GHPull] {
        try await get("repos/\(fullName)/pulls", query: ["state": open ? "open" : "closed", "per_page": "50"])
    }

    public func pull(_ fullName: String, number: Int) async throws -> GHPull {
        try await get("repos/\(fullName)/pulls/\(number)")
    }

    public func createPull(_ fullName: String, title: String, head: String, base: String, body: String) async throws -> GHPull {
        try await send("POST", "repos/\(fullName)/pulls", json: ["title": title, "head": head, "base": base, "body": body])
    }

    public func mergePull(_ fullName: String, number: Int, method: String) async throws -> GHMergeResult {
        try await send("PUT", "repos/\(fullName)/pulls/\(number)/merge", json: ["merge_method": method])
    }

    public func setPull(_ fullName: String, number: Int, open: Bool) async throws -> GHPull {
        try await send("PATCH", "repos/\(fullName)/pulls/\(number)", json: ["state": open ? "open" : "closed"])
    }

    public func runs(_ fullName: String) async throws -> GHRunList {
        try await get("repos/\(fullName)/actions/runs", query: ["per_page": "30"])
    }

    public func rerun(_ fullName: String, runID: Int) async throws {
        try await perform("POST", "repos/\(fullName)/actions/runs/\(runID)/rerun")
    }

    public func releases(_ fullName: String) async throws -> [GHRelease] {
        try await get("repos/\(fullName)/releases", query: ["per_page": "30"])
    }

    public func createRelease(_ fullName: String, tag: String, name: String, notes: String, target: String, prerelease: Bool) async throws -> GHRelease {
        try await send("POST", "repos/\(fullName)/releases", json: [
            "tag_name": tag, "name": name, "body": notes, "target_commitish": target, "prerelease": prerelease
        ])
    }

    public func deleteRelease(_ fullName: String, id: Int) async throws {
        try await perform("DELETE", "repos/\(fullName)/releases/\(id)")
    }

    public func setStar(_ fullName: String, starred: Bool) async throws {
        try await perform(starred ? "PUT" : "DELETE", "user/starred/\(fullName)")
    }

    // MARK: Segurança

    /// Alertas abertos do Dependabot (dependências com falhas conhecidas).
    public func dependabotAlerts(_ fullName: String) async throws -> [GHDependabotAlert] {
        try await get("repos/\(fullName)/dependabot/alerts", query: ["state": "open", "per_page": "100"])
    }

    /// Os alertas de dependências estão ligados? (o GitHub responde 204 = sim, 404 = não)
    public func vulnerabilityAlertsEnabled(_ fullName: String) async throws -> Bool {
        do {
            _ = try await send(request("GET", "repos/\(fullName)/vulnerability-alerts"))
            return true
        } catch GitHubError.notFound {
            return false
        }
    }

    /// Liga os alertas de dependências e as correções automáticas do Dependabot.
    public func enableSecurityAlerts(_ fullName: String) async throws {
        try await perform("PUT", "repos/\(fullName)/vulnerability-alerts")
        try? await perform("PUT", "repos/\(fullName)/automated-security-fixes")
    }

    /// Segredos que o próprio GitHub encontrou no repositório (quando a varredura está disponível).
    public func secretScanningAlerts(_ fullName: String) async throws -> [GHSecretAlert] {
        try await get("repos/\(fullName)/secret-scanning/alerts", query: ["state": "open", "per_page": "100"])
    }

    // MARK: Pessoas

    public func collaborators(_ fullName: String) async throws -> [GHCollaborator] {
        try await getAll("repos/\(fullName)/collaborators", query: ["affiliation": "all"])
    }

    public func invitations(_ fullName: String) async throws -> [GHInvitation] {
        try await getAll("repos/\(fullName)/invitations")
    }

    /// Convida alguém (ou muda a permissão de quem já está). permission: pull, triage, push, maintain, admin.
    public func addCollaborator(_ fullName: String, login: String, permission: String) async throws {
        try await perform("PUT", "repos/\(fullName)/collaborators/\(login)", json: ["permission": permission])
    }

    public func removeCollaborator(_ fullName: String, login: String) async throws {
        try await perform("DELETE", "repos/\(fullName)/collaborators/\(login)")
    }

    public func deleteInvitation(_ fullName: String, id: Int) async throws {
        try await perform("DELETE", "repos/\(fullName)/invitations/\(id)")
    }

    // MARK: Busca

    /// Tarefas e pedidos de mudança em que você está envolvido e que combinam com o texto.
    public func searchIssues(_ text: String, login: String) async throws -> [GHIssueSearchItem] {
        let result: GHSearchResult<GHIssueSearchItem> = try await get("search/issues", query: [
            "q": "\(text) involves:\(login)", "per_page": "15", "sort": "updated"
        ])
        return result.items
    }
}

struct GraphQLEnvelope<D: Decodable>: Decodable { let data: D? }

/// Últimas respostas do GitHub com as etiquetas para perguntar “mudou algo?”,
/// e o intervalo mínimo entre perguntas que o GitHub pede (X-Poll-Interval).
public actor ResponseCache {
    struct Entry: Sendable {
        let etag: String?
        let lastModified: String?
        let data: Data
    }

    private var entries: [URL: Entry] = [:]
    private var pollIntervals: [String: TimeInterval] = [:]

    public init() {}

    func entry(for url: URL) -> Entry? { entries[url] }

    func store(_ entry: Entry, for url: URL) {
        entries[url] = entry
    }

    func setPollInterval(_ seconds: TimeInterval, for path: String) {
        pollIntervals[path] = seconds
    }

    /// Quanto esperar até a próxima verificação: o maior intervalo pedido pelo GitHub (padrão 60 s).
    public func pollInterval(minimum: TimeInterval = 60) -> TimeInterval {
        max(minimum, pollIntervals.values.max() ?? 0)
    }
}
