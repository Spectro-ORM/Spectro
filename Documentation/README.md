# Spectro documentation

The DocC website combines authored guides and searchable API reference for three public libraries:

| Library | Start here | Package product |
|---|---|---|
| Spectro | [Connect, define schemas, and query](../Sources/Spectro/Spectro.docc/Spectro.md) | `SpectroKit` |
| SpectroMigrations | [Declare and deploy Swift migrations](../Sources/SpectroMigrations/SpectroMigrations.docc/SpectroMigrations.md) | `SpectroMigrations` |
| SpectroCommon | [Shared migration values and errors](../Sources/SpectroCommon/SpectroCommon.docc/SpectroCommon.md) | `SpectroCommon` |

These docs describe Spectro **2.1.0**. See the [release notes](../CHANGELOG.md), [2.1 upgrade guide](../docs/UPGRADING-2.1.md), and [CLI reference](../docs/CLI.md).

## Build and preview

Use Python 3 and a Swift toolchain whose DocC supports `docc merge`. The documentation toolchain can be newer than Spectro's Swift 6.0 minimum. `docc` is found on `PATH`, with `xcrun --find docc` as a macOS fallback.

From the repository root:

```sh
python3 scripts/build_docs.py
```

The script builds public symbol graphs, checks all three catalogs with DocC's `--warnings-as-errors --analyze`, resolves links between libraries, and merges the archives into **Spectro Libraries**. It stages catalog contents without inherited filesystem flags and verifies that every guide was rendered, including when building from a hidden worktree. It prints the generated archive path and a local preview command. Copy that command, start the server, and open `http://127.0.0.1:8000/documentation/`.

No PostgreSQL instance or database credentials are needed. SwiftPM may fetch dependencies during the build. The script compiles test modules without running tests because Swift 6.4's symbol extraction also visits the generated test module. Build artifacts live in a per-checkout directory under `~/Library/Caches/spectro-documentation` on macOS, or `$XDG_CACHE_HOME/spectro-documentation` (`~/.cache` by default) on Linux. Native SwiftPM is selected explicitly to avoid Clang symbol extraction of private dependency headers with Xcode 27 beta.

To choose your own paths:

```sh
python3 scripts/build_docs.py \
  --scratch-path "$HOME/.cache/spectro-docs-build" \
  --output "$HOME/.cache/Spectro.doccarchive"
python3 -m http.server 8000 --bind 127.0.0.1 \
  --directory "$HOME/.cache/Spectro.doccarchive"
```

Existing output is replaced only after a successful build. The output must end in `.doccarchive`; an existing directory without DocC metadata is refused.

## Static hosting

The archive contains the website assets, article data, search index, and navigation. Serve its contents at the root of a static host. To serve under `/Spectro/`, build with `--hosting-base-path /Spectro` and mount the archive at that prefix. Browse `/Spectro/documentation/`.

Building the archive does not publish it. Check links and navigation locally before uploading a release's archive.

## Maintain the docs

Each module has a `Sources/<Module>/<Module>.docc` catalog. The module landing page groups guides and public symbols into sidebar topics. Add prose to an article, API contracts to Swift documentation comments, and curate new articles in the landing page. Rebuild to catch unresolved symbol and article links.

The migration guides cover executable setup, the DSL, rollback, legacy SQL, command configuration, and production distribution. Keep CLI examples synchronized with `spectro --help` and the project executable's `--help` output.
