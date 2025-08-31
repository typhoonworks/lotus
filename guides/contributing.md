# Contributing to Lotus

Thank you for your interest in contributing to Lotus! This guide will help you get started with development and explain our contribution process.

## Getting Started

### Prerequisites

- Elixir 1.16 or later
- OTP 25 or later
- PostgreSQL 13 or later (for main development database)
- SQLite 3 (for multi-database testing)
- Git

### Development Setup

1. **Fork and clone the repository**
   ```bash
   git clone https://github.com/typhoonworks/lotus.git
   cd lotus
   ```

2. **Install dependencies**
   ```bash
   mix deps.get
   ```

3. **Set up the development databases**
   ```bash
   # Start PostgreSQL (if not running)
   # Then create and migrate the databases
   mix ecto.setup
   ```
   
   This creates:
   - PostgreSQL database (`lotus_dev`) with both Lotus tables and test data tables
   - SQLite database (`lotus_dev.db`) with e-commerce sample data

4. **Run the tests**
   ```bash
   # Run all tests
   mix test
   
   # Run PostgreSQL-specific tests
   mix test --exclude sqlite
   
   # Run SQLite-specific tests  
   mix test --only sqlite
   ```

5. **Start exploring with interactive development**
   ```bash
   iex -S mix
   ```
   
   The development environment automatically starts both PostgreSQL and SQLite repos for testing. You can immediately start experimenting:
   
   ```elixir
   # Test PostgreSQL functionality
   Lotus.run_sql("SELECT COUNT(*) FROM users", [], repo: "postgres")
   
   # Test SQLite functionality
   Lotus.run_sql("SELECT COUNT(*) FROM products", [], repo: "sqlite")
   
   # Create and run queries
   {:ok, query} = Lotus.create_query(%{
     name: "Test Query",
     statement: "SELECT 1 as test"
   })
   Lotus.run_query(query)
   ```

## Development Workflow

### Making Changes

1. **Create a feature branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Make your changes**
   - Follow the existing code style
   - Add tests for new functionality
   - Update documentation as needed

3. **Test your changes**
   ```bash
   # Run all tests
   mix test

   # Run specific test files
   mix test test/lotus/storage_test.exs

   # Run with coverage
   mix test --cover
   ```

4. **Ensure code quality**
   ```bash
   # Format code
   mix format

   # Run static analysis
   mix dialyzer

   # Run linting (if available)
   mix lint
   ```

5. **Commit your changes**
   ```bash
   git add .
   git commit -m "Add feature: your feature description"
   ```

6. **Push and create a pull request**
   ```bash
   git push origin feature/your-feature-name
   ```

### Code Style Guidelines

#### Elixir Style

- Use `mix format` to ensure consistent formatting
- Keep lines under 100 characters when possible
- Use descriptive variable and function names

#### Documentation

- All public functions must have `@doc` strings
- Use `@spec` for type specifications
- Include examples in documentation when helpful

```elixir
@doc """
Creates a new query with the given attributes.

## Parameters

  * `attrs` - A map containing query attributes

## Returns

  * `{:ok, query}` - Successfully created query
  * `{:error, changeset}` - Validation or database errors

## Examples

    iex> Lotus.create_query(%{name: "User Count", statement: "SELECT COUNT(*) FROM users"})
    {:ok, %Lotus.Storage.Query{}}

"""
@spec create_query(map()) :: {:ok, Query.t()} | {:error, Ecto.Changeset.t()}
def create_query(attrs) do
  # Implementation
end
```

#### Testing

- Write tests for all new functionality
- Use descriptive test names
- Group related tests with `describe` blocks
- Include both happy path and error case tests

```elixir
describe "create_query/1" do
  test "creates query with valid attributes" do
    attrs = %{name: "Test Query", statement: "SELECT 1"}

    assert {:ok, query} = Lotus.create_query(attrs)
    assert query.name == "Test Query"
  end

  test "returns error with invalid attributes" do
    attrs = %{name: "", statement: "SELECT 1"}

    assert {:error, changeset} = Lotus.create_query(attrs)
    assert "can't be blank" in errors_on(changeset).name
  end
end
```

## Types of Contributions

### Bug Reports

When reporting bugs, please include:

- **Environment**: Elixir version, OTP version, database type and version
- **Steps to reproduce**: Clear, step-by-step instructions
- **Expected behavior**: What you expected to happen
- **Actual behavior**: What actually happened
- **Error messages**: Full error messages and stack traces
- **Code samples**: Minimal code that reproduces the issue

### Feature Requests

For new features, please include:

- **Problem description**: What problem does this solve?
- **Proposed solution**: How would you like it to work?
- **Alternatives considered**: What other approaches did you consider?
- **Examples**: Show how the feature would be used

### Code Contributions

We welcome contributions of all sizes! Here are some areas where help is especially appreciated:

#### Good First Issues

- Documentation improvements
- Additional test coverage
- Small bug fixes
- Code formatting and style improvements

#### Medium Complexity

- New configuration options
- Performance optimizations
- Additional query validation features
- Enhanced error messages

#### Advanced Features

- Additional cache backends (Redis, Memcached, distributed caching)
- Cache statistics and telemetry integration (`Lotus.Cache.stats()`)
- Query performance monitoring and metrics
- Advanced security features
- Table visibility rule enhancements

## Pull Request Process

### Before Submitting

1. **Check existing issues**: Make sure your change isn't already being worked on
2. **Discuss large changes**: Open an issue to discuss major features or breaking changes
3. **Update documentation**: Include relevant documentation updates
4. **Add tests**: Ensure your changes are well-tested
5. **Follow conventions**: Match the existing code style and patterns

### Pull Request Template

When creating a pull request, please include:

```markdown
## Description
Brief description of the changes

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Documentation update
- [ ] Performance improvement
- [ ] Refactoring

## Testing
- [ ] Tests pass locally
- [ ] New tests added for functionality
- [ ] Documentation updated

## Checklist
- [ ] Code follows project style guidelines
- [ ] Self-review completed
- [ ] Comments added for complex logic
- [ ] Corresponding documentation updated
```

### Review Process

1. **Automated checks**: CI will run tests and style checks
2. **Code review**: Maintainers will review your changes
3. **Feedback**: Address any requested changes
4. **Approval**: Once approved, changes will be merged

## Development Guidelines

### Database Changes

When making changes that affect the database:

1. **Create migrations**: Use `Lotus.Migrations` for schema changes
2. **Test migrations**: Ensure migrations work both up and down on PostgreSQL and SQLite
3. **Update version**: Bump the migration version appropriately
4. **Test multi-database**: Verify changes work with both PostgreSQL and SQLite adapters

### Testing Multi-Database Features

When working on features that affect multiple database types:

```bash
# Test against PostgreSQL
mix test --exclude sqlite

# Test against SQLite  
mix test --only sqlite

# Test table visibility across adapters
mix test test/lotus/visibility_test.exs

# Test data repo functionality
mix test test/lotus/data_repo_test.exs
```

### Caching Features

When working on caching-related features:

```bash
# Test cache functionality
mix test test/lotus/cache_test.exs

# Test cache integration
mix test test/integration/caching_test.exs

# Test ETS adapter specifically
mix test test/lotus/cache/ets_test.exs
```

**Contributing New Cache Backends:**

To implement a new cache backend (Redis, Memcached, etc.):

1. **Implement the behaviour**: Create a module that implements `Lotus.Cache`
2. **Required callbacks**: `get_or_store/4`, `put/4`, `invalidate_tags/1`
3. **Add tests**: Create comprehensive tests following the ETS adapter pattern
4. **Add to documentation**: Update configuration guides and examples
5. **Consider dependencies**: Keep external dependencies optional when possible

**Cache Telemetry and Statistics:**

The caching system would benefit from:
- Cache hit/miss ratios
- Memory usage tracking
- TTL effectiveness metrics
- Tag invalidation statistics

### API Changes

For changes to the public API:

1. **Backward compatibility**: Avoid breaking existing functionality
2. **Deprecation process**: Deprecate before removing functionality
3. **Documentation**: Update all relevant documentation
4. **Examples**: Update examples in guides

### Performance Considerations

- **Benchmark changes**: Use `:timer.tc/1` or benchmarking tools for performance-critical changes
- **Memory usage**: Be mindful of memory allocation in hot paths
- **Database queries**: Optimize query patterns and avoid N+1 queries

## Release Process

### Versioning

Lotus follows [Semantic Versioning](https://semver.org/):

- **Major (1.0.0)**: Breaking changes
- **Minor (0.2.0)**: New features, backward compatible
- **Patch (0.0.1)**: Bug fixes, backward compatible

### Changelog

All notable changes are documented in `CHANGELOG.md`:

- **Added**: New features
- **Changed**: Changes in existing functionality
- **Deprecated**: Soon-to-be removed features
- **Removed**: Removed features
- **Fixed**: Bug fixes
- **Security**: Security improvements

## Community Guidelines

### Code of Conduct

We are committed to providing a welcoming and inspiring community for all. Please:

- **Be respectful**: Treat everyone with respect and kindness
- **Be inclusive**: Welcome newcomers and help them get started
- **Be constructive**: Provide helpful feedback and suggestions
- **Be patient**: Remember that everyone has different experience levels

### Communication

- **GitHub Issues**: For bug reports, feature requests, and discussions
- **Pull Requests**: For code contributions and reviews
- **Discussions**: For general questions and community interaction

### Getting Help

If you need help:

1. **Check the documentation**: Start with the guides and API documentation
2. **Search existing issues**: Your question might already be answered
3. **Ask in discussions**: Use GitHub Discussions for general questions
4. **Open an issue**: For specific bugs or feature requests

## Recognition

Contributors are recognized in:

- **CONTRIBUTORS.md**: List of all contributors
- **Release notes**: Acknowledgment in release announcements
- **Documentation**: Attribution for significant documentation contributions

## License

By contributing to Lotus, you agree that your contributions will be licensed under the same license as the project (MIT License).

---

Thank you for contributing to Lotus! Your help makes this project better for everyone.
