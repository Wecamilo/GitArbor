import Foundation
import Testing
@testable import GitArborCore

/// Repositório de teste numa pasta temporária, com nome e e-mail próprios.
struct TempRepo {
    let folder: URL

    init() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("arbor-tl-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try await git("init", "-b", "main")
        try await git("config", "user.name", "Teste")
        try await git("config", "user.email", "teste@exemplo.com")
        try await git("config", "commit.gpgsign", "false")
    }

    @discardableResult
    func git(_ args: String...) async throws -> String { try await LocalGit.run(args, in: folder) }

    func write(_ name: String, _ text: String) throws {
        let url = folder.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    func read(_ name: String) -> String? { try? String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8) }

    func commit(_ message: String) async throws {
        try await git("add", "-A")
        try await git("commit", "-m", message)
    }

    func remove() { try? FileManager.default.removeItem(at: folder) }
}

@Suite struct ConflictDocumentTests {
    let text = """
    linha 1
    <<<<<<< HEAD
    do Mac
    =======
    do GitHub
    >>>>>>> origin/main
    linha 3
    """

    @Test func separaTrechos() {
        let doc = ConflictDocument.parse(text)
        #expect(doc.conflictCount == 1)
        #expect(doc.segments.count == 3)
        if case .conflict(let c) = doc.segments[1] {
            #expect(c.ours == "do Mac")
            #expect(c.theirs == "do GitHub")
            #expect(c.oursLabel == "HEAD")
            #expect(c.theirsLabel == "origin/main")
        } else {
            Issue.record("esperava conflito")
        }
    }

    @Test func resolveCadaEscolha() {
        let doc = ConflictDocument.parse(text)
        #expect(doc.resolved([.ours]) == "linha 1\ndo Mac\nlinha 3")
        #expect(doc.resolved([.theirs]) == "linha 1\ndo GitHub\nlinha 3")
        #expect(doc.resolved([.both]) == "linha 1\ndo Mac\ndo GitHub\nlinha 3")
    }

    @Test func ignoraBaseDoDiff3() {
        let doc = ConflictDocument.parse("<<<<<<< a\nx\n||||||| base\nb\n=======\ny\n>>>>>>> c")
        #expect(doc.resolved([.both]) == "x\ny")
    }

    @Test func marcaSemFimFicaComoEsta() {
        let doc = ConflictDocument.parse("a\n<<<<<<< HEAD\nb")
        #expect(doc.conflictCount == 0)
        #expect(doc.resolved([]) == "a\n<<<<<<< HEAD\nb")
    }
}

@Suite struct ParserTests {
    @Test func numstatComRenomeacao() {
        let stats = LocalGit.parseNumstat("3\t1\tREADME.md\n-\t-\timg.png\n2\t0\tSources/{Old.swift => New.swift}\n")
        #expect(stats["README.md"]?.added == 3)
        #expect(stats["img.png"]?.added == 0)
        #expect(stats["Sources/New.swift"]?.added == 2)
    }

    @Test func ramos() {
        let text = "main\u{1f}origin/main\u{1f}ahead 2, behind 1\u{1f}2026-01-01T10:00:00Z\u{1f}Assunto\u{1f}*\nvelho\u{1f}origin/velho\u{1f}gone\u{1f}2026-01-01T10:00:00Z\u{1f}x\u{1f} \n"
        let branches = LocalGit.parseBranches(text)
        #expect(branches.count == 2)
        #expect(branches[0].ahead == 2 && branches[0].behind == 1 && branches[0].isCurrent)
        #expect(branches[1].gone && !branches[1].isCurrent)
    }

    @Test func stashes() {
        let list = LocalGit.parseStashes("stash@{0}\u{1f}On main: antes de trocar\u{1f}2026-01-01T10:00:00Z\nstash@{1}\u{1f}WIP on dev: abc123 assunto\u{1f}2026-01-01T10:00:00Z\n")
        #expect(list.count == 2)
        #expect(list[0].message == "antes de trocar" && list[0].branch == "main")
        #expect(list[1].branch == "dev")
    }

    @Test func nomeDeRamo() {
        #expect(LocalGit.branchSlug("Nova Função de Busca!") == "nova-funcao-de-busca")
        #expect(LocalGit.branchSlug("  teste/ação ") == "teste/acao")
    }
}

@Suite struct ExplainerTests {
    @Test func sugestaoParaUmArquivo() {
        #expect(ChangeExplainer.suggestMessage([FileChange(path: "README.md", kind: .modified)]) == "Atualiza README.md")
        #expect(ChangeExplainer.suggestMessage([FileChange(path: "a/logo.png", kind: .untracked)]) == "Adiciona logo.png")
        #expect(ChangeExplainer.suggestMessage([FileChange(path: "x.txt", kind: .deleted)]) == "Remove x.txt")
    }

    @Test func sugestaoAgrupada() {
        let changes = [FileChange(path: "img/a.png", kind: .added), FileChange(path: "img/b.png", kind: .added)]
        #expect(ChangeExplainer.suggestMessage(changes) == "Adiciona 2 imagens em img")
        let mixed = [FileChange(path: "a.swift", kind: .modified), FileChange(path: "b.swift", kind: .modified), FileChange(path: "c.md", kind: .added)]
        #expect(ChangeExplainer.suggestMessage(mixed) == "Atualiza 2 arquivos de código e adiciona c.md")
    }

    @Test func resumo() {
        let changes = [FileChange(path: "a.swift", kind: .modified), FileChange(path: "b.png", kind: .added)]
        let lines = ChangeExplainer.summary(changes, stats: ["a.swift": (10, 2), "b.png": (0, 0)])
        #expect(lines.first == "1 arquivo novo e 1 arquivo alterado.")
        #expect(lines.contains { $0.contains("12") == false && $0.contains("10 linhas escritas") })
    }
}

@Suite struct SecretScannerTests {
    @Test func encontraChavesEEscondeOValor() {
        let log = """
        \u{1e}abc\u{1f}Adiciona config\u{1f}2026-01-01T10:00:00Z
        diff --git a/config.js b/config.js
        +++ b/config.js
        +const token = "ghp_\(String(repeating: "a", count: 36))"
        +const senha = "minhaSenhaForte99"
        +const exemplo = "changeme-exemplo"
        """
        let found = SecretScanner.scan(log: log)
        #expect(found.count == 2)
        #expect(found.contains { $0.kind == "Chave do GitHub" && $0.path == "config.js" && $0.commit == "abc" })
        #expect(found.allSatisfy { !$0.preview.contains("aaaaaaaaaaaa") })
    }
}

@Suite(.serialized) struct TimelineGitTests {
    @Test func desfazUltimaVersaoNaoEnviada() async throws {
        let repo = try await TempRepo()
        defer { repo.remove() }
        try repo.write("a.txt", "1")
        try await repo.commit("Primeira")
        try repo.write("a.txt", "2")
        try await repo.commit("Segunda")
        try await LocalGit.undoLastCommit(at: repo.folder)
        let history = try await LocalGit.history(at: repo.folder)
        #expect(history.map(\.message) == ["Primeira"])
        #expect(history.first?.pushed == nil)
        let status = try await LocalGit.status(at: repo.folder)
        #expect(status.changes.map(\.path) == ["a.txt"])
    }

    @Test func revertEVoltarNoTempo() async throws {
        let repo = try await TempRepo()
        defer { repo.remove() }
        try repo.write("a.txt", "1")
        try await repo.commit("Primeira")
        try repo.write("a.txt", "2")
        try repo.write("b.txt", "novo")
        try await repo.commit("Segunda")
        let history = try await LocalGit.history(at: repo.folder)
        #expect(try await LocalGit.revert(history[0], at: repo.folder) == .done)
        #expect(repo.read("a.txt") == "1")
        #expect(repo.read("b.txt") == nil)

        // Volta para a “Segunda” como uma versão nova.
        try await LocalGit.restoreProject(to: history[0], at: repo.folder)
        #expect(repo.read("b.txt") == "novo")
        let after = try await LocalGit.history(at: repo.folder)
        #expect(after.count == 4)
        #expect(after[0].message.hasPrefix("Volta o projeto"))
    }

    @Test func recuperaArquivoApagado() async throws {
        let repo = try await TempRepo()
        defer { repo.remove() }
        try repo.write("docs/guia.md", "texto")
        try await repo.commit("Guia")
        try FileManager.default.removeItem(at: repo.folder.appendingPathComponent("docs/guia.md"))
        try await repo.commit("Apaga guia")
        let deleted = await LocalGit.deletedFiles(at: repo.folder)
        #expect(deleted.map(\.path) == ["docs/guia.md"])
        try await LocalGit.restoreFile("docs/guia.md", from: deleted[0].deletedIn + "^", at: repo.folder)
        #expect(repo.read("docs/guia.md") == "texto")
    }

    @Test func guardaETrazDeVolta() async throws {
        let repo = try await TempRepo()
        defer { repo.remove() }
        try repo.write("a.txt", "1")
        try await repo.commit("Primeira")
        try repo.write("a.txt", "mudado")
        try repo.write("novo.txt", "n")
        try await LocalGit.stash(at: repo.folder, message: "teste")
        #expect(try await LocalGit.status(at: repo.folder).changes.isEmpty)
        let list = await LocalGit.stashes(at: repo.folder)
        #expect(list.count == 1 && list[0].message == "teste")
        #expect(try await LocalGit.applyStash(list[0], at: repo.folder) == .done)
        #expect(repo.read("novo.txt") == "n")
        #expect(await LocalGit.stashes(at: repo.folder).isEmpty)
    }

    @Test func ramosEConflito() async throws {
        let repo = try await TempRepo()
        defer { repo.remove() }
        try repo.write("a.txt", "base")
        try await repo.commit("Base")
        try await LocalGit.createBranch("ideia", at: repo.folder)
        try repo.write("a.txt", "da ideia")
        try await repo.commit("Ideia")
        var branches = try await LocalGit.branches(at: repo.folder)
        #expect(branches.first { $0.isCurrent }?.name == "ideia")
        let main = try #require(branches.first { $0.name == "main" })
        try await LocalGit.switchBranch(main, at: repo.folder)
        try repo.write("a.txt", "do main")
        try await repo.commit("Main")

        branches = try await LocalGit.branches(at: repo.folder)
        let ideia = try #require(branches.first { $0.name == "ideia" })
        #expect(try await LocalGit.merge(ideia, at: repo.folder) == .conflicts)
        var status = try await LocalGit.status(at: repo.folder)
        #expect(status.operation == .merge)
        #expect(status.state == .conflict)
        #expect(status.conflicts.map(\.path) == ["a.txt"])

        let doc = ConflictDocument.parse(try #require(LocalGit.conflictText("a.txt", at: repo.folder)))
        #expect(doc.conflictCount == 1)
        try await LocalGit.resolveConflict("a.txt", content: doc.resolved([.both]), at: repo.folder)
        try await LocalGit.continueOperation(at: repo.folder)
        status = try await LocalGit.status(at: repo.folder)
        #expect(status.operation == nil)
        #expect(status.state != .conflict)
        #expect(repo.read("a.txt")?.trimmingCharacters(in: .whitespacesAndNewlines) == "do main\nda ideia")

        try await LocalGit.deleteBranch(ideia, at: repo.folder)
        #expect(try await LocalGit.branches(at: repo.folder).map(\.name) == ["main"])
    }

    @Test func desistirDaJuncao() async throws {
        let repo = try await TempRepo()
        defer { repo.remove() }
        try repo.write("a.txt", "base")
        try await repo.commit("Base")
        try await LocalGit.createBranch("outro", at: repo.folder)
        try repo.write("a.txt", "outro")
        try await repo.commit("Outro")
        try await repo.git("switch", "main")
        try repo.write("a.txt", "main")
        try await repo.commit("Main")
        let outro = try #require(try await LocalGit.branches(at: repo.folder).first { $0.name == "outro" })
        #expect(try await LocalGit.merge(outro, at: repo.folder) == .conflicts)
        try await LocalGit.abortOperation(at: repo.folder)
        #expect(repo.read("a.txt") == "main")
        #expect(try await LocalGit.status(at: repo.folder).state != .conflict)
    }

    @Test func varreHistoricoReal() async throws {
        let repo = try await TempRepo()
        defer { repo.remove() }
        try repo.write("chave.txt", "AKIAABCDEFGHIJKLMNOP")
        try await repo.commit("Chave")
        let found = await SecretScanner.scan(at: repo.folder)
        #expect(found.map(\.kind) == ["Chave da AWS"])
    }
}
