[
  # The spec is intentionally more general than the implementation
  # to allow for future versions without breaking the API
  {"lib/lotus/migrations.ex", :contract_supertype, 17},

  # opts() type is intentionally flexible for future expansion
  {"lib/lotus.ex", :contract_supertype, 101},

  # :composite type is available for manual type annotations and custom handlers
  # but not automatically detected from schema (requires additional pg_type queries)
  {"lib/lotus/storage/type_mapper.ex", :extra_range, 64}
]

