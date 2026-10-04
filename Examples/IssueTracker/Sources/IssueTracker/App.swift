import Foundation
import Peregrine
import PostgresNIO
import Spectro

@Schema("projects")
struct Project {
    @ID var id: UUID
    @Column var slug: String
    @Column("display_name") var name: String = ""
    @Timestamp var createdAt: Date
}

@Schema("issues")
struct Issue {
    @ID var id: UUID
    @ForeignKey var projectId: UUID
    @Column("display_name") var name: String = ""
    @Column var note: String?
    @Timestamp var createdAt: Date
}

struct IssueView: Codable, Sendable {
    let id: UUID
    let projectId: UUID
    let name: String
    let note: String?
    let createdAt: Date

    init(_ issue: Issue) {
        id = issue.id; projectId = issue.projectId; name = issue.name
        note = issue.note; createdAt = issue.createdAt
    }
}

struct ProjectView: Codable, Sendable {
    let id: UUID
    let slug: String
    let name: String
    let createdAt: Date
    let issue: IssueView?

    init(_ project: Project, issue: Issue? = nil) {
        id = project.id; slug = project.slug; name = project.name; createdAt = project.createdAt
        self.issue = issue.map(IssueView.init)
    }
}

/// Unwrap public errors to distinguish a known uniqueness conflict from a server failure.
private func isUniqueViolation(_ error: any Error) -> Bool {
    if case .server(let info) = error as? PostgresError {
        return info.fields[.sqlState] == "23505"
    }
    if let postgres = error as? PSQLError {
        return postgres.serverInfo?[.sqlState] == "23505"
    }
    if let spectro = error as? SpectroError {
        switch spectro {
        case .queryExecutionFailed(_, let cause), .transactionFailed(let cause):
            return isUniqueViolation(cause)
        default: break
        }
    }
    return false
}

@main
struct IssueTrackerApp: PeregrineApp {
    var database: Database? { .postgres() }

    @RouteBuilder var routes: [Route] {
        GET("/health") { conn in
            _ = try await conn.spectro.testConnection()
            return try conn.json(value: ["status": "ok"])
        }

        GET("/projects") { conn in
            let rows = try await conn.repo().query(Project.self)
                .leftJoinAndExecute(Issue.self, on: { $0.left.id == $0.right.projectId })
            return try conn.json(value: rows.map { ProjectView($0.0, issue: $0.1) })
        }

        POST("/projects") { conn in
            let input = try conn.decode(as: [String: String].self)
            let changeset = Changeset<Project>.cast(nil, params: input, permitted: ["slug", "name"])
                .validateRequired(["slug", "name"])
            guard changeset.isValid else {
                return try conn.json(status: .unprocessableContent, value: changeset.errors)
            }
            do {
                let result = try await conn.spectro.transaction { repo in
                    let project = try await repo.insert(changeset)
                    var issue: Issue?
                    if let title = input["firstIssue"] {
                        // Both records commit together; invalid issue data rolls back the project.
                        let changeset = Changeset<Issue>.cast(nil, params: [
                            "projectId": project.id, "name": title,
                        ], permitted: ["projectId", "name"]).validateRequired(["projectId", "name"])
                        issue = try await repo.insert(changeset)
                    }
                    return ProjectView(project, issue: issue)
                }
                return try conn.json(status: .created, value: result)
            } catch {
                if isUniqueViolation(error) {
                    return try conn.json(status: .conflict, value: ["error": "Project slug already exists"])
                }
                // Exercise Spectro's real error formatting, including wrapped transaction errors.
                return try conn.json(status: .internalServerError, value: ["error": error.localizedDescription])
            }
        }

        POST("/issues") { conn in
            let input = try conn.decode(as: [String: String].self)
            let changeset = Changeset<Issue>.cast(nil, params: input, permitted: ["projectId", "name", "note"])
                .validateRequired(["projectId", "name"])
            guard changeset.isValid else {
                return try conn.json(status: .unprocessableContent, value: changeset.errors)
            }
            let issue = try await conn.repo().insert(changeset)
            return try conn.json(status: .created, value: IssueView(issue))
        }
    }
}
