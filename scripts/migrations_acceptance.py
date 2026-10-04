#!/usr/bin/env python3
"""Validate copied migration artifacts against disposable PostgreSQL databases."""
import argparse
import contextlib
import hashlib
import json
import os
from pathlib import Path
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "Tests/Fixtures/SwiftMigrationsConsumer"
PRODUCTS = ("FixtureMigrations", "MissingMigrations", "DuplicateMigrations", "SlowMigrations")


def run(command, *, env=None, cwd=None, expected=0, timeout=60):
    result = subprocess.run([str(x) for x in command], env=env, cwd=cwd, text=True,
                            capture_output=True, timeout=timeout)
    if (expected == 0 and result.returncode != 0) or (expected != 0 and result.returncode == 0):
        raise AssertionError(f"Unexpected exit {result.returncode}:\n{result.stdout}\n{result.stderr}")
    return result


def build(command, log):
    with log.open("w") as output:
        result = subprocess.run(command, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT, timeout=900)
    if result.returncode:
        raise RuntimeError(log.read_text()[-12000:])


def main():
    cache = Path.home() / ("Library/Caches" if sys.platform == "darwin" else ".cache")
    identity = hashlib.sha256(os.fsencode(ROOT)).hexdigest()[:12]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-root", type=Path, default=cache / "spectro-migrations-acceptance" / identity)
    parser.add_argument("--skip-build", action="store_true")
    parser.add_argument("--jobs", type=int, default=4)
    parser.add_argument("--cli", type=Path, default=os.environ.get("SPECTRO_CLI_PATH"))
    parser.add_argument("--artifact-dir", type=Path, help="Keep copied release executables and resource bundles here")
    parser.add_argument("--runtime-image", help="Run migrations in this compiler-free Docker image instead")
    parser.add_argument("--docker-network", default="host")
    parser.add_argument("--runtime-db-host")
    parser.add_argument("--runtime-db-port")
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error("--jobs must be positive")
    psql = shutil.which("psql")
    if not psql:
        raise RuntimeError("psql must be installed")
    env = dict(os.environ)
    for key, value in {"DB_HOST": "127.0.0.1", "DB_PORT": "5432", "DB_USER": "postgres", "DB_PASSWORD": "postgres"}.items():
        env.setdefault(key, value)
    env["PGPASSWORD"] = env["DB_PASSWORD"]
    scratch = args.build_root.expanduser().resolve()
    scratch.mkdir(parents=True, exist_ok=True)
    cli_command = ["swift", "build", "--package-path", str(ROOT), "--scratch-path", str(scratch / "cli")]
    if args.cli:
        cli = args.cli.expanduser().resolve()
    else:
        if not args.skip_build:
            build([*cli_command, "--jobs", str(args.jobs), "--product", "spectro"], scratch / "cli-build.log")
        cli = Path(run([*cli_command, "--show-bin-path"]).stdout.strip()) / "spectro"
    consumer_command = ["swift", "build", "--package-path", str(FIXTURE),
                        "--scratch-path", str(scratch / "consumer"), "-c", "release"]
    if not args.runtime_image:
        if not args.skip_build:
            build([*consumer_command, "--jobs", str(args.jobs)], scratch / "consumer-build.log")
        binary_dir = Path(run([*consumer_command, "--show-bin-path"]).stdout.strip())

    with tempfile.TemporaryDirectory(prefix="spectro-artifact-") as temporary:
        work = Path(temporary)
        artifact = (args.artifact_dir or work / "artifact").resolve()
        if not args.runtime_image:
            artifact.mkdir(parents=True, exist_ok=True)
            for name in PRODUCTS:
                shutil.copy2(binary_dir / name, artifact / name)
            bundles = [p for p in binary_dir.iterdir() if p.suffix in (".bundle", ".resources")]
            assert bundles, "The fixture must ship its legacy SQL resource bundle"
            for bundle in bundles:
                shutil.copytree(bundle, artifact / bundle.name, dirs_exist_ok=True)
        docker = shutil.which("docker") if args.runtime_image else None
        if args.runtime_image:
            if not docker:
                raise RuntimeError("docker must be installed for --runtime-image")
            run([docker, "run", "--rm", "--entrypoint", "/bin/sh", args.runtime_image, "-c",
                 "for tool in swift swiftc swift-build mint; do "
                 "if command -v \"$tool\" >/dev/null 2>&1; then exit 1; fi; done; "
                 "test ! -d /work/Spectro; test ! -d /artifact/Sources"])

        def sql(statement, database="postgres"):
            return run([psql, "-X", "-v", "ON_ERROR_STOP=1", "-h", env["DB_HOST"], "-p", env["DB_PORT"],
                        "-U", env["DB_USER"], "-d", database, "-Atc", statement], env=env, timeout=15).stdout.strip()

        @contextlib.contextmanager
        def database():
            name = "spectro_migrations_" + uuid.uuid4().hex[:12]
            sql(f'CREATE DATABASE "{name}"')
            try:
                yield name
            finally:
                sql(f'DROP DATABASE "{name}" WITH (FORCE)')

        def migration_command(name, arguments, db=None):
            child_env = {k: v for k, v in env.items() if not k.startswith("DB_")}
            child_env["PATH"] = "/nonexistent"
            if db:
                child_env.update({k: v for k, v in env.items() if k.startswith("DB_")})
                child_env["DB_NAME"] = db
            if args.runtime_image:
                # Docker resolves its own client helpers using the host PATH.
                child_env["PATH"] = env.get("PATH", "")
                command = [docker, "run", "--rm", "--network", args.docker_network]
                if db:
                    child_env["DB_HOST"] = args.runtime_db_host or env["DB_HOST"]
                    child_env["DB_PORT"] = args.runtime_db_port or env["DB_PORT"]
                    for key in ("DB_HOST", "DB_PORT", "DB_USER", "DB_PASSWORD", "DB_NAME"):
                        command += ["-e", key]
                command += ["--entrypoint", "/artifact/" + name, args.runtime_image, *arguments]
            else:
                command = [str(artifact / name), *arguments]
            return command, child_env

        def migrate(*arguments, db=None, name="FixtureMigrations", expected=0):
            command, child_env = migration_command(name, arguments, db)
            return run(command, env=child_env, cwd=work, expected=expected, timeout=45)

        for arguments in (["--help"], ["help", "plan"], ["plan"], ["plan", "--direction", "down"], ["down", "--step", "0"]):
            result = migrate(*arguments)
            if arguments[0] == "plan":
                assert "legacy_items" in result.stdout and "pending" not in result.stdout
        migrate("plan", "--migration", "missing", expected=1)
        migrate("down", "--step=-1", expected=1)
        print("PASS: copied executable and resources, offline help/plan, no compiler on runtime PATH", flush=True)

        if not args.runtime_image:
            previews = []
            for product in ("FixtureMigrations", "MissingMigrations"):
                project = work / product
                project.mkdir()
                (project / "Package.swift").write_text("// launcher fixture")
                (project / ".spectro.json").write_text(json.dumps({
                    "formatVersion": 1, "migrations": {"product": product, "sourceDirectory": "Sources/" + product}
                }))
                # The launcher selects the project's runtime; both executables use the public library.
                (project / "swift").write_text('#!/bin/sh\nproduct="$4"\nshift 4\nexec ' +
                    shlex.quote(str(artifact)) + '/"$product" "$@"\n')
                (project / "swift").chmod(0o755)
                offline_env = {k: v for k, v in env.items() if not k.startswith("DB_")}
                offline_env["PATH"] = str(project)
                previews.append(run([cli, "migrate", "plan"], cwd=project, env=offline_env).stdout)
            assert "ADD COLUMN" in previews[0] and "ADD COLUMN" not in previews[1]
            print("PASS: the same installed launcher executes two distinct project runtime plans", flush=True)

        with database() as db:
            # A new status-only role has CONNECT but cannot create tracking objects.
            role = "spectro_status_" + uuid.uuid4().hex[:10]
            sql(f"CREATE ROLE {role} LOGIN PASSWORD 'status_test'")
            try:
                command, status_env = migration_command("FixtureMigrations", ["status"], db)
                status_env.update(DB_USER=role, DB_PASSWORD="status_test")
                result = run(command, env=status_env, cwd=work)
                assert "pending" in result.stdout
                assert sql("SELECT to_regclass('schema_migrations') IS NULL", db) == "t"
            finally:
                sql(f"DROP ROLE {role}")
            legacy = work / "Sources/Migrations"
            legacy.mkdir(parents=True)
            original = FIXTURE / "Sources/FixtureDefinitions/LegacySQL/1700000000_create_legacy_items.sql"
            shutil.copy2(original, legacy)
            legacy_env = dict(env, DB_NAME=db)
            run([cli, "migrate", "up"], cwd=work, env=legacy_env)
            sql("INSERT INTO legacy_items VALUES (1,'keep this row')", db)
            migrate("up", db=db)
            assert sql("SELECT COUNT(*) FROM schema_migrations WHERE status='completed'", db) == "3"
            assert sql("SELECT COUNT(*) FROM schema_migrations WHERE version='1700000000_create_legacy_items'", db) == "1"
            migrate("down", "--step", "1", db=db, name="MissingMigrations", expected=1)
            assert sql("SELECT priority FROM legacy_items WHERE id=1", db) == "0"
            assert sql("SELECT COUNT(*) FROM schema_migrations WHERE status='completed'", db) == "3"
            migrate("down", "--step", "1", db=db)
            assert sql("SELECT COUNT(*) FROM information_schema.columns WHERE table_name='legacy_items' AND column_name='priority'", db) == "0"
            assert sql("SELECT to_regclass('legacy_priority_index') IS NULL", db) == "t"
            migrate("up", db=db)
            assert sql("SELECT title||':'||priority FROM legacy_items WHERE id=1", db) == "keep this row:0"
            migrate("down", db=db)
            assert sql("SELECT COUNT(*) FROM schema_migrations WHERE status='completed'", db) == "0"
            print("PASS: read-only status, unchanged SQL adoption, populated rollback/reapply, missing-history preflight", flush=True)

        with database() as db:
            command, child_env = migration_command("FixtureMigrations", ["up"], db)
            processes = [subprocess.Popen(command, env=child_env, cwd=work, stdout=subprocess.PIPE, stderr=subprocess.STDOUT) for _ in range(2)]
            try:
                for process in processes:
                    output, _ = process.communicate(timeout=45)
                    assert process.returncode == 0, output.decode()
            finally:
                for process in processes:
                    if process.poll() is None:
                        process.kill()
                        process.wait(timeout=10)
            assert sql("SELECT COUNT(*) FROM schema_migrations WHERE status='completed'", db) == "3"
            print("PASS: independent processes serialize a fresh migration history", flush=True)

        with database() as db:
            migrate("up", db=db, name="DuplicateMigrations", expected=1)
            assert sql("SELECT to_regclass('legacy_items') IS NULL", db) == "t"
            assert sql("SELECT to_regclass('schema_migrations') IS NULL", db) == "t"
            command, child_env = migration_command("SlowMigrations", ["up"], db)
            if not args.runtime_image:
                # Isolate launcher supervision from SwiftPM compilation while executing a real DB migration.
                project = work / "launcher"
                project.mkdir()
                (project / "Package.swift").write_text("// launcher fixture")
                (project / ".spectro.json").write_text('{"formatVersion":1,"migrations":{"product":"SlowMigrations","sourceDirectory":"Sources/SlowMigrations"}}')
                (project / "swift").write_text("#!/bin/sh\nshift 4\nexec " + shlex.quote(str(artifact / "SlowMigrations")) + ' "$@"\n')
                (project / "swift").chmod(0o755)
                command = [str(cli), "migrate", "up"]
                child_env["PATH"] = str(project)
                cwd = project
            else:
                cwd = work
            process = subprocess.Popen(command, env=child_env, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            try:
                deadline = time.monotonic() + 15
                while time.monotonic() < deadline:
                    if process.poll() is not None:
                        raise AssertionError(process.stdout.read().decode())
                    active = sql("SELECT COUNT(*) FROM pg_stat_activity WHERE datname='" + db +
                                 "' AND query LIKE '%spectro_swift_kill_probe%' AND pid<>pg_backend_pid()", db)
                    if active != "0":
                        break
                    time.sleep(0.05)
                else:
                    raise AssertionError("The migration never acquired its connection")
                process.send_signal(signal.SIGTERM)
                process.communicate(timeout=10)
                assert process.returncode != 0
                migrate("up", db=db)
                assert sql("SELECT to_regclass('slow_probe') IS NULL", db) == "t"
                assert sql("SELECT COUNT(*) FROM schema_migrations WHERE status='completed'", db) == "3"
            finally:
                if process.poll() is None:
                    process.kill()
                    process.wait(timeout=10)
            print("PASS: duplicate IDs fail before DDL; termination rolls back and releases the migration lock", flush=True)
        if args.artifact_dir and not args.runtime_image:
            print(f"Artifact: {artifact}", flush=True)


if __name__ == "__main__":
    main()
