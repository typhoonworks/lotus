# Changelog

## [Unreleased]

### Added
- **NEW:** Comprehensive caching system with pluggable adapters and ETS backend
- **NEW:** OTP application and supervisor support for production deployment
- Added `Lotus.Application` and `Lotus.Supervisor` for managed cache backend lifecycle
- Added `Lotus.child_spec/1` and `Lotus.start_link/1` for supervision tree integration
- Added `Lotus.Cache` behaviour for implementing custom cache adapters
- Added `Lotus.Cache.ETS` adapter providing in-memory caching with TTL support
- Added cache configuration with profiles (`:results`, `:options`, `:schema`) for different TTL strategies
- Added cache namespace support for multi-tenant applications
- Added tag-based cache invalidation for targeted cache clearing
- Added cache modes: default caching, `:bypass` (skip cache), `:refresh` (update cache)
- Added cache key generation based on SQL, parameters, repository, search path, and Lotus version
- Added cache integration for both `run_sql/3` and `run_query/2` functions
- Added cache options passing (`max_bytes`, `compress`) through the API layer
- Added comprehensive cache integration tests demonstrating all cache behaviors

### Enhanced  
- Enhanced `run_sql/3` and `run_query/2` to automatically use configured cache when available
- Enhanced cache system with automatic adapter detection and graceful fallback when no adapter configured
- Enhanced cache configuration with profile-specific TTL settings and runtime overrides

### Changed
- **BREAKING:** Renamed `Lotus.Adapter` behaviour to `Lotus.Source` in preparation for caching functionality and to support future non-SQL data sources
- **BREAKING:** Renamed adapter modules from `Lotus.Adapters.*` to `Lotus.Sources.*` (`Lotus.Sources.Postgres`, `Lotus.Sources.MySQL`, `Lotus.Sources.SQLite3`, `Lotus.Sources.Default`)
- **BREAKING:** Renamed `Lotus.SourceUtils` module to `Lotus.Sources` and expanded its functionality to include data source registration, dynamic module resolution, and comprehensive source management utilities

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
