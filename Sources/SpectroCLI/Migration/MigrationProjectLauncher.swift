import Dispatch
import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

enum MigrationProjectLauncher {
    static func run(project: MigrationProject, arguments: [String]) async throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swift", "run", "--package-path", project.root.path, project.product] + arguments
        process.currentDirectoryURL = project.root
        process.environment = ProcessInfo.processInfo.environment
        process.standardInput = FileHandle.standardInput
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError

        // Foundation launches Process in its own process group on Darwin and Linux.
        // Keep signal handlers until termination so SwiftPM and its runner receive cancellation.
        // Caught dispositions reset on exec; SIG_IGN would be inherited by the
        // Linux child and make forwarded termination signals ineffective.
        let oldINT = signal(SIGINT) { _ in }
        let oldTERM = signal(SIGTERM) { _ in }
        let queue = DispatchQueue(label: "spectro.migration-signals")
        let sources = [SIGINT, SIGTERM].map { number -> any DispatchSourceSignal in
            let source = DispatchSource.makeSignalSource(signal: number, queue: queue)
            source.setEventHandler {
                if process.isRunning { kill(-process.processIdentifier, number) }
            }
            source.resume()
            return source
        }
        defer {
            for source in sources { source.cancel() }
            signal(SIGINT, oldINT)
            signal(SIGTERM, oldTERM)
        }
        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { child in
                let status = child.terminationReason == .uncaughtSignal ? 128 + child.terminationStatus : child.terminationStatus
                continuation.resume(returning: status)
            }
            do {
                // Swift's Linux worker threads block signals. Foundation Process
                // inherits that mask; a child spawned here must receive normal signals.
                var emptyMask = sigset_t()
                var previousMask = sigset_t()
                sigemptyset(&emptyMask)
                pthread_sigmask(SIG_SETMASK, &emptyMask, &previousMask)
                defer { pthread_sigmask(SIG_SETMASK, &previousMask, nil) }
                try process.run()
            }
            catch { continuation.resume(throwing: error) }
        }
    }
}
