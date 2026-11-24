import Foundation
import Testing
@testable import GitArborCore

struct LocalGitTests {
    let folder = URL(fileURLWithPath: "/tmp/projeto")

    @Test func lêRamoEDiferençaComOGitHub() {
        let text = [
            "# branch.oid 1234567890abcdef",
            "# branch.head main",
            "# branch.upstream origin/main",
            "# branch.ab +2 -1",
        ].joined(separator: "\0") + "\0"
        let s = LocalGit.parseStatus(text, folder: folder)
        #expect(s.branch == "main")
        #expect(s.upstream == "origin/main")
        #expect(s.ahead == 2)
        #expect(s.behind == 1)
        #expect(s.changes.isEmpty)
    }

    @Test func lêArquivosMudados() {
        let records = [
            "# branch.head main",
            "1 .M N... 100644 100644 100644 aaa bbb Sources/App.swift",
            "1 A. N... 000000 100644 100644 000 ccc Novo arquivo.swift",
            "1 D. N... 100644 000000 000000 ddd 000 velho.txt",
            "2 R. N... 100644 100644 100644 eee eee R100 novo nome.md",
            "nome antigo.md",
            "u UU N... 100644 100644 100644 100644 a b c conflito.swift",
            "? notas com espaço.txt",
        ]
        let s = LocalGit.parseStatus(records.joined(separator: "\0") + "\0", folder: folder)
        #expect(s.changes.map(\.path) == ["Sources/App.swift", "Novo arquivo.swift", "velho.txt", "novo nome.md", "conflito.swift", "notas com espaço.txt"])
        #expect(s.changes.map(\.kind) == [.modified, .added, .deleted, .renamed, .conflict, .untracked])
        #expect(s.state == .conflict)
    }

    @Test func situaçãoSegueAOrdemCerta() {
        var s = LocalRepoStatus(folder: folder, branch: "main", upstream: "origin/main", remoteURL: "https://github.com/a/b.git")
        #expect(s.state == .clean)
        s.ahead = 1
        #expect(s.state == .toSend)
        s.behind = 2
        #expect(s.state == .diverged)
        s.ahead = 0
        #expect(s.state == .toReceive)
        s.changes = [FileChange(path: "x", kind: .modified)]
        #expect(s.state == .unsaved)
        s.changes = []
        s.remoteURL = nil
        #expect(s.state == .noRemote)
    }

    @Test func reconheceEndereçoDoGitHub() {
        #expect(LocalGit.gitHubFullName(fromRemote: "https://github.com/octocat/Hello-World.git") == "octocat/Hello-World")
        #expect(LocalGit.gitHubFullName(fromRemote: "git@github.com:octocat/Spoon-Knife.git\n") == "octocat/Spoon-Knife")
        #expect(LocalGit.gitHubFullName(fromRemote: "https://github.com/dono/repo") == "dono/repo")
        #expect(LocalGit.gitHubFullName(fromRemote: "https://gitlab.com/dono/repo.git") == nil)
    }
}

struct ModelTests {
    @Test func decodificaRepositório() throws {
        let json = """
        {"id": 1, "name": "Hello-World", "full_name": "octocat/Hello-World", "private": true,
         "owner": {"login": "octocat", "avatar_url": "https://avatars.githubusercontent.com/u/1"},
         "description": null, "fork": false, "html_url": "https://github.com/octocat/Hello-World",
         "default_branch": "main", "language": "Swift", "stargazers_count": 3, "forks_count": 0,
         "open_issues_count": 2, "pushed_at": "2026-11-20T10:00:00Z"}
        """
        let repo = try GitHubClient.decoder.decode(GHRepo.self, from: Data(json.utf8))
        #expect(repo.isPrivate)
        #expect(repo.fullName == "octocat/Hello-World")
        #expect(repo.branch == "main")
        #expect(repo.lastActivity != nil)
    }

    @Test func endereçoDaNotificaçãoNoSite() {
        let n = GHNotification(id: "1", unread: true, reason: "mention", updatedAt: Date(),
                               subject: .init(title: "x", type: "PullRequest", url: URL(string: "https://api.github.com/repos/a/b/pulls/7")),
                               repository: .init(fullName: "a/b", htmlUrl: nil))
        #expect(n.webURL?.absoluteString == "https://github.com/a/b/pull/7")
    }

    @Test func conteúdoEmBase64() throws {
        let json = #"{"name":"a.txt","path":"a.txt","type":"file","size":5,"sha":"x","content":"b2zD\nqQ==\n","encoding":"base64"}"#
        let file = try GitHubClient.decoder.decode(GHContent.self, from: Data(json.utf8))
        #expect(file.decodedText == "olé")
    }

    @Test func sequênciaDeDiasComAtividade() {
        func day(_ n: Int) -> ContributionCalendar.Day { .init(date: "", contributionCount: n, weekday: 0) }
        let cal = ContributionCalendar(totalContributions: 6, weeks: [.init(contributionDays: [day(1), day(0), day(2), day(3), day(0)])])
        #expect(cal.currentStreak == 2)
        #expect(cal.maxCount == 3)
    }

    @Test func traduzErrosComuns() {
        let data = Data(#"{"message":"Repository creation failed.","errors":[{"message":"name already exists on this account"}]}"#.utf8)
        #expect(GitHubClient.error(status: 422, data: data) == .invalid("já existe um repositório com esse nome."))
        #expect(GitHubClient.error(status: 401, data: Data()) == .unauthorized)
    }

    @Test func glossárioTemTodasAsLições() {
        #expect(Glossary.lesson("commit")?.term == "Commit")
        #expect(Set(Glossary.lessons.map(\.id)).count == Glossary.lessons.count)
    }
}

struct AutoPushTests {
    @Test func lêOÚltimoEnvio() {
        let log = """
        2026-11-23 14:50:39 enviando main b434b9b
        2026-11-23 14:50:41 ok       main b434b9b
        2026-11-23 15:00:38 enviando main 43ccdaf
        2026-11-23 15:00:38 FALHOU   main 43ccdaf (sem internet? o próximo commit tenta de novo; ou rode: git push)

        """
        let r = LocalGit.parseAutoPushLog(log)
        #expect(r.last == .failed)
        #expect(r.commit == "43ccdaf")
        #expect(r.date != nil)
        #expect(LocalGit.parseAutoPushLog("2026-11-20 11:46:06 enviando main f5e2af8\n").last == .sending)
        #expect(LocalGit.parseAutoPushLog("").last == nil)
    }

    @Test func ligaEDesligaNumaPastaDeVerdade() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("arbor-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try await LocalGit.run(["init", "-q", "-b", "main"], in: folder)
        #expect(await LocalGit.autoPush(at: folder).enabled == false)
        try await LocalGit.setAutoPush(true, at: folder)
        let on = await LocalGit.autoPush(at: folder)
        #expect(on.enabled && !on.foreignHook)
        try await LocalGit.setAutoPush(false, at: folder)
        #expect(await LocalGit.autoPush(at: folder).enabled == false)
    }

    @Test func reconheceArquivosSensíveis() {
        #expect(LocalGit.isSensitive(".env"))
        #expect(LocalGit.isSensitive("config/.env.production"))
        #expect(!LocalGit.isSensitive(".env.example"))
        #expect(LocalGit.isSensitive("certs/assinatura.p12"))
        #expect(LocalGit.isSensitive("client_secret.json"))
        #expect(!LocalGit.isSensitive("Sources/App.swift"))
    }
}

struct AutoPushAttentionTests {
    @Test func falhaAntigaJáResolvidaNãoPedeAtenção() {
        var s = LocalRepoStatus(folder: URL(fileURLWithPath: "/tmp/x"), branch: "main", upstream: "origin/main", remoteURL: "https://github.com/a/b.git")
        s.autoPush = AutoPush(enabled: true, last: .failed)
        #expect(!s.autoPushNeedsAttention)
        s.ahead = 2
        #expect(s.autoPushNeedsAttention)
        s.autoPush.last = .ok
        #expect(!s.autoPushNeedsAttention)
    }
}

struct RemoteTests {
    @Test func lêOrigemDoConfig() {
        let config = """
        [core]
        \trepositoryformatversion = 0
        [remote "upstream"]
        \turl = https://github.com/outro/repo.git
        [remote "origin"]
        \turl = https://github.com/octocat/linguist.git
        \tfetch = +refs/heads/*:refs/remotes/origin/*
        """
        #expect(LocalGit.parseOriginURL(fromConfig: config) == "https://github.com/octocat/linguist.git")
        #expect(LocalGit.parseOriginURL(fromConfig: "[core]\n\tbare = false\n") == nil)
    }

    @Test func pastaSemRemotoDáNil() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("arbor-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try await LocalGit.run(["init", "-q", "-b", "main"], in: folder)
        #expect(await LocalGit.remoteURL(at: folder) == nil)
        try await LocalGit.run(["remote", "add", "origin", "https://github.com/a/b.git"], in: folder)
        #expect(await LocalGit.remoteURL(at: folder) == "https://github.com/a/b.git")
    }
}

struct SlugTests {
    @Test func nomeDeRepositórioNoPadrão() {
        #expect(Phrases.repoSlug("Site - Loja Online") == "site-loja-online")
        #expect(Phrases.repoSlug("Coleção") == "colecao")
        #expect(Phrases.repoSlug("App - Gestão Financeira") == "app-gestao-financeira")
        #expect(Phrases.repoSlug("meu_script_v2") == "meu_script_v2")
        #expect(Phrases.repoSlug("  meu   projeto! ") == "meu-projeto")
    }
}

struct ProtectionTests {
    func tempRepo() async throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("arbor-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try await LocalGit.run(["init", "-q", "-b", "main"], in: folder)
        try await LocalGit.run(["config", "user.email", "teste@exemplo.com"], in: folder)
        try await LocalGit.run(["config", "user.name", "Teste"], in: folder)
        try await LocalGit.run(["config", "commit.gpgsign", "false"], in: folder)
        try await LocalGit.run(["config", "core.hooksPath", ".git/hooks"], in: folder)
        return folder
    }

    @Test func protegeCaminhosComAcentoESemInterpretarCuringa() async throws {
        let folder = try await tempRepo()
        defer { try? FileManager.default.removeItem(at: folder) }
        let names = [".env", "certificação.pem", "chave[s].pem", "segredo\nprivado.key"]
        for name in names {
            try "FICTÍCIO".write(to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        try "oi".write(to: folder.appendingPathComponent("app.txt"), atomically: true, encoding: .utf8)
        try await LocalGit.commitAll(at: folder, message: "inicial")
        #expect(Set(await LocalGit.exposedSensitiveFiles(at: folder)) == Set(names))

        let removed = try await LocalGit.protect(at: folder)
        #expect(Set(removed) == Set(names))
        #expect(LocalGit.isProtected(at: folder))
        #expect(await LocalGit.exposedSensitiveFiles(at: folder).isEmpty)
        for name in names { #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path)) }
        #expect(try await LocalGit.protect(at: folder).isEmpty)
    }

    @Test func impedePublicaçãoDeHistóricoComSegredoInclusiveNumMerge() async throws {
        let folder = try await tempRepo()
        let remote = folder.deletingLastPathComponent().appendingPathComponent("arbor-\(UUID().uuidString).git")
        defer {
            try? FileManager.default.removeItem(at: folder)
            try? FileManager.default.removeItem(at: remote)
        }
        try await LocalGit.run(["init", "--bare", "-b", "main", remote.path], in: folder)
        try await LocalGit.run(["commit", "--allow-empty", "-m", "base"], in: folder)
        try await LocalGit.run(["switch", "-c", "temporario"], in: folder)
        try "FICTÍCIO".write(to: folder.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
        try await LocalGit.commitAll(at: folder, message: "credencial fictícia")
        try await LocalGit.protect(at: folder)
        try await LocalGit.run(["switch", "main"], in: folder)
        try await LocalGit.run(["merge", "--no-ff", "temporario", "-m", "merge"], in: folder)
        do {
            try await LocalGit.publish(at: folder, remote: remote.path)
            Issue.record("A publicação deveria bloquear a credencial que ficou no histórico.")
        } catch let failure as GitFailure {
            #expect(failure.command == "publicar")
            #expect(failure.output.contains(".env"))
        }
        #expect(await LocalGit.remoteURL(at: folder) == nil)
        #expect(try await LocalGit.run(["--git-dir", remote.path, "for-each-ref"], in: folder).isEmpty)
    }

    @Test func publicaSomenteRamoConferidoELigaUpstream() async throws {
        let folder = try await tempRepo()
        let remote = folder.deletingLastPathComponent().appendingPathComponent("arbor-\(UUID().uuidString).git")
        defer {
            try? FileManager.default.removeItem(at: folder)
            try? FileManager.default.removeItem(at: remote)
        }
        try await LocalGit.run(["init", "--bare", "-b", "main", remote.path], in: folder)
        try await LocalGit.run(["commit", "--allow-empty", "-m", "base"], in: folder)
        try await LocalGit.run(["tag", "-am", "tag", "v1"], in: folder)
        try await LocalGit.run(["config", "push.followTags", "true"], in: folder)
        try await LocalGit.run(["branch", "outro"], in: folder)
        try await LocalGit.publish(at: folder, remote: remote.path)
        #expect(try await LocalGit.status(at: folder).upstream == "origin/main")
        #expect(try await LocalGit.run(["--git-dir", remote.path, "for-each-ref", "--format=%(refname)"], in: folder) == "refs/heads/main\n")
    }

    @Test func desfazRenomeaçãoDosDoisLadosEProtegeOrigemRecriada() async throws {
        let folder = try await tempRepo()
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = folder.appendingPathComponent("origem.txt")
        try "original".write(to: original, atomically: true, encoding: .utf8)
        try await LocalGit.commitAll(at: folder, message: "base")
        try await LocalGit.run(["mv", "origem.txt", "destino.txt"], in: folder)
        let change = try #require(try await LocalGit.status(at: folder).changes.first)
        #expect(change.originalPath == "origem.txt")
        #expect(await LocalGit.diff(change, at: folder).contains("rename from origem.txt"))
        try "outro arquivo".write(to: original, atomically: true, encoding: .utf8)
        await #expect(throws: GitFailure.self) {
            try await LocalGit.discard(change, at: folder)
        }
        #expect(try String(contentsOf: original, encoding: .utf8) == "outro arquivo")
        try FileManager.default.removeItem(at: original)
        try await LocalGit.discard(change, at: folder)
        #expect(try await LocalGit.status(at: folder).changes.isEmpty)
        #expect(try String(contentsOf: original, encoding: .utf8) == "original")
    }

    @Test func mantémHookAnteriorDuranteEnvioERestauraAoDesligar() async throws {
        let folder = try await tempRepo()
        defer { try? FileManager.default.removeItem(at: folder) }
        let hook = try #require(await LocalGit.hookURL(at: folder))
        let script = "#!/bin/sh\ntouch rodou-hook-original\n"
        try script.write(to: hook, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o751], ofItemAtPath: hook.path)
        try await LocalGit.setAutoPush(false, at: folder)
        #expect(FileManager.default.isExecutableFile(atPath: hook.path))
        try await LocalGit.setAutoPush(true, at: folder)
        try await LocalGit.setAutoPush(true, at: folder)
        try await LocalGit.run(["commit", "--allow-empty", "-m", "com hook"], in: folder)
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("rodou-hook-original").path))
        try await LocalGit.setAutoPush(false, at: folder)
        #expect(try String(contentsOf: hook, encoding: .utf8) == script)
        #expect((try FileManager.default.attributesOfItem(atPath: hook.path)[.posixPermissions] as? Int) == 0o751)
    }

    @Test func projetoNovoJáNasceProtegido() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("arbor-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try "SENHA=1".write(to: folder.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
        try "x".write(to: folder.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        try await LocalGit.run(["init", "-q", "-b", "main"], in: folder)
        try await LocalGit.run(["config", "user.email", "teste@exemplo.com"], in: folder)
        try await LocalGit.run(["config", "user.name", "Teste"], in: folder)
        try LocalGit.writeProtection(at: folder, newProject: true)
        try await LocalGit.commitAll(at: folder, message: "primeira")
        let files = try await LocalGit.run(["ls-files"], in: folder)
        #expect(files.contains("index.html"))
        #expect(!files.contains(".env"))
    }

    @Test func listaPadrãoCobreOsSensíveis() {
        for name in [".env", "a.pem", "b.p12", "id_rsa", "client_secret.json", "chave.key"] {
            #expect(LocalGit.isSensitive(name))
        }
        #expect(LocalGit.protectionBlock.contains("*.p12"))
        #expect(LocalGit.protectionBlock.contains("!.env.example"))
    }
}
