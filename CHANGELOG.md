# Changelog

## [Unreleased]

## [0.9.1] - 2025-09-05

### Added

- Added windowed pagination capped at max 1000 pages to prevent performance degradation

## [0.9.0] - 2025-09-04

### Added
- Added `num_rows`, `duration_ms`, and `command` attributes to `Lotus.Result` struct returned by query execution
- Added comprehensive error messages for type conversion failures in query variables
- Added support for both integer and float parsing in `:number` type variables

### Changed
- **BREAKING:** Enhanced `QueryVariable.static_options` to support multiple input formats but normalize output to `%{value: String.t(), label: String.t()}` maps

### Fixed
- Fixed type casting errors that previously showed generic "Missing required variable" instead of specific type conversion issues
- Fixed number type variables to properly handle both integers (`"123"`) and floats (`"123.45"`)
- Fixed date type variables to show clear error messages for invalid date formats
- Improved error messages to distinguish between truly missing variables and type conversion failures

#### Data Migration Required

If you have existing queries stored in your database with `static_options` in the old format, you will need to migrate them. See the [Migration Guide in README.md](README.md#upgrading-from-versions--090) for detailed instructions and migration script.

## [0.9.0] - 2025-09-03

### Added
- **NEW:** Two-level schema and table visibility system with schema rules taking precedence over table rules
- **NEW:** Comprehensive export system with CSV, JSON, and JSONL support for Lotus.Result structs
- Added `schema_visibility` configuration for controlling which schemas are accessible through Lotus
- Added schema visibility functions to `Lotus.Visibility` module:
  - `allowed_schema?/2` - Check if a schema is visible
  - `filter_schemas/2` - Filter a list of schemas by visibility rules
  - `validate_schemas/2` - Validate that all requested schemas are visible
- Added `builtin_schema_denies/1` callback to Source behaviour for adapter-specific system schema filtering
- Added automatic schema visibility filtering to `list_schemas` and `list_tables` functions
- Added implementation of `list_schemas` for all database adapters:
  - PostgreSQL: Returns actual schema names from `information_schema.schemata`
  - MySQL: Returns database names as schemas
  - SQLite: Returns empty list (no schema support)
- Added comprehensive MySQL adapter tests in `Lotus.SchemaTest` covering all schema introspection functions
- Added `Lotus.Export` module with `to_csv/1`, `to_json/1`, and `to_jsonl/1` functions for exporting query results
- Added protocol-based `Lotus.Export.Normalizer` system for database value normalization with support for:
  - All basic Elixir types (atoms, numbers, strings, booleans, dates/times)
  - Database-specific types (PostgreSQL ranges, intervals, INET, geometric types)
  - Binary data handling (UUIDs, Base64 encoding for non-UTF-8 data)
  - Collections (maps preserved for JSON, stringified for CSV)
  - Decimal types with proper NaN/Infinity handling
- Added battle-tested UUID binary handling using `Ecto.UUID.load/1`
- Added comprehensive test coverage for all export functionality and edge cases
- Added NimbleCSV integration for robust CSV generation with proper escaping
- Added central `Lotus.Value` module providing unified interface for value normalization across JSON/CSV/UI contexts

### Changed
- **BREAKING:** Renamed `Lotus.QueryResult` to `Lotus.Result` for cleaner API naming with the introduction of `Lotus.Value`

### Fixed
- Fixed SQL quoting in `get_table_stats` to use adapter-specific quote characters (backticks for MySQL, double quotes for PostgreSQL)
- Fixed MySQL builtin_denies to properly filter system tables with database-specific schema names
- Fixed PostgreSQL and MySQL schema tests to correctly expect errors (not empty results) for non-existent tables

## [0.7.0] - 2025-09-01

### Added
- **NEW:** Comprehensive caching system with adapter behaviour and ETS backend
- **NEW:** OTP application and supervisor support for production deployment
- Added `Lotus.Application` and `Lotus.Supervisor` for managed cache backend lifecycle
- Added `Lotus.child_spec/1` and `Lotus.start_link/1` for supervision tree integration
- Added `Lotus.Cache` behaviour for implementing custom cache adapters
- Added `Lotus.Cache.ETS` adapter providing in-memory caching with TTL support
- Added cache configuration with predefined profiles (`:results`, `:options`, `:schema`) that ship with built-in defaults and support custom TTL strategies
- Added cache namespace support for multi-tenant applications
- Added tag-based cache invalidation for targeted cache clearing
- Added cache modes: default caching, `:bypass` (skip cache), `:refresh` (update cache)
- Added cache key generation based on SQL, parameters, repository, search path, and Lotus version
- Added cache integration for both `run_sql/3` and `run_query/2` functions
- Added cache integration for all Schema functions (`list_tables/2`, `get_table_schema/3`, `get_table_stats/3`, `list_relations/2`)
- Added cache options passing (`max_bytes`, `compress`) through the API layer
- Added built-in cache profile defaults: `:results` (60s TTL), `:schema` (1h TTL), `:options` (5m TTL) - available without any configuration

### Enhanced
- Enhanced `run_sql/3` and `run_query/2` to automatically use configured cache when available
- Enhanced all Schema functions with read-through caching using appropriate profiles (`:schema` for metadata, `:results` for statistics)
- Enhanced cache system with automatic adapter detection and graceful fallback when no adapter configured
- Enhanced cache configuration with profile-specific TTL settings and runtime overrides
- **MAJOR:** Refactored schema introspection system to be completely database-agnostic with proper caching of table schema resolution queries

### Changed
- **BREAKING:** Renamed `Lotus.Adapter` behaviour to `Lotus.Source` in preparation for caching functionality and to support future non-SQL data sources
- **BREAKING:** Renamed adapter modules from `Lotus.Adapters.*` to `Lotus.Sources.*` (`Lotus.Sources.Postgres`, `Lotus.Sources.MySQL`, `Lotus.Sources.SQLite3`, `Lotus.Sources.Default`)
- **BREAKING:** Renamed `Lotus.SourceUtils` module to `Lotus.Sources` and expanded its functionality to include data source registration, dynamic module resolution, and comprehensive source management utilities
- **INTERNAL:** Moved all database-specific schema operations (`list_tables`, `get_table_schema`, `resolve_table_schema`) from `Lotus.Schema` to respective source modules for better separation of concerns
- **INTERNAL:** `Lotus.Schema` is now completely database-agnostic and delegates all DB-specific operations to source modules
- **PERFORMANCE:** Added caching to `resolve_table_schema` queries to eliminate the expensive "which schema is this table in?" database lookups that were being repeatedly executed

### Fixed
- Fixed schema introspection for SQLite databases by properly handling schema-less database architecture (empty schemas list instead of `["public"]`)

## [0.6.0] - 2025-08-31

### Added
- Added `Lotus.can_run?/1` and `Lotus.can_run?/2` functions to check if a query has all required variables available before execution
- Added `Lotus.SQL.Transformer` for transforming SQL queries to ensure database-specific syntax compatibility when using lotus variables
- Added `Lotus.SourceUtils` module providing utility functions for detecting data source types and feature support across adapters
- Added comprehensive interval query transformation support for PostgreSQL (INTERVAL syntax, make_interval functions)
- Added quoted wildcard pattern transformation for database-specific string concatenation (supports both PostgreSQL || and MySQL CONCAT)
- Added quoted variable placeholder stripping for cleaner parameter binding
- Added `reset_read_only/1` callback to adapter behaviour for resetting database sessions back to read-write mode after query execution

### Enhanced
- Enhanced query execution to automatically transform SQL statements based on target database adapter before parameter binding

### Fixed
- **CRITICAL:** Fixed database session persistence issue where session-level settings (`PRAGMA query_only` for SQLite, `SET SESSION TRANSACTION READ ONLY` and `max_execution_time` for MySQL) were not being properly restored after query execution, causing connection pool pollution that could break subsequent operations. Lotus now uses a robust snapshot/restore pattern to preserve and restore original session state for each database connection.

## [0.5.4] - 2025-08-29

### Fixed
- Fixed incomplete `@type opts()` specification - added missing `:repo` and `:vars` options to eliminate Dialyzer type errors

## [0.5.3] - 2025-08-29

### Enhanced
- Added type-specific SQL parameter placeholders for MySQL adapter supporting date, datetime, time, number, integer, boolean, and json types
- Added type-specific SQL parameter placeholders for PostgreSQL adapter supporting date, datetime, time, number, integer, boolean, and json types
- Added `extract_variables_from_statement/1` function to extract unique variable names from SQL statements in order of first occurrence
- Added `get_option_source/1` function to QueryVariable module to determine if options come from query or static sources

### Fixed
- Added proper type casting in parameter placeholders to ensure correct SQL data type handling across database adapters

## [0.5.2] - 2025-08-28

### Enhanced
- Enhanced `Lotus.run_query/2` variable resolution to properly merge default variable values with runtime overrides via `vars` option
- Improved `Lotus.run_query/2` documentation with comprehensive examples showing variable resolution order, type casting, and usage patterns

### Fixed
- Removed non-functional identifier variable substitution (e.g., `{{table}}` for table names) that would cause Ecto adapter crashes
- Clarified documentation that variables are only safe for SQL values (WHERE clauses, ORDER BY values), never for identifiers like table or column names

## [0.5.1] - 2025-08-27

### Fixed
- Fixed error handling for optional Ecto adapters - removed hardcoded references to specific adapter error structs (`Postgrex.Error`, `MyXQL.Error`, `Exqlite.Error`) to prevent compilation crashes when those adapters are not installed in host applications
- Added MySQL preflight authorization support with intelligent alias resolution and schema-qualified table parsing

### Changed
- Refactored adapter error formatting to use dynamic error type checking instead of pattern matching on specific error structs

## [0.5.0] - 2025-08-26

### Added
- Introduced `Lotus.Adapter` behaviour with dedicated implementations for PostgreSQL, SQLite, MySQL, and Default
- Added MySQL support with full adapter implementation using `:myxql` dependency
- Added `default_repo` configuration option for cleaner multi-database setup
- Added `param_placeholder/3` callback to adapter behaviour for generating database-specific SQL parameter placeholders
- Added `builtin_denies/1` callback to allow adapters to define system table filtering rules
- Added `handled_errors/0` callback to allow adapters to declare which exceptions they format
- Added MySQL development environment setup with Docker Compose

### Changed
- **BREAKING:** Removed `param_style/1` API in favor of `param_placeholder/4` facade that delegates to adapters
- **BREAKING:** Storage repo no longer used as fallback for query execution - only data repos are valid execution targets
- Enhanced configuration validation to require `default_repo` when multiple data repositories are configured
- Refactored error formatting to delegate based on `handled_errors/0`, ensuring cleaner and more extensible error handling
- Refactored table visibility system to use adapter-specific `builtin_denies/1` for system table filtering
- Consolidated adapter tests into a single facade-level `Lotus.AdapterTest` covering all supported databases

## [0.4.0] - 2025-08-26

### Added
- Database-level read-only protection for SQLite using `PRAGMA query_only` (SQLite 3.8.0+)
- Comprehensive CTE (Common Table Expression) destructive operation tests for both PostgreSQL and SQLite

### Changed
- **BREAKING:** Replaced `var_defaults` field with structured `variables` field for enhanced UI integration
- **BREAKING:** Changed variable placeholder syntax from `{var}` to `{{var}}` for better parsing
- **BREAKING:** Database schema migration removes `var_defaults` column and adds `variables` column to `lotus_queries` table
- Enhanced QueryVariable schema with type definitions (text, number, date), widget controls (input, select), labels, and option support
- Added `static_options` field for predefined dropdown choices
- Added `options_query` field for dynamic dropdown population from database queries
- Added validation to ensure select widgets define either `static_options` or `options_query`

## [0.3.3] - 2025-08-25

### Changed
- Improved table visibility rules: bare string patterns (e.g., `"api_keys"`) now match table names across all schemas in PostgreSQL, not just nil/empty schemas. This provides a more intuitive API where `"api_keys"` blocks the table in any schema, while `{"public", "api_keys"}` blocks it only in the public schema.

## [0.3.2] - 2025-08-25

- Change `statement` col from varchar to text

## [0.3.1] - 2025-08-25

- Specify `repo` option in `Lotus.run_sql`

## [0.3.0] - 2025-08-25

- **BREAKING:** Removed `tags` field from queries - queries no longer support tagging/filtering by tags
- **BREAKING:** Changed query field from `query` (map with `sql` and `params`) to `statement` (string)
- Add smart variable support with `{var}` placeholders in SQL statements
- Add `var_defaults` field to queries for providing default variable values
- Add comprehensive adapter tests for `Lotus.Adapter` module
- Add `get_query` to fetch queries without raising when they don't exist

## [0.2.0] - 2025-08-21

- **BREAKING:** Removed support for fk and pk configuration options
- **BREAKING:** Changed configuration structure - `repo` config replaced with `ecto_repo` and `data_repos`
- **BREAKING:** Removed unused `prefix` option from query execution opts (was never implemented)
- **BREAKING:** `list_tables` now returns `{schema, table}` tuples instead of just table names
- Add PostgreSQL per-query `search_path` support for multi-schema applications
- Add `search_path` field to stored queries for automatic schema resolution
- Add runtime `search_path` override option for ad-hoc queries
- Add `search_path` validation to prevent injection attacks
- Add preflight authorization support for `search_path` (EXPLAIN uses same path as execution)
- Add multi-schema support to `list_tables`, `get_table_schema`, and `get_table_stats`
- Add `list_relations` function to return tables with schema information
- Add schema-aware table discovery with `:schema`, `:schemas`, and `:search_path` options
- Add multi-database support with PostgreSQL and SQLite
- Add table visibility controls for enhanced security
- Add support for multiple data repositories with flexible routing
- Add `data_repo` field to stored queries for automatic repository selection
- Add comprehensive development environment setup with sample data
- Add read-only repository configuration guidance

## [0.1.0] - 2025-08-09
- Initial release
- Query storage, execution, and basic filtering
- Read-only SQL runner with safety checks
