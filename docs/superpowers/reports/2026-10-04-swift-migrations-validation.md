# Swift migration implementation validation

Baseline: main / 2.0.0 at b13c41c. Implementation branch: codex/migrations-design.

## Local evidence

| Check | Result |
|---|---|
| Full macOS suite, Swift 6.4 / PostgreSQL 18.6 | 413 tests passed |
| Full Linux suite, Swift 6.0.3 / PostgreSQL 16 | 413 tests passed; CLI override explicitly absent |
| Separate public consumer package | Builds and runs on both platforms |
| Approved DSL examples | Compile and prepare through public imports on Swift 6.0 and 6.4 |
| Copied release binaries and SQL resources | Acceptance passed on both platforms, outside the checkout and without compiler lookup |
| Linux runtime-only container | All acceptance scenarios passed, with no Swift compiler, SwiftPM, Mint, or source mounts |
| CLI supervision | SIGINT/SIGTERM forwarding and child reaping passed on macOS and Linux |
| Real SwiftPM launcher | Linux `swift run` termination, child reaping and subsequent lock acquisition passed |
| Mixed-history lifecycle | Unchanged SQL adoption, populated rollback/reapply, concurrent runners, missing history and duplicate IDs passed |
| Interruption during owned migration | Transaction rollback and subsequent lock acquisition passed; Linux PID 1 is covered |
| IssueTracker HTTP example | Original SQL scenario and compiled Swift migration scenario passed, including restart persistence |
| SQL composition regressions | Trailing line comments preserve create/alter foreign keys, checks, partial indexes, and forward/rollback statement boundaries |
| Offline preview order | Release artifacts print ascending up plans and descending down plans |

The macOS HTTP run used Swift 6.4/Xcode 27.2. Its existing CI configuration remains Swift 6.3.3/Xcode 26.3. A temporary source snapshot named Spectro was necessary for the example's documented SwiftPM dependency identity requirement; the worktree name is migrations-design. No dependency update was included.

Hosted CI was configured but has not run for this branch. In particular, local macOS testing used Swift 6.4; macOS Swift 6.0.3 remains a hosted gate. Linux verified the Swift 6.0 language and package floor.

## Compatibility assessment

MigrationManager retains its public initializer, defaults, method signatures, MigrationFile returns, and legacy rollback selection. Existing public error enums and protocols are unchanged. SpectroKit users do not need SpectroMigrations. The new module depends on Spectro; the core does not depend on the new module. ArgumentParser was already a package dependency.

The SQL statement parser changed only after focused tests reproduced incorrect handling of quoted identifiers, escape strings, nested comments, and bind parameters. The legacy SQL migration and CLI suites remain green.

A 2.1.0 release is proposed because the public surface is additive. No version tag or publication is part of this implementation.

## Decisions recorded during execution

- The user's implementation approval superseded the earlier proposal-only wording. This authorized implementation in the isolated worktree; it did not request a merge or release.
- AlterTable.add returns ColumnDefinition, the same immutable modifier value used by table.column. Separate builders supply their contexts. This avoids duplicated modifier APIs; introducing distinct behavior later would need an explicit API extension.
- Nested Reversible operations select the enclosing direction. Ordinary operations inside that selected branch execute forward in written order. Changing this would reverse explicitly authored instructions a second time.
- The standalone consumer pins the root dependency graph. This makes its Swift 6.0 check reproducible; those pins must follow future dependency updates. Local macOS uses the available newer toolchain and does not replace the hosted minimum-version gate.
- Empty generated accessors use get {} because Swift 6.0 rejects the shorthand empty accessor. Nonempty declarations retain the concise proposed DSL; the extra getter wrapper can be removed when authoring operations.
- Legacy SQL-directory sources retain their historical rollback selection and transaction-control permissiveness. Prepared migrations receive the stricter preflight. This preserves compatibility at the cost of retaining the legacy limitations.
- PostgreSQL validates arbitrary trusted SQL grammar and schema references. Offline planning checks lexical and structural correctness, and the compiler preserves fragment boundaries. SQL syntax or schema errors can therefore still surface during transactional execution.

## Review status

The independent whole-branch review completed on 2026-10-05 against b13c41c..7ab22c4. It found three actionable issues, all fixed in one regression-driven pass:

| Finding | Reproduction and verification |
|---|---|
| SQL comments consumed generated syntax, including foreign keys | Three new integration tests reproduced six PostgreSQL failures: create/alter FK omissions, check/index syntax errors, and merged up/down statements. Newline boundaries preserve the caller's SQL and generated syntax; all cases pass. |
| Signal tests required an undocumented SPECTRO_CLI_PATH | Both signals failed with the variable absent. The test now shares the normal executable-path fallback. Focused tests and the full Linux suite pass with the override explicitly unset; the external build's executable was linked at the standard .build/debug path. |
| Down previews printed ascending catalog order | The copied-artifact assertion failed on dependent migrations. Down previews now reverse the catalog; the rebuilt macOS, Linux, and runtime-container artifacts pass the output-order assertion. |

After these fixes, both full suites passed all 413 tests, both copied-release acceptance runs passed, the rebuilt compiler-free container passed, and the original plus extended HTTP acceptance passed. No deferred minor findings remain. The reviewer left the legacy compatibility policy and arbitrary SQL grammar validation to the implementer; both decisions are recorded above.

All work remains on codex/migrations-design. Main and the published 2.0.0 tag are unchanged; hosted CI, merging and publication remain outside this local implementation.
