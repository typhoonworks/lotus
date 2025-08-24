# Changelog

## Unreleased

- **BREAKING:** Removed `tags` field from queries - queries no longer support tagging/filtering by tags
- **BREAKING:** Changed query field from `query` (map with `sql` and `params`) to `statement` (string)
- Add smart variable support with `{var}` placeholders in SQL statements
- Add `var_defaults` field to queries for providing default variable values
- Add comprehensive adapter tests for `Lotus.Adapter` module
- Add `get_query` to fetch queries without raising when they don't exist

## [0.2.0] - 2025-01-21

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

## [0.1.0] - 2025-01-09
- Initial release
- Query storage, execution, and basic filtering
- Read-only SQL runner with safety checks
