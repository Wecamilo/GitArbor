import Foundation

/// Uma mudança num arquivo que ainda não foi salva no histórico (commit).
public struct FileChange: Sendable, Hashable, Identifiable, Codable {
    public enum Kind: String, Sendable, Hashable, Codable {
        case added, modified, deleted, renamed, untracked, conflict

        public var label: String {
            switch self {
            case .added: "Novo"
            case .modified: "Alterado"
            case .deleted: "Apagado"
            case .renamed: "Renomeado"
            case .untracked: "Novo"
            case .conflict: "Conflito"
            }
        }
    }
    public let path: String
    public let kind: Kind
    public var originalPath: String? = nil
    public var id: String { path }

    public init(path: String, kind: Kind, originalPath: String? = nil) {
        self.path = path
        self.kind = kind
        self.originalPath = originalPath
    }
}

/// Situação de um projeto (repositório Git) no Mac.
public struct LocalRepoStatus: Sendable, Hashable, Identifiable, Codable {
    public let folder: URL
    public var branch: String?
    public var upstream: String?
    public var ahead: Int
    public var behind: Int
    public var changes: [FileChange]
    public var remoteURL: String?
    public var lastCommitMessage: String?
    public var lastCommitDate: Date?
    /// Envio automático depois de cada commit (hook post-commit).
    public var autoPush = AutoPush()
    /// O .gitignore tem a lista padrão de arquivos sensíveis do Git Arbor.
    public var protected = false
    /// Arquivos com cara de senha ou chave que já estão no histórico ou iriam no próximo commit.
    public var exposedFiles: [String] = []
    /// Junção, rebase ou revert parado no meio (quase sempre por conflito).
    public var operation: GitOperation? = nil
    /// Quantas mudanças estão guardadas para depois (stash).
    public var stashCount = 0

    public var id: URL { folder }
    /// Arquivos em conflito agora.
    public var conflicts: [FileChange] { changes.filter { $0.kind == .conflict } }
    public var name: String { folder.lastPathComponent }
    /// O último envio automático falhou (ou não confirmou) e ainda há versões esperando para ir ao GitHub.
    /// Se o ramo já está igual ao do GitHub, a falha antiga foi resolvida (ex.: um envio manual depois).
    public var autoPushNeedsAttention: Bool {
        guard autoPush.enabled, upstream != nil, ahead > 0 else { return false }
        return autoPush.last == .failed || autoPush.last == .sending
    }
    public var hasRemote: Bool { remoteURL != nil }
    /// "dono/nome" no GitHub, quando o projeto está ligado a um repositório de lá.
    public var gitHubFullName: String? { remoteURL.flatMap(LocalGit.gitHubFullName(fromRemote:)) }

    public enum State: Sendable, Hashable {
        case conflict, unsaved, toSend, toReceive, diverged, noRemote, noUpstream, clean
    }

    /// O que mais importa agora, na ordem em que o usuário deve agir.
    public var state: State {
        if changes.contains(where: { $0.kind == .conflict }) || operation != nil { return .conflict }
        if !changes.isEmpty { return .unsaved }
        if !hasRemote { return .noRemote }
        if upstream == nil { return branch == nil ? .clean : .noUpstream }
        if ahead > 0 && behind > 0 { return .diverged }
        if ahead > 0 { return .toSend }
        if behind > 0 { return .toReceive }
        return .clean
    }

    public init(folder: URL, branch: String? = nil, upstream: String? = nil, ahead: Int = 0, behind: Int = 0,
                changes: [FileChange] = [], remoteURL: String? = nil) {
        self.folder = folder
        self.branch = branch
        self.upstream = upstream
        self.ahead = ahead
        self.behind = behind
        self.changes = changes
        self.remoteURL = remoteURL
    }
}

/// Envio automático: o hook `post-commit` que faz `git push` sozinho depois de cada commit,
/// e o resultado do último envio (registrado em `.git/auto-push.log`).
public struct AutoPush: Sendable, Hashable, Codable {
    public enum Last: String, Sendable, Hashable, Codable {
        case ok, failed, sending
    }
    public var enabled = false
    /// O hook existe, mas é de outra pessoa/ferramenta (não foi feito pelo Git Arbor).
    public var foreignHook = false
    public var last: Last?
    public var lastDate: Date?
    public var lastCommit: String?

    public init(enabled: Bool = false, foreignHook: Bool = false, last: Last? = nil, lastDate: Date? = nil, lastCommit: String? = nil) {
        self.enabled = enabled
        self.foreignHook = foreignHook
        self.last = last
        self.lastDate = lastDate
        self.lastCommit = lastCommit
    }
}

public struct GitFailure: LocalizedError, Sendable {
    public let command: String
    public let output: String

    public var errorDescription: String? {
        let lower = output.lowercased()
        if lower.contains("could not read username") || lower.contains("authentication failed") {
            return "O Git não conseguiu entrar no GitHub. Rode “gh auth login” no Terminal uma vez e tente de novo."
        }
        if lower.contains("non-fast-forward") || lower.contains("fetch first") || lower.contains("rejected") {
            return "O GitHub tem novidades que este Mac ainda não tem. Use “Baixar” primeiro e depois envie de novo."
        }
        if lower.contains("not possible to fast-forward") || lower.contains("diverging") {
            return "O Mac e o GitHub mudaram ao mesmo tempo. Resolva no Terminal ou peça ajuda — nada foi perdido."
        }
        if lower.contains("nothing to commit") { return "Não há mudanças para salvar." }
        if lower.contains("would be overwritten") || lower.contains("please commit your changes or stash them") {
            return "Há mudanças não salvas que seriam perdidas. Salve uma versão ou use “Guardar para depois” e tente de novo."
        }
        if lower.contains("not fully merged") {
            return "Este ramo tem versões que ainda não foram juntadas em nenhum outro. Junte antes de apagar, para não perder nada."
        }
        if lower.contains("is not a valid branch name") || lower.contains("not a valid branch name") {
            return "Esse nome não serve para ramo. Use letras, números e hífen, sem espaços."
        }
        if lower.contains("a branch named") && lower.contains("already exists") {
            return "Já existe um ramo com esse nome."
        }
        if lower.contains("please tell me who you are") {
            return "O Git ainda não sabe o seu nome. Abra o Terminal e rode: git config --global user.name \"Seu Nome\" e git config --global user.email voce@exemplo.com"
        }
        if lower.contains("already exists and is not an empty directory") {
            return "Já existe uma pasta com esse nome no lugar escolhido."
        }
        return "O Git informou um problema:\n\n" + output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum LocalGit {
    /// Caminho do executável do Git.
    public static let gitPath = "/usr/bin/git"

    /// Ambiente com o Homebrew no PATH (o `gh` cuida do login no GitHub).
    static var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        let extra = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        env["PATH"] = extra + ":" + (env["PATH"] ?? "")
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["LANG"] = "en_US.UTF-8"
        return env
    }

    /// Roda o Git numa pasta e devolve a saída. Lança `GitFailure` quando o Git falha.
    @discardableResult
    public static func run(_ args: [String], in folder: URL?) async throws -> String {
        try await runProcess(gitPath, args, in: folder)
    }

    /// Roda um programa e devolve toda a saída, sem bloquear nenhuma linha de execução.
    /// Só responde quando as duas coisas aconteceram: o programa terminou **e** a leitura chegou
    /// ao fim da saída (EOF). Antes, quando o programa terminava muito rápido, o último pedaço
    /// da resposta podia chegar depois e se perder (ramo vazio, remoto “sumido” etc.).
    public static func runProcess(_ executable: String, _ args: [String], in folder: URL?) async throws -> String {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = args
            if let folder { process.currentDirectoryURL = folder }
            process.environment = environment
            let out = Pipe()
            process.standardOutput = out
            process.standardError = out
            process.standardInput = FileHandle.nullDevice

            let buffer = OutputBuffer()
            let done = DispatchGroup()
            done.enter() // leitura até o fim
            done.enter() // fim do programa
            out.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                    done.leave()
                } else {
                    buffer.append(chunk)
                }
            }
            process.terminationHandler = { _ in done.leave() }
            do {
                try process.run()
            } catch {
                out.fileHandleForReading.readabilityHandler = nil
                cont.resume(throwing: error)
                return
            }
            done.notify(queue: .global(qos: .userInitiated)) {
                let text = buffer.text
                if process.terminationStatus == 0 {
                    cont.resume(returning: text)
                } else {
                    cont.resume(throwing: GitFailure(command: ([executable] + args).joined(separator: " "), output: text))
                }
            }
        }
    }

    /// Pastas (até dois níveis) que são repositórios Git.
    public static func findRepositories(in folder: URL) -> [URL] {
        let fm = FileManager.default
        var found: [URL] = []
        func isRepo(_ url: URL) -> Bool { fm.fileExists(atPath: url.appendingPathComponent(".git").path) }
        if isRepo(folder) { return [folder] }
        let children = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        for child in children where (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            if isRepo(child) {
                found.append(child)
            } else {
                let grand = (try? fm.contentsOfDirectory(at: child, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
                found += grand.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true && isRepo($0) }
            }
        }
        return found.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// Pastas de primeiro nível que ainda não usam Git.
    public static func foldersWithoutGit(in folder: URL) -> [URL] {
        let fm = FileManager.default
        let children = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey], options: [.skipsHiddenFiles])) ?? []
        let repos = Set(findRepositories(in: folder).map(\.standardizedFileURL))
        return children.filter { url in
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey]),
                  values.isDirectory == true, values.isPackage != true else { return false }
            if repos.contains(url.standardizedFileURL) { return false }
            return !repos.contains { $0.path.hasPrefix(url.standardizedFileURL.path + "/") }
        }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// Endereço do GitHub (remoto “origin”). Só devolve nil quando o Git confirma que não há remoto:
    /// numa pasta do iCloud a leitura às vezes falha por um instante, e isso não pode virar “Só no Mac”.
    public static func remoteURL(at folder: URL) async -> String? {
        for attempt in 0..<3 {
            do {
                return try await run(["remote", "get-url", "origin"], in: folder)
                    .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            } catch let failure as GitFailure where failure.output.contains("No such remote") {
                return nil
            } catch {
                if attempt < 2 { try? await Task.sleep(for: .milliseconds(400)) }
            }
        }
        // Último recurso: lê o arquivo de configuração do Git direto.
        let config = folder.appendingPathComponent(".git/config")
        guard let text = try? String(contentsOf: config, encoding: .utf8) else { return nil }
        return parseOriginURL(fromConfig: text)
    }

    /// Endereço do remoto “origin” no texto do .git/config.
    public static func parseOriginURL(fromConfig text: String) -> String? {
        var inOrigin = false
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") { inOrigin = line == "[remote \"origin\"]"; continue }
            if inOrigin, line.hasPrefix("url") , let eq = line.firstIndex(of: "=") {
                return line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces).nilIfEmpty
            }
        }
        return nil
    }

    public static func status(at folder: URL) async throws -> LocalRepoStatus {
        // A resposta sempre traz “# branch.oid”; se vier sem, a leitura falhou: tenta de novo.
        var text = ""
        for attempt in 0..<3 {
            text = try await run(["--no-optional-locks", "status", "--porcelain=v2", "--branch", "-z", "--untracked-files=all"], in: folder)
            if text.contains("# branch.oid") { break }
            if attempt == 2 { throw GitFailure(command: "git status", output: "Resposta incompleta do Git.") }
            try? await Task.sleep(for: .milliseconds(300))
        }
        var status = parseStatus(text, folder: folder)
        status.remoteURL = await remoteURL(at: folder)
        status.autoPush = await autoPush(at: folder)
        status.protected = isProtected(at: folder)
        status.exposedFiles = await exposedSensitiveFiles(at: folder)
        status.operation = await operation(at: folder)
        status.stashCount = await stashes(at: folder).count
        if let log = try? await run(["log", "-1", "--format=%s%x1f%cI"], in: folder) {
            let parts = log.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\u{1f}")
            status.lastCommitMessage = parts.first?.nilIfEmpty
            if parts.count > 1 { status.lastCommitDate = ISO8601DateFormatter().date(from: parts[1]) }
        }
        return status
    }

    /// Lê a saída de `git status --porcelain=v2 --branch -z`.
    public static func parseStatus(_ text: String, folder: URL) -> LocalRepoStatus {
        var status = LocalRepoStatus(folder: folder)
        let records = text.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)
        var i = 0
        while i < records.count {
            let line = records[i]
            if line.hasPrefix("# branch.head ") {
                let head = String(line.dropFirst("# branch.head ".count))
                status.branch = head == "(detached)" ? nil : head
            } else if line.hasPrefix("# branch.upstream ") {
                status.upstream = String(line.dropFirst("# branch.upstream ".count))
            } else if line.hasPrefix("# branch.ab ") {
                let parts = line.dropFirst("# branch.ab ".count).split(separator: " ")
                if parts.count == 2 {
                    status.ahead = Int(parts[0].dropFirst()) ?? 0
                    status.behind = Int(parts[1].dropFirst()) ?? 0
                }
            } else if line.hasPrefix("1 ") {
                let fields = line.split(separator: " ", maxSplits: 8, omittingEmptySubsequences: false)
                if fields.count == 9 {
                    status.changes.append(FileChange(path: String(fields[8]), kind: kind(xy: String(fields[1]))))
                }
            } else if line.hasPrefix("2 ") {
                let fields = line.split(separator: " ", maxSplits: 9, omittingEmptySubsequences: false)
                if fields.count == 10, i + 1 < records.count {
                    let copied = fields[8].hasPrefix("C")
                    status.changes.append(FileChange(path: String(fields[9]), kind: copied ? .added : .renamed,
                                                     originalPath: copied ? nil : records[i + 1]))
                }
                i += 1 // o caminho antigo vem no registro seguinte
            } else if line.hasPrefix("u ") {
                let fields = line.split(separator: " ", maxSplits: 10, omittingEmptySubsequences: false)
                if let path = fields.last { status.changes.append(FileChange(path: String(path), kind: .conflict)) }
            } else if line.hasPrefix("? ") {
                status.changes.append(FileChange(path: String(line.dropFirst(2)), kind: .untracked))
            }
            i += 1
        }
        return status
    }

    static func kind(xy: String) -> FileChange.Kind {
        let chars = Array(xy)
        let flags = Set(chars)
        if flags.contains("D") { return .deleted }
        if flags.contains("A") { return .added }
        if flags.contains("R") { return .renamed }
        return .modified
    }

    /// "dono/nome" a partir do endereço do remoto (https ou ssh).
    public static func gitHubFullName(fromRemote remote: String) -> String? {
        var s = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.contains("github.com") else { return nil }
        if let range = s.range(of: "github.com/") ?? s.range(of: "github.com:") {
            s = String(s[range.upperBound...])
        } else {
            return nil
        }
        if s.hasSuffix(".git") { s.removeLast(4) }
        if s.hasSuffix("/") { s.removeLast() }
        let parts = s.split(separator: "/")
        guard parts.count == 2 else { return nil }
        return "\(parts[0])/\(parts[1])"
    }

    // MARK: Envio automático

    /// Marca que identifica o hook feito por nós.
    static let hookMarker = "Push automático"

    /// Hook `post-commit`: depois de cada commit, envia o ramo atual ao GitHub em segundo plano.
    /// Registra cada envio em `<pasta do git>/auto-push.log`.
    public static let autoPushHook = #"""
    #!/bin/sh
    # Push automático: depois de cada commit, envia o branch atual para o GitHub.
    # Roda em segundo plano (desligado do terminal) para o commit não esperar a rede.
    # Registro de cada envio: <pasta do git>/auto-push.log
    # Se um envio falhar (sem internet), o próximo commit envia tudo que ficou pendente.
    # Instalado pelo Git Arbor.

    # Só envia se estiver num branch (durante rebase/merge o HEAD fica solto)
    branch=$(git symbolic-ref --short -q HEAD) || exit 0

    # Só envia se o branch estiver ligado a um branch no GitHub
    git rev-parse --abbrev-ref "$branch@{upstream}" >/dev/null 2>&1 || exit 0

    log="$(git rev-parse --absolute-git-dir)/auto-push.log"
    commit=$(git rev-parse --short HEAD)

    # Registra já, antes do envio, para dar para ver que o hook rodou
    echo "$(date '+%Y-%m-%d %H:%M:%S') enviando $branch $commit" >>"$log"

    # nohup: o envio continua mesmo se o terminal ou programa que fez o commit fechar
    nohup sh -c '
      if git push --quiet >>"$1" 2>&1; then
        echo "$(date "+%Y-%m-%d %H:%M:%S") ok       $2 $3" >>"$1"
      else
        echo "$(date "+%Y-%m-%d %H:%M:%S") FALHOU   $2 $3 (sem internet? o próximo commit tenta de novo; ou rode: git push)" >>"$1"
      fi
    ' sh "$log" "$branch" "$commit" </dev/null >/dev/null 2>&1 &

    exit 0

    """#

    /// Onde o Git realmente procura o roteiro post-commit.
    static func hookURL(at folder: URL) async -> URL? {
        for attempt in 0..<2 {
            if let path = try? await run(["rev-parse", "--git-path", "hooks/post-commit"], in: folder) {
                let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed.hasPrefix("/") ? URL(fileURLWithPath: trimmed) : folder.appendingPathComponent(trimmed)
                }
            }
            if attempt == 0 { try? await Task.sleep(for: .milliseconds(300)) }
        }
        return nil
    }

    /// Lê um arquivo de texto tentando de novo uma vez (arquivos do iCloud às vezes falham na primeira leitura).
    static func readText(_ url: URL) async -> String? {
        if let text = try? String(contentsOf: url, encoding: .utf8) { return text }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        try? await Task.sleep(for: .milliseconds(300))
        return try? String(contentsOf: url, encoding: .utf8)
    }

    static func logURL(at folder: URL) async -> URL? {
        guard let dir = try? await run(["rev-parse", "--absolute-git-dir"], in: folder) else { return nil }
        return URL(fileURLWithPath: dir.trimmingCharacters(in: .whitespacesAndNewlines)).appendingPathComponent("auto-push.log")
    }

    /// Situação do envio automático de um projeto.
    public static func autoPush(at folder: URL) async -> AutoPush {
        var info = AutoPush()
        if let hook = await hookURL(at: folder), FileManager.default.isExecutableFile(atPath: hook.path) {
            let text = await readText(hook) ?? ""
            info.enabled = text.contains(hookMarker) && text.contains("git push")
            info.foreignHook = !text.contains(hookMarker)
        }
        let log = await logURL(at: folder) ?? folder.appendingPathComponent(".git/auto-push.log")
        if let text = await readText(log) {
            let parsed = parseAutoPushLog(text)
            info.last = parsed.last
            info.lastDate = parsed.date
            info.lastCommit = parsed.commit
        }
        return info
    }

    /// Lê a última linha do registro: "AAAA-MM-DD HH:MM:SS ok|FALHOU|enviando ramo commit".
    public static func parseAutoPushLog(_ text: String) -> (last: AutoPush.Last?, date: Date?, commit: String?) {
        let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let line = lines.last(where: { $0.count > 20 && $0.first?.isNumber == true }) else { return (nil, nil, nil) }
        let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 3 else { return (nil, nil, nil) }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let date = f.date(from: parts[0] + " " + parts[1])
        let last: AutoPush.Last? = switch parts[2] {
        case "ok": .ok
        case "FALHOU": .failed
        case "enviando": .sending
        default: nil
        }
        return (last, date, parts.count >= 5 ? parts[4] : nil)
    }

    /// Mantém o hook anterior ativo e devolve o arquivo original ao desligar.
    public static func setAutoPush(_ enabled: Bool, at folder: URL) async throws {
        guard let hook = await hookURL(at: folder) else {
            throw GitFailure(command: "post-commit", output: "Não consegui localizar o hook deste projeto.")
        }
        let gitDir = try await run(["rev-parse", "--path-format=absolute", "--git-common-dir"], in: folder)
        let common = URL(fileURLWithPath: gitDir.trimmingCharacters(in: .newlines)).resolvingSymlinksInPath().path
        let hooks = hook.deletingLastPathComponent().resolvingSymlinksInPath()
        guard hooks.path.hasPrefix(common + "/") else {
            throw GitFailure(command: "post-commit", output: "Este projeto usa uma pasta de hooks externa ao diretório do Git. Configure o envio automático nessa pasta manualmente.")
        }

        let fm = FileManager.default
        let backup = hooks.appendingPathComponent("post-commit.git-arbor-original")
        let legacy = hook.appendingPathExtension("bak")
        let exists = (try? fm.attributesOfItem(atPath: hook.path)) != nil
        let text = exists ? (try? String(contentsOf: hook, encoding: .utf8)) : nil
        let managed = text?.contains(hookMarker) == true
        let chained = text?.contains(backup.lastPathComponent) == true

        if !enabled {
            guard managed else { return }
            if chained {
                _ = try fm.replaceItemAt(hook, withItemAt: backup, options: .usingNewMetadataOnly)
            } else if fm.fileExists(atPath: legacy.path) {
                _ = try fm.replaceItemAt(hook, withItemAt: legacy, options: .usingNewMetadataOnly)
            } else {
                try fm.removeItem(at: hook)
            }
            return
        }
        if managed && (chained || !fm.fileExists(atPath: legacy.path)) { return }

        try fm.createDirectory(at: hooks, withIntermediateDirectories: true)
        let keepOriginal = exists
        if keepOriginal {
            try fm.copyItem(at: managed ? legacy : hook, to: backup)
        }
        let chain = #"""
        original="$(dirname "$0")/post-commit.git-arbor-original"
        if [ -x "$original" ]; then "$original" "$@"; fi

        """#
        let script = keepOriginal
            ? autoPushHook.replacingOccurrences(of: "branch=$(git symbolic-ref", with: chain + "\nbranch=$(git symbolic-ref")
            : autoPushHook
        // Prepara a permissão antes de trocar o hook que o Git executa.
        let staged = hooks.appendingPathComponent("post-commit.git-arbor-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: staged) }
        do {
            try script.write(to: staged, atomically: false, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: staged.path)
            if exists {
                _ = try fm.replaceItemAt(hook, withItemAt: staged, options: .usingNewMetadataOnly)
            } else {
                try fm.moveItem(at: staged, to: hook)
            }
        } catch {
            if keepOriginal { try? fm.removeItem(at: backup) }
            throw error
        }
    }

    /// Quantos commits o ramo atual tem (para mostrar o que vai ser enviado).
    public static func commitCount(at folder: URL) async -> Int {
        Int(((try? await run(["rev-list", "--count", "HEAD"], in: folder)) ?? "0").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    /// Arquivos com cara de senha ou chave que iriam junto ao publicar.
    public static func sensitiveFiles(at folder: URL) async -> [String] {
        if let paths = try? await exposedPaths(at: folder) { return paths }
        // Pasta ainda sem Git: olha os arquivos direto.
        return sensitiveFilesWithoutGit(in: folder)
    }

    /// Procura arquivos sensíveis numa pasta sem Git (sem entrar em pastas ocultas nem em dependências).
    static func sensitiveFilesWithoutGit(in folder: URL) -> [String] {
        var found: [String] = []
        let skip: Set<String> = ["node_modules", ".build", "build", "DerivedData", "Pods", "vendor"]
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        var seen = 0
        for case let url as URL in walker {
            seen += 1
            if seen > 20_000 { break }
            let name = url.lastPathComponent
            if skip.contains(name) || (name.hasPrefix(".") && name != ".env" && !name.hasPrefix(".env.")) {
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { walker.skipDescendants() }
                if !name.hasPrefix(".env") { continue }
            }
            let relative = String(url.path.dropFirst(folder.path.count + 1))
            if isSensitive(relative) { found.append(relative) }
        }
        return found
    }

    public static func isSensitive(_ path: String) -> Bool {
        let name = (path as NSString).lastPathComponent.lowercased()
        let ext = (name as NSString).pathExtension
        if name == ".env" || name.hasPrefix(".env.") && name != ".env.example" && name != ".env.sample" { return true }
        if ["pem", "p12", "pfx", "key", "keychain", "keychain-db", "keystore", "jks", "mobileprovision", "ovpn"].contains(ext) { return true }
        if ["id_rsa", "id_ed25519", "id_ecdsa", "credentials", "credentials.json", "secrets.json", "service-account.json"].contains(name) { return true }
        return name.contains("secret") && ["json", "yml", "yaml", "txt", "plist"].contains(ext)
    }

    // MARK: Proteção de arquivos sensíveis

    /// Marca do bloco que o Git Arbor coloca no .gitignore.
    public static let protectionMarker = "# Arquivos sensíveis (senhas e chaves) — lista padrão do Git Arbor"

    /// Lista padrão: o que nunca deve ir para o GitHub. Mantida igual a `isSensitive`.
    public static let protectionBlock = """
    \(protectionMarker)
    .env
    .env.*
    !.env.example
    !.env.sample
    *.pem
    *.p12
    *.pfx
    *.key
    *.keychain
    *.keychain-db
    *.keystore
    *.jks
    *.mobileprovision
    *.ovpn
    id_rsa
    id_ed25519
    id_ecdsa
    credentials
    credentials.json
    secrets.json
    service-account.json
    *secret*.json
    *secret*.yml
    *secret*.yaml
    *secret*.txt
    *secret*.plist

    """

    /// Para projetos novos sem .gitignore: o lixo comum que também não deve subir.
    public static let commonJunkBlock = """
    # Arquivos do sistema e de ferramentas (não precisam ir para o GitHub)
    .DS_Store
    node_modules/
    .venv/
    venv/
    __pycache__/
    .build/
    .swiftpm/
    DerivedData/
    *.log

    """

    public static func isProtected(at folder: URL) -> Bool {
        let text = (try? String(contentsOf: folder.appendingPathComponent(".gitignore"), encoding: .utf8)) ?? ""
        return text.contains(protectionMarker)
    }

    /// Acrescenta a lista padrão ao .gitignore (cria o arquivo se não existir). Não mexe no que já está lá.
    /// Devolve true se mudou o arquivo.
    @discardableResult
    public static func writeProtection(at folder: URL, newProject: Bool = false) throws -> Bool {
        let url = folder.appendingPathComponent(".gitignore")
        let current: String
        do {
            current = try String(contentsOf: url, encoding: .utf8)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            current = ""
        }
        let currentRules = Set(current.split(separator: "\n"))
        let requiredRules = Set(protectionBlock.split(separator: "\n"))
        guard !requiredRules.isSubset(of: currentRules) else { return false }
        var text = current
        if !text.isEmpty && !text.hasSuffix("\n") { text += "\n" }
        if !text.isEmpty { text += "\n" }
        if current.isEmpty && newProject { text += commonJunkBlock + "\n" }
        text += protectionBlock
        try text.write(to: url, atomically: true, encoding: .utf8)
        return true
    }

    static func sensitivePaths(in output: String) -> [String] {
        Set(output.split(separator: "\0").map(String.init).filter(isSensitive)).sorted()
    }

    private static func exposedPaths(at folder: URL) async throws -> [String] {
        let paths = try await run(["ls-files", "-z", "--cached", "--others", "--exclude-standard"], in: folder)
        return sensitivePaths(in: paths)
    }

    /// Arquivos sensíveis rastreados ou soltos sem estar ignorados.
    public static func exposedSensitiveFiles(at folder: URL) async -> [String] {
        (try? await exposedPaths(at: folder)) ?? []
    }

    /// Recusa publicar um ramo com caminhos sensíveis em qualquer commit que vá junto.
    @discardableResult
    public static func checkPublishableHistory(at folder: URL) async throws -> String {
        let shallow = try await run(["rev-parse", "--is-shallow-repository"], in: folder)
        guard shallow.trimmingCharacters(in: .newlines) == "false" else {
            throw GitFailure(command: "publicar", output: "Este clone tem um histórico parcial. Baixe o histórico completo antes de publicar.")
        }
        _ = try await run(["symbolic-ref", "HEAD"], in: folder)
        let head = try await run(["rev-parse", "--verify", "HEAD^{commit}"], in: folder)
            .trimmingCharacters(in: .newlines)
        let log = try await run(["--no-replace-objects", "log", "--full-history", "--diff-merges=separate",
                                 "--root", "--format=", "--no-renames", "--name-only", "-z", head, "--"], in: folder)
        let paths = sensitivePaths(in: log)
        if !paths.isEmpty {
            throw GitFailure(command: "publicar", output: """
                A publicação foi bloqueada: há arquivos com nomes de credenciais no histórico do ramo.
                \(paths.prefix(8).joined(separator: ", "))

                Revise esses commits e remova os arquivos do histórico antes de publicar. Se uma credencial já saiu deste Mac, troque-a.
                """)
        }
        return head
    }

    /// Ignora os sensíveis daqui em diante. Os commits antigos são preservados.
    @discardableResult
    public static func protect(at folder: URL) async throws -> [String] {
        let staged = try await run(["diff", "--cached", "--name-only", "-z"], in: folder)
        let tracked = sensitivePaths(in: try await run(["ls-files", "-z"], in: folder))
        let changed = try writeProtection(at: folder)
        if !tracked.isEmpty {
            try await run(["--literal-pathspecs", "rm", "--cached", "--quiet", "--"] + tracked, in: folder)
        }
        guard changed || !tracked.isEmpty else { return [] }
        try await run(["add", "--", ".gitignore"], in: folder)
        if staged.isEmpty {
            try await run(["commit", "-m", "Protege arquivos sensíveis (senhas e chaves) no .gitignore"], in: folder)
        }
        return tracked
    }

    // MARK: Ações

    /// Salva todas as mudanças no histórico (git add -A + commit).
    public static func commitAll(at folder: URL, message: String) async throws {
        try await run(["add", "-A"], in: folder)
        try await run(["commit", "-m", message], in: folder)
    }

    /// Salva alterações para publicação após conferir quais arquivos entrarão no commit.
    public static func commitForPublication(at folder: URL, message: String) async throws {
        let paths = try await exposedPaths(at: folder)
        guard paths.isEmpty else {
            throw GitFailure(command: "publicar", output: "Ainda há arquivos sensíveis fora da regra de exclusão: \(paths.prefix(8).joined(separator: ", ")).")
        }
        try await run(["add", "-A"], in: folder)
        let staged = sensitivePaths(in: try await run(["ls-files", "-z"], in: folder))
        guard staged.isEmpty else {
            throw GitFailure(command: "publicar", output: "O índice passou a incluir arquivos sensíveis. Confira as alterações antes de publicar.")
        }
        try await run(["commit", "-m", message], in: folder)
    }

    public static func push(at folder: URL) async throws {
        let status = try await status(at: folder)
        if status.upstream == nil {
            try await run(["push", "-u", "origin", "HEAD"], in: folder)
        } else {
            try await run(["push"], in: folder)
        }
    }

    public static func pull(at folder: URL) async throws {
        try await run(["pull", "--ff-only"], in: folder)
    }

    public static func fetch(at folder: URL) async throws {
        try await run(["fetch", "--prune", "--quiet"], in: folder)
    }

    /// Desfaz as mudanças de um arquivo (volta ao último commit). Arquivos novos vão para o Lixo.
    public static func discard(_ change: FileChange, at folder: URL) async throws {
        let output = try await run(["--no-optional-locks", "status", "--porcelain=v2", "-z", "--untracked-files=all"], in: folder)
        let changes = parseStatus(output, folder: folder).changes
        guard let current = changes.first(where: { $0.path == change.path && $0.kind == change.kind }),
              change.originalPath == nil || change.originalPath == current.originalPath else {
            throw GitFailure(command: "desfazer", output: "O estado deste arquivo mudou. Confira a lista antes de desfazer.")
        }
        switch current.kind {
        case .untracked, .added:
            let url = folder.appendingPathComponent(current.path)
            if current.kind == .added {
                try await run(["--literal-pathspecs", "rm", "-f", "--cached", "--", current.path], in: folder)
            }
            if (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            }
        case .renamed:
            guard let original = current.originalPath,
                  (try? FileManager.default.attributesOfItem(atPath: folder.appendingPathComponent(original).path)) == nil else {
                throw GitFailure(command: "desfazer", output: "O caminho original da renomeação já está ocupado. Mova o arquivo que está nele antes de desfazer.")
            }
            try await run(["--literal-pathspecs", "restore", "--source=HEAD", "--staged", "--worktree", "--", original, current.path], in: folder)
        default:
            try await run(["--literal-pathspecs", "restore", "--source=HEAD", "--staged", "--worktree", "--", current.path], in: folder)
        }
    }

    public static func clone(_ url: String, into parent: URL) async throws -> URL {
        let path = URL(string: url)?.path.nilIfEmpty ?? url
        var name = path.split(separator: "/").last.map(String.init) ?? "repo"
        if name.hasSuffix(".git") { name.removeLast(4) }
        guard !name.isEmpty, name != ".", name != ".." else {
            throw GitFailure(command: "git clone", output: "O endereço não tem um nome válido para a pasta.")
        }
        try await run(["clone", "--", url, "./" + name], in: parent)
        return parent.appendingPathComponent(name)
    }

    /// Começa a usar Git numa pasta e faz o primeiro commit.
    public static func initialize(at folder: URL) async throws {
        try await run(["init", "-b", "main"], in: folder)
        try writeProtection(at: folder, newProject: true)
        try await run(["add", "-A"], in: folder)
        let staged = sensitivePaths(in: try await run(["ls-files", "-z"], in: folder))
        if !staged.isEmpty {
            try await run(["--literal-pathspecs", "rm", "--cached", "--"] + staged, in: folder)
        }
        try await run(["commit", "--allow-empty", "-m", "Primeira versão"], in: folder)
    }

    /// Liga a pasta a um repositório do GitHub e envia tudo.
    public static func publish(at folder: URL, remote: String) async throws {
        let head = try await checkPublishableHistory(at: folder)
        let branch = try await run(["symbolic-ref", "HEAD"], in: folder).trimmingCharacters(in: .newlines)
        let previous = try await originConfiguration(at: folder)
        if let previous, previous != remote {
            throw GitFailure(command: "publicar", output: "Este projeto já tem um remoto origin. Confira a configuração antes de publicar em outro destino.")
        }
        // Envia o commit conferido. URL explícita impede que pushurl ou configurações de
        // envio de outros ramos incluam referências que não passaram pela verificação.
        try await run(["-c", "push.followTags=false", "push", "--", remote, "\(head):\(branch)"], in: folder)
        if previous == nil { try await run(["remote", "add", "origin", remote], in: folder) }
        let name = String(branch.dropFirst("refs/heads/".count))
        try await run(["update-ref", "refs/remotes/origin/\(name)", head], in: folder)
        try await run(["branch", "--set-upstream-to=origin/\(name)", name], in: folder)
    }

    private static func originConfiguration(at folder: URL) async throws -> String? {
        do {
            return try await run(["remote", "get-url", "origin"], in: folder).trimmingCharacters(in: .newlines)
        } catch let failure as GitFailure where failure.output.contains("No such remote") {
            return nil
        }
    }

    /// Diferença de um arquivo em relação ao último commit (para mostrar antes de salvar).
    public static func diff(_ change: FileChange, at folder: URL) async -> String {
        if change.kind == .untracked {
            let url = folder.appendingPathComponent(change.path)
            guard let data = try? Data(contentsOf: url), data.count < 200_000,
                  let text = String(data: data, encoding: .utf8) else { return "" }
            return text.split(separator: "\n", omittingEmptySubsequences: false).map { "+" + $0 }.joined(separator: "\n")
        }
        let paths = [change.originalPath, change.path].compactMap { $0 }
        return (try? await run(["--literal-pathspecs", "diff", "HEAD", "--no-color", "--"] + paths, in: folder)) ?? ""
    }
}

/// Acumula a saída do processo vinda de outra fila.
final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: data, as: UTF8.self)
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
