import Foundation

/// Escolhe, entre os arquivos de um projeto, o que melhor serve de ícone:
/// o ícone do app (AppIcon.icns, AppIcon.appiconset), o ícone de site (apple-touch-icon, favicon)
/// ou um icon/logo na raiz. Sem candidato bom, o card mostra o ícone genérico.
public enum RepoIcon {
    /// Formatos que o macOS abre sozinho (NSImage).
    public static let extensions: Set<String> = ["icns", "png", "svg", "ico", "jpg", "jpeg", "webp"]

    /// Arquivos maiores que isso não são ícones (e não vale baixar).
    public static let maxBytes = 4 * 1024 * 1024

    /// Pastas que nunca guardam o ícone do próprio projeto.
    static let ignoredFolders: Set<String> = [
        "node_modules", "vendor", "pods", "carthage", ".build", "build", "dist", "deriveddata",
        "test", "tests", "spec", "specs", "__tests__", "fixtures", "reports", "docs", "doc",
        "examples", "example", "samples", "brands", "third_party", "thirdparty", "installer"
    ]

    /// Pastas onde um "logo" ou "icon" genérico costuma ser do próprio projeto.
    static let usualFolders: Set<String> = [
        "resources", "assets", "public", "static", "public_html", "www", "web", "images", "img",
        "icons", "icon", "artwork", "branding", "media", "res", "src", "app"
    ]

    /// O melhor caminho para usar como ícone, ou nil quando nada serve.
    public static func bestCandidate(in paths: [String]) -> String? {
        var best: (path: String, score: Int)?
        for path in paths {
            guard let s = score(path) else { continue }
            // Maior pontuação vence; no empate, o caminho mais curto.
            if let b = best, s < b.score || (s == b.score && path.count >= b.path.count) { continue }
            best = (path, s)
        }
        return best?.path
    }

    /// Pontuação do caminho como ícone; nil quando não é candidato.
    public static func score(_ path: String) -> Int? {
        let parts = path.split(separator: "/").map(String.init)
        guard let file = parts.last else { return nil }
        let folders = parts.dropLast().map { $0.lowercased() }
        let ext = (file as NSString).pathExtension.lowercased()
        guard extensions.contains(ext) else { return nil }
        if folders.contains(where: { ignoredFolders.contains($0) || $0.hasPrefix(".") }) { return nil }
        let name = (file as NSString).deletingPathExtension.lowercased()
        let depth = folders.count
        let inIconSet = folders.last.map { $0.hasSuffix(".appiconset") || $0.hasSuffix(".iconset") } ?? false
        let inUsualFolder = folders.allSatisfy { usualFolders.contains($0) || $0.hasSuffix(".xcassets") || $0.hasSuffix(".appiconset") || $0.hasSuffix(".iconset") }

        var base: Int
        if inIconSet {
            // Dentro de um conjunto de ícones, o maior tamanho vence.
            base = 700 + min(pixelSize(in: name), 1024) / 8
        } else if name.hasPrefix("appicon") {
            base = ext == "icns" ? 1000 : 900
            if name.contains("1024") || name.contains("512") { base += 50 }
            // Variações (claro, escuro, selecionado, arte-fonte) perdem para a principal.
            if name != "appicon" && !name.hasPrefix("appicon-1024") && !name.hasPrefix("appicon_1024") { base -= 60 }
        } else if ext == "icns" {
            base = 750
        } else if name.hasPrefix("apple-touch-icon") {
            base = 600
        } else if name == "icon" || name == "app-icon" || name == "app_icon" {
            guard depth <= 2 else { return nil }
            base = 550
        } else if name == "logo" {
            guard inUsualFolder, depth <= 3 else { return nil }
            base = 500
        } else if name.hasPrefix("favicon") {
            base = 400
            if ext == "svg" { base += 40 } else if ext == "ico" { base += 20 }
            let size = pixelSize(in: name)
            if size > 0 { base += min(size, 512) / 16 - 4 }
        } else if name.hasPrefix("android-chrome") || name.hasPrefix("mstile") {
            base = 380
        } else {
            return nil
        }
        // Ícones rasos ganham dos enterrados em subpastas.
        return base - depth * 15 + (ext == "svg" || ext == "icns" ? 5 : 0)
    }

    /// Maior número do nome (ex.: "icon_512x512@2x" → 1024, "favicon_32" → 32).
    static func pixelSize(in name: String) -> Int {
        let numbers = name.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard var size = numbers.filter({ $0 >= 16 && $0 <= 2048 }).max() else { return 0 }
        if name.contains("@2x") { size *= 2 } else if name.contains("@3x") { size *= 3 }
        return size
    }
}

public struct GHTree: Decodable, Sendable {
    public struct Item: Decodable, Sendable {
        public let path: String
        public let type: String
        public let size: Int?
    }
    public let tree: [Item]
    public let truncated: Bool?
}

extension GitHubClient {
    /// Todos os arquivos do ramo (um pedido só).
    public func tree(_ fullName: String, branch: String) async throws -> GHTree {
        let ref = branch.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? branch
        return try await get("repos/\(fullName)/git/trees/\(ref)", query: ["recursive": "1"])
    }

    /// Conteúdo bruto de um arquivo (binário).
    public func rawFile(_ fullName: String, path: String, ref: String?) async throws -> Data {
        let (data, _) = try await send(request("GET", "repos/\(fullName)/contents/\(path)",
                                               query: ref.map { ["ref": $0] } ?? [:],
                                               accept: "application/vnd.github.raw+json"))
        return data
    }
}
