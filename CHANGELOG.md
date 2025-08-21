# Changelog

## Unreleased
- **BREAKING:** Removed support for fk and pk configuration options
- **BREAKING:** Changed configuration structure - `repo` config replaced with `ecto_repo` and `data_repos`
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
