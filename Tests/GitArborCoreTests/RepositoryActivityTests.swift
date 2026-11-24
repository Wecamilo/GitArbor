import Foundation
import Testing
@testable import GitArborCore

struct RepositoryActivityTests {
    @Test func estimaSessõesSemSomarIntervalosLongos() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let dates = [160, 0, 50, 40, 40].map { start.addingTimeInterval(Double($0) * 60) }
        #expect(GitHubClient.estimatedActivityMinutes(dates) == 80)
        #expect(GitHubClient.estimatedActivityMinutes([]) == 0)
        #expect(GitHubClient.estimatedActivityMinutes([start]) == 15)
    }

    @Test func somaPáginasESeparaProjetoVazioDeHistóricoIndisponível() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ActivityAPIStub.self]
        let client = GitHubClient(token: "teste", session: URLSession(configuration: config))
        let parser = ISO8601DateFormatter()
        let start = try #require(parser.date(from: "2026-11-01T00:00:00Z"))
        let end = try #require(parser.date(from: "2026-12-01T00:00:00Z"))

        let data = try await client.repositoryActivity(["org/app", "org/vazio", "org/indisponível"], from: start, through: end)

        #expect(data["org/app"] == RepositoryActivity(commits: 83, estimatedMinutes: 55))
        #expect(data["org/vazio"] == RepositoryActivity(commits: 0, estimatedMinutes: 0))
        #expect(data["org/indisponível"] == nil)
    }
}

private final class ActivityAPIStub: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        let bytes = request.httpBody ?? request.httpBodyStream.flatMap(read)
        let json = bytes.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        let variables = json?["variables"] as? [String: String] ?? [:]
        let query = json?["query"] as? String ?? ""
        let response: String
        if query.contains("viewer { id }") {
            response = #"{"data":{"viewer":{"id":"author1"}}}"#
        } else if variables["author"] == "author1", variables["owner0"] == "org", variables["name0"] == "app" {
            if variables["cursor0"] == "page-two" {
                response = #"{"data":{"repo0":{"defaultBranchRef":{"target":{"recent":{"nodes":[{"committedDate":"2026-11-02T10:00:00Z"}],"pageInfo":{"hasNextPage":false}}}}}}}"#
            } else {
                response = #"{"data":{"repo0":{"defaultBranchRef":{"target":{"total":{"totalCount":83},"recent":{"nodes":[{"committedDate":"2026-11-02T10:40:00Z"}],"pageInfo":{"hasNextPage":true,"endCursor":"page-two"}}}}},"repo1":{"defaultBranchRef":null},"repo2":null}}"#
            }
        } else {
            response = #"{"errors":[{"message":"Consulta inválida"}]}"#
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                            cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(response.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private func read(_ stream: InputStream) -> Data? {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 2048)
        while true {
            let length = stream.read(&buffer, maxLength: buffer.count)
            guard length >= 0 else { return nil }
            if length == 0 { return data }
            data.append(contentsOf: buffer.prefix(length))
        }
    }
}
