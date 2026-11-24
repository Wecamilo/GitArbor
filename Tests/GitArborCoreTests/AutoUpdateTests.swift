import Foundation
import Testing
@testable import GitArborCore

/// Servidor falso: devolve 200 com etiqueta na primeira vez e 304 quando recebe a etiqueta de volta.
final class FakeGitHub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var body = Data("[]".utf8)
    nonisolated(unsafe) static var etag = "\"v1\""
    nonisolated(unsafe) static var sentTags: [String?] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let sent = request.value(forHTTPHeaderField: "If-None-Match")
        Self.sentTags.append(sent)
        let notModified = sent == Self.etag
        let response = HTTPURLResponse(url: request.url!, statusCode: notModified ? 304 : 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["ETag": Self.etag, "X-Poll-Interval": "90"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !notModified { client?.urlProtocol(self, didLoad: Self.body) }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct ConditionalRequestTests {
    func makeClient() -> GitHubClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FakeGitHub.self]
        return GitHubClient(token: "teste", session: URLSession(configuration: config))
    }

    @Test func nadaMudouVoltaNilEUsaAEtiqueta() async throws {
        FakeGitHub.sentTags = []
        FakeGitHub.etag = "\"v1\""
        FakeGitHub.body = Data("[1]".utf8)
        let client = makeClient()
        let first = try await client.conditionalGet("notifications")
        #expect(first.changed)
        let raw1 = try await client.conditionalGet("notifications")
        #expect(raw1.changed == false)                       // segunda pergunta: 304
        #expect(raw1.data == FakeGitHub.body)                // usa a resposta guardada
        #expect(FakeGitHub.sentTags == [nil, "\"v1\""])
        #expect(await client.responses.pollInterval() == 90) // respeita o intervalo do GitHub
    }

    @Test func novidadeVoltaComOConteúdoNovo() async throws {
        FakeGitHub.sentTags = []
        FakeGitHub.etag = "\"a\""
        FakeGitHub.body = Data("[1]".utf8)
        let client = makeClient()
        let first: [Int]? = try await client.getIfChanged("user/events")
        #expect(first == [1])
        FakeGitHub.etag = "\"b\""
        FakeGitHub.body = Data("[1,2]".utf8)
        let second: [Int]? = try await client.getIfChanged("user/events")
        #expect(second == [1, 2])
        let third: [Int]? = try await client.getIfChanged("user/events")
        #expect(third == nil)
        let plain: [Int] = try await client.get("user/events")
        #expect(plain == [1, 2])                             // o get comum continua devolvendo tudo
    }
}

struct FolderWatcherTests {
    let root = URL(fileURLWithPath: "/tmp/Projetos")
    var repos: [URL] { [root.appendingPathComponent("App"), root.appendingPathComponent("Grupo/Site")] }

    func classify(_ relative: String) -> FolderWatcher.Change {
        FolderWatcher.classify(path: root.path + "/" + relative, root: root, repos: repos)
    }

    @Test func arquivoEditadoReleOProjeto() {
        #expect(classify("App/Sources/main.swift") == .repo(repos[0]))
        #expect(classify("Grupo/Site/index.html") == .repo(repos[1]))
    }

    @Test func commitEEnvioReleemOProjeto() {
        #expect(classify("App/.git/index") == .repo(repos[0]))
        #expect(classify("App/.git/HEAD") == .repo(repos[0]))
        #expect(classify("App/.git/refs/heads/main") == .repo(repos[0]))
        #expect(classify("App/.git/refs/remotes/origin/main") == .repo(repos[0]))
        #expect(classify("App/.git/auto-push.log") == .repo(repos[0]))
    }

    @Test func oQueAPrópriaLeituraMexeÉIgnorado() {
        #expect(classify("App/.git/index.lock") == .ignore)
        #expect(classify("App/.git/objects/ab/cdef") == .ignore)
        #expect(classify("App/.build/debug/App") == .ignore)
        #expect(classify("App/node_modules/x/index.js") == .ignore)
        #expect(classify("App/.DS_Store") == .ignore)
        #expect(FolderWatcher.classify(path: "/outro/lugar", root: root, repos: repos) == .ignore)
    }

    @Test func projetoNovoOuApagadoProcuraDeNovo() {
        #expect(classify("Novo/.git") == .rescan)
        #expect(classify("Grupo/Outro/.git") == .rescan)
        #expect(classify("App") == .rescan)               // a pasta do projeto foi apagada ou renomeada
        #expect(classify("App/.git") == .rescan)
        #expect(classify("Sumiu") == .rescan)             // não existe mais
        #expect(classify("SemGit/fundo/arquivo.txt") == .ignore)
    }

    @Test func índiceEscolheOProjetoAninhadoMaisEspecífico() {
        let nested = repos[0].appendingPathComponent("plugins/Extensão")
        let sibling = root.appendingPathComponent("AppTeste")
        let index = FolderWatcher.ProjectIndex(root: root, repos: repos + [nested, sibling, nested])
        let paths = [
            root.path + "/App/./plugins/Extensão/src/../readme.md",
            root.path + "/AppTeste/.git/index",
            root.path + "Vizinho/App/index.html",
            nested.path + "/.git/index.lock"
        ]
        #expect(paths.map(index.classify(path:)) == [.repo(nested), .repo(sibling), .ignore, .ignore])
    }

    @Test func índiceReconheceProjetoNaPrópriaRaiz() {
        let index = FolderWatcher.ProjectIndex(root: root, repos: [root])
        #expect(index.classify(path: root.path) == .repo(root))
        #expect(index.classify(path: root.path + "/.git") == .rescan)
        #expect(index.classify(path: root.path + "/node_modules/pacote/index.js") == .ignore)
    }

    @Test func avisaDeVerdadeQuandoUmArquivoMuda() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("arbor-watch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let (stream, continuation) = AsyncStream<[String]>.makeStream()
        let watcher = try #require(FolderWatcher(folder: folder, latency: 0.1) { continuation.yield($0) })
        defer { watcher.stop() }
        try await Task.sleep(for: .milliseconds(300))
        try "oi".write(to: folder.appendingPathComponent("nota.txt"), atomically: false, encoding: .utf8)
        let got = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await paths in stream where paths.contains(where: { $0.hasSuffix("nota.txt") }) { return true }
                return false
            }
            group.addTask { try? await Task.sleep(for: .seconds(5)); return false }
            let first = await group.next() ?? false
            group.cancelAll()
            continuation.finish()
            return first
        }
        #expect(got)
    }
}
