#!/usr/bin/env python3
"""Run the public API consumer against a new, disposable PostgreSQL database."""
import argparse
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import shutil
import shlex
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
import uuid

ROOT = Path(__file__).resolve().parents[1]
EXAMPLE = ROOT / "Examples" / "IssueTracker"


def default_build_root():
    # Keep generated bundles outside Documents/Desktop: File Provider can attach
    # FinderInfo there, which makes Apple's resource-bundle signing fail.
    cache = (Path.home() / "Library/Caches" if sys.platform == "darwin"
             else Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")))
    checkout = hashlib.sha256(os.fsencode(ROOT)).hexdigest()[:16]
    return cache / "spectro-acceptance" / checkout


def swift_build_command(package, scratch):
    return ["swift", "build", "--package-path", str(package), "--scratch-path", str(scratch)]


def executable_path(command, name, override):
    if override:
        return Path(override).expanduser().resolve()
    # SwiftPM's native and SwiftBuild engines use different output layouts.
    result = subprocess.run([*command, "--show-bin-path"], cwd=ROOT, check=True,
                            text=True, stdout=subprocess.PIPE)
    return Path(result.stdout.strip()) / name


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--skip-build", action="store_true")
    parser.add_argument("--jobs", type=int, default=4)
    parser.add_argument("--build-root", type=Path, default=default_build_root(),
                        help="Persistent build cache; choose a directory outside cloud-synced folders")
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error("--jobs must be positive")
    env = os.environ.copy()
    env.setdefault("DB_HOST", "localhost")
    env.setdefault("DB_PORT", "5432")
    env.setdefault("DB_USER", "postgres")
    env.setdefault("DB_PASSWORD", "postgres")
    # Never reuse a caller's application database.
    env["DB_NAME"] = "spectro_acceptance_" + uuid.uuid4().hex[:12]
    env["PEREGRINE_ENV"] = "test"
    env["PEREGRINE_HOST"] = "127.0.0.1"
    env["PGPASSWORD"] = env["DB_PASSWORD"]
    if not shutil.which("psql"):
        raise RuntimeError("Install PostgreSQL client tools (psql) before running acceptance")
    build_root = args.build_root.expanduser().resolve()
    cli_build = swift_build_command(ROOT, build_root / "cli")
    app_build = swift_build_command(EXAMPLE, build_root / "app")
    print(f"Acceptance build cache: {build_root}", flush=True)
    if not args.skip_build:
        for command in (cli_build, app_build):
            subprocess.run([*command, "--jobs", str(args.jobs)], cwd=ROOT, check=True)
    cli = executable_path(cli_build, "spectro", env.get("SPECTRO_CLI_PATH"))
    app = executable_path(app_build, "IssueTracker", env.get("SPECTRO_EXAMPLE_PATH"))
    swift_migrations = executable_path(app_build, "IssueTrackerMigrations", env.get("SPECTRO_EXAMPLE_MIGRATIONS_PATH"))
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    env["PEREGRINE_PORT"] = str(port)
    base = f"http://127.0.0.1:{port}"

    with tempfile.TemporaryDirectory(prefix="spectro-acceptance-") as temporary:
        work = Path(temporary)
        migrations = work / "Sources/Migrations"
        migrations.mkdir(parents=True)
        server = None
        log = None
        created = False

        def command(*arguments):
            result = subprocess.run([str(cli), *arguments], cwd=work, env=env,
                                    text=True, capture_output=True, timeout=45)
            if result.returncode:
                raise RuntimeError(result.stdout + result.stderr)
            return result.stdout

        def sql(statement):
            result = subprocess.run([
                "psql", "-X", "-h", env["DB_HOST"], "-p", env["DB_PORT"],
                "-U", env["DB_USER"], "-d", env["DB_NAME"], "-v", "ON_ERROR_STOP=1", "-Atc", statement,
            ], env=env, text=True, capture_output=True, check=True, timeout=10)
            return result.stdout.strip()

        def request(path, payload=None):
            data = None if payload is None else json.dumps(payload).encode()
            req = urllib.request.Request(base + path, data=data, headers={"Content-Type": "application/json"})
            try:
                response = urllib.request.urlopen(req, timeout=10)
            except urllib.error.HTTPError as error:
                response = error
            with response:
                return response.status, json.load(response)

        def stop():
            nonlocal server, log
            if server:
                server.terminate()
                try:
                    server.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    server.kill()
                    server.wait()
                server = None
            if log:
                log.close()
                log = None

        def start():
            nonlocal server, log
            log = open(work / "server.log", "a")
            server = subprocess.Popen([str(app)], cwd=work, env=env, stdout=log, stderr=log)
            deadline = time.monotonic() + 20
            while time.monotonic() < deadline:
                if server.poll() is not None:
                    raise RuntimeError((work / "server.log").read_text())
                try:
                    if request("/health")[0] == 200:
                        return
                except (OSError, ValueError):
                    pass
                time.sleep(0.05)
            raise RuntimeError("HTTP server did not become healthy")

        try:
            created = True
            command("database", "create", env["DB_NAME"])
            first, upgrade = sorted((EXAMPLE / "Migrations").glob("*.sql"))
            shutil.copy(first, migrations)
            command("migrate", "up")
            start()

            status, errors = request("/projects", {"slug": "", "name": "Invalid"})
            assert status == 422 and "slug" in errors, (status, errors)
            status, project = request("/projects", {
                "slug": "alpha", "name": "Project Alpha", "firstIssue": "First issue",
            })
            assert status == 201, (status, project)
            assert project["id"] != project["issue"]["id"]
            assert project["issue"]["projectId"] == project["id"]
            assert project["issue"]["name"] == "First issue"
            assert "note" not in project["issue"]
            status, empty = request("/projects", {"slug": "empty", "name": "Empty project"})
            assert status == 201, (status, empty)
            status, rows = request("/projects")
            assert status == 200, rows
            assert next(row for row in rows if row["slug"] == "alpha") == project
            assert "issue" not in next(row for row in rows if row["slug"] == "empty")
            status, errors = request("/issues", {"projectId": "invalid UUID", "name": "Bad"})
            assert status == 422 and "projectId" in errors, (status, errors)
            status, issue = request("/issues", {
                "projectId": empty["id"], "name": "Second issue", "note": "Persist this note",
            })
            assert status == 201 and issue["note"] == "Persist this note", (status, issue)

            # Force a failure after the project insert, inside the same transaction.
            status, error = request("/projects", {
                "slug": "rolled-back", "name": "Transient project", "firstIssue": "",
            })
            assert status == 500 and "error" in error, (status, error)
            assert sql("SELECT count(*) FROM projects WHERE slug = 'rolled-back'") == "0"
            with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
                results = list(executor.map(lambda _: request("/projects", {
                    "slug": "contested", "name": "Contested project", "firstIssue": "Contested issue",
                }), range(2)))
            assert sorted(status for status, _ in results) == [201, 409], results
            assert sql("SELECT count(*) FROM projects WHERE slug = 'contested'") == "1"
            assert sql("SELECT count(*) FROM issues WHERE display_name = 'Contested issue'") == "1"
            before = sorted(request("/projects")[1], key=lambda row: row["slug"])
            print("PASS: changesets, joined reads, nullable fields, transactions, competing writes", flush=True)

            stop()
            shutil.copy(upgrade, migrations)
            command("migrate", "up")
            assert sql("SELECT priority FROM issues WHERE display_name = 'First issue'") == "1"
            assert sql("SELECT count(*) FROM schema_migrations WHERE status = 'completed'") == "2"
            start()
            assert sorted(request("/projects")[1], key=lambda row: row["slug"]) == before
            stop()
            command("migrate", "down", "--step", "1")
            assert sql("SELECT count(*) FROM issues") == "3"
            assert sql("SELECT count(*) FROM information_schema.columns WHERE table_name = 'issues' AND column_name = 'priority'") == "0"
            assert sql("SELECT to_regclass('issues_project_id_idx') IS NULL") == "t"
            assert sql("SELECT status FROM schema_migrations WHERE version = '1700000001_issue_priority'") == "pending"
            command("migrate", "up")
            assert sql("SELECT priority FROM issues WHERE display_name = 'First issue'") == "1"
            assert sql("SELECT to_regclass('issues_project_id_idx') IS NOT NULL") == "t"
            assert sql("SELECT status FROM schema_migrations WHERE version = '1700000001_issue_priority'") == "completed"
            start()
            assert sorted(request("/projects")[1], key=lambda row: row["slug"]) == before
            print("PASS: populated migration, rollback/reapply, and HTTP restart persistence", flush=True)

            stop()
            def compiled_migrations(*arguments):
                result = subprocess.run([str(swift_migrations), *arguments], cwd=work, env=env,
                                        text=True, capture_output=True, timeout=45)
                if result.returncode:
                    raise RuntimeError(result.stdout + result.stderr)
            compiled_migrations("up")
            assert sql("SELECT count(*) FROM issues WHERE archived = false") == "3"
            assert sql("SELECT to_regclass('issues_unarchived_index') IS NOT NULL") == "t"
            assert sql("SELECT count(*) FROM schema_migrations WHERE status = 'completed'") == "3"
            start()
            assert sorted(request("/projects")[1], key=lambda row: row["slug"]) == before
            stop()
            compiled_migrations("down", "--step", "1")
            assert sql("SELECT count(*) FROM issues") == "3"
            assert sql("SELECT count(*) FROM information_schema.columns WHERE table_name='issues' AND column_name='archived'") == "0"
            compiled_migrations("up")
            start()
            assert sorted(request("/projects")[1], key=lambda row: row["slug"]) == before
            print("PASS: compiled Swift migration, unchanged SQL history, rollback/reapply and HTTP restart", flush=True)
        except Exception:
            if (work / "server.log").exists():
                print((work / "server.log").read_text()[-6000:])
            raise
        finally:
            stop()
            if created:
                command("database", "drop", "--force", env["DB_NAME"])


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        if error.stderr:
            print(error.stderr, file=sys.stderr)
        print(f"Acceptance command failed (exit {error.returncode}): {shlex.join(error.cmd)}", file=sys.stderr)
        raise SystemExit(error.returncode) from None
