import Testing
@testable import GitArborCore

struct RepoIconTests {
    @Test func preferIconeDoAppAosOutros() {
        let paths = ["Installer/Resources/installer-icon.png", "Resources/AppIcon-artwork.png",
                     "Resources/AppIcon-selected.svg", "Resources/AppIcon.icns", "Resources/AppIcon64.png",
                     "Tests/Reports/appearance-1.0.6-dark.png"]
        #expect(RepoIcon.bestCandidate(in: paths) == "Resources/AppIcon.icns")
        #expect(RepoIcon.bestCandidate(in: ["Resources/AppIcon-1024.png", "Resources/AppIcon.icns"]) == "Resources/AppIcon.icns")
        #expect(RepoIcon.bestCandidate(in: ["assets/AppIcon-claro.png", "assets/AppIcon.png"]) == "assets/AppIcon.png")
    }

    @Test func pegaOMaiorDoConjuntoDeIcones() {
        let paths = ["App/Assets.xcassets/AppIcon.appiconset/icon_16x16.png",
                     "App/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png",
                     "App/Assets.xcassets/AppIcon.appiconset/icon_256x256.png"]
        #expect(RepoIcon.bestCandidate(in: paths) == "App/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png")
    }

    @Test func usaIconeDeSiteQuandoNaoHaApp() {
        #expect(RepoIcon.bestCandidate(in: ["public/apple-touch-icon.png", "public/favicon.ico", "public/favicon.svg"])
                == "public/apple-touch-icon.png")
        #expect(RepoIcon.bestCandidate(in: ["public_html/favicon.ico", "public_html/favicon_16.png", "public_html/favicon_32.png",
                                            "public_html/assets/brands/amazon-logo-official.svg"]) == "public_html/favicon.ico")
        #expect(RepoIcon.bestCandidate(in: ["public/favicon.ico", "src/main.js"]) == "public/favicon.ico")
    }

    @Test func ignoraImagensQueNaoSaoDoProjeto() {
        #expect(RepoIcon.bestCandidate(in: ["reels/imagens/logo.png", "README.md"]) == nil)
        #expect(RepoIcon.bestCandidate(in: ["node_modules/pkg/icon.png", "docs/logo.svg"]) == nil)
        #expect(RepoIcon.bestCandidate(in: ["main.py", "setup.cfg"]) == nil)
        #expect(RepoIcon.bestCandidate(in: ["samsung-tv/icon.png"]) == "samsung-tv/icon.png")
    }
}
