# ``SpectroCommon``

Share migration definitions, ledger values, and errors across Spectro's libraries and CLI.

## Overview

This module provides the values that connect migration authoring to execution. It has no external package dependencies. Applications normally use `SpectroKit` or `SpectroMigrations`; import `SpectroCommon` directly when working with prepared definitions, migration sources, or shared errors.

## Topics

### Understand the migration contract

- <doc:MigrationValues>

### Describe migration input

- ``PreparedMigration``
- ``MigrationRollback``
- ``MigrationSource``

### Inspect migration history

- ``MigrationFile``
- ``MigrationRecord``
- ``MigrationStatus``

### Handle errors

- ``MigrationPlanningError``
- ``MigrationError``
- ``DatabaseError``

### Order query results

- ``OrderDirection``
