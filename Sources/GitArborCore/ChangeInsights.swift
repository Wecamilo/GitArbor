import Foundation

// “Explica esta mudança”: resumo em português e sugestão de frase para o commit.
// Varredura de segredos (chaves e senhas) que já foram para o histórico.

public enum FileCategory: String, Sendable, CaseIterable {
    case code, text, image, config, data, other

    /// Nome no singular e no plural ("arquivo de código", "arquivos de código").
    public var noun: (one: String, many: String) {
        switch self {
        case .code: ("arquivo de código", "arquivos de código")
        case .text: ("texto", "textos")
        case .image: ("imagem", "imagens")
        case .config: ("arquivo de configuração", "arquivos de configuração")
        case .data: ("arquivo de dados", "arquivos de dados")
        case .other: ("arquivo", "arquivos")
        }
    }

    public static func of(_ path: String) -> FileCategory {
        let name = (path as NSString).lastPathComponent.lowercased()
        let ext = (name as NSString).pathExtension
        if name.hasPrefix(".") && ext.isEmpty || ["package.swift", "makefile", "dockerfile", "gemfile", "podfile"].contains(name) { return .config }
        if ["swift", "js", "mjs", "cjs", "ts", "tsx", "jsx", "py", "rb", "go", "rs", "java", "kt", "c", "h", "cc", "cpp", "hpp", "m", "mm",
            "cs", "php", "css", "scss", "sass", "less", "html", "htm", "vue", "svelte", "sh", "zsh", "bash", "sql", "lua", "dart", "r"].contains(ext) { return .code }
        if ["md", "markdown", "txt", "rtf", "pdf", "doc", "docx", "tex", "rst"].contains(ext) { return .text }
        if ["png", "jpg", "jpeg", "gif", "svg", "webp", "heic", "icns", "ico", "tiff", "bmp", "psd", "sketch", "fig"].contains(ext) { return .image }
        if ["json", "yml", "yaml", "toml", "plist", "xml", "ini", "cfg", "conf", "lock", "resolved", "entitlements", "xcconfig", "gradle"].contains(ext) { return .config }
        if ["csv", "tsv", "sqlite", "db", "parquet", "xlsx", "xls"].contains(ext) { return .data }
        return .other
    }
}

public enum ChangeExplainer {
    public typealias Stats = [String: (added: Int, removed: Int)]

    /// Frases curtas explicando o conjunto de mudanças.
    public static func summary(_ changes: [FileChange], stats: Stats = [:]) -> [String] {
        guard !changes.isEmpty else { return ["Nenhum arquivo mudou."] }
        var lines: [String] = []

        // O que aconteceu, por tipo de mudança.
        let added = changes.filter { $0.kind == .added || $0.kind == .untracked }
        let modified = changes.filter { $0.kind == .modified }
        let deleted = changes.filter { $0.kind == .deleted }
        let renamed = changes.filter { $0.kind == .renamed }
        var parts: [String] = []
        if !added.isEmpty { parts.append(Phrases.plural(added.count, "arquivo novo", "arquivos novos")) }
        if !modified.isEmpty { parts.append(Phrases.plural(modified.count, "arquivo alterado", "arquivos alterados")) }
        if !deleted.isEmpty { parts.append(Phrases.plural(deleted.count, "arquivo apagado", "arquivos apagados")) }
        if !renamed.isEmpty { parts.append(Phrases.plural(renamed.count, "arquivo renomeado", "arquivos renomeados")) }
        lines.append(join(parts).capitalizedFirst + ".")

        // De que tipo são.
        let byCategory = Dictionary(grouping: changes) { FileCategory.of($0.path) }
        if byCategory.count > 1 || byCategory.keys.first != .other {
            let kinds = byCategory.sorted { $0.value.count > $1.value.count }.map { category, items in
                "\(items.count) \(items.count == 1 ? category.noun.one : category.noun.many)"
            }
            lines.append("São " + join(kinds) + ".")
        }

        // Tamanho da mudança.
        let relevant = changes.compactMap { stats[$0.path] }
        let totalAdded = relevant.reduce(0) { $0 + $1.added }
        let totalRemoved = relevant.reduce(0) { $0 + $1.removed }
        if totalAdded + totalRemoved > 0 {
            lines.append("No total: \(Phrases.plural(totalAdded, "linha escrita", "linhas escritas")) e \(Phrases.plural(totalRemoved, "linha tirada", "linhas tiradas")) — \(size(totalAdded + totalRemoved)).")
            if changes.count > 1, let biggest = changes.max(by: { total(stats[$0.path]) < total(stats[$1.path]) }),
               total(stats[biggest.path]) > 0 {
                lines.append("A maior mudança foi em “\((biggest.path as NSString).lastPathComponent)” (\(total(stats[biggest.path])) linhas).")
            }
        }

        // Onde.
        let folders = Set(changes.map { folderOf($0.path) })
        if folders.count == 1, let only = folders.first, !only.isEmpty {
            lines.append("Tudo dentro da pasta “\(only)”.")
        } else if folders.count > 1 {
            lines.append("Espalhado por \(folders.count) pastas.")
        }

        if changes.contains(where: { $0.kind == .conflict }) {
            lines.append("Atenção: há arquivos em conflito, que mudaram nos dois lados.")
        }
        if changes.contains(where: { LocalGit.isSensitive($0.path) }) {
            lines.append("Atenção: algum arquivo tem nome de senha ou chave. Confira antes de enviar.")
        }
        return lines
    }

    /// Frase sugerida para o commit, no estilo “Atualiza README.md” ou “Adiciona 3 imagens”.
    public static func suggestMessage(_ changes: [FileChange]) -> String {
        guard !changes.isEmpty else { return "" }
        if changes.count == 1, let c = changes.first {
            let name = (c.path as NSString).lastPathComponent
            switch c.kind {
            case .added, .untracked: return "Adiciona \(name)"
            case .deleted: return "Remove \(name)"
            case .renamed: return "Renomeia \(((c.originalPath ?? "") as NSString).lastPathComponent) para \(name)"
            case .modified, .conflict: return "Atualiza \(name)"
            }
        }
        let groups: [(verb: String, items: [FileChange])] = [
            ("adiciona", changes.filter { $0.kind == .added || $0.kind == .untracked }),
            ("atualiza", changes.filter { $0.kind == .modified || $0.kind == .conflict }),
            ("remove", changes.filter { $0.kind == .deleted }),
            ("renomeia", changes.filter { $0.kind == .renamed })
        ].filter { !$0.items.isEmpty }.sorted { $0.items.count > $1.items.count }

        let clauses = groups.prefix(2).map { "\($0.verb) \(describe($0.items))" }
        var message = clauses.joined(separator: " e ").capitalizedFirst
        if groups.count > 2 { message += " e mais" }
        let folders = Set(changes.map { folderOf($0.path) })
        if folders.count == 1, let only = folders.first, !only.isEmpty {
            message += " em \((only as NSString).lastPathComponent)"
        }
        return message
    }

    /// "README.md", "2 imagens" ou "3 arquivos".
    static func describe(_ items: [FileChange]) -> String {
        if items.count == 1 { return (items[0].path as NSString).lastPathComponent }
        let categories = Set(items.map { FileCategory.of($0.path) })
        if categories.count == 1, let c = categories.first {
            return "\(items.count) \(c.noun.many)"
        }
        return "\(items.count) arquivos"
    }

    static func folderOf(_ path: String) -> String {
        (path as NSString).deletingLastPathComponent
    }

    static func total(_ s: (added: Int, removed: Int)?) -> Int { (s?.added ?? 0) + (s?.removed ?? 0) }

    static func size(_ lines: Int) -> String {
        switch lines {
        case ..<20: "uma mudança pequena"
        case ..<200: "uma mudança média"
        default: "uma mudança grande"
        }
    }

    static func join(_ parts: [String]) -> String {
        switch parts.count {
        case 0: ""
        case 1: parts[0]
        default: parts.dropLast().joined(separator: ", ") + " e " + parts.last!
        }
    }
}

// MARK: - Segredos no histórico

public struct SecretFinding: Sendable, Hashable, Identifiable {
    public let kind: String
    public let path: String
    public let commit: String
    public let commitMessage: String
    public let date: Date?
    /// Começo do valor, com o resto escondido.
    public let preview: String
    public var id: String { kind + path + preview }
}

public enum SecretScanner {
    struct Rule: Sendable {
        let kind: String
        let pattern: String
    }

    static let rules: [Rule] = [
        Rule(kind: "Chave privada", pattern: #"-----BEGIN (?:RSA |EC |DSA |OPENSSH |PGP |ENCRYPTED )?PRIVATE KEY"#),
        Rule(kind: "Chave do GitHub", pattern: #"\b(?:gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{50,})"#),
        Rule(kind: "Chave da AWS", pattern: #"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b"#),
        Rule(kind: "Chave da Anthropic", pattern: #"\bsk-ant-[A-Za-z0-9_\-]{20,}"#),
        Rule(kind: "Chave da OpenAI", pattern: #"\bsk-(?:proj-)?[A-Za-z0-9_\-]{32,}"#),
        Rule(kind: "Chave do Google", pattern: #"\bAIza[0-9A-Za-z_\-]{35}\b"#),
        Rule(kind: "Chave do Stripe", pattern: #"\b(?:sk|rk)_live_[0-9A-Za-z]{20,}"#),
        Rule(kind: "Chave do Slack", pattern: #"\bxox[abprs]-[A-Za-z0-9\-]{10,}"#),
        Rule(kind: "Senha escrita no código", pattern: #"(?i)\b(?:password|passwd|senha|secret|api[_-]?key|access[_-]?token)\b["']?\s*[:=]\s*["']([^"'\s$<>{}]{8,})["']"#)
    ]

    /// Procura nas linhas acrescentadas de todos os commits (até `limit` commits).
    public static func scan(at folder: URL, limit: Int = 1500) async -> [SecretFinding] {
        guard let text = try? await LocalGit.run(["log", "--all", "-n", String(limit), "-p", "-U0", "--no-color", "--no-ext-diff",
                                                  "--format=%x1e%H%x1f%s%x1f%cI"], in: folder) else { return [] }
        return scan(log: text)
    }

    /// Lê a saída de `git log -p` com cabeçalhos `\x1e sha \x1f assunto \x1f data`.
    public static func scan(log text: String) -> [SecretFinding] {
        let compiled = rules.compactMap { rule in (try? NSRegularExpression(pattern: rule.pattern)).map { (rule.kind, $0) } }
        var findings: [SecretFinding] = []
        var seen: Set<String> = []
        var commit = "", message = "", date: Date?
        var path = ""
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            if line.first == "\u{1e}" {
                let f = line.dropFirst().components(separatedBy: "\u{1f}")
                commit = f.first ?? ""
                message = f.count > 1 ? f[1] : ""
                date = f.count > 2 ? ISO8601DateFormatter().date(from: f[2]) : nil
                continue
            }
            if line.hasPrefix("+++ ") {
                path = line.hasPrefix("+++ b/") ? String(line.dropFirst(6)) : ""
                continue
            }
            guard line.hasPrefix("+"), line.count < 3000, !path.isEmpty else { continue }
            let content = String(line.dropFirst())
            let range = NSRange(content.startIndex..., in: content)
            for (kind, regex) in compiled {
                guard let match = regex.firstMatch(in: content, range: range) else { continue }
                let captured = match.numberOfRanges > 1 && match.range(at: 1).location != NSNotFound ? match.range(at: 1) : match.range
                guard let r = Range(captured, in: content) else { continue }
                let value = String(content[r])
                if kind == "Senha escrita no código" && looksLikePlaceholder(value) { continue }
                let preview = mask(value)
                let key = kind + path + preview
                if seen.insert(key).inserted {
                    findings.append(SecretFinding(kind: kind, path: path, commit: commit, commitMessage: message, date: date, preview: preview))
                }
                break
            }
        }
        return findings
    }

    static func mask(_ value: String) -> String {
        if value.hasPrefix("-----BEGIN") { return "-----BEGIN … PRIVATE KEY" }
        return String(value.prefix(min(6, max(2, value.count / 4)))) + String(repeating: "•", count: 8)
    }

    static func looksLikePlaceholder(_ value: String) -> Bool {
        let lower = value.lowercased()
        let placeholders = ["example", "exemplo", "changeme", "your", "seu_", "sua_", "xxxx", "****", "placeholder", "dummy", "process.env", "getenv"]
        let exact = ["password", "senha", "secret", "test", "teste", "12345678", "password123"]
        return placeholders.contains { lower.contains($0) } || exact.contains(lower) || Set(value).count < 4
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
