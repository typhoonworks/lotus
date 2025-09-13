defmodule Lotus.Visibility.PolicyTest do
  use ExUnit.Case, async: true
  alias Lotus.Visibility.Policy

  describe "schema policies" do
    test "schema_allow/0" do
      assert Policy.schema_allow() == :allow
    end

    test "schema_deny/0" do
      assert Policy.schema_deny() == :deny
    end

    test "valid_schema_policy?/1" do
      assert Policy.valid_schema_policy?(:allow) == true
      assert Policy.valid_schema_policy?(:deny) == true
      assert Policy.valid_schema_policy?(:invalid) == false
      assert Policy.valid_schema_policy?(%{}) == false
    end
  end

  describe "table policies" do
    test "table_allow/0" do
      assert Policy.table_allow() == :allow
    end

    test "table_deny/0" do
      assert Policy.table_deny() == :deny
    end

    test "valid_table_policy?/1" do
      assert Policy.valid_table_policy?(:allow) == true
      assert Policy.valid_table_policy?(:deny) == true
      assert Policy.valid_table_policy?(:invalid) == false
      assert Policy.valid_table_policy?(%{}) == false
    end
  end

  describe "column policies" do
    test "column_allow/0" do
      policy = Policy.column_allow()
      assert policy == %{action: :allow, mask: nil, show_in_schema?: true}
    end

    test "column_allow/1 with options" do
      policy = Policy.column_allow(show_in_schema?: false)
      assert policy == %{action: :allow, mask: nil, show_in_schema?: false}
    end

    test "column_omit/0" do
      policy = Policy.column_omit()
      assert policy == %{action: :omit, mask: nil, show_in_schema?: true}
    end

    test "column_omit/1 with options" do
      policy = Policy.column_omit(show_in_schema?: false)
      assert policy == %{action: :omit, mask: nil, show_in_schema?: false}
    end

    test "column_error/0" do
      policy = Policy.column_error()
      assert policy == %{action: :error, mask: nil, show_in_schema?: true}
    end

    test "column_error/1 with options" do
      policy = Policy.column_error(show_in_schema?: false)
      assert policy == %{action: :error, mask: nil, show_in_schema?: false}
    end

    test "column_mask/1 with different strategies" do
      policy = Policy.column_mask(:null)
      assert policy == %{action: :mask, mask: :null, show_in_schema?: true}

      policy = Policy.column_mask(:sha256)
      assert policy == %{action: :mask, mask: :sha256, show_in_schema?: true}

      policy = Policy.column_mask({:fixed, "REDACTED"})
      assert policy == %{action: :mask, mask: {:fixed, "REDACTED"}, show_in_schema?: true}

      policy = Policy.column_mask({:partial, keep_last: 4})
      assert policy == %{action: :mask, mask: {:partial, keep_last: 4}, show_in_schema?: true}
    end

    test "column_mask/2 with options" do
      policy = Policy.column_mask(:sha256, show_in_schema?: false)
      assert policy == %{action: :mask, mask: :sha256, show_in_schema?: false}
    end

    test "valid_column_policy?/1" do
      assert Policy.valid_column_policy?(%{action: :allow}) == true
      assert Policy.valid_column_policy?(%{action: :omit}) == true
      assert Policy.valid_column_policy?(%{action: :mask}) == true
      assert Policy.valid_column_policy?(%{action: :error}) == true
      assert Policy.valid_column_policy?(%{action: :invalid}) == false
      assert Policy.valid_column_policy?(%{}) == false
      assert Policy.valid_column_policy?(:allow) == false
    end
  end

  describe "mask strategy validation" do
    test "validate_mask_strategy!/1 with valid strategies" do
      assert Policy.validate_mask_strategy!(:null) == :null
      assert Policy.validate_mask_strategy!(:sha256) == :sha256
      assert Policy.validate_mask_strategy!({:fixed, "test"}) == {:fixed, "test"}
      assert Policy.validate_mask_strategy!({:partial, keep_last: 4}) == {:partial, keep_last: 4}
    end

    test "validate_mask_strategy!/1 with invalid strategies" do
      assert_raise ArgumentError, ~r/Invalid mask strategy/, fn ->
        Policy.validate_mask_strategy!(:invalid)
      end

      assert_raise ArgumentError, ~r/Invalid mask strategy/, fn ->
        Policy.validate_mask_strategy!({:unknown, "value"})
      end

      assert_raise ArgumentError, ~r/Invalid mask strategy/, fn ->
        Policy.validate_mask_strategy!("not_atom")
      end
    end
  end

  describe "normalize_column_policy/1" do
    test "normalizes keyword list" do
      policy =
        Policy.normalize_column_policy(action: :mask, mask: :sha256, show_in_schema?: false)

      expected = %{action: :mask, mask: :sha256, show_in_schema?: false}
      assert policy == expected
    end

    test "normalizes keyword list with defaults" do
      policy = Policy.normalize_column_policy([])
      expected = %{action: :mask, mask: :null, show_in_schema?: true}
      assert policy == expected
    end

    test "normalizes atom shorthand" do
      assert Policy.normalize_column_policy(:allow) == %{
               action: :allow,
               mask: nil,
               show_in_schema?: true
             }

      assert Policy.normalize_column_policy(:omit) == %{
               action: :omit,
               mask: nil,
               show_in_schema?: true
             }

      assert Policy.normalize_column_policy(:error) == %{
               action: :error,
               mask: nil,
               show_in_schema?: true
             }

      assert Policy.normalize_column_policy(:mask) == %{
               action: :mask,
               mask: :null,
               show_in_schema?: true
             }
    end

    test "normalizes map" do
      input = %{action: :mask, mask: :sha256}
      expected = %{action: :mask, mask: :sha256, show_in_schema?: true}
      assert Policy.normalize_column_policy(input) == expected
    end

    test "normalizes map with defaults" do
      input = %{}
      expected = %{action: :mask, mask: :null, show_in_schema?: true}
      assert Policy.normalize_column_policy(input) == expected
    end
  end

  describe "helper functions" do
    test "requires_mask?/1" do
      assert Policy.requires_mask?(%{action: :mask}) == true
      assert Policy.requires_mask?(%{action: :allow}) == false
      assert Policy.requires_mask?(%{action: :omit}) == false
      assert Policy.requires_mask?(%{action: :error}) == false
    end

    test "causes_error?/1" do
      assert Policy.causes_error?(%{action: :error}) == true
      assert Policy.causes_error?(%{action: :allow}) == false
      assert Policy.causes_error?(%{action: :omit}) == false
      assert Policy.causes_error?(%{action: :mask}) == false
    end

    test "omits_column?/1" do
      assert Policy.omits_column?(%{action: :omit}) == true
      assert Policy.omits_column?(%{action: :allow}) == false
      assert Policy.omits_column?(%{action: :error}) == false
      assert Policy.omits_column?(%{action: :mask}) == false
    end

    test "allows_column?/1" do
      assert Policy.allows_column?(%{action: :allow}) == true
      assert Policy.allows_column?(%{action: :omit}) == false
      assert Policy.allows_column?(%{action: :error}) == false
      assert Policy.allows_column?(%{action: :mask}) == false
    end

    test "hidden_from_schema?/1" do
      assert Policy.hidden_from_schema?(%{show_in_schema?: false}) == true
      assert Policy.hidden_from_schema?(%{show_in_schema?: true}) == false
      # default show_in_schema?: true
      assert Policy.hidden_from_schema?(%{action: :mask}) == false
      assert Policy.hidden_from_schema?(nil) == false
      assert Policy.hidden_from_schema?("invalid") == false
    end
  end

  describe "backwards compatibility" do
    test "existing column visibility patterns still work" do
      # These are patterns from the existing tests
      _rules = [
        {"public", "users", "password", [mask: :sha256]},
        {"users", "api_key", :omit},
        {"password_hash", :error}
      ]

      # The normalize function should handle all these formats
      policy1 = Policy.normalize_column_policy(mask: :sha256)
      assert policy1.action == :mask
      assert policy1.mask == :sha256

      policy2 = Policy.normalize_column_policy(:omit)
      assert policy2.action == :omit

      policy3 = Policy.normalize_column_policy(:error)
      assert policy3.action == :error
    end

    test "can mix builder functions with raw policies" do
      # Using builder functions
      builder_policy = Policy.column_mask(:sha256)

      # Using raw keyword list (existing format)
      raw_policy = Policy.normalize_column_policy(action: :mask, mask: :sha256)

      # Should produce equivalent results
      assert builder_policy == raw_policy
    end
  end

  describe "extensibility examples" do
    test "policy structure supports future extensions" do
      # The map-based approach allows easy extension
      extended_policy = Map.put(Policy.column_mask(:sha256), :audit_log, true)

      # Still validates as a column policy
      assert Policy.valid_column_policy?(extended_policy) == true
      assert Policy.requires_mask?(extended_policy) == true
    end
  end
end
