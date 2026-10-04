import Foundation
import NIOSSL
import Testing
@testable import Spectro

@Suite("Database configuration")
struct DatabaseConfigurationTests {
    @Test("Invalid explicit TLS configuration is rejected instead of ignored")
    func invalidTLSConfiguration() async throws {
        var tls = TLSConfiguration.makeClientConfiguration()
        tls.trustRoots = .file("/nonexistent-spectro-ca-\(UUID().uuidString).pem")
        do {
            let connection = try DatabaseConnection(configuration: .init(
                username: "unused", password: "unused", database: "unused", numberOfThreads: 1,
                tlsConfiguration: tls
            ))
            await connection.shutdown()
            Issue.record("Expected invalid TLS trust roots to fail initialization")
        } catch {}
    }
}
