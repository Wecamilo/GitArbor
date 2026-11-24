import Foundation
import Testing
@testable import GitArborCore

struct ProcessTests {
    /// Muitas execuções ao mesmo tempo: a saída tem que vir sempre inteira.
    @Test func saídaSempreCompleta() async throws {
        let expected = (1...3000).map(String.init).joined(separator: "\n") + "\n"
        var broken = 0
        await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<200 {
                group.addTask { (try? await LocalGit.runProcess("/usr/bin/seq", ["1", "3000"], in: nil)) == expected }
            }
            for await ok in group where !ok { broken += 1 }
        }
        #expect(broken == 0, "\(broken) de 200 saídas vieram incompletas")
    }

    @Test func statusSempreTemORamo() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("arbor-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try await LocalGit.run(["init", "-q", "-b", "main"], in: folder)
        var missing = 0
        await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<150 { group.addTask { (try? await LocalGit.status(at: folder))?.branch == "main" } }
            for await ok in group where !ok { missing += 1 }
        }
        #expect(missing == 0, "\(missing) de 150 leituras sem o ramo")
    }
}
