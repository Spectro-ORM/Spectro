import Foundation

public enum DatabaseError: LocalizedError {
    case alreadyExists(String)
    case insufficientPrivileges(String)
    case createFailed(String)
    case doesNotExist(String)
    case dropFailed(String)

    public var errorDescription: String? {
        switch self {
        case .alreadyExists(let database):
            return "Database \(database) already exists"
        case .insufficientPrivileges(let user):
            return "User \(user) does not have enough privileges"
        case .createFailed(let reason):
            return "Failed to create database: \(reason)"
        case .doesNotExist(let database):
            return "Database \(database) does not exist"
        case .dropFailed(let reason):
            return "Failed to drop database: \(reason)"
        }
    }
}
