@resultBuilder
public enum MigrationBuilder {
    public static func buildExpression<S: MigrationStep>(_ expression: S) -> MigrationPlan { expression.migrationPlan }
    public static func buildBlock(_ components: MigrationPlan...) -> MigrationPlan { combine(components) }
    public static func buildOptional(_ component: MigrationPlan?) -> MigrationPlan { component ?? MigrationPlan([]) }
    public static func buildEither(first: MigrationPlan) -> MigrationPlan { first }
    public static func buildEither(second: MigrationPlan) -> MigrationPlan { second }
    public static func buildArray(_ components: [MigrationPlan]) -> MigrationPlan { combine(components) }

    private static func combine(_ components: [MigrationPlan]) -> MigrationPlan {
        MigrationPlan(components.flatMap(\.operations))
    }
}

