import Foundation

// Máquina do tempo, guardar para depois (stash), ramos e conflitos num projeto do Mac.

/// Uma versão salva (commit) do histórico local.
public struct LocalCommit: Sendable, Hashable, Identifiable {
    public let sha: String
    public let shortSHA: String
    public let message: String
    public let author: String
    public let date: Date?
    public let parents: Int
    /// true: já está no GitHub; false: só neste Mac; nil: o projeto não tem GitHub.
    public var pushed: Bool?
    public var id: String { sha }
    public var isMerge: Bool { parents > 1 }

    public init(sha: String, shortSHA: String, message: String, author: String, date: Date?, parents: Int, pushed: Bool? = nil) {
        self.sha = sha
        self.shortSHA = shortSHA
        self.message = message
        self.author = author
        self.date = date
        self.parents = parents
        self.pushed = pushed
    }
}

/// Um arquivo que foi apagado em algum commit e não existe mais na pasta.
public struct DeletedFile: Sendable, Hashable, Identifiable {
    public let path: String
    /// Commit que apagou o arquivo; a versão boa está no anterior a ele.
    public let deletedIn: String
    public let message: String
    public let date: Date?
    public var id: String { path }
}

/// Mudanças guardadas para depois (stash).
public struct StashEntry: Sendable, Hashable, Identifiable {
    public let ref: String       // stash@{0}
    public let message: String
    public let branch: String?
    public let date: Date?
    public var id: String { ref }
}

/// Um ramo do projeto no Mac.
public struct LocalBranch: Sendable, Hashable, Identifiable {
    public let name: String
    public let upstream: String?
    public let ahead: Int
    public let behind: Int
    /// O ramo sumiu do GitHub (apagado lá).
    public let gone: Bool
    public let date: Date?
    public let subject: String?
    public let isCurrent: Bool
    /// Existe só no GitHub; trocar para ele cria a cópia no Mac.
    public let remoteOnly: Bool
    public var id: String { (remoteOnly ? "origin/" : "") + name }
}

/// Operação do Git parada no meio (geralmente por causa de conflitos).
public enum GitOperation: String, Sendable, Hashable, Codable {
    case merge, rebase, revert, cherryPick

    public var title: String {
        switch self {
        case .merge: "Junção (merge) em andamento"
        case .rebase: "Reaplicação (rebase) em andamento"
        case .revert: "Desfazer versão (revert) em andamento"
        case .cherryPick: "Cópia de versão (cherry-pick) em andamento"
        }
    }
}

/// Resultado de uma ação que pode parar em conflito.
public enum MergeOutcome: Sendable, Equatable {
    case done
    case conflicts
}

// MARK: - Conflitos

/// Um arquivo em conflito, quebrado em trechos comuns e trechos em disputa.
public struct ConflictDocument: Sendable, Equatable {
    public struct Conflict: Sendable, Equatable {
        public var ours: String
        public var theirs: String
        public var oursLabel: String
        public var theirsLabel: String
    }
    public enum Segment: Sendable, Equatable {
        case common(String)
        case conflict(Conflict)
    }
    public enum Choice: String, Sendable, Hashable, CaseIterable {
        case ours, theirs, both
    }

    public var segments: [Segment]
    public var conflictCount: Int { segments.filter { if case .conflict = $0 { true } else { false } }.count }

    /// Lê o texto com as marcas `<<<<<<<`, `|||||||`, `=======` e `>>>>>>>`.
    public static func parse(_ text: String) -> ConflictDocument {
        var segments: [Segment] = []
        var common: [Substring] = []
        var ours: [Substring] = [], theirs: [Substring] = []
        var oursLabel = "", theirsLabel = ""
        enum Mode { case common, ours, base, theirs }
        var mode = Mode.common
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        func flushCommon() {
            if !common.isEmpty { segments.append(.common(common.joined(separator: "\n"))); common = [] }
        }
        for line in lines {
            switch mode {
            case .common:
                if line.hasPrefix("<<<<<<<") {
                    flushCommon()
                    oursLabel = line.dropFirst(7).trimmingCharacters(in: .whitespaces)
                    ours = []; theirs = []
                    mode = .ours
                } else {
                    common.append(line)
                }
            case .ours:
                if line.hasPrefix("|||||||") { mode = .base }
                else if line.hasPrefix("=======") { mode = .theirs }
                else { ours.append(line) }
            case .base:
                if line.hasPrefix("=======") { mode = .theirs }
            case .theirs:
                if line.hasPrefix(">>>>>>>") {
                    theirsLabel = line.dropFirst(7).trimmingCharacters(in: .whitespaces)
                    segments.append(.conflict(Conflict(ours: ours.joined(separator: "\n"), theirs: theirs.joined(separator: "\n"),
                                                       oursLabel: oursLabel, theirsLabel: theirsLabel)))
                    mode = .common
                } else {
                    theirs.append(line)
                }
            }
        }
        // Marca sem fim: devolve o texto como estava.
        if mode != .common { return ConflictDocument(segments: [.common(text)]) }
        flushCommon()
        return ConflictDocument(segments: segments)
    }

    /// Texto final com a escolha de cada conflito (na ordem em que aparecem).
    public func resolved(_ choices: [Choice]) -> String {
        var index = 0
        var parts: [String] = []
        for segment in segments {
            switch segment {
            case .common(let text):
                parts.append(text)
            case .conflict(let c):
                let choice = index < choices.count ? choices[index] : .both
                index += 1
                switch choice {
                case .ours: parts.append(c.ours)
                case .theirs: parts.append(c.theirs)
                case .both: parts.append([c.ours, c.theirs].filter { !$0.isEmpty }.joined(separator: "\n"))
                }
            }
        }
        // Um trecho vazio não deixa linha em branco sobrando.
        return parts.enumerated().filter { $0.offset == 0 || $0.offset == parts.count - 1 || !$0.element.isEmpty }
            .map(\.element).joined(separator: "\n")
    }
}

extension LocalGit {
    // MARK: Linha do tempo

    /// Últimas versões salvas do ramo atual, das mais novas para as mais antigas.
    public static func history(at folder: URL, limit: Int = 80) async throws -> [LocalCommit] {
        let text: String
        do {
            text = try await run(["log", "-n", String(limit), "--format=%H%x1f%h%x1f%s%x1f%an%x1f%cI%x1f%P%x1e"], in: folder)
        } catch let failure as GitFailure where failure.output.contains("does not have any commits") {
            return []
        }
        var commits = parseHistory(text)
        let unpushed = await unpushedSHAs(at: folder)
        for i in commits.indices { commits[i].pushed = unpushed.map { !$0.contains(commits[i].sha) } }
        return commits
    }

    static func parseHistory(_ text: String) -> [LocalCommit] {
        text.split(separator: "\u{1e}").compactMap { record in
            let f = record.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\u{1f}")
            guard f.count >= 6, !f[0].isEmpty else { return nil }
            return LocalCommit(sha: f[0], shortSHA: f[1], message: f[2], author: f[3],
                               date: ISO8601DateFormatter().date(from: f[4]),
                               parents: f[5].split(separator: " ").count)
        }
    }

    /// Commits que ainda não estão em nenhum ramo do GitHub. nil quando o projeto não tem GitHub.
    static func unpushedSHAs(at folder: URL) async -> Set<String>? {
        guard await remoteURL(at: folder) != nil,
              let text = try? await run(["rev-list", "-n", "500", "HEAD", "--not", "--remotes"], in: folder) else { return nil }
        return Set(text.split(separator: "\n").map(String.init))
    }

    /// Arquivos que mudaram num commit (comparado ao anterior).
    public static func filesChanged(in sha: String, at folder: URL) async -> [FileChange] {
        guard let text = try? await run(["diff-tree", "--no-commit-id", "-r", "-M", "--root", "--name-status", "-z", sha], in: folder) else { return [] }
        return parseNameStatus(text)
    }

    static func parseNameStatus(_ text: String) -> [FileChange] {
        let fields = text.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)
        var changes: [FileChange] = []
        var i = 0
        while i < fields.count {
            let status = fields[i]
            if status.hasPrefix("R") || status.hasPrefix("C"), i + 2 < fields.count {
                changes.append(FileChange(path: fields[i + 2], kind: status.hasPrefix("R") ? .renamed : .added, originalPath: fields[i + 1]))
                i += 3
                continue
            }
            guard i + 1 < fields.count else { break }
            let kind: FileChange.Kind = switch status.first {
            case "A": .added
            case "D": .deleted
            default: .modified
            }
            changes.append(FileChange(path: fields[i + 1], kind: kind))
            i += 2
        }
        return changes
    }

    /// O que mudou num commit (texto de diferença), limitado para não pesar na tela.
    public static func patch(of sha: String, at folder: URL, path: String? = nil) async -> String {
        var args = ["show", "--format=", "--no-color", "-M", sha]
        if let path { args = ["--literal-pathspecs"] + args + ["--", path] }
        let text = (try? await run(args, in: folder)) ?? ""
        return text.count > 400_000 ? String(text.prefix(400_000)) + "\n… (diferença grande, cortada)" : text
    }

    /// Linhas adicionadas e removidas por arquivo num commit.
    public static func lineStats(of sha: String, at folder: URL) async -> [String: (added: Int, removed: Int)] {
        parseNumstat((try? await run(["show", "--format=", "--numstat", "-M", sha], in: folder)) ?? "")
    }

    /// Linhas adicionadas e removidas por arquivo nas mudanças ainda não salvas.
    public static func pendingLineStats(at folder: URL, changes: [FileChange]) async -> [String: (added: Int, removed: Int)] {
        var stats = parseNumstat((try? await run(["diff", "HEAD", "--numstat", "-M"], in: folder)) ?? "")
        for change in changes where change.kind == .untracked {
            let url = folder.appendingPathComponent(change.path)
            if let data = try? Data(contentsOf: url), data.count < 2_000_000, let text = String(data: data, encoding: .utf8) {
                stats[change.path] = (text.split(separator: "\n", omittingEmptySubsequences: false).count, 0)
            }
        }
        return stats
    }

    static func parseNumstat(_ text: String) -> [String: (added: Int, removed: Int)] {
        var stats: [String: (added: Int, removed: Int)] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 2)
            guard parts.count == 3 else { continue }
            var path = String(parts[2])
            // Renomeação: "pasta/{velho => novo}.txt" ou "velho => novo".
            if let arrow = path.range(of: " => ") {
                if let open = path.firstIndex(of: "{"), let close = path.firstIndex(of: "}"), open < arrow.lowerBound {
                    let prefix = path[..<open], suffix = path[path.index(after: close)...]
                    path = String(prefix) + String(path[arrow.upperBound..<close]) + String(suffix)
                    path = path.replacingOccurrences(of: "//", with: "/")
                } else {
                    path = String(path[arrow.upperBound...])
                }
            }
            stats[path] = (Int(parts[0]) ?? 0, Int(parts[1]) ?? 0)
        }
        return stats
    }

    /// Lança um aviso claro se houver mudanças não salvas (ações que mexem em tudo precisam da pasta limpa).
    static func requireClean(at folder: URL, action: String) async throws {
        let s = try await status(at: folder)
        if !s.changes.isEmpty {
            throw GitFailure(command: action, output: "Há mudanças não salvas. Salve uma versão ou guarde as mudanças para depois antes de \(action).")
        }
    }

    /// Desfaz a última versão salva que ainda não foi enviada: as mudanças voltam a ficar “não salvas”.
    public static func undoLastCommit(at folder: URL) async throws {
        let commits = try await history(at: folder, limit: 1)
        guard let last = commits.first else {
            throw GitFailure(command: "desfazer", output: "Não há versão salva para desfazer.")
        }
        if last.pushed == true {
            throw GitFailure(command: "desfazer", output: "Esta versão já está no GitHub. Use “Desfazer esta versão”, que cria uma versão nova ao contrário sem apagar o histórico.")
        }
        guard last.parents >= 1 else {
            throw GitFailure(command: "desfazer", output: "Esta é a primeira versão do projeto; não há uma anterior para voltar.")
        }
        try await run(["reset", "--soft", "HEAD~1"], in: folder)
    }

    /// Cria uma versão nova que desfaz o que um commit fez (seguro para o que já foi enviado).
    public static func revert(_ commit: LocalCommit, at folder: URL) async throws -> MergeOutcome {
        try await requireClean(at: folder, action: "desfazer uma versão")
        var args = ["-c", "core.editor=true", "revert", "--no-edit"]
        if commit.isMerge { args += ["-m", "1"] }
        return try await runAllowingConflicts(args + [commit.sha], at: folder)
    }

    /// Deixa todos os arquivos como estavam numa versão e salva isso como uma versão nova.
    /// Nada do histórico é apagado: dá para voltar de novo depois.
    public static func restoreProject(to commit: LocalCommit, at folder: URL) async throws {
        try await requireClean(at: folder, action: "voltar no tempo")
        try await run(["restore", "--source=\(commit.sha)", "--staged", "--worktree", "--", ":/"], in: folder)
        let staged = try await run(["diff", "--cached", "--name-only"], in: folder)
        guard !staged.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GitFailure(command: "voltar", output: "O projeto já está igual a essa versão.")
        }
        try await run(["commit", "-m", "Volta o projeto para a versão “\(commit.message)” (\(commit.shortSHA))"], in: folder)
    }

    /// Traz de volta um arquivo como estava numa versão (fica como mudança não salva).
    public static func restoreFile(_ path: String, from sha: String, at folder: URL) async throws {
        try await run(["--literal-pathspecs", "restore", "--source=\(sha)", "--worktree", "--", path], in: folder)
    }

    /// Arquivos apagados em algum commit e que não existem mais.
    public static func deletedFiles(at folder: URL, limit: Int = 300) async -> [DeletedFile] {
        guard let text = try? await run(["log", "-n", String(limit), "--diff-filter=D", "--name-only", "-z",
                                         "--format=%x1e%H%x1f%s%x1f%cI"], in: folder) else { return [] }
        return parseDeleted(text).filter {
            (try? FileManager.default.attributesOfItem(atPath: folder.appendingPathComponent($0.path).path)) == nil
        }
    }

    static func parseDeleted(_ text: String) -> [DeletedFile] {
        var seen: Set<String> = []
        var files: [DeletedFile] = []
        for record in text.split(separator: "\u{1e}") {
            let parts = record.split(separator: "\0", omittingEmptySubsequences: true).map {
                $0.trimmingCharacters(in: .newlines)
            }.filter { !$0.isEmpty }
            guard let header = parts.first else { continue }
            let f = header.components(separatedBy: "\u{1f}")
            guard f.count >= 3 else { continue }
            let date = ISO8601DateFormatter().date(from: f[2])
            for path in parts.dropFirst() where seen.insert(path).inserted {
                files.append(DeletedFile(path: path, deletedIn: f[0], message: f[1], date: date))
            }
        }
        return files
    }

    // MARK: Guardar para depois (stash)

    public static func stashes(at folder: URL) async -> [StashEntry] {
        guard let text = try? await run(["stash", "list", "--format=%gd%x1f%gs%x1f%cI"], in: folder) else { return [] }
        return parseStashes(text)
    }

    static func parseStashes(_ text: String) -> [StashEntry] {
        text.split(separator: "\n").compactMap { line in
            let f = line.components(separatedBy: "\u{1f}")
            guard f.count >= 3 else { return nil }
            // "On main: mensagem" ou "WIP on main: abc123 assunto"
            var subject = f[1]
            var branch: String?
            if let colon = subject.firstIndex(of: ":") {
                let head = subject[..<colon]
                if let on = head.range(of: "on ", options: [.caseInsensitive, .backwards]) {
                    branch = String(head[on.upperBound...])
                }
                subject = subject[subject.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
            return StashEntry(ref: f[0], message: subject, branch: branch, date: ISO8601DateFormatter().date(from: f[2]))
        }
    }

    /// Guarda todas as mudanças (inclusive arquivos novos) e deixa a pasta como na última versão.
    public static func stash(at folder: URL, message: String) async throws {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        try await run(["stash", "push", "--include-untracked", "-m", text.isEmpty ? "Guardado pelo Git Arbor" : text], in: folder)
    }

    /// Traz de volta mudanças guardadas. Se der conflito, elas continuam guardadas também.
    public static func applyStash(_ entry: StashEntry, at folder: URL) async throws -> MergeOutcome {
        try await runAllowingConflicts(["stash", "pop", entry.ref], at: folder)
    }

    public static func dropStash(_ entry: StashEntry, at folder: URL) async throws {
        try await run(["stash", "drop", entry.ref], in: folder)
    }

    // MARK: Ramos

    public static func branches(at folder: URL) async throws -> [LocalBranch] {
        let format = "%(refname:short)%1f%(upstream:short)%1f%(upstream:track,nobracket)%1f%(committerdate:iso-strict)%1f%(contents:subject)%1f%(HEAD)"
        let local = parseBranches(try await run(["for-each-ref", "refs/heads", "--format=\(format)"], in: folder))
        let remoteText = (try? await run(["for-each-ref", "refs/remotes/origin", "--format=%(refname:lstrip=3)%1f%(committerdate:iso-strict)%1f%(contents:subject)"], in: folder)) ?? ""
        let names = Set(local.map(\.name))
        let remote = remoteText.split(separator: "\n").compactMap { line -> LocalBranch? in
            let f = line.components(separatedBy: "\u{1f}")
            guard f.count >= 3, f[0] != "HEAD", !names.contains(f[0]) else { return nil }
            return LocalBranch(name: f[0], upstream: "origin/" + f[0], ahead: 0, behind: 0, gone: false,
                               date: ISO8601DateFormatter().date(from: f[1]), subject: f[2], isCurrent: false, remoteOnly: true)
        }
        return local + remote
    }

    static func parseBranches(_ text: String) -> [LocalBranch] {
        text.split(separator: "\n").compactMap { line in
            let f = line.components(separatedBy: "\u{1f}")
            guard f.count >= 6 else { return nil }
            var ahead = 0, behind = 0
            for part in f[2].split(separator: ",") {
                let words = part.trimmingCharacters(in: .whitespaces).split(separator: " ")
                guard words.count == 2, let n = Int(words[1]) else { continue }
                if words[0] == "ahead" { ahead = n } else if words[0] == "behind" { behind = n }
            }
            return LocalBranch(name: f[0], upstream: f[1].nilIfEmpty, ahead: ahead, behind: behind, gone: f[2] == "gone",
                               date: ISO8601DateFormatter().date(from: f[3]), subject: f[4].nilIfEmpty,
                               isCurrent: f[5] == "*", remoteOnly: false)
        }
    }

    /// Nome de ramo aceito pelo Git (sem espaços, acentos viram letras simples).
    public static func branchSlug(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
        var slug = ""
        var lastDash = false
        for ch in folded {
            if ch.isLetter && ch.isASCII || ch.isNumber || ch == "/" || ch == "_" || ch == "." {
                slug.append(ch)
                lastDash = false
            } else if !lastDash && !slug.isEmpty {
                slug.append("-")
                lastDash = true
            }
        }
        while slug.hasSuffix("-") || slug.hasSuffix(".") || slug.hasSuffix("/") { slug.removeLast() }
        return slug.replacingOccurrences(of: "..", with: ".")
    }

    /// Cria um ramo a partir do ponto atual e já passa a trabalhar nele (as mudanças não salvas vão junto).
    public static func createBranch(_ name: String, at folder: URL) async throws {
        try await run(["check-ref-format", "--branch", name], in: folder)
        try await run(["switch", "-c", name], in: folder)
    }

    /// Troca de ramo. Um ramo que só existe no GitHub ganha uma cópia no Mac ligada a ele.
    public static func switchBranch(_ branch: LocalBranch, at folder: URL) async throws {
        if branch.remoteOnly {
            try await run(["switch", "--track", "origin/\(branch.name)"], in: folder)
        } else {
            try await run(["switch", branch.name], in: folder)
        }
    }

    /// Junta outro ramo no ramo atual.
    public static func merge(_ branch: LocalBranch, at folder: URL) async throws -> MergeOutcome {
        try await requireClean(at: folder, action: "juntar ramos")
        let ref = branch.remoteOnly ? "origin/\(branch.name)" : branch.name
        return try await runAllowingConflicts(["merge", "--no-edit", ref], at: folder)
    }

    /// Apaga um ramo do Mac, só se tudo dele já estiver juntado em outro lugar (o Git confere).
    public static func deleteBranch(_ branch: LocalBranch, at folder: URL) async throws {
        try await run(["branch", "-d", branch.name], in: folder)
    }

    // MARK: Conflitos

    /// Baixa as novidades juntando com o que mudou no Mac (para quando os dois lados mudaram).
    public static func pullMerging(at folder: URL) async throws -> MergeOutcome {
        try await requireClean(at: folder, action: "baixar e juntar")
        return try await runAllowingConflicts(["pull", "--no-rebase", "--no-edit"], at: folder)
    }

    /// Roda um comando que pode parar em conflito: conflito não é erro, é um estado a resolver.
    static func runAllowingConflicts(_ args: [String], at folder: URL) async throws -> MergeOutcome {
        do {
            try await run(args, in: folder)
            return .done
        } catch let failure as GitFailure {
            let lower = failure.output.lowercased()
            if lower.contains("conflict") {
                let s = try? await status(at: folder)
                if s?.changes.contains(where: { $0.kind == .conflict }) == true { return .conflicts }
            }
            throw failure
        }
    }

    /// Operação parada no meio, lida dos arquivos de controle do Git.
    public static func operation(at folder: URL) async -> GitOperation? {
        guard let dir = try? await run(["rev-parse", "--absolute-git-dir"], in: folder) else { return nil }
        let git = URL(fileURLWithPath: dir.trimmingCharacters(in: .whitespacesAndNewlines))
        let fm = FileManager.default
        if fm.fileExists(atPath: git.appendingPathComponent("rebase-merge").path)
            || fm.fileExists(atPath: git.appendingPathComponent("rebase-apply").path) { return .rebase }
        if fm.fileExists(atPath: git.appendingPathComponent("MERGE_HEAD").path) { return .merge }
        if fm.fileExists(atPath: git.appendingPathComponent("REVERT_HEAD").path) { return .revert }
        if fm.fileExists(atPath: git.appendingPathComponent("CHERRY_PICK_HEAD").path) { return .cherryPick }
        return nil
    }

    /// Texto atual (com as marcas de conflito) de um arquivo.
    public static func conflictText(_ path: String, at folder: URL) -> String? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(path)), data.count < 2_000_000 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Grava o arquivo já resolvido e marca o conflito como resolvido.
    public static func resolveConflict(_ path: String, content: String, at folder: URL) async throws {
        try content.write(to: folder.appendingPathComponent(path), atomically: true, encoding: .utf8)
        try await run(["--literal-pathspecs", "add", "--", path], in: folder)
    }

    /// Fica com um dos lados inteiro (bom para imagens e arquivos que não são texto).
    public static func resolveConflict(_ path: String, keepOurs: Bool, at folder: URL) async throws {
        do {
            try await run(["--literal-pathspecs", "checkout", keepOurs ? "--ours" : "--theirs", "--", path], in: folder)
            try await run(["--literal-pathspecs", "add", "--", path], in: folder)
        } catch let failure as GitFailure where failure.output.contains("does not have") {
            // Esse lado apagou o arquivo: ficar com ele é apagar.
            try await run(["--literal-pathspecs", "rm", "--quiet", "--", path], in: folder)
        }
    }

    /// Conclui a operação depois de resolver todos os conflitos.
    public static func continueOperation(at folder: URL) async throws {
        let s = try await status(at: folder)
        if s.changes.contains(where: { $0.kind == .conflict }) {
            throw GitFailure(command: "concluir", output: "Ainda há arquivos em conflito. Resolva todos antes de concluir.")
        }
        switch await operation(at: folder) {
        case .merge: try await run(["-c", "core.editor=true", "commit", "--no-edit"], in: folder)
        case .rebase: try await run(["-c", "core.editor=true", "rebase", "--continue"], in: folder)
        case .revert: try await run(["-c", "core.editor=true", "revert", "--continue"], in: folder)
        case .cherryPick: try await run(["-c", "core.editor=true", "cherry-pick", "--continue"], in: folder)
        case nil: break
        }
    }

    /// Desiste da operação e volta tudo como estava antes dela.
    public static func abortOperation(at folder: URL) async throws {
        switch await operation(at: folder) {
        case .merge: try await run(["merge", "--abort"], in: folder)
        case .rebase: try await run(["rebase", "--abort"], in: folder)
        case .revert: try await run(["revert", "--abort"], in: folder)
        case .cherryPick: try await run(["cherry-pick", "--abort"], in: folder)
        case nil:
            throw GitFailure(command: "desistir", output: "Não há junção em andamento. Os conflitos vieram de mudanças guardadas: resolva ou desfaça os arquivos.")
        }
    }
}
