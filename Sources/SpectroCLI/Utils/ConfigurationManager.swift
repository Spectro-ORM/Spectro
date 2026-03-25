import Foundation

public actor ConfigurationManager {
    public static let shared = ConfigurationManager()
    private var envVars: [String: String] = [:]
    private init() {}

    // Sendable so it can cross actor boundaries in async CLI commands
    public struct DatabaseConfig: Sendable {
        public let hostname: String
        public let port: Int
        public let username: String
        public let password: String
        public let database: String
    }

    public func loadEnvFile() throws {
        let envPath = FileManager.default.currentDirectoryPath + "/.env"
        guard FileManager.default.fileExists(atPath: envPath) else { return }
        let contents = try String(contentsOfFile: envPath, encoding: .utf8)
        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty && !trimmed.hasPrefix("#") else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            envVars[key] = value
        }
    }

    public func getDatabaseConfig(overrides: [String: String] = [:]) -> DatabaseConfig {
        let env = ProcessInfo.processInfo.environment
        return DatabaseConfig(
            hostname: overrides["hostname"] ?? envVars["DB_HOST"] ?? env["DB_HOST"] ?? "localhost",
            port:     Int(overrides["port"] ?? envVars["DB_PORT"] ?? env["DB_PORT"] ?? "5432") ?? 5432,
            username: overrides["username"] ?? envVars["DB_USER"] ?? env["DB_USER"] ?? "postgres",
            password: overrides["password"] ?? envVars["DB_PASSWORD"] ?? env["DB_PASSWORD"] ?? "",
            database: overrides["database"] ?? envVars["DB_NAME"] ?? env["DB_NAME"] ?? "postgres"
        )
    }
}
