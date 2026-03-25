import SwiftSyntax
import SwiftSyntaxMacros
import SwiftDiagnostics

public struct SchemaMacro {}

// MARK: - Property Analysis

private enum WrapperKind {
    case id, column, timestamp, foreignKey, hasMany, hasOne, belongsTo, manyToMany
}

private struct PropertyInfo {
    let name: String
    let typeName: String      // Base type (e.g. "String" even for String?)
    let fullType: String       // Full type as written (e.g. "String?")
    let isOptional: Bool
    let wrapper: WrapperKind
    let hasExplicitDefault: Bool
    let explicitDefault: String?
    let hasWrapperArguments: Bool  // Whether the @Wrapper has arguments, e.g. @ManyToMany(junctionTable: ...)
    let columnName: String?        // from @Column("custom_name") — overrides snake_case convention
    let foreignKeyOverride: String? // from @HasMany(foreignKey: "col") / @HasOne / @BelongsTo
}

private let columnAttributeNames: Set<String> = ["ID", "Column", "Timestamp", "ForeignKey"]

private func toSnakeCase(_ input: String) -> String {
    var result = ""
    for (i, char) in input.enumerated() {
        if char.isUppercase && i > 0 {
            result += "_"
        }
        result += char.lowercased()
    }
    return result
}

private func classifyWrapper(_ attrNames: [String]) -> WrapperKind? {
    if attrNames.contains("ID") { return .id }
    if attrNames.contains("Column") { return .column }
    if attrNames.contains("Timestamp") { return .timestamp }
    if attrNames.contains("ForeignKey") { return .foreignKey }
    if attrNames.contains("HasMany") { return .hasMany }
    if attrNames.contains("HasOne") { return .hasOne }
    if attrNames.contains("BelongsTo") { return .belongsTo }
    if attrNames.contains("ManyToMany") { return .manyToMany }
    return nil
}

/// Map a WrapperKind back to its attribute name string.
private func wrapperAttributeName(_ kind: WrapperKind) -> String {
    switch kind {
    case .id:         return "ID"
    case .column:     return "Column"
    case .timestamp:  return "Timestamp"
    case .foreignKey: return "ForeignKey"
    case .hasMany:    return "HasMany"
    case .hasOne:     return "HasOne"
    case .belongsTo:  return "BelongsTo"
    case .manyToMany: return "ManyToMany"
    }
}

/// Extract a string literal from the first unlabeled argument of an attribute.
/// E.g. `@Column("display_name")` → `"display_name"`
private func extractUnlabeledStringArg(from attr: AttributeSyntax) -> String? {
    guard let arguments = attr.arguments?.as(LabeledExprListSyntax.self),
          let firstArg = arguments.first,
          firstArg.label == nil,
          let stringLiteral = firstArg.expression.as(StringLiteralExprSyntax.self),
          let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self)
    else { return nil }
    return segment.content.text
}

/// Extract a string literal from a labeled argument of an attribute.
/// E.g. `@HasMany(foreignKey: "author_id")` with label `"foreignKey"` → `"author_id"`
private func extractLabeledStringArg(from attr: AttributeSyntax, label: String) -> String? {
    guard let arguments = attr.arguments?.as(LabeledExprListSyntax.self) else { return nil }
    for arg in arguments {
        if arg.label?.text == label,
           let stringLiteral = arg.expression.as(StringLiteralExprSyntax.self),
           let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) {
            return segment.content.text
        }
    }
    return nil
}

private func collectProperties(from structDecl: StructDeclSyntax) -> [PropertyInfo] {
    structDecl.memberBlock.members.compactMap { member in
        guard let varDecl = member.decl.as(VariableDeclSyntax.self),
              varDecl.bindingSpecifier.text == "var",
              let binding = varDecl.bindings.first,
              let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
              let typeAnnotation = binding.typeAnnotation?.type
        else { return nil }

        let attrs: [AttributeSyntax] = varDecl.attributes.compactMap {
            $0.as(AttributeSyntax.self)
        }
        let attrNames: [String] = attrs.compactMap {
            $0.attributeName.as(IdentifierTypeSyntax.self)?.name.text
        }

        guard let wrapper = classifyWrapper(attrNames) else { return nil }

        // Find the primary wrapper attribute node for argument extraction
        let wrapperAttr = attrs.first { attr in
            guard let name = attr.attributeName.as(IdentifierTypeSyntax.self)?.name.text else { return false }
            return classifyWrapper([name]) == wrapper
        }

        // Check if the wrapper attribute has explicit arguments (e.g. @ManyToMany(junctionTable: ...))
        let hasWrapperArgs = wrapperAttr?.arguments != nil

        // Extract @Column("custom_name") — first unlabeled string argument
        var columnName: String? = nil
        if wrapper == .column, let attr = wrapperAttr {
            columnName = extractUnlabeledStringArg(from: attr)
        }

        // Extract foreignKey override from @HasMany(foreignKey:), @HasOne(foreignKey:), @BelongsTo(foreignKey:)
        var foreignKeyOverride: String? = nil
        if (wrapper == .hasMany || wrapper == .hasOne || wrapper == .belongsTo),
           let attr = wrapperAttr {
            foreignKeyOverride = extractLabeledStringArg(from: attr, label: "foreignKey")
        }

        let isOptional = typeAnnotation.is(OptionalTypeSyntax.self)
        let baseType: String
        if let opt = typeAnnotation.as(OptionalTypeSyntax.self) {
            baseType = opt.wrappedType.trimmedDescription
        } else {
            baseType = typeAnnotation.trimmedDescription
        }

        return PropertyInfo(
            name: pattern.identifier.text,
            typeName: baseType,
            fullType: typeAnnotation.trimmedDescription,
            isOptional: isOptional,
            wrapper: wrapper,
            hasExplicitDefault: binding.initializer != nil,
            explicitDefault: binding.initializer?.value.trimmedDescription,
            hasWrapperArguments: hasWrapperArgs,
            columnName: columnName,
            foreignKeyOverride: foreignKeyOverride
        )
    }
}

private func extractTableName(from node: AttributeSyntax) -> String? {
    guard let arguments = node.arguments?.as(LabeledExprListSyntax.self),
          let firstArg = arguments.first,
          let stringLiteral = firstArg.expression.as(StringLiteralExprSyntax.self),
          let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self)
    else { return nil }
    return segment.content.text
}

private func defaultValueExpression(for prop: PropertyInfo) -> String {
    if prop.isOptional { return "nil" }
    switch prop.wrapper {
    case .id, .foreignKey:
        switch prop.typeName {
        case "UUID":   return "UUID()"
        case "Int":    return "0"
        case "String": return "\"\""
        default:       return "\(prop.typeName)()"
        }
    case .timestamp:           return "Date()"
    case .hasMany, .manyToMany: return "[]"
    case .hasOne, .belongsTo:   return "nil"
    case .column:
        switch prop.typeName {
        case "String": return "\"\""
        case "Int":    return "0"
        case "Bool":   return "false"
        case "Double": return "0.0"
        case "Float":  return "0.0"
        case "Date":   return "Date()"
        case "UUID":   return "UUID()"
        default:       return "\(prop.typeName)()"
        }
    }
}

// MARK: - Existing-member Detection

private struct ExistingMembers {
    var hasTableName = false
    var hasDefaultInit = false
}

private func detectExisting(in structDecl: StructDeclSyntax) -> ExistingMembers {
    var result = ExistingMembers()
    for member in structDecl.memberBlock.members {
        if let varDecl = member.decl.as(VariableDeclSyntax.self),
           let binding = varDecl.bindings.first,
           let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
           pattern.identifier.text == "tableName" {
            result.hasTableName = true
        }
        if let initDecl = member.decl.as(InitializerDeclSyntax.self),
           initDecl.signature.parameterClause.parameters.isEmpty {
            result.hasDefaultInit = true
        }
    }
    return result
}

// MARK: - MemberMacro

extension SchemaMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            context.diagnose(Diagnostic(node: node, message: SchemaDiagnostic.onlyStructs))
            return []
        }

        guard let tableName = extractTableName(from: node) else {
            context.diagnose(Diagnostic(node: node, message: SchemaDiagnostic.missingTableName))
            return []
        }

        let properties = collectProperties(from: structDecl)

        guard properties.contains(where: { $0.wrapper == .id }) else {
            context.diagnose(Diagnostic(node: node, message: SchemaDiagnostic.missingID))
            return []
        }

        let existing = detectExisting(in: structDecl)
        var decls: [DeclSyntax] = []

        // --- static let tableName ---
        if !existing.hasTableName {
            decls.append("static let tableName = \"\(raw: tableName)\"")
        }

        // --- init() ---
        if !existing.hasDefaultInit {
            // Skip @ManyToMany properties with wrapper arguments — they get their
            // default from the wrapper declaration (e.g. @ManyToMany(junctionTable: ...))
            // so we must not overwrite them with `self.tags = []`.
            let initProps = properties.filter {
                !($0.wrapper == .manyToMany && $0.hasWrapperArguments)
            }
            let assignments = initProps.map { prop in
                if let explicit = prop.explicitDefault, prop.hasExplicitDefault {
                    return "self.\(prop.name) = \(explicit)"
                }
                return "self.\(prop.name) = \(defaultValueExpression(for: prop))"
            }
            let body = assignments.joined(separator: "\n        ")
            let initDecl: DeclSyntax = """
            init() {
                    \(raw: body)
                }
            """
            decls.append(initDecl)
        }

        // --- convenience init(column params...) ---
        // Exclude @Column properties with a columnName override — they are mapped
        // to a custom DB column and should keep their default value, not be init params.
        let columnProps = properties.filter {
            ($0.wrapper == .column || $0.wrapper == .foreignKey) && $0.columnName == nil
        }
        if !columnProps.isEmpty {
            var params: [String] = []
            for prop in columnProps {
                if prop.isOptional {
                    params.append("\(prop.name): \(prop.fullType) = nil")
                } else {
                    params.append("\(prop.name): \(prop.typeName)")
                }
            }

            // Skip @ManyToMany properties with wrapper arguments in convenience init too —
            // they get their default from the wrapper declaration.
            let convInitProps = properties.filter {
                !($0.wrapper == .manyToMany && $0.hasWrapperArguments)
            }
            let assignments = convInitProps.map { prop in
                // @Column properties with columnName override are not init parameters,
                // so they get a default value instead of being assigned from a parameter.
                if prop.wrapper == .column && prop.columnName != nil {
                    return "self.\(prop.name) = \(defaultValueExpression(for: prop))"
                }
                switch prop.wrapper {
                case .id:                  return "self.\(prop.name) = \(defaultValueExpression(for: prop))"
                case .timestamp:           return "self.\(prop.name) = Date()"
                case .column, .foreignKey: return "self.\(prop.name) = \(prop.name)"
                case .hasMany, .manyToMany: return "self.\(prop.name) = []"
                case .hasOne, .belongsTo:   return "self.\(prop.name) = nil"
                }
            }

            let paramStr = params.joined(separator: ", ")
            let body = assignments.joined(separator: "\n        ")
            let convInit: DeclSyntax = """
            init(\(raw: paramStr)) {
                    \(raw: body)
                }
            """
            decls.append(convInit)
        }

        // --- static let _keyPathToColumn ---
        let typeName = structDecl.name.text
        var entries: [String] = []
        for prop in properties {
            switch prop.wrapper {
            case .id, .column, .timestamp, .foreignKey:
                entries.append("\\\(typeName).\(prop.name): \"\(prop.name)\"")
            case .hasMany, .hasOne, .belongsTo, .manyToMany:
                entries.append("\\\(typeName).$\(prop.name): \"\(prop.name)\"")
            }
        }
        let entriesStr = entries.joined(separator: ",\n            ")
        let keyPathDecl: DeclSyntax = """
        nonisolated(unsafe) static let _keyPathToColumn: [AnyKeyPath: String] = [
                \(raw: entriesStr)
            ]
        """
        decls.append(keyPathDecl)

        return decls
    }
}

// MARK: - ExtensionMacro

extension SchemaMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else { return [] }

        let typeName = structDecl.name.text
        let allProps = collectProperties(from: structDecl)
        var assignments: [String] = []

        // Column-attribute properties: @ID, @Column, @Timestamp, @ForeignKey
        for prop in allProps where columnAttributeNames.contains(wrapperAttributeName(prop.wrapper)) {
            // Always use the Swift property name as the dict key.
            // Schema.from(row:) populates the dict keyed by property name, not database column name.
            let dictKey = prop.name

            if prop.isOptional {
                assignments.append(
                    "instance.\(prop.name) = values[\"\(dictKey)\"] as? \(prop.typeName)"
                )
            } else {
                assignments.append(
                    "if let __v = values[\"\(dictKey)\"] as? \(prop.typeName) { instance.\(prop.name) = __v }"
                )
            }
        }

        // Relationship loader injection
        let idProp = allProps.first(where: { $0.wrapper == .id })

        if let idProp = idProp {
            let conventionFK = toSnakeCase(typeName) + "_id"
            let idType = idProp.typeName

            for prop in allProps {
                switch prop.wrapper {
                case .hasMany:
                    let fk = prop.foreignKeyOverride ?? conventionFK
                    let elementType = String(prop.typeName.dropFirst().dropLast())
                    assignments.append(
                        "if let __parentId = values[\"\(idProp.name)\"] as? \(idType) { instance.$\(prop.name) = instance.$\(prop.name).withLoader(SpectroLazyRelation<[\(elementType)]>.hasManyLoader(parentId: __parentId, foreignKey: \"\(fk)\")) }"
                    )
                case .hasOne:
                    let fk = prop.foreignKeyOverride ?? conventionFK
                    assignments.append(
                        "if let __parentId = values[\"\(idProp.name)\"] as? \(idType) { instance.$\(prop.name) = instance.$\(prop.name).withLoader(SpectroLazyRelation<\(prop.typeName)?>.hasOneLoader(parentId: __parentId, foreignKey: \"\(fk)\")) }"
                    )
                case .belongsTo:
                    // Use foreignKeyOverride if specified, otherwise convention: <propName>Id
                    let fkPropName = prop.foreignKeyOverride ?? "\(prop.name)Id"
                    if let fkProp = allProps.first(where: { $0.wrapper == .foreignKey && $0.name == fkPropName }) {
                        let fkType = fkProp.typeName
                        assignments.append(
                            "if let __fk = values[\"\(fkPropName)\"] as? \(fkType) { instance.$\(prop.name) = instance.$\(prop.name).withLoader(SpectroLazyRelation<\(prop.typeName)?>.belongsToLoader(foreignKeyValue: __fk)) }"
                        )
                    }
                default:
                    break
                }
            }
        }

        let body = assignments.joined(separator: "\n            ")

        let ext: DeclSyntax = """
        extension \(raw: typeName): Schema, SchemaBuilder {
            public static func build(from values: [String: Any]) -> \(raw: typeName) {
                var instance = \(raw: typeName)()
                \(raw: body)
                return instance
            }
        }
        """

        guard let extDecl = ext.as(ExtensionDeclSyntax.self) else { return [] }
        return [extDecl]
    }
}

// MARK: - Diagnostics

private struct SchemaDiagnostic: DiagnosticMessage {
    let message: String
    let diagnosticID: MessageID
    let severity: DiagnosticSeverity

    static let onlyStructs = SchemaDiagnostic(
        message: "@Schema can only be applied to struct types",
        diagnosticID: MessageID(domain: "SpectroMacros", id: "onlyStructs"),
        severity: .error
    )

    static let missingTableName = SchemaDiagnostic(
        message: "@Schema requires a table name argument, e.g. @Schema(\"users\")",
        diagnosticID: MessageID(domain: "SpectroMacros", id: "missingTableName"),
        severity: .error
    )

    static let missingID = SchemaDiagnostic(
        message: "@Schema requires at least one @ID property",
        diagnosticID: MessageID(domain: "SpectroMacros", id: "missingID"),
        severity: .error
    )
}
