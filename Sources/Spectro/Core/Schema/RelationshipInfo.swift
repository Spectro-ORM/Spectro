public enum RelationType: Sendable {
    case hasMany
    case hasOne
    case belongsTo
    case manyToMany
}

public struct RelationshipInfo: Sendable {
    public let name: String
    public let relatedTypeName: String
    public let kind: RelationType
    public let foreignKey: String?

    // Many-to-many junction table metadata
    public let junctionTable: String?
    public let parentForeignKey: String?
    public let relatedForeignKey: String?

    public init(name: String, relatedTypeName: String, kind: RelationType, foreignKey: String?) {
        self.name = name
        self.relatedTypeName = relatedTypeName
        self.kind = kind
        self.foreignKey = foreignKey
        self.junctionTable = nil
        self.parentForeignKey = nil
        self.relatedForeignKey = nil
    }

    public init(
        name: String,
        relatedTypeName: String,
        kind: RelationType,
        foreignKey: String?,
        junctionTable: String,
        parentForeignKey: String,
        relatedForeignKey: String
    ) {
        self.name = name
        self.relatedTypeName = relatedTypeName
        self.kind = kind
        self.foreignKey = foreignKey
        self.junctionTable = junctionTable
        self.parentForeignKey = parentForeignKey
        self.relatedForeignKey = relatedForeignKey
    }
}
