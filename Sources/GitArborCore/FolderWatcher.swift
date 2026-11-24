import CoreServices
import Foundation

/// Avisa quando algo muda dentro de uma pasta (FSEvents do macOS): o app não precisa ficar perguntando.
public final class FolderWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let handler: @Sendable ([String]) -> Void
    private let queue = DispatchQueue(label: "GitArbor.FolderWatcher")

    /// `latency`: o macOS junta as mudanças desse intervalo num aviso só.
    public init?(folder: URL, latency: TimeInterval = 0.8, handler: @escaping @Sendable ([String]) -> Void) {
        self.handler = handler
        var context = FSEventStreamContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)
        context.info = Unmanaged.passUnretained(self).toOpaque()
        let callback: FSEventStreamCallback = { _, info, _, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            let list = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as? [String] ?? []
            watcher.handler(list)
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot)
        guard let created = FSEventStreamCreate(nil, callback, &context, [folder.path] as CFArray,
                                                FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags) else { return nil }
        stream = created
        FSEventStreamSetDispatchQueue(created, queue)
        guard FSEventStreamStart(created) else {
            stop()
            return nil
        }
    }

    public func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit { stop() }

    // MARK: O que fazer com cada mudança

    public enum Change: Equatable, Sendable {
        /// Nada a fazer (arquivos internos do Git que a própria leitura mexe, pastas de compilação…).
        case ignore
        /// Reler a situação deste projeto.
        case repo(URL)
        /// Procurar os projetos de novo (pasta nova, apagada ou renomeada).
        case rescan
    }

    /// Arquivos dentro de `.git` que mudam a situação mostrada (ramo, envio, último commit).
    static let relevantGitPaths = ["HEAD", "ORIG_HEAD", "FETCH_HEAD", "packed-refs", "config", "index", "auto-push.log", "refs", "hooks"]
    /// Pastas que mudam muito e não interessam (compilação, dependências).
    static let noisyFolders: Set<String> = [".build", "node_modules", "DerivedData", ".swiftpm", "__pycache__", ".venv"]

    /// Índice imutável de projetos. Procura pelos ancestrais do caminho, da pasta mais específica à raiz.
    public struct ProjectIndex: Sendable {
        private let root: String
        private let prefix: String
        private let projects: [String: URL]

        public init(root: URL, repos: [URL]) {
            let path = root.standardizedFileURL.path
            self.root = path
            self.prefix = path == "/" ? path : path + "/"
            self.projects = Dictionary(repos.map { ($0.standardizedFileURL.path, $0) },
                                       uniquingKeysWith: { first, _ in first })
        }

        public func classify(path: String) -> Change {
            let path = URL(fileURLWithPath: path).standardizedFileURL.path
            guard path == root || path.hasPrefix(prefix), (path as NSString).lastPathComponent != ".DS_Store" else { return .ignore }

            let match = containingProject(of: path)
            guard let match else {
                // Fora de qualquer projeto: só interessa um .git novo ou pastas até dois níveis
                // (onde os projetos ficam) que apareceram ou sumiram. Arquivos soltos não.
                let depth = path == root ? 0 : path.dropFirst(prefix.count).split(separator: "/").count
                if (path as NSString).lastPathComponent == ".git" { return depth <= 3 ? .rescan : .ignore }
                guard depth <= 2 else { return .ignore }
                var isDirectory: ObjCBool = false
                let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
                return !exists || isDirectory.boolValue ? .rescan : .ignore
            }
            if path == match.path { return path == root ? .repo(match.url) : .rescan }

            let inside = path.dropFirst(match.path == "/" ? 1 : match.path.count + 1).split(separator: "/")
            if inside.first == ".git" {
                guard inside.count > 1 else { return .rescan }   // a pasta .git sumiu ou apareceu
                let item = inside[1]
                if item.hasSuffix(".lock") { return .ignore }
                return FolderWatcher.relevantGitPaths.contains(String(item)) ? .repo(match.url) : .ignore
            }
            if inside.contains(where: { FolderWatcher.noisyFolders.contains(String($0)) }) { return .ignore }
            return .repo(match.url)
        }

        private func containingProject(of path: String) -> (path: String, url: URL)? {
            var candidate = path[...]
            while !candidate.isEmpty {
                if let url = projects[String(candidate)] { return (String(candidate), url) }
                guard candidate.count > root.count, let slash = candidate.lastIndex(of: "/") else { break }
                candidate = candidate[..<slash]
            }
            if root == "/", let url = projects[root] { return (root, url) }
            return nil
        }
    }

    public static func classify(path: String, root: URL, repos: [URL]) -> Change {
        ProjectIndex(root: root, repos: repos).classify(path: path)
    }
}
