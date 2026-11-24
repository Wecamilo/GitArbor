import AppKit
import GitArborCore

/// Ícone de cada repositório para os cards. Procura primeiro na pasta do projeto neste Mac;
/// sem cópia local, pede ao GitHub a lista de arquivos e baixa só o ícone escolhido.
/// O resultado (inclusive "não tem ícone") fica em ~/Library/Caches/GitArbor/RepoIcons
/// e só é procurado de novo quando o repositório recebe código novo.
@Observable
final class RepoIconStore {
    private(set) var images: [String: NSImage] = [:]
    @ObservationIgnored private var stamps: [String: String] = [:]
    @ObservationIgnored private var inFlight: Set<String> = []
    @ObservationIgnored private lazy var manifest: [String: Entry] = Self.loadManifest()

    struct Entry: Codable { var stamp: String; var file: String? }

    /// Lado do PNG guardado (em pixels): nítido no card em telas Retina.
    nonisolated static let side = 128

    static var folder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/GitArbor/RepoIcons")
    }

    func image(for repo: GHRepo) -> NSImage? { images[repo.fullName.lowercased()] }

    func load(_ repo: GHRepo, client: GitHubClient?, localFolder: URL?) async {
        let key = repo.fullName.lowercased()
        let stamp = (localFolder.map { "local:" + $0.path } ?? "remote") + "|" + (repo.pushedAt?.ISO8601Format() ?? "-")
        guard stamps[key] != stamp, !inFlight.contains(key) else { return }
        inFlight.insert(key)
        defer { inFlight.remove(key) }

        // Já procurado antes com o mesmo estado: mostra o que ficou guardado. Do GitHub, isso basta;
        // da pasta local, confere de novo uma vez por sessão (o ícone pode ter mudado sem envio).
        if let entry = manifest[key], entry.stamp == stamp {
            images[key] = entry.file.flatMap { NSImage(contentsOf: Self.folder.appendingPathComponent($0)) }
            if localFolder == nil { stamps[key] = stamp; return }
        }

        let png: Data?
        if let localFolder {
            png = await Self.localIcon(in: localFolder)
        } else if let client {
            do { png = try await Self.remoteIcon(repo, client: client) } catch { return } // sem rede: tenta depois
        } else {
            return
        }

        stamps[key] = stamp
        var entry = Entry(stamp: stamp, file: nil)
        if let png {
            let file = key.replacingOccurrences(of: "/", with: "__") + ".png"
            try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
            try? png.write(to: Self.folder.appendingPathComponent(file), options: .atomic)
            entry.file = file
            images[key] = NSImage(data: png)
        } else {
            images[key] = nil
        }
        manifest[key] = entry
        saveManifest()
    }

    func clear() {
        images = [:]
        stamps = [:]
        manifest = [:]
        try? FileManager.default.removeItem(at: Self.folder)
    }

    // MARK: Fontes

    nonisolated private static func localIcon(in folder: URL) async -> Data? {
        guard let list = try? await LocalGit.run(["ls-files", "-z"], in: folder) else { return nil }
        let paths = list.split(separator: "\0").map(String.init)
        guard let best = RepoIcon.bestCandidate(in: paths) else { return nil }
        let url = folder.appendingPathComponent(best)
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= RepoIcon.maxBytes,
              let data = try? Data(contentsOf: url) else { return nil }
        return normalized(data)
    }

    nonisolated private static func remoteIcon(_ repo: GHRepo, client: GitHubClient) async throws -> Data? {
        let tree: GHTree
        do {
            tree = try await client.tree(repo.fullName, branch: repo.branch)
        } catch GitHubError.notFound {
            return nil // repositório vazio
        } catch GitHubError.invalid {
            return nil
        }
        let files = tree.tree.filter { $0.type == "blob" && ($0.size ?? 0) <= RepoIcon.maxBytes }
        guard let best = RepoIcon.bestCandidate(in: files.map(\.path)) else { return nil }
        let data = try await client.rawFile(repo.fullName, path: best, ref: repo.branch)
        return normalized(data)
    }

    /// Converte qualquer formato (icns, ico, svg…) num PNG quadrado de tamanho fixo.
    nonisolated static func normalized(_ data: Data) -> Data? {
        guard let image = NSImage(data: data), image.size.width > 0, image.size.height > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = NSSize(width: side, height: side)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        // Mantém a proporção, centralizado.
        let scale = CGFloat(side) / max(image.size.width, image.size.height)
        let w = image.size.width * scale, h = image.size.height * scale
        image.draw(in: NSRect(x: (CGFloat(side) - w) / 2, y: (CGFloat(side) - h) / 2, width: w, height: h),
                   from: .zero, operation: .copy, fraction: 1)
        context.flushGraphics()
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: Registro em disco

    private static var manifestURL: URL { folder.appendingPathComponent("manifest.json") }

    private static func loadManifest() -> [String: Entry] {
        (try? Data(contentsOf: manifestURL)).flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]
    }

    private func saveManifest() {
        guard let data = try? JSONEncoder().encode(manifest) else { return }
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        try? data.write(to: Self.manifestURL, options: .atomic)
    }
}
