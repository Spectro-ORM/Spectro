#!/usr/bin/env bash
set -euo pipefail

# Create the test database for Spectro integration tests.
# Reads the same env vars as the test suite (with identical defaults).

DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_USER="${DB_USER:-postgres}"
DB_PASSWORD="${DB_PASSWORD:-postgres}"
TEST_DB_NAME="${TEST_DB_NAME:-spectro_test}"

export PGPASSWORD="$DB_PASSWORD"

echo "Creating test database '$TEST_DB_NAME' on $DB_HOST:$DB_PORT as $DB_USER..."

psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -tc \
  "SELECT 1 FROM pg_database WHERE datname = '$TEST_DB_NAME'" | grep -q 1 \
  || psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -c "CREATE DATABASE \"$TEST_DB_NAME\""

echo "Done. Run tests with: swift test"
