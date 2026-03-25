import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct SpectroMacrosPlugin: CompilerPlugin {
    let providingMacros: [any Macro.Type] = [
        SchemaMacro.self,
    ]
}
