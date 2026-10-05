#!/usr/bin/env python3
"""Build and link-check the Spectro libraries as one browsable DocC website."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parent.parent
# Convert dependencies first so symbol links resolve across public libraries.
MODULES = ("SpectroCommon", "Spectro", "SpectroMigrations")


def run(arguments, **kwargs):
    print("+ " + shlex.join(str(argument) for argument in arguments), flush=True)
    return subprocess.run([str(argument) for argument in arguments], check=True, **kwargs)


def stage_catalog(source, destination):
    # Synced folders and hidden worktrees can mark even ordinary Markdown files
    # hidden. DocC silently skips them, so copy content without filesystem flags.
    destination.mkdir()
    for path in source.rglob("*"):
        target = destination / path.relative_to(source)
        if path.is_dir():
            target.mkdir(parents=True, exist_ok=True)
        elif path.is_file():
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, target)


def check_catalog(archive, catalog, module):
    data = archive / "data" / "documentation"
    landing = json.loads((data / f"{module.lower()}.json").read_text())
    if not landing.get("abstract"):
        raise RuntimeError(f"DocC omitted the authored landing page for {module}")
    for article in catalog.glob("*.md"):
        if article.stem != module:
            rendered = data / module.lower() / f"{article.stem.lower()}.json"
            if not rendered.is_file():
                raise RuntimeError(f"DocC omitted the article {module}/{article.name}")


def main():
    cache_base = Path.home() / "Library/Caches" if sys.platform == "darwin" else Path(
        os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")
    )
    checkout = hashlib.sha256(str(ROOT).encode()).hexdigest()[:16]
    cache = cache_base / "spectro-documentation" / checkout
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scratch-path", type=Path, default=cache / "build",
                        help="SwiftPM build directory (defaults outside the source checkout)")
    parser.add_argument("--output", type=Path, default=cache / "Spectro.doccarchive",
                        help="combined documentation archive and static website directory")
    parser.add_argument("--hosting-base-path", default="/",
                        help="URL prefix when hosting under a subdirectory, such as /Spectro")
    args = parser.parse_args()
    scratch = args.scratch_path.expanduser().resolve()
    output = args.output.expanduser().resolve()
    if output.suffix != ".doccarchive":
        parser.error("--output must end in .doccarchive")
    if output.exists() and not (output / "metadata.json").is_file():
        parser.error("--output exists but is not a DocC archive")
    docc = shutil.which("docc")
    if docc is None and shutil.which("xcrun"):
        docc = subprocess.check_output(["xcrun", "--find", "docc"], text=True).strip()
    if not docc:
        parser.error("DocC is required; select a Swift toolchain that includes docc merge")
    # Fail before compiling if the selected DocC cannot merge library archives.
    run([docc, "merge", "--help"], stdout=subprocess.DEVNULL)

    # Native SwiftPM avoids Clang extraction of private dependency headers. Build
    # tests without running them: Swift 6.4 also extracts the generated test module.
    run(["swift", "build", "--package-path", ROOT, "--scratch-path", scratch,
         "--build-system", "native", "--build-tests"])
    result = run(["swift", "package", "--package-path", ROOT, "--scratch-path", scratch,
                  "--build-system", "native", "dump-symbol-graph",
                  "--minimum-access-level", "public", "--skip-synthesized-members"],
                 stdout=subprocess.PIPE, text=True)
    print(result.stdout, end="", flush=True)
    match = re.search(r"^Files written to (.+)$", result.stdout, re.MULTILINE)
    if not match:
        raise RuntimeError("SwiftPM did not report its symbol graph output directory")
    graphs = Path(match.group(1).strip())
    output.parent.mkdir(parents=True, exist_ok=True)

    # A failed conversion leaves the previous website intact.
    with tempfile.TemporaryDirectory(prefix="spectro-docc-", dir=output.parent) as temporary:
        workspace = Path(temporary)
        archives = []
        for module in MODULES:
            module_graphs = workspace / module
            module_graphs.mkdir()
            graph = graphs / f"{module}.symbols.json"
            if not graph.is_file():
                raise RuntimeError(f"Missing symbol graph for {module}: {graph}")
            for source in [graph, *graphs.glob(f"{module}@*.symbols.json")]:
                shutil.copy2(source, module_graphs / source.name)
            catalog = workspace / f"{module}.docc"
            stage_catalog(ROOT / "Sources" / module / f"{module}.docc", catalog)
            archive = workspace / f"{module}.doccarchive"
            dependencies = [argument for dependency in archives
                            for argument in ("--dependency", dependency)]
            run([docc, "convert", catalog,
                 "--additional-symbol-graph-dir", module_graphs,
                 "--output-path", archive,
                 "--fallback-bundle-identifier", f"org.spectro.{module}",
                 "--fallback-default-module-kind", "Library",
                 "--hosting-base-path", args.hosting_base_path,
                 "--enable-experimental-external-link-support", *dependencies,
                 "--warnings-as-errors", "--analyze"])
            check_catalog(archive, catalog, module)
            archives.append(archive)
        combined = workspace / "Combined.doccarchive"
        # Use the ORM's archive metadata for the combined package.
        ordered = [workspace / f"{module}.doccarchive"
                   for module in ("Spectro", "SpectroMigrations", "SpectroCommon")]
        run([docc, "merge", *ordered, "--output-path", combined,
             "--synthesized-landing-page-name", "Spectro Libraries"])
        previous = workspace / "Previous.doccarchive"
        if output.exists():
            output.rename(previous)
        try:
            combined.rename(output)
        except OSError:
            if previous.exists():
                previous.rename(output)
            raise

    print(f"\nDocumentation: {output}")
    prefix = args.hosting_base_path.strip("/")
    if prefix:
        print(f"Mount this archive at /{prefix}/ on your static host.")
    else:
        serve = ["python3", "-m", "http.server", "8000", "--bind", "127.0.0.1",
                 "--directory", str(output)]
        print("Serve locally: " + shlex.join(serve))
        print("Open: http://127.0.0.1:8000/documentation/")


if __name__ == "__main__":
    try:
        main()
    except (subprocess.CalledProcessError, RuntimeError, OSError) as error:
        print(f"Documentation build failed: {error}", file=sys.stderr)
        sys.exit(1)
