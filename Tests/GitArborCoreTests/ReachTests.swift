import Foundation
import Testing
@testable import GitArborCore

struct ReachTests {
    private func day(_ key: String) -> Date { ReachHistory.date(key)! }

    @Test func lêVisitasDoGitHub() throws {
        let json = """
        {"count": 14, "uniques": 5, "views": [
          {"timestamp": "2026-11-10T00:00:00Z", "count": 4, "uniques": 2},
          {"timestamp": "2026-11-11T00:00:00Z", "count": 10, "uniques": 4}]}
        """
        let views = try GitHubClient.decoder.decode(GHTrafficViews.self, from: Data(json.utf8))
        #expect(views.count == 14)
        #expect(views.views.map(\.count) == [4, 10])
        #expect(ReachHistory.key(views.views[0].timestamp) == "2026-11-10")
    }

    @Test func juntaDiasSemPerderOsAntigos() {
        var h = ReachHistory()
        h.merge(views: [GHTrafficDay(timestamp: day("2026-11-01"), count: 3, uniques: 2)], clones: [])
        // Nova leitura: o dia 1 já saiu da janela de 14 dias do GitHub; o dia 15 cresceu.
        h.merge(views: [GHTrafficDay(timestamp: day("2026-11-15"), count: 5, uniques: 3)],
                clones: [GHTrafficDay(timestamp: day("2026-11-15"), count: 2, uniques: 1)])
        h.merge(views: [GHTrafficDay(timestamp: day("2026-11-15"), count: 8, uniques: 4)], clones: [])
        #expect(h.days["2026-11-01"]?.views == 3)
        #expect(h.days["2026-11-15"] == ReachDay(views: 8, viewUniques: 4, clones: 2, cloneUniques: 1))
        #expect(h.totalViews == 11)
        #expect(h.totalClones == 2)
        #expect(h.firstDay == day("2026-11-01"))
    }

    @Test func sérieContínuaComZeros() {
        var h = ReachHistory()
        h.merge(views: [GHTrafficDay(timestamp: day("2026-11-20"), count: 6, uniques: 2),
                        GHTrafficDay(timestamp: day("2026-11-22"), count: 1, uniques: 1)], clones: [])
        let s = h.series(lastDays: 30, until: day("2026-11-23").addingTimeInterval(3600))
        // Começa no primeiro dia guardado, não 30 dias antes.
        #expect(s.map { ReachHistory.key($0.date) } == ["2026-11-20", "2026-11-21", "2026-11-22", "2026-11-23"])
        #expect(s.map(\.day.views) == [6, 0, 1, 0])

        let curta = h.series(lastDays: 2, until: day("2026-11-23"))
        #expect(curta.map { ReachHistory.key($0.date) } == ["2026-11-22", "2026-11-23"])
    }

    @Test func somaDownloadsDeTodasAsVersões() throws {
        let json = """
        [{"id": 1, "tag_name": "v1.1.0", "name": null, "body": null, "draft": false, "prerelease": false,
          "html_url": "https://github.com/octocat/Hello-World/releases/v1.1.0",
          "assets": [{"id": 10, "name": "app.zip", "size": 100, "download_count": 7, "browser_download_url": null},
                     {"id": 11, "name": "app.zip.sha256", "size": 1, "download_count": 2, "browser_download_url": null}]},
         {"id": 2, "tag_name": "v1.0.0", "name": null, "body": null, "draft": false, "prerelease": false,
          "html_url": "https://github.com/octocat/Hello-World/releases/v1.0.0", "assets": []}]
        """
        let releases = try GitHubClient.decoder.decode([GHRelease].self, from: Data(json.utf8))
        #expect(Reach.totalDownloads(releases) == 9)
        #expect(Reach.totalDownloads([]) == 0)
    }

    @Test func nomesAmigáveis() {
        #expect(Reach.referrerName("github.com") == "GitHub")
        #expect(Reach.referrerName("Google") == "Google")
        #expect(Reach.referrerName("meublog.com.br") == "meublog.com.br")
        let p = GHPopularPath(path: "/octocat/Hello-World/blob/main/README.md", title: "README", count: 1, uniques: 1)
        #expect(p.shortPath(repoFullName: "octocat/Hello-World") == "blob/main/README.md")
        let home = GHPopularPath(path: "/octocat/Hello-World", title: "Hello-World", count: 1, uniques: 1)
        #expect(home.shortPath(repoFullName: "octocat/Hello-World") == "Página inicial")
    }
}
