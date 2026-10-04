import Foundation
import Testing
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

@Suite("Swift migration CLI", .serialized)
struct SwiftMigrationCLITests {
    private struct Result { let code: Int32; let output: String }
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("spectro project \(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "// Keep this manifest unchanged.\n".write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        return root
    }
    private func run(_ arguments: [String], at root: URL, env: [String: String] = [:]) async throws -> Result {
        let binary = ProcessInfo.processInfo.environment["SPECTRO_CLI_PATH"]
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/debug/spectro").path
        let output = root.appendingPathComponent("output-\(UUID()).txt")
        FileManager.default.createFile(atPath: output.path, contents: nil)
        let handle = try FileHandle(forWritingTo: output)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments
        process.currentDirectoryURL = root
        process.standardOutput = handle
        process.standardError = handle
        process.environment = ProcessInfo.processInfo.environment.merging(env) { _, new in new }
        try process.run()
        try handle.close()
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while process.isRunning, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
            while process.isRunning { try await Task.sleep(for: .milliseconds(10)) }
            Issue.record("CLI timed out")
        }
        return Result(code: process.terminationStatus, output: try String(contentsOf: output, encoding: .utf8))
    }
    private func descriptor(_ root: URL, product: String = "AppMigrations", directory: String = "Sources/AppMigrations", version: Int = 1) throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "formatVersion": version, "migrations": ["product": product, "sourceDirectory": directory]
        ])
        try data.write(to: root.appendingPathComponent(".spectro.json"))
    }

    @Test("Init and generation are offline and leave the manifest intact")
    func initialize() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let initialized = try await run(["migrate", "init", "--target", "AppMigrations"], at: root, env: ["DB_PORT": "invalid"])
        #expect(initialized.code == 0, "\(initialized.output)")
        #expect(initialized.output.contains(".executableTarget("))
        #expect(initialized.output.contains("SpectroMigrations"))
        let manifest = try String(contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8)
        #expect(manifest == "// Keep this manifest unchanged.\n")
        let entry = try String(contentsOf: root.appendingPathComponent("Sources/AppMigrations/EntryPoint.swift"), encoding: .utf8)
        #expect(entry.contains("@main"))
        let generated = try await run(["generate", "migration", "CreateHTTPEvents"], at: root, env: ["DB_PORT": "invalid"])
        #expect(generated.code == 0, "\(generated.output)")
        #expect(generated.output.contains("CreateHTTPEvents()"))
        let file = root.appendingPathComponent("Sources/AppMigrations/Migrations/CreateHTTPEvents.swift")
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text.contains("_create_http_events"))
        #expect(text.contains("var change: MigrationPlan"))
        let again = try await run(["generate", "migration", "CreateHTTPEvents"], at: root)
        #expect(again.code != 0)
        #expect(try String(contentsOf: file, encoding: .utf8) == text)
        let repeated = try await run(["migrate", "init", "--target", "OtherMigrations"], at: root)
        #expect(repeated.code != 0)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources/OtherMigrations").path))
    }

    @Test("Init preflights conflicts and rejects invalid target names")
    func conflicts() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Sources/AppMigrations")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try "User content".write(to: source.appendingPathComponent("EntryPoint.swift"), atomically: true, encoding: .utf8)
        let result = try await run(["migrate", "init", "--target", "AppMigrations"], at: root)
        #expect(result.code != 0)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(".spectro.json").path))
        for name in ["../Escape", "bad-name", "Self"] {
            let invalid = try await run(["migrate", "init", "--target", name], at: root)
            #expect(invalid.code != 0)
        }
    }

    @Test("Malformed descriptors fail closed", arguments: [
        "{", #"{"formatVersion":2,"migrations":{"product":"App","sourceDirectory":"Sources/App"}}"#,
        #"{"formatVersion":1,"migrations":{"sourceDirectory":"Sources/App"}}"#,
        #"{"formatVersion":1,"migrations":{"product":"-bad","sourceDirectory":"Sources/App"}}"#,
        #"{"formatVersion":1,"migrations":{"product":"App","sourceDirectory":"../outside"}}"#
    ])
    func malformed(json: String) async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try json.write(to: root.appendingPathComponent(".spectro.json"), atomically: true, encoding: .utf8)
        let result = try await run(["generate", "migration", "CreateUsers"], at: root)
        #expect(result.code != 0)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources/Migrations").path))
    }

    @Test("Source symlinks cannot escape the package")
    func escapingSymlink() async throws {
        let root = try fixture(), outside = try fixture()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Sources"), withDestinationURL: outside)
        try descriptor(root)
        let result = try await run(["generate", "migration", "CreateUsers"], at: root)
        #expect(result.code != 0)
        #expect(!FileManager.default.fileExists(atPath: outside.appendingPathComponent("AppMigrations").path))
    }

    @Test("Launcher forwards argv, environment, root, project output and exit status")
    func launch() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let bin = root.appendingPathComponent("tools")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let stub = bin.appendingPathComponent("swift")
        try """
            #!/bin/sh
            printf '%s\\n' "$@" > "$SPECTRO_ARGV_FILE"
            printf '%s\\n' "$SPECTRO_STUB_OUTPUT"
            exit "$SPECTRO_STUB_EXIT"
            """.write(to: stub, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stub.path)
        let nested = root.appendingPathComponent("nested folder")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let argsFile = root.appendingPathComponent("argv")
        for product in ["AlphaMigrations", "BetaMigrations"] {
            try descriptor(root, product: product)
            let env = ["PATH": bin.path, "DB_PORT": "invalid", "SPECTRO_ARGV_FILE": argsFile.path,
                       "SPECTRO_STUB_OUTPUT": product + " runtime plan", "SPECTRO_STUB_EXIT": "0"]
            let result = try await run(["migrate", "plan", "--direction", "down", "--migration", "1700000001_example"], at: nested, env: env)
            #expect(result.code == 0, "\(result.output)")
            #expect(result.output.contains(product + " runtime plan"))
            let args = try String(contentsOf: argsFile, encoding: .utf8).split(separator: "\n").map(String.init)
            #expect(args == ["run", "--package-path", root.resolvingSymlinksInPath().path, product, "plan",
                             "--direction", "down", "--migration", "1700000001_example"])
            let failed = try await run(["migrate", "up"], at: nested,
                env: env.merging(["SPECTRO_STUB_EXIT": "23"]) { _, new in new })
            #expect(failed.code == 23)
        }
        try "// nested package".write(to: nested.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        let bounded = try await run(["migrate", "plan"], at: nested)
        #expect(bounded.code != 0)
        #expect(!bounded.output.contains("BetaMigrations runtime plan"))
    }
    @Test("SIGINT and SIGTERM reach and reap the launched process", arguments: [SIGINT, SIGTERM])
    func signals(number: Int32) async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try descriptor(root)
        let tools = root.appendingPathComponent("tools")
        try FileManager.default.createDirectory(at: tools, withIntermediateDirectories: true)
        let stub = tools.appendingPathComponent("swift")
        try """
            #!/bin/sh
            printf '%s' "$$" > "$SPECTRO_PID_FILE"
            exec /bin/sleep 30
            """.write(to: stub, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stub.path)
        let pidFile = root.appendingPathComponent("pid")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["SPECTRO_CLI_PATH"]))
        process.arguments = ["migrate", "up"]
        process.currentDirectoryURL = root
        process.environment = ProcessInfo.processInfo.environment.merging(
            ["PATH": tools.path, "SPECTRO_PID_FILE": pidFile.path]) { _, new in new }
        try process.run()
        let startedDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !FileManager.default.fileExists(atPath: pidFile.path), ContinuousClock.now < startedDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let pidText = try String(contentsOf: pidFile, encoding: .utf8)
        let child = try #require(Int32(pidText))
        #expect(getpgid(child) == child)
        kill(process.processIdentifier, number)
        let endedDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        while process.isRunning, ContinuousClock.now < endedDeadline { try await Task.sleep(for: .milliseconds(20)) }
        if process.isRunning {
            kill(child, SIGKILL)
            kill(process.processIdentifier, SIGKILL)
            Issue.record("Signal did not terminate the child")
            while process.isRunning { try await Task.sleep(for: .milliseconds(10)) }
        }
        #expect(process.terminationStatus == 128 + number)
        #expect(kill(child, 0) == -1)
    }

}

