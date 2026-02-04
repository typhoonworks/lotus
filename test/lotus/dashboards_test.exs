defmodule Lotus.DashboardsTest do
  use Lotus.Case, async: true

  import Lotus.Fixtures

  alias Lotus.Dashboards

  alias Lotus.Storage.{
    Dashboard,
    DashboardCard,
    DashboardCardFilterMapping,
    DashboardFilter
  }

  describe "list_dashboards/0" do
    test "returns empty list when no dashboards exist" do
      assert [] == Dashboards.list_dashboards()
    end

    test "returns all dashboards ordered by name" do
      dashboard_fixture(%{name: "Zebra Dashboard"})
      dashboard_fixture(%{name: "Alpha Dashboard"})
      dashboard_fixture(%{name: "Middle Dashboard"})

      dashboards = Dashboards.list_dashboards()

      assert length(dashboards) == 3

      assert [%{name: "Alpha Dashboard"}, %{name: "Middle Dashboard"}, %{name: "Zebra Dashboard"}] =
               dashboards
    end
  end

  describe "list_dashboards_by/1" do
    test "filters by search term" do
      dashboard_fixture(%{name: "Sales Dashboard"})
      dashboard_fixture(%{name: "Marketing Dashboard"})
      dashboard_fixture(%{name: "Product Analytics"})

      results = Dashboards.list_dashboards_by(search: "Dashboard")
      assert length(results) == 2

      results = Dashboards.list_dashboards_by(search: "sales")
      assert length(results) == 1
      assert hd(results).name == "Sales Dashboard"
    end

    test "returns all dashboards when no search term" do
      dashboard_fixture(%{name: "Dashboard 1"})
      dashboard_fixture(%{name: "Dashboard 2"})

      results = Dashboards.list_dashboards_by([])
      assert length(results) == 2
    end
  end

  describe "get_dashboard/1" do
    test "returns dashboard when found" do
      dashboard = dashboard_fixture(%{name: "Test Dashboard"})
      result = Dashboards.get_dashboard(dashboard.id)

      assert result.id == dashboard.id
      assert result.name == "Test Dashboard"
    end

    test "returns nil when not found" do
      assert nil == Dashboards.get_dashboard(999_999)
    end
  end

  describe "get_dashboard!/1" do
    test "returns dashboard when found" do
      dashboard = dashboard_fixture()
      result = Dashboards.get_dashboard!(dashboard.id)
      assert result.id == dashboard.id
    end

    test "raises when not found" do
      assert_raise Ecto.NoResultsError, fn ->
        Dashboards.get_dashboard!(999_999)
      end
    end
  end

  describe "create_dashboard/1" do
    test "creates dashboard with valid attributes" do
      assert {:ok, %Dashboard{} = dashboard} =
               Dashboards.create_dashboard(%{name: "New Dashboard"})

      assert dashboard.name == "New Dashboard"
    end

    test "creates dashboard with all attributes" do
      assert {:ok, %Dashboard{} = dashboard} =
               Dashboards.create_dashboard(%{
                 name: "Full Dashboard",
                 description: "A complete dashboard",
                 settings: %{"theme" => "dark"},
                 auto_refresh_seconds: 300
               })

      assert dashboard.description == "A complete dashboard"
      assert dashboard.settings == %{"theme" => "dark"}
      assert dashboard.auto_refresh_seconds == 300
    end

    test "returns error with invalid attributes" do
      assert {:error, changeset} = Dashboards.create_dashboard(%{})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "update_dashboard/2" do
    test "updates dashboard with valid attributes" do
      dashboard = dashboard_fixture(%{name: "Original"})

      assert {:ok, %Dashboard{} = updated} =
               Dashboards.update_dashboard(dashboard, %{name: "Updated"})

      assert updated.name == "Updated"
    end

    test "returns error with invalid attributes" do
      dashboard = dashboard_fixture()

      assert {:error, changeset} =
               Dashboards.update_dashboard(dashboard, %{name: ""})

      assert %{name: _} = errors_on(changeset)
    end
  end

  describe "delete_dashboard/1" do
    test "deletes dashboard" do
      dashboard = dashboard_fixture()
      assert {:ok, %Dashboard{}} = Dashboards.delete_dashboard(dashboard)
      assert nil == Dashboards.get_dashboard(dashboard.id)
    end

    test "cascade deletes cards and filters" do
      dashboard = dashboard_fixture()
      dashboard_card_fixture(dashboard, %{card_type: :text, position: 0})
      dashboard_filter_fixture(dashboard)

      assert [_] = Dashboards.list_dashboard_cards(dashboard)
      assert [_] = Dashboards.list_dashboard_filters(dashboard)

      {:ok, _} = Dashboards.delete_dashboard(dashboard)

      assert [] == Dashboards.list_dashboard_cards(dashboard.id)
      assert [] == Dashboards.list_dashboard_filters(dashboard.id)
    end
  end

  describe "enable_public_sharing/1" do
    test "generates unique token" do
      dashboard = dashboard_fixture()
      assert dashboard.public_token == nil

      assert {:ok, %Dashboard{} = updated} = Dashboards.enable_public_sharing(dashboard)

      assert updated.public_token != nil
      assert String.length(updated.public_token) > 20
    end

    test "generates different tokens for different dashboards" do
      dashboard1 = dashboard_fixture()
      dashboard2 = dashboard_fixture()

      {:ok, updated1} = Dashboards.enable_public_sharing(dashboard1)
      {:ok, updated2} = Dashboards.enable_public_sharing(dashboard2)

      assert updated1.public_token != updated2.public_token
    end
  end

  describe "disable_public_sharing/1" do
    test "removes public token" do
      dashboard = dashboard_fixture()
      {:ok, with_token} = Dashboards.enable_public_sharing(dashboard)
      assert with_token.public_token != nil

      {:ok, without_token} = Dashboards.disable_public_sharing(with_token)
      assert without_token.public_token == nil
    end
  end

  describe "get_dashboard_by_token/1" do
    test "returns dashboard when token matches" do
      dashboard = dashboard_fixture()
      {:ok, with_token} = Dashboards.enable_public_sharing(dashboard)

      result = Dashboards.get_dashboard_by_token(with_token.public_token)
      assert result.id == dashboard.id
    end

    test "returns nil when token not found" do
      assert nil == Dashboards.get_dashboard_by_token("nonexistent_token")
    end
  end

  describe "list_dashboard_cards/1" do
    test "returns empty list when no cards exist" do
      dashboard = dashboard_fixture()
      assert [] == Dashboards.list_dashboard_cards(dashboard)
    end

    test "returns cards ordered by position then id" do
      dashboard = dashboard_fixture()

      {:ok, c1} =
        Dashboards.create_dashboard_card(dashboard, %{card_type: :text, position: 2, content: %{}})

      {:ok, c2} =
        Dashboards.create_dashboard_card(dashboard, %{card_type: :text, position: 0, content: %{}})

      {:ok, c3} =
        Dashboards.create_dashboard_card(dashboard, %{card_type: :text, position: 0, content: %{}})

      cards = Dashboards.list_dashboard_cards(dashboard)

      # Position 0 items first (ordered by id), then position 2
      assert [%{position: 0}, %{position: 0}, %{position: 2}] = cards
      assert Enum.at(cards, 0).id == c2.id
      assert Enum.at(cards, 1).id == c3.id
      assert Enum.at(cards, 2).id == c1.id
    end

    test "accepts dashboard id as argument" do
      dashboard = dashboard_fixture()
      dashboard_card_fixture(dashboard)

      assert [%DashboardCard{}] = Dashboards.list_dashboard_cards(dashboard.id)
    end
  end

  describe "create_dashboard_card/2" do
    test "creates text card" do
      dashboard = dashboard_fixture()

      assert {:ok, %DashboardCard{} = card} =
               Dashboards.create_dashboard_card(dashboard, %{
                 card_type: :text,
                 position: 0,
                 content: %{"text" => "Hello"}
               })

      assert card.card_type == :text
      assert card.content == %{"text" => "Hello"}
    end

    test "creates query card with query_id" do
      dashboard = dashboard_fixture()
      query = query_fixture()

      assert {:ok, %DashboardCard{} = card} =
               Dashboards.create_dashboard_card(dashboard, %{
                 card_type: :query,
                 query_id: query.id,
                 position: 0
               })

      assert card.card_type == :query
      assert card.query_id == query.id
    end

    test "creates card with layout" do
      dashboard = dashboard_fixture()

      assert {:ok, %DashboardCard{} = card} =
               Dashboards.create_dashboard_card(dashboard, %{
                 card_type: :text,
                 position: 0,
                 layout: %{x: 6, y: 2, w: 4, h: 3}
               })

      assert card.layout.x == 6
      assert card.layout.y == 2
      assert card.layout.w == 4
      assert card.layout.h == 3
    end

    test "accepts dashboard id as argument" do
      dashboard = dashboard_fixture()

      assert {:ok, %DashboardCard{}} =
               Dashboards.create_dashboard_card(dashboard.id, %{
                 card_type: :text,
                 position: 0
               })
    end
  end

  describe "update_dashboard_card/2" do
    test "updates card attributes" do
      dashboard = dashboard_fixture()
      card = dashboard_card_fixture(dashboard, %{title: "Original"})

      assert {:ok, %DashboardCard{} = updated} =
               Dashboards.update_dashboard_card(card, %{title: "Updated"})

      assert updated.title == "Updated"
    end

    test "updates layout" do
      dashboard = dashboard_fixture()
      card = dashboard_card_fixture(dashboard)

      assert {:ok, %DashboardCard{} = updated} =
               Dashboards.update_dashboard_card(card, %{layout: %{x: 3, y: 1, w: 8, h: 5}})

      assert updated.layout.x == 3
      assert updated.layout.w == 8
    end
  end

  describe "delete_dashboard_card/1" do
    test "deletes by struct" do
      dashboard = dashboard_fixture()
      card = dashboard_card_fixture(dashboard)

      assert {:ok, %DashboardCard{}} = Dashboards.delete_dashboard_card(card)
      assert [] == Dashboards.list_dashboard_cards(dashboard)
    end

    test "deletes by id" do
      dashboard = dashboard_fixture()
      card = dashboard_card_fixture(dashboard)

      assert {:ok, %DashboardCard{}} = Dashboards.delete_dashboard_card(card.id)
      assert [] == Dashboards.list_dashboard_cards(dashboard)
    end

    test "returns error when not found" do
      assert {:error, :not_found} = Dashboards.delete_dashboard_card(999_999)
    end
  end

  describe "reorder_dashboard_cards/2" do
    test "updates positions based on order" do
      dashboard = dashboard_fixture()

      {:ok, c1} = Dashboards.create_dashboard_card(dashboard, %{card_type: :text, position: 0})
      {:ok, c2} = Dashboards.create_dashboard_card(dashboard, %{card_type: :text, position: 1})
      {:ok, c3} = Dashboards.create_dashboard_card(dashboard, %{card_type: :text, position: 2})

      # Reorder: c3, c1, c2
      assert :ok = Dashboards.reorder_dashboard_cards(dashboard, [c3.id, c1.id, c2.id])

      cards = Dashboards.list_dashboard_cards(dashboard)
      assert Enum.map(cards, & &1.id) == [c3.id, c1.id, c2.id]
      assert Enum.map(cards, & &1.position) == [0, 1, 2]
    end
  end

  describe "list_dashboard_filters/1" do
    test "returns empty list when no filters exist" do
      dashboard = dashboard_fixture()
      assert [] == Dashboards.list_dashboard_filters(dashboard)
    end

    test "returns filters ordered by position then id" do
      dashboard = dashboard_fixture()

      {:ok, f1} =
        Dashboards.create_dashboard_filter(dashboard, %{
          name: "f1",
          label: "Filter 1",
          filter_type: :text,
          widget: :input,
          position: 2
        })

      {:ok, f2} =
        Dashboards.create_dashboard_filter(dashboard, %{
          name: "f2",
          label: "Filter 2",
          filter_type: :text,
          widget: :input,
          position: 0
        })

      filters = Dashboards.list_dashboard_filters(dashboard)

      assert [%{name: "f2"}, %{name: "f1"}] = filters
      assert Enum.at(filters, 0).id == f2.id
      assert Enum.at(filters, 1).id == f1.id
    end
  end

  describe "create_dashboard_filter/2" do
    test "creates filter with valid attributes" do
      dashboard = dashboard_fixture()

      assert {:ok, %DashboardFilter{} = filter} =
               Dashboards.create_dashboard_filter(dashboard, %{
                 name: "date_range",
                 label: "Select Dates",
                 filter_type: :date_range,
                 widget: :date_range_picker,
                 position: 0
               })

      assert filter.name == "date_range"
      assert filter.filter_type == :date_range
    end

    test "creates filter with default value" do
      dashboard = dashboard_fixture()

      assert {:ok, %DashboardFilter{} = filter} =
               Dashboards.create_dashboard_filter(dashboard, %{
                 name: "status",
                 label: "Status",
                 filter_type: :select,
                 widget: :select,
                 position: 0,
                 default_value: "active",
                 config: %{"options" => ["active", "inactive"]}
               })

      assert filter.default_value == "active"
      assert filter.config == %{"options" => ["active", "inactive"]}
    end
  end

  describe "update_dashboard_filter/2" do
    test "updates filter attributes" do
      dashboard = dashboard_fixture()
      filter = dashboard_filter_fixture(dashboard, %{label: "Original"})

      assert {:ok, %DashboardFilter{} = updated} =
               Dashboards.update_dashboard_filter(filter, %{label: "Updated"})

      assert updated.label == "Updated"
    end
  end

  describe "delete_dashboard_filter/1" do
    test "deletes by struct" do
      dashboard = dashboard_fixture()
      filter = dashboard_filter_fixture(dashboard)

      assert {:ok, %DashboardFilter{}} = Dashboards.delete_dashboard_filter(filter)
      assert [] == Dashboards.list_dashboard_filters(dashboard)
    end

    test "deletes by id" do
      dashboard = dashboard_fixture()
      filter = dashboard_filter_fixture(dashboard)

      assert {:ok, %DashboardFilter{}} = Dashboards.delete_dashboard_filter(filter.id)
    end

    test "returns error when not found" do
      assert {:error, :not_found} = Dashboards.delete_dashboard_filter(999_999)
    end
  end

  describe "create_filter_mapping/4" do
    test "creates mapping between filter and card variable" do
      dashboard = dashboard_fixture()
      query = query_fixture(%{statement: "SELECT * FROM users WHERE id = {{user_id}}"})
      card = dashboard_card_fixture(dashboard, %{card_type: :query, query_id: query.id})
      filter = dashboard_filter_fixture(dashboard)

      assert {:ok, %DashboardCardFilterMapping{} = mapping} =
               Dashboards.create_filter_mapping(card, filter, "user_id")

      assert mapping.card_id == card.id
      assert mapping.filter_id == filter.id
      assert mapping.variable_name == "user_id"
    end

    test "creates mapping with transform" do
      dashboard = dashboard_fixture()
      query = query_fixture()
      card = dashboard_card_fixture(dashboard, %{card_type: :query, query_id: query.id})

      filter =
        dashboard_filter_fixture(dashboard, %{
          filter_type: :date_range,
          widget: :date_range_picker
        })

      assert {:ok, %DashboardCardFilterMapping{} = mapping} =
               Dashboards.create_filter_mapping(card, filter, "start_date",
                 transform: %{"type" => "date_range_start"}
               )

      assert mapping.transform == %{"type" => "date_range_start"}
    end

    test "accepts card and filter ids" do
      dashboard = dashboard_fixture()
      query = query_fixture()
      card = dashboard_card_fixture(dashboard, %{card_type: :query, query_id: query.id})
      filter = dashboard_filter_fixture(dashboard)

      assert {:ok, %DashboardCardFilterMapping{}} =
               Dashboards.create_filter_mapping(card.id, filter.id, "var_name")
    end
  end

  describe "list_card_filter_mappings/1" do
    test "returns mappings for a card" do
      dashboard = dashboard_fixture()
      query = query_fixture()
      card = dashboard_card_fixture(dashboard, %{card_type: :query, query_id: query.id})
      filter1 = dashboard_filter_fixture(dashboard, %{name: "filter1"})
      filter2 = dashboard_filter_fixture(dashboard, %{name: "filter2"})

      filter_mapping_fixture(card, filter1, "var1")
      filter_mapping_fixture(card, filter2, "var2")

      mappings = Dashboards.list_card_filter_mappings(card)

      assert length(mappings) == 2
      assert Enum.all?(mappings, &(&1.card_id == card.id))
    end

    test "preloads filter association" do
      dashboard = dashboard_fixture()
      query = query_fixture()
      card = dashboard_card_fixture(dashboard, %{card_type: :query, query_id: query.id})
      filter = dashboard_filter_fixture(dashboard, %{name: "my_filter"})

      filter_mapping_fixture(card, filter, "var")

      [mapping] = Dashboards.list_card_filter_mappings(card)

      assert %DashboardFilter{name: "my_filter"} = mapping.filter
    end
  end

  describe "delete_filter_mapping/1" do
    test "deletes mapping" do
      dashboard = dashboard_fixture()
      query = query_fixture()
      card = dashboard_card_fixture(dashboard, %{card_type: :query, query_id: query.id})
      filter = dashboard_filter_fixture(dashboard)
      mapping = filter_mapping_fixture(card, filter, "var")

      assert {:ok, %DashboardCardFilterMapping{}} = Dashboards.delete_filter_mapping(mapping)
      assert [] == Dashboards.list_card_filter_mappings(card)
    end

    test "returns error when not found" do
      assert {:error, :not_found} = Dashboards.delete_filter_mapping(999_999)
    end
  end

  describe "run_dashboard_card/2" do
    test "returns error for non-query cards" do
      dashboard = dashboard_fixture()
      card = dashboard_card_fixture(dashboard, %{card_type: :text})

      assert {:error, :not_a_query_card} = Dashboards.run_dashboard_card(card)
    end

    test "returns error when card not found" do
      assert {:error, :not_found} = Dashboards.run_dashboard_card(999_999)
    end
  end

  describe "Lotus module delegations" do
    test "delegates list_dashboards/0" do
      dashboard_fixture(%{name: "Delegated"})
      assert [%{name: "Delegated"}] = Lotus.list_dashboards()
    end

    test "delegates create_dashboard/1" do
      assert {:ok, %Dashboard{name: "Created"}} =
               Lotus.create_dashboard(%{name: "Created"})
    end

    test "delegates get_dashboard/1" do
      dashboard = dashboard_fixture()
      assert %Dashboard{} = Lotus.get_dashboard(dashboard.id)
    end

    test "delegates get_dashboard!/1" do
      dashboard = dashboard_fixture()
      assert %Dashboard{} = Lotus.get_dashboard!(dashboard.id)
    end

    test "delegates update_dashboard/2" do
      dashboard = dashboard_fixture()

      assert {:ok, %Dashboard{name: "Updated"}} =
               Lotus.update_dashboard(dashboard, %{name: "Updated"})
    end

    test "delegates delete_dashboard/1" do
      dashboard = dashboard_fixture()
      assert {:ok, %Dashboard{}} = Lotus.delete_dashboard(dashboard)
    end

    test "delegates enable_public_sharing/1" do
      dashboard = dashboard_fixture()

      assert {:ok, %Dashboard{public_token: token}} =
               Lotus.enable_public_sharing(dashboard)

      assert token != nil
    end

    test "delegates disable_public_sharing/1" do
      dashboard = dashboard_fixture()
      {:ok, with_token} = Lotus.enable_public_sharing(dashboard)

      assert {:ok, %Dashboard{public_token: nil}} =
               Lotus.disable_public_sharing(with_token)
    end

    test "delegates get_dashboard_by_token/1" do
      dashboard = dashboard_fixture()
      {:ok, with_token} = Lotus.enable_public_sharing(dashboard)
      assert %Dashboard{} = Lotus.get_dashboard_by_token(with_token.public_token)
    end

    test "delegates list_dashboard_cards/1" do
      dashboard = dashboard_fixture()
      dashboard_card_fixture(dashboard)
      assert [%DashboardCard{}] = Lotus.list_dashboard_cards(dashboard)
    end

    test "delegates create_dashboard_card/2" do
      dashboard = dashboard_fixture()

      assert {:ok, %DashboardCard{}} =
               Lotus.create_dashboard_card(dashboard, %{card_type: :text, position: 0})
    end

    test "delegates list_dashboard_filters/1" do
      dashboard = dashboard_fixture()
      dashboard_filter_fixture(dashboard)
      assert [%DashboardFilter{}] = Lotus.list_dashboard_filters(dashboard)
    end

    test "delegates create_dashboard_filter/2" do
      dashboard = dashboard_fixture()

      assert {:ok, %DashboardFilter{}} =
               Lotus.create_dashboard_filter(dashboard, %{
                 name: "test",
                 label: "Test",
                 filter_type: :text,
                 widget: :input,
                 position: 0
               })
    end

    test "delegates create_filter_mapping/4" do
      dashboard = dashboard_fixture()
      query = query_fixture()
      card = dashboard_card_fixture(dashboard, %{card_type: :query, query_id: query.id})
      filter = dashboard_filter_fixture(dashboard)

      assert {:ok, %DashboardCardFilterMapping{}} =
               Lotus.create_filter_mapping(card, filter, "var")
    end

    test "delegates list_card_filter_mappings/1" do
      dashboard = dashboard_fixture()
      query = query_fixture()
      card = dashboard_card_fixture(dashboard, %{card_type: :query, query_id: query.id})
      filter = dashboard_filter_fixture(dashboard)
      filter_mapping_fixture(card, filter, "var")

      assert [%DashboardCardFilterMapping{}] = Lotus.list_card_filter_mappings(card)
    end
  end
end
