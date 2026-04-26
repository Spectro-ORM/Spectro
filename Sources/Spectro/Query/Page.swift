import Foundation

/// A paginated result set returned by `Query<T>.page(size:page:)`.
public struct Page<T: Schema>: Sendable {
    /// The records on the current page.
    public let items: [T]
    /// Total matching records across all pages (from COUNT query).
    public let totalCount: Int
    /// Number of records per page as requested.
    public let pageSize: Int
    /// Current page number (1-based).
    public let pageNumber: Int

    public var totalPages: Int {
        totalCount == 0 ? 1 : Int(ceil(Double(totalCount) / Double(pageSize)))
    }
    public var hasNextPage: Bool { pageNumber < totalPages }
    public var hasPreviousPage: Bool { pageNumber > 1 }
}
