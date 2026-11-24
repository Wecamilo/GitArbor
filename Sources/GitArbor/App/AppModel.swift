import AppKit
import CryptoKit
import Foundation
import GitArborCore
import LocalAuthentication
import Observation
import SwiftUI

/// Seções da barra lateral.
enum AppSection: String, Hashable, CaseIterable, Identifiable {
    case home, panorama, repos, local, notifications

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Início"
        case .panorama: "Panorama"
        case .repos: "Repositórios"
        case .local: "Projetos no Mac"
        case .notifications: "Notificações"
        }
    }

    var subtitle: String {
        switch self {
        case .home: "Resumo do seu GitHub"
        case .panorama: "Tudo em gráficos"
        case .repos: "Seus projetos na nuvem"
        case .local: "Pastas com Git neste Mac"
        case .notifications: "Avisos do GitHub"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .panorama: "chart.pie.fill"
        case .repos: "shippingbox.fill"
        case .local: "laptopcomputer"
        case .notifications: "bell.fill"
        }
    }

    var tint: Color {
        switch self {
        case .home: Theme.accent
        case .panorama: .teal
        case .repos: .blue
        case .local: .indigo
        case .notifications: .orange
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .home: "1"
        case .panorama: "2"
        case .repos: "3"
        case .local: "4"
        case .notifications: "5"
        }
    }
}

/// Uma semana da “maré” de código: linhas adicionadas e removidas.
nonisolated struct CodeWeek: Identifiable, Hashable, Sendable, Codable {
    let id: Date
    let additions: Int
    let deletions: Int
}

/// De onde vem a chave de acesso ao GitHub.
enum TokenSource: String {
    case githubCLI   // pega do `gh` a cada entrada
    case keychain    // colada pelo usuário e guardada no Chaves
}

/// Estado do app: sessão, dados do GitHub e projetos locais.
@Observable
final class AppModel {
    enum Phase: Equatable {
        case welcome   // nenhuma conta conectada
        case locked    // conta conectada: pedir a digital
        case unlocked
    }

    // MARK: Sessão
    /// A digital (ou a senha) acabou de confirmar o dono: as pastas da tela de bloqueio ganham cor.
    var ownerConfirmed = false
    var phase: Phase
    private(set) var client: GitHubClient?
    var section: AppSection = .home
    var repoPath: [GHRepo] = []
    /// Lição aberta na janela de ajuda (Aprender); nil = janela fechada.
    var learning: Lesson?
    /// Busca rápida (⌘K) aberta.
    var quickSearchOpen = false

    // MARK: GitHub
    var user: GHUser?
    var repos: [GHRepo] = []
    /// Ícones dos projetos, mostrados no cabeçalho dos cards.
    let repoIcons = RepoIconStore()
    var events: [GHEvent] = []
    var notifications: [GHNotification] = []
    var calendar: ContributionCalendar? {
        didSet {
            if calendar != oldValue { prepareActivityLabels() }
        }
    }
    private(set) var activityLabels: [String: String] = [:]
    @ObservationIgnored private var activityLabelTask: Task<Void, Never>?
    var isRefreshing = false
    var lastRefresh: Date?

    // MARK: Estatísticas do Panorama
    /// Bytes de código por linguagem, somando todos os repositórios.
    var languageBytes: [String: Int] = [:]
    private(set) var languageRepositoryCount = 0
    private(set) var isLoadingLanguages = false
    /// Linhas adicionadas e removidas por semana, somando todos os repositórios.
    var codeWeeks: [CodeWeek] = []
    var isLoadingPanorama = false
    private var languagesExpireAt: Date?
    private var codeWeeksExpireAt: Date?
    private var panoramaRepositories: [String] = []
    private var codeRepositories: [String] = []
    private var panoramaRequest: UUID?

    // MARK: Mac
    /// Pastas onde ficam os projetos: pode haver várias, espalhadas pelo Mac.
    var localFolders: [URL] {
        didSet {
            guard localFolders != oldValue else { return }
            UserDefaults.standard.set(localFolders.map(\.path), forKey: Keys.localFolders)
            if phase == .unlocked { startWatching() }
        }
    }
    /// Primeira pasta: ponto de partida dos painéis de escolher pasta.
    var localFolder: URL { localFolders.first ?? Self.defaultLocalFolder }
    var localRepos: [LocalRepoStatus] = []
    var foldersWithoutGit: [URL] = []
    var isScanningLocal = false
    var busyFolders: Set<URL> = []
    private var lastLocalScan: Date?

    // MARK: Atualização automática
    /// Pergunta ao GitHub de tempos em tempos (com etiqueta: “nada mudou” sai de graça).
    private var pollTask: Task<Void, Never>?
    /// Aviso do macOS quando algo muda nas pastas de projetos.
    private var watchers: [FolderWatcher] = []
    private var watcherID: UUID?
    private var pendingFolders: Set<URL> = []
    private var pendingRescan = false
    private var fileEventTask: Task<Void, Never>?

    // MARK: Avisos
    var errorMessage: String?
    var toast: Toast?

    struct Toast: Equatable, Identifiable {
        let id = UUID()
        let symbol: String
        let text: String
    }

    // MARK: Preferências
    var requireTouchID: Bool {
        didSet { UserDefaults.standard.set(requireTouchID, forKey: Keys.requireTouchID) }
    }
    var lockOnSleep: Bool {
        didSet { UserDefaults.standard.set(lockOnSleep, forKey: Keys.lockOnSleep) }
    }
    var showExplanations: Bool {
        didSet { UserDefaults.standard.set(showExplanations, forKey: Keys.showExplanations) }
    }
    /// Avisos na Central de Notificações do macOS.
    var systemNotifications: Bool {
        didSet {
            UserDefaults.standard.set(systemNotifications, forKey: Keys.systemNotifications)
            if systemNotifications && phase == .unlocked { SystemNotifier.shared.activate(model: self) }
        }
    }
    /// Avisos do GitHub já vistos (id + data): só os novos viram aviso do macOS. nil = ainda não carregou.
    @ObservationIgnored private var seenNotificationKeys: Set<String>?
    private(set) var tokenSource: TokenSource?

    enum Keys {
        static let tokenSource = "tokenSource"
        static let requireTouchID = "requireTouchID"
        static let lockOnSleep = "lockOnSleep"
        static let localFolder = "localFolder"
        static let localFolders = "localFolders"
        static let showExplanations = "showExplanations"
        static let systemNotifications = "systemNotifications"
        static let lastLogin = "lastLogin"
        static let lastAvatar = "lastAvatar"
    }

    /// Repositórios renomeados no GitHub cuja pasta no Mac ainda usa o nome antigo
    /// (nome antigo em minúsculas → nome atual). O GitHub redireciona o endereço antigo,
    /// então tudo funciona, mas sem isto o app não reconheceria que são o mesmo projeto.
    var renamedRepos: [String: String] = UserDefaults.standard.dictionary(forKey: "renamedRepos") as? [String: String] ?? [:] {
        didSet { UserDefaults.standard.set(renamedRepos, forKey: "renamedRepos") }
    }

    /// Nome atual no GitHub do projeto do Mac (considera renomeações).
    func gitHubName(of local: LocalRepoStatus) -> String? {
        guard let name = local.gitHubFullName else { return nil }
        return renamedRepos[name.lowercased()] ?? name
    }

    /// Cópia do repositório neste Mac, se houver.
    func localCopy(of repo: GHRepo) -> LocalRepoStatus? {
        localRepos.first { gitHubName(of: $0)?.caseInsensitiveCompare(repo.fullName) == .orderedSame }
    }

    /// Pasta deste Mac com a cópia do repositório, se houver.
    func localFolder(for repo: GHRepo) -> URL? { localCopy(of: repo)?.folder }

    /// O repositório foi renomeado no GitHub e a pasta ainda aponta para o nome antigo.
    func renamedTarget(for local: LocalRepoStatus) -> GHRepo? {
        guard let old = local.gitHubFullName, let current = renamedRepos[old.lowercased()],
              current.caseInsensitiveCompare(old) != .orderedSame else { return nil }
        return repos.first { $0.fullName.caseInsensitiveCompare(current) == .orderedSame }
    }

    /// Pergunta ao GitHub o nome atual dos projetos do Mac que não batem com nenhum repositório
    /// (o GitHub responde pelo nome antigo e devolve o novo).
    func resolveRenamedRepos() async {
        guard let client, !repos.isEmpty else { return }
        let known = Set(repos.map { $0.fullName.lowercased() })
        let unmatched = localRepos.compactMap(\.gitHubFullName).filter {
            !known.contains($0.lowercased()) && renamedRepos[$0.lowercased()] == nil
        }
        for name in Set(unmatched) {
            guard let repo: GHRepo = try? await client.get("repos/\(name)"), isCurrent(client) else { continue }
            if repo.fullName.caseInsensitiveCompare(name) != .orderedSame {
                renamedRepos[name.lowercased()] = repo.fullName
            }
        }
        // Percebeu a renomeação: já troca o endereço da pasta, sem precisar de botão.
        // Se não der agora (pasta ocupada, por exemplo), o aviso fica no cartão e tenta de novo depois.
        for local in localRepos {
            guard let target = renamedTarget(for: local) else { continue }
            await updateRemote(of: local, to: target)
        }
    }

    /// Troca o endereço antigo da pasta pelo nome atual do repositório no GitHub.
    func updateRemote(of local: LocalRepoStatus, to repo: GHRepo) async {
        let old = local.remoteURL ?? ""
        let new = (old.hasPrefix("git@") || old.hasPrefix("ssh://")) ? (repo.sshUrl ?? repo.cloneUrl) : repo.cloneUrl
        guard let new else { return }
        let folder = local.folder
        if await runLocal(folder, success: "Endereço de “\(local.name)” atualizado para \(repo.fullName)", {
            try await LocalGit.run(["remote", "set-url", "origin", new], in: folder)
        }) {
            if let key = local.gitHubFullName?.lowercased() { renamedRepos[key] = nil }
        }
    }

    func loadIcon(for repo: GHRepo) async {
        await repoIcons.load(repo, client: client, localFolder: localFolder(for: repo))
    }

    /// Acrescenta uma pasta de projetos. Uma pasta que já está dentro de outra da lista não entra;
    /// uma que contém pastas da lista fica no lugar delas.
    func addLocalFolder(_ url: URL) {
        let new = url.standardizedFileURL
        if localFolders.contains(where: { Self.folder(new, isInside: $0) }) {
            show("folder.fill", "Essa pasta já está na lista")
            return
        }
        localFolders = localFolders.filter { !Self.folder($0, isInside: new) } + [new]
        Task { await scanLocal() }
        show("folder.badge.plus", "Pasta “\(new.lastPathComponent)” acrescentada")
    }

    func removeLocalFolder(_ url: URL) {
        guard localFolders.count > 1 else { return }
        localFolders.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
        let roots = localFolders
        localRepos.removeAll { repo in !roots.contains { Self.folder(repo.folder, isInside: $0) } }
        foldersWithoutGit.removeAll { folder in !roots.contains { Self.folder(folder, isInside: $0) } }
        Task { await scanLocal() }
    }

    /// `folder` é a própria `root` ou fica dentro dela.
    nonisolated static func folder(_ folder: URL, isInside root: URL) -> Bool {
        let a = folder.standardizedFileURL.path, b = root.standardizedFileURL.path
        return a == b || a.hasPrefix(b == "/" ? b : b + "/")
    }

    static var defaultLocalFolder: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/Projetos"),
            home.appendingPathComponent("Projetos"),
            home.appendingPathComponent("Developer"),
            home.appendingPathComponent("GitHub")
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) } ?? home
    }

    init() {
        let d = UserDefaults.standard
        let source = d.string(forKey: Keys.tokenSource).flatMap(TokenSource.init(rawValue:))
        tokenSource = source
        requireTouchID = d.object(forKey: Keys.requireTouchID) as? Bool ?? true
        lockOnSleep = d.object(forKey: Keys.lockOnSleep) as? Bool ?? true
        showExplanations = d.object(forKey: Keys.showExplanations) as? Bool ?? true
        systemNotifications = d.object(forKey: Keys.systemNotifications) as? Bool ?? true
        if let paths = d.stringArray(forKey: Keys.localFolders), !paths.isEmpty {
            localFolders = paths.map { URL(fileURLWithPath: $0) }
        } else {
            localFolders = [d.string(forKey: Keys.localFolder).map { URL(fileURLWithPath: $0) } ?? Self.defaultLocalFolder]
        }
        phase = source == nil ? .welcome : .locked

        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.phase == .unlocked, !self.isScanningLocal else { return }
                if let last = self.lastLocalScan, Date().timeIntervalSince(last) < 30 { return }
                Task { await self.scanLocal() }
            }
        }

        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.lockOnSleep, self.phase == .unlocked else { return }
                self.lock()
            }
        }
    }

    var lastLogin: String? { UserDefaults.standard.string(forKey: Keys.lastLogin) }
    /// Foto da última conta, para a tela de bloqueio (que ainda não tem o usuário carregado).
    var lastAvatar: URL? {
        if let url = user?.avatarUrl { return url }
        if let url = UserDefaults.standard.url(forKey: Keys.lastAvatar) { return url }
        return lastLogin.flatMap { URL(string: "https://github.com/\($0).png") }
    }
    var unreadCount: Int { notifications.filter(\.unread).count }

    // MARK: Conectar e entrar

    /// Primeira vez: usa o GitHub CLI já conectado.
    func connectWithGitHubCLI(enableTouchID: Bool) async throws {
        let token = try await GitHubCLI.token()
        try await connect(token: token, source: .githubCLI, enableTouchID: enableTouchID)
    }

    /// Primeira vez: chave de acesso colada.
    func connectWithToken(_ token: String, enableTouchID: Bool) async throws {
        let cleaned = token.trimmingCharacters(in: .whitespacesAndNewlines)
        try await connect(token: cleaned, source: .keychain, enableTouchID: enableTouchID)
    }

    private func connect(token: String, source: TokenSource, enableTouchID: Bool) async throws {
        let client = GitHubClient(token: token)
        let user = try await client.currentUser()
        if source == .keychain { try TokenStore.save(token) } else { TokenStore.delete() }
        tokenSource = source
        UserDefaults.standard.set(source.rawValue, forKey: Keys.tokenSource)
        requireTouchID = enableTouchID
        start(client: client, user: user)
    }

    /// Depois da digital (ou da senha do Mac): carrega a chave e abre o app.
    func unlockAfterVerification() async throws {
        let token: String
        switch tokenSource {
        case .githubCLI: token = try await GitHubCLI.token()
        case .keychain: token = try TokenStore.load()
        case nil: phase = .welcome; return
        }
        let client = GitHubClient(token: token)
        let cached: AppCache?
        if let preloaded { cached = preloaded } else { cached = await CacheStore.load() }
        if let cached, cached.login == lastLogin, cached.credentialID == Self.credentialID(token) {
            apply(cached)
            start(client: client, user: cached.user)
            return
        }
        let user = try await client.currentUser()
        if let cached, cached.login == user.login { apply(cached) }
        start(client: client, user: user)
    }

    private static func credentialID(_ token: String) -> String {
        SHA256.hash(data: Data(token.utf8)).description
    }

    private func isCurrent(_ client: GitHubClient) -> Bool {
        self.client?.responses === client.responses
    }

    private func start(client: GitHubClient, user: GHUser) {
        self.client = client
        self.user = user
        UserDefaults.standard.set(user.login, forKey: Keys.lastLogin)
        UserDefaults.standard.set(user.avatarUrl, forKey: Keys.lastAvatar)
        withAnimation(.smooth(duration: 0.3)) { phase = .unlocked }
        if systemNotifications { SystemNotifier.shared.activate(model: self) }
        Task { await refreshAll() }
        Task { await scanLocal() }
        startPolling()
        startWatching()
    }

    // MARK: Cache

    /// Cópia atual do cache, usada ao desbloquear durante a mesma execução.
    private var preloaded: AppCache?

    private func apply(_ cache: AppCache) {
        user = cache.user
        repos = cache.repos
        events = cache.events
        notifications = cache.notifications
        calendar = cache.calendar
        lastRefresh = cache.savedAt
        let cachedFolders = cache.localFolders ?? cache.localFolder.map { [$0] } ?? []
        if cachedFolders.map(\.standardizedFileURL) == localFolders.map(\.standardizedFileURL) {
            localRepos = cache.localRepos
            foldersWithoutGit = cache.foldersWithoutGit
        }
        // O Panorama abre com os últimos gráficos; a consulta ao GitHub atualiza em segundo plano.
        if let weeks = cache.codeWeeks { codeWeeks = weeks }
        if let bytes = cache.languageBytes {
            languageBytes = bytes
            languageRepositoryCount = cache.languageRepositoryCount ?? 0
        }
    }

    private func snapshot() -> AppCache? {
        guard let user, let client else { return nil }
        return AppCache(login: user.login, credentialID: Self.credentialID(client.token), savedAt: lastRefresh ?? Date(), user: user, repos: repos, events: events,
                        notifications: notifications, calendar: calendar, localFolders: localFolders,
                        localRepos: localRepos, foldersWithoutGit: foldersWithoutGit,
                        codeWeeks: codeWeeks.isEmpty ? nil : codeWeeks,
                        languageBytes: languageBytes.isEmpty ? nil : languageBytes,
                        languageRepositoryCount: languageRepositoryCount)
    }

    private func saveCache() {
        guard phase == .unlocked, let cache = snapshot() else { return }
        preloaded = cache
        CacheStore.save(cache)
    }

    /// Fecha o app até a próxima digital.
    func lock() {
        clearSession(keepCache: true)
    }

    private func clearSession(keepCache: Bool) {
        ownerConfirmed = false
        seenNotificationKeys = nil
        if keepCache, let cache = snapshot() { preloaded = cache; CacheStore.save(cache) }
        stopAutoUpdates()
        client = nil
        user = nil
        repos = []
        events = []
        notifications = []
        calendar = nil
        lastRefresh = nil
        isRefreshing = false
        localRepos = []
        foldersWithoutGit = []
        lastLocalScan = nil
        isScanningLocal = false
        languageBytes = [:]
        languageRepositoryCount = 0
        isLoadingLanguages = false
        codeRepositories = []
        codeWeeks = []
        languagesExpireAt = nil
        codeWeeksExpireAt = nil
        panoramaRepositories = []
        panoramaRequest = nil
        isLoadingPanorama = false
        repoPath = []
        withAnimation(.smooth(duration: 0.3)) { phase = tokenSource == nil ? .welcome : .locked }
    }

    /// Desconecta a conta: apaga a chave guardada e volta para a tela de boas-vindas.
    func signOut() {
        tokenSource = nil
        clearSession(keepCache: false)
        preloaded = nil
        CacheStore.delete()
        ReachStore.delete()
        repoIcons.clear()
        TokenStore.delete()
        let defaults = UserDefaults.standard
        for key in [Keys.tokenSource, Keys.lastLogin, Keys.lastAvatar] {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: Dados do GitHub

    func refreshAll() async {
        guard !isRefreshing, let client, let login = user?.login else { return }
        isRefreshing = true
        defer { if isCurrent(client) { isRefreshing = false } }
        async let u = client.currentUser()
        async let r = client.repositories()
        async let e = client.events(login: login)
        async let n = client.notifications()
        async let c = client.contributionCalendar()
        do {
            let (updatedUser, updatedRepos) = try await (u, r)
            let (updatedEvents, updatedNotifications, updatedCalendar) = await ((try? e), (try? n), (try? c))
            guard isCurrent(client), !Task.isCancelled else { return }
            user = updatedUser
            repos = updatedRepos
            if let updatedEvents { events = updatedEvents }
            if let updatedNotifications { notifications = updatedNotifications; announce(updatedNotifications) }
            if let updatedCalendar { calendar = updatedCalendar }
            lastRefresh = Date()
            saveCache()
        } catch {
            if isCurrent(client) { report(error) }
            return
        }
        await resolveRenamedRepos()
    }

    private func prepareActivityLabels() {
        activityLabelTask?.cancel()
        activityLabelTask = nil
        activityLabels = [:]
        guard let calendar else { return }
        activityLabelTask = Task { [weak self] in
            let labels = await Self.makeActivityLabels(calendar)
            guard !Task.isCancelled else { return }
            self?.activityLabels = labels
        }
    }

    @concurrent private static func makeActivityLabels(_ calendar: ContributionCalendar) async -> [String: String] {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.calendar = Calendar(identifier: .gregorian)
        parser.dateFormat = "yyyy-MM-dd"
        let format = Date.FormatStyle.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "pt_BR"))
        var labels: [String: String] = [:]
        for week in calendar.weeks {
            if Task.isCancelled { return [:] }
            for day in week.contributionDays {
                let date = parser.date(from: day.date)?.formatted(format) ?? day.date
                let count = day.contributionCount
                labels[day.date] = count == 0
                    ? "\(date): nenhuma atividade"
                    : "\(date): \(Phrases.plural(count, "contribuição", "contribuições"))"
            }
        }
        return labels
    }

    /// Linguagens e maré de código aparecem assim que a consulta de cada card termina.
    func loadPanoramaExtras() async {
        guard let client else { return }
        let names = repos.map(\.fullName).sorted()
        let nonForks = repos.filter { !$0.fork }.map(\.fullName).sorted()
        // Lista de repositórios mudou (ou é a primeira consulta): pede de novo, mas continua
        // mostrando os últimos números (do cache) até os novos chegarem.
        if names != panoramaRepositories {
            panoramaRepositories = names
            languagesExpireAt = nil
        }
        if nonForks != codeRepositories {
            codeRepositories = nonForks
            codeWeeksExpireAt = nil
        }
        let now = Date()
        let loadLanguages = (languagesExpireAt ?? .distantPast) <= now
        let loadCode = (codeWeeksExpireAt ?? .distantPast) <= now
        guard loadLanguages || loadCode else { return }
        let request = UUID()
        panoramaRequest = request
        isLoadingLanguages = loadLanguages && !names.isEmpty
        isLoadingPanorama = loadCode && !nonForks.isEmpty
        defer {
            if panoramaRequest == request {
                panoramaRequest = nil
                isLoadingLanguages = false
                isLoadingPanorama = false
            }
        }

        await withTaskGroup(of: PanoramaUpdate.self) { group in
            if loadLanguages {
                group.addTask { await Self.fetchLanguages(names, client: client) }
            }
            if loadCode {
                group.addTask { await Self.fetchCodeWeeks(nonForks, client: client) }
            }
            for await update in group {
                guard !Task.isCancelled, isCurrent(client), panoramaRequest == request else {
                    group.cancelAll()
                    return
                }
                switch update {
                case let .languages(bytes, count):
                    if let bytes {
                        languageBytes = bytes
                        languageRepositoryCount = count
                    }
                    languagesExpireAt = Date().addingTimeInterval(count == names.count ? 3600 : 600)
                    isLoadingLanguages = false
                    if bytes != nil { saveCache() }
                case let .codeWeeks(weeks, complete):
                    if let weeks, weeks != codeWeeks { codeWeeks = weeks }
                    codeWeeksExpireAt = Date().addingTimeInterval(complete ? 3600 : 600)
                    isLoadingPanorama = false
                    if weeks != nil { saveCache() }
                }
            }
        }
    }

    private enum PanoramaUpdate: Sendable {
        case languages([String: Int]?, count: Int)
        case codeWeeks([CodeWeek]?, complete: Bool)
    }

    private enum CodeFrequency: Sendable {
        case rows([[Int]])
        case pending
        case unavailable
    }

    @concurrent private static func fetchLanguages(_ names: [String], client: GitHubClient) async -> PanoramaUpdate {
        let results = await fetchPanorama(names) { try? await client.languages($0) }
        let languages = results.compactMap { $0.value }
        let bytes = languages.reduce(into: [String: Int]()) { $0.merge($1, uniquingKeysWith: +) }
        return .languages(languages.isEmpty && !names.isEmpty ? nil : bytes, count: languages.count)
    }

    @concurrent private static func fetchCodeWeeks(_ names: [String], client: GitHubClient) async -> PanoramaUpdate {
        let get: @Sendable (String) async -> CodeFrequency = { name in
            do {
                if let rows = try await client.codeFrequency(name) { return .rows(rows) }
                return .pending
            } catch {
                return .unavailable
            }
        }
        let initial = await fetchPanorama(names, get: get)
        let pending = initial.compactMap { result -> String? in
            if case .pending = result.value { return result.name }
            return nil
        }
        var responses = initial.map(\.value)
        if !pending.isEmpty {
            do { try await Task.sleep(for: .seconds(4)) }
            catch { return .codeWeeks(nil, complete: false) }
            responses += await fetchPanorama(pending, get: get).map(\.value)
        }

        var totals: [Int: (additions: Int, deletions: Int)] = [:]
        var finished = 0
        for response in responses {
            guard case let .rows(rows) = response else { continue }
            finished += 1
            for row in rows where row.count >= 3 {
                let previous = totals[row[0], default: (0, 0)]
                totals[row[0]] = (previous.additions + row[1], previous.deletions + abs(row[2]))
            }
        }
        let weeks = totals.keys.sorted().suffix(26).compactMap { timestamp in
            totals[timestamp].map {
                CodeWeek(id: Date(timeIntervalSince1970: TimeInterval(timestamp)), additions: $0.additions, deletions: $0.deletions)
            }
        }
        return .codeWeeks(finished == 0 && !names.isEmpty ? nil : weeks, complete: finished == names.count)
    }

    /// Mantém até seis pedidos simultâneos por consulta, inclusive nas novas tentativas.
    @concurrent private static func fetchPanorama<Value: Sendable>(
        _ names: [String], get: @escaping @Sendable (String) async -> Value
    ) async -> [(name: String, value: Value)] {
        await withTaskGroup(of: (String, Value).self) { group in
            var queue = names.makeIterator()
            for _ in 0..<min(6, names.count) {
                guard let name = queue.next(), !Task.isCancelled else { break }
                group.addTask { (name, await get(name)) }
            }
            var values: [(String, Value)] = []
            for await value in group {
                guard !Task.isCancelled else { break }
                values.append(value)
                if let name = queue.next() {
                    group.addTask { (name, await get(name)) }
                }
            }
            return values
        }
    }

    /// Verificação silenciosa: só troca o que o GitHub disser que mudou.
    func pollGitHub() async {
        guard phase == .unlocked, !isRefreshing, let client, let login = user?.login else { return }
        // Cada consulta atualiza sua própria seção mesmo se outra falhar.
        async let n = client.notificationsIfChanged()
        async let e = client.eventsIfChanged(login: login)
        async let r = client.repositoriesIfChanged()
        let (updatedNotifications, updatedEvents, updatedRepos) = await ((try? n), (try? e), (try? r))
        guard isCurrent(client), !Task.isCancelled else { return }
        if let updatedNotifications { notifications = updatedNotifications; announce(updatedNotifications) }
        if let updatedRepos { repos = updatedRepos }
        if let updatedEvents {
            events = updatedEvents
            let updatedCalendar = try? await client.contributionCalendar()
            guard isCurrent(client), !Task.isCancelled else { return }
            if let updatedCalendar { calendar = updatedCalendar }
        }
        if updatedNotifications != nil || updatedEvents != nil || updatedRepos != nil {
            lastRefresh = Date()
            saveCache()
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let client = self?.client else { return }
                let wait = await client.responses.pollInterval()
                try? await Task.sleep(for: .seconds(wait))
                if Task.isCancelled { return }
                await self?.pollGitHub()
            }
        }
    }

    private func stopAutoUpdates() {
        pollTask?.cancel()
        pollTask = nil
        stopWatching()
    }

    private func stopWatching() {
        watcherID = nil
        watchers.forEach { $0.stop() }
        watchers = []
        fileEventTask?.cancel()
        fileEventTask = nil
        pendingFolders = []
        pendingRescan = false
    }

    func refreshRepos() async {
        guard let client else { return }
        do {
            let updated = try await client.repositories()
            if isCurrent(client) { repos = updated; saveCache() }
        } catch { if isCurrent(client) { report(error) } }
    }

    func refreshNotifications() async {
        guard let client else { return }
        do {
            let updated = try await client.notifications()
            if isCurrent(client) { notifications = updated; saveCache() }
        } catch { if isCurrent(client) { report(error) } }
    }

    func markAllRead() async {
        guard let client else { return }
        do {
            try await client.markAllNotificationsRead()
            guard isCurrent(client) else { return }
            notifications = []
            saveCache()
            show("checkmark.circle.fill", "Todas as notificações foram marcadas como lidas")
        } catch { report(error) }
    }

    func markRead(_ n: GHNotification) async {
        guard let client else { return }
        do {
            try await client.markNotificationRead(n.id)
            guard isCurrent(client) else { return }
            notifications.removeAll { $0.id == n.id }
            saveCache()
        } catch { report(error) }
    }

    /// Tarefas e pedidos de mudança do GitHub para a busca rápida (falhas ficam em silêncio).
    func searchIssues(_ text: String) async -> [GHIssueSearchItem] {
        guard let client, let login = user?.login else { return [] }
        return (try? await client.searchIssues(text, login: login)) ?? []
    }

    func createRepository(name: String, description: String, isPrivate: Bool, withReadme: Bool) async -> GHRepo? {
        guard let client else { return nil }
        do {
            let repo = try await client.createRepository(name: name, description: description, isPrivate: isPrivate, withReadme: withReadme)
            guard isCurrent(client) else { return nil }
            repos.insert(repo, at: 0)
            saveCache()
            show("checkmark.circle.fill", "Repositório “\(repo.name)” criado")
            return repo
        } catch {
            report(error)
            return nil
        }
    }

    func replace(_ repo: GHRepo) {
        if let i = repos.firstIndex(where: { $0.id == repo.id }) { repos[i] = repo }
        if let i = repoPath.firstIndex(where: { $0.id == repo.id }) { repoPath[i] = repo }
    }

    func removeRepo(_ repo: GHRepo) {
        repos.removeAll { $0.id == repo.id }
        repoPath.removeAll { $0.id == repo.id }
    }

    func open(_ repo: GHRepo) {
        section = .repos
        repoPath = [repo]
    }

    func open(fullName: String) {
        let fullName = renamedRepos[fullName.lowercased()] ?? fullName
        if let repo = repos.first(where: { $0.fullName.caseInsensitiveCompare(fullName) == .orderedSame }) {
            open(repo)
        } else if let url = URL(string: "https://github.com/\(fullName)") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Projetos no Mac

    private var localScan: UUID?

    func scanLocal() async {
        guard let client else { return }
        let scan = UUID()
        localScan = scan
        isScanningLocal = true
        defer { if localScan == scan { isScanningLocal = false } }
        let roots = localFolders
        let (urls, otherFolders) = await Task.detached { () -> ([URL], [URL]) in
            var repos: [URL] = [], others: [URL] = []
            var seen: Set<String> = []
            for root in roots {
                for url in LocalGit.findRepositories(in: root) where seen.insert(url.standardizedFileURL.path).inserted {
                    repos.append(url)
                }
                for url in LocalGit.foldersWithoutGit(in: root) where seen.insert(url.standardizedFileURL.path).inserted {
                    others.append(url)
                }
            }
            return (repos, others)
        }.value
        var results: [LocalRepoStatus] = []
        await withTaskGroup(of: LocalRepoStatus?.self) { group in
            for url in urls { group.addTask { try? await LocalGit.status(at: url) } }
            for await status in group { if let status { results.append(status) } }
        }
        guard isCurrent(client), localScan == scan, roots == localFolders, !Task.isCancelled else { return }
        lastLocalScan = Date()
        foldersWithoutGit = otherFolders
        localRepos = results.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        saveCache()
        await resolveRenamedRepos()
    }

    /// Passa a observar as pastas de projetos (de novo, se a lista mudou).
    private func startWatching() {
        stopWatching()
        let id = UUID()
        watcherID = id
        watchers = localFolders.compactMap { root in
            FolderWatcher(folder: root) { [weak self] paths in
                Task { @MainActor in await self?.handleFileEvents(paths, root: root, watcher: id) }
            }
        }
    }

    private func handleFileEvents(_ paths: [String], root: URL, watcher id: UUID) async {
        guard watcherID == id else { return }
        let known = localRepos.map(\.folder)
        let changes = await Self.classifyFileEvents(paths, root: root, repos: known)
        guard watcherID == id else { return }
        pendingFolders.formUnion(changes.folders)
        pendingRescan = pendingRescan || changes.rescan
        guard pendingRescan || !pendingFolders.isEmpty, fileEventTask == nil else { return }
        fileEventTask = Task { [weak self] in
            // Espera as mudanças assentarem (salvar, commit e envio costumam vir em sequência).
            try? await Task.sleep(for: .seconds(1))
            await self?.applyFileEvents(watcher: id)
        }
    }

    @concurrent private static func classifyFileEvents(_ paths: [String], root: URL, repos: [URL]) async
        -> (folders: Set<URL>, rescan: Bool) {
        let index = FolderWatcher.ProjectIndex(root: root, repos: repos)
        var folders: Set<URL> = []
        for path in paths {
            switch index.classify(path: path) {
            case .ignore: continue
            case .repo(let folder): folders.insert(folder)
            case .rescan: return ([], true)
            }
        }
        return (folders, false)
    }

    private func applyFileEvents(watcher id: UUID) async {
        defer { if watcherID == id { fileEventTask = nil } }
        while watcherID == id, !Task.isCancelled, pendingRescan || !pendingFolders.isEmpty {
            if isScanningLocal {
                try? await Task.sleep(for: .seconds(1))
                continue
            }
            if pendingRescan {
                pendingRescan = false
                pendingFolders = []
                await scanLocal()
            } else {
                let folders = pendingFolders.subtracting(busyFolders)
                pendingFolders.subtract(folders)
                for folder in folders {
                    guard watcherID == id, !Task.isCancelled else { return }
                    await refreshLocal(folder)
                }
                if !pendingFolders.isEmpty { try? await Task.sleep(for: .seconds(1)) }
            }
        }
        if watcherID == id, !Task.isCancelled { saveCache() }
    }

    /// Avisa no macOS só os avisos do GitHub que ainda não tinham aparecido.
    private func announce(_ list: [GHNotification]) {
        let unread = list.filter(\.unread)
        let keys = Set(unread.map { "\($0.id)-\($0.updatedAt.timeIntervalSince1970)" })
        defer { seenNotificationKeys = (seenNotificationKeys ?? []).union(keys) }
        // Na primeira carga só registra o que já existia: nada de enxurrada ao abrir o app.
        guard systemNotifications, let seen = seenNotificationKeys else { return }
        let fresh = unread.filter { !seen.contains("\($0.id)-\($0.updatedAt.timeIntervalSince1970)") }
        if fresh.count > 3 {
            SystemNotifier.shared.post(id: "gh-lote-\(Date().timeIntervalSince1970)", title: "GitHub",
                                       body: "\(Phrases.plural(fresh.count, "aviso novo", "avisos novos")) em \(Set(fresh.map(\.repository.fullName)).count) repositórios.",
                                       section: .notifications)
            return
        }
        for n in fresh {
            SystemNotifier.shared.post(id: "gh-\(n.id)-\(n.updatedAt.timeIntervalSince1970)",
                                       title: "\(SystemNotifier.kind(n.subject.type)) · \(n.repository.fullName)",
                                       body: n.subject.title, section: .notifications)
        }
    }

    func refreshLocal(_ folder: URL) async {
        guard let client else { return }
        let roots = localFolders
        guard let status = try? await LocalGit.status(at: folder),
              isCurrent(client), roots == localFolders, !Task.isCancelled else { return }
        if let i = localRepos.firstIndex(where: { $0.folder == folder }) {
            let before = localRepos[i]
            if systemNotifications, status.autoPushNeedsAttention, !before.autoPushNeedsAttention {
                SystemNotifier.shared.post(id: "autopush-\(folder.path)-\(Date().timeIntervalSince1970)",
                                           title: "Envio automático falhou · \(status.name)",
                                           body: "\(Phrases.plural(status.ahead, "versão salva espera", "versões salvas esperam")) para ir ao GitHub. Abra o Git Arbor e clique em Enviar.",
                                           section: .local, folder: folder)
            }
            localRepos[i] = status
        } else {
            localRepos.append(status)
            localRepos.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    /// Busca no GitHub as novidades de todos os projetos (sem mudar nada nas pastas).
    func fetchAllLocal() async {
        guard !isScanningLocal, let client else { return }
        let targets = localRepos.filter(\.hasRemote).map(\.folder)
        guard !targets.isEmpty else {
            show("info.circle", "Nenhum projeto com remoto para conferir")
            return
        }
        isScanningLocal = true
        let roots = localFolders
        let failures = await withTaskGroup(of: String?.self, returning: [String].self) { group in
            for folder in targets {
                group.addTask {
                    do {
                        try await LocalGit.fetch(at: folder)
                        return nil
                    } catch {
                        return folder.lastPathComponent
                    }
                }
            }
            var failures: [String] = []
            for await name in group { if let name { failures.append(name) } }
            return failures.sorted()
        }
        guard isCurrent(client), roots == localFolders else { return }
        await scanLocal()
        guard isCurrent(client), roots == localFolders else { return }
        if failures.isEmpty {
            show("arrow.triangle.2.circlepath", "Situação conferida com o GitHub")
        } else {
            errorMessage = "Não consegui conferir estes projetos: \(failures.joined(separator: ", ")). A situação deles pode estar desatualizada."
        }
    }

    /// O projeto está ligado a um repositório da conta conectada (e não de outra pessoa).
    func isMine(_ repo: LocalRepoStatus) -> Bool {
        guard let owner = gitHubName(of: repo)?.split(separator: "/").first, let login = user?.login else { return false }
        return owner.caseInsensitiveCompare(login) == .orderedSame
    }

    /// Aplica a lista padrão e retira do rastreamento os arquivos sensíveis.
    func protect(folder: URL) async {
        guard busyFolders.insert(folder).inserted else { return }
        defer { busyFolders.remove(folder) }
        guard let client else { return }
        let removed: [String]
        do {
            removed = try await LocalGit.protect(at: folder)
        } catch {
            await refreshLocal(folder)
            if isCurrent(client) { report(error) }
            return
        }
        await refreshLocal(folder)
        guard isCurrent(client) else { return }
        show("lock.shield.fill", "Lista de arquivos sensíveis aplicada")
        if !removed.isEmpty {
            errorMessage = "Os arquivos continuam na pasta e saíram do rastreamento: \(removed.joined(separator: ", ")). Os commits antigos ainda podem conter esses arquivos. Se uma credencial já saiu deste Mac, troque-a."
        }
    }

    /// Protege os projetos próprios que ainda têm arquivos expostos ou precisam da lista padrão.
    func protectAll() async {
        let targets = localRepos.filter { (!$0.protected || !$0.exposedFiles.isEmpty) && (!$0.hasRemote || isMine($0)) }.map(\.folder)
        await runBatch(targets, label: "Proteção de arquivos", action: { _ = try await LocalGit.protect(at: $0) })
    }

    /// Liga ou desliga o envio automático de um projeto.
    func setAutoPush(_ on: Bool, folder: URL) async {
        _ = await runLocal(folder, success: on ? "Envio automático ligado" : "Envio automático desligado") {
            try await LocalGit.setAutoPush(on, at: folder)
        }
    }

    /// Liga o envio automático em todos os projetos ligados ao GitHub que ainda não têm.
    func enableAutoPushEverywhere() async {
        let targets = localRepos.filter { isMine($0) && !$0.autoPush.enabled }.map(\.folder)
        await runBatch(targets, label: "Envio automático", action: { try await LocalGit.setAutoPush(true, at: $0) })
    }

    private func runBatch(_ targets: [URL], label: String, action: (URL) async throws -> Void) async {
        var completed = 0
        var failures: [String] = []
        for folder in targets {
            guard phase == .unlocked else { return }
            guard busyFolders.insert(folder).inserted else {
                failures.append("\(folder.lastPathComponent): outra ação em andamento")
                continue
            }
            do {
                try await action(folder)
                completed += 1
            } catch {
                failures.append("\(folder.lastPathComponent): \(error.localizedDescription)")
            }
            await refreshLocal(folder)
            busyFolders.remove(folder)
        }
        guard phase == .unlocked else { return }
        if failures.isEmpty {
            show("checkmark.circle.fill", "\(label) · \(Phrases.plural(completed, "projeto atualizado", "projetos atualizados"))")
        } else {
            errorMessage = "\(label) · \(completed) de \(targets.count) projetos atualizados.\n\n" + failures.joined(separator: "\n\n")
        }
    }

    /// Roda uma ação do Git numa pasta mostrando que está ocupada.
    func runLocal(_ folder: URL, success: String, _ action: @escaping @Sendable () async throws -> Void) async -> Bool {
        guard let client, busyFolders.insert(folder).inserted else { return false }
        defer { busyFolders.remove(folder) }
        do {
            try await action()
            guard isCurrent(client) else { return false }
            await refreshLocal(folder)
            show("checkmark.circle.fill", success)
            return true
        } catch {
            guard isCurrent(client) else { return false }
            await refreshLocal(folder)
            report(error)
            return false
        }
    }

    /// Como `runLocal`, para ações que podem parar em conflito (juntar, baixar e juntar, desfazer, trazer de volta).
    /// Conflito não é erro: devolve `.conflicts` e avisa que há algo a resolver.
    func runLocalOutcome(_ folder: URL, success: String,
                         _ action: @escaping @Sendable () async throws -> MergeOutcome) async -> MergeOutcome? {
        guard let client, busyFolders.insert(folder).inserted else { return nil }
        defer { busyFolders.remove(folder) }
        do {
            let outcome = try await action()
            guard isCurrent(client) else { return nil }
            await refreshLocal(folder)
            if outcome == .done {
                show("checkmark.circle.fill", success)
            } else {
                show("exclamationmark.triangle.fill", "Há conflitos para resolver em “\(folder.lastPathComponent)”")
            }
            return outcome
        } catch {
            guard isCurrent(client) else { return nil }
            await refreshLocal(folder)
            report(error)
            return nil
        }
    }

    func localStatus(_ folder: URL) -> LocalRepoStatus? {
        localRepos.first { $0.folder == folder }
    }

    // MARK: Avisos

    func report(_ error: Error) {
        // Trocar de aba ou de tela cancela pedidos em andamento: não é erro.
        if error is CancellationError { return }
        if let url = error as? URLError, url.code == .cancelled { return }
        if let gh = error as? GitHubError, gh == .unauthorized {
            errorMessage = gh.localizedDescription
            return
        }
        errorMessage = error.localizedDescription
    }

    func show(_ symbol: String, _ text: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { toast = Toast(symbol: symbol, text: text) }
        let current = toast
        Task {
            try? await Task.sleep(for: .seconds(2.6))
            if toast == current { withAnimation(.easeOut(duration: 0.25)) { toast = nil } }
        }
    }

    func copy(_ text: String, label: String = "Copiado") {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        show("doc.on.doc.fill", label)
    }
}
