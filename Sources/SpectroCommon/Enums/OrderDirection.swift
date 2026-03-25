public enum OrderDirection: Sendable {
    case asc
    case desc

    public var sql: String {
        switch self {
        case .asc: return "ASC"
        case .desc: return "DESC"
        }
    }
}
