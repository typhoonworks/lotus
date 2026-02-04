defmodule Lotus.Fixtures do
  @moduledoc """
  Test fixtures for database tests.
  """

  alias Lotus.{Dashboards, Storage}
  alias Lotus.Test.Repo
  alias Lotus.Test.Schemas

  def insert_user(attrs \\ %{}, repo \\ Repo) do
    defaults = %{
      name: "User #{System.unique_integer([:positive])}",
      email: "user#{System.unique_integer([:positive])}@example.com",
      age: 25,
      active: true,
      metadata: %{"role" => "member"}
    }

    attrs = Map.merge(defaults, attrs)

    {:ok, user} =
      struct(Schemas.User, attrs)
      |> repo.insert()

    user
  end

  def insert_post(user_id, attrs \\ %{}, repo \\ Repo) do
    defaults = %{
      title: "Post #{System.unique_integer([:positive])}",
      content: "This is test content.",
      user_id: user_id,
      published: false,
      published_at: nil,
      view_count: 0,
      tags: ["test"]
    }

    attrs = Map.merge(defaults, attrs)

    {:ok, post} =
      struct(Schemas.Post, attrs)
      |> repo.insert()

    post
  end

  def setup_test_data do
    kerouac =
      insert_user(%{
        name: "Jack Kerouac",
        email: "jack@ontheroad.com",
        age: 47,
        active: true,
        metadata: %{"role" => "admin", "location" => "Lowell, MA", "style" => "spontaneous prose"}
      })

    thompson =
      insert_user(%{
        name: "Hunter S. Thompson",
        email: "hunter@gonzo.net",
        age: 37,
        active: true,
        metadata: %{
          "role" => "member",
          "location" => "Woody Creek, CO",
          "style" => "gonzo journalism"
        }
      })

    bukowski =
      insert_user(%{
        name: "Charles Bukowski",
        email: "hank@factotum.org",
        age: 73,
        active: false,
        metadata: %{
          "role" => "member",
          "location" => "Los Angeles, CA",
          "style" => "dirty realism"
        }
      })

    insert_post(kerouac.id, %{
      title: "The Mad Ones",
      content:
        "The only people for me are the mad ones, the ones who are mad to live, mad to talk, mad to be saved, desirous of everything at the same time.",
      published: true,
      view_count: 150,
      tags: ["beat", "prose", "dharma"]
    })

    insert_post(kerouac.id, %{
      title: "First Thought Best Thought",
      content:
        "Somewhere along the line I knew there'd be girls, visions, everything; somewhere along the line the pearl would be handed to me.",
      published: true,
      view_count: 75,
      tags: ["beat", "buddhism", "spontaneous"]
    })

    insert_post(thompson.id, %{
      title: "Draft: Fear and Loathing at the Typewriter",
      content:
        "We were somewhere around Barstow on the edge of the desert when the drugs began to take hold.",
      published: false,
      view_count: 0,
      tags: ["gonzo", "draft", "vegas"]
    })

    insert_post(bukowski.id, %{
      title: "Notes of a Dirty Old Man",
      content:
        "Find what you love and let it kill you. Let it drain you of your all. Let it cling onto your back and weigh you down into eventual nothingness.",
      published: true,
      view_count: 200,
      tags: ["poetry", "realism", "whiskey"]
    })

    %{
      users: %{kerouac: kerouac, thompson: thompson, bukowski: bukowski}
    }
  end

  def clean_test_data do
    Repo.query!("DELETE FROM test_posts", [])
    Repo.query!("DELETE FROM test_users", [])
  end

  @doc """
  Creates a query fixture for testing.

  ## Examples

      query = query_fixture()
      query = query_fixture(%{name: "Custom Query"})

  """
  def query_fixture(attrs \\ %{}) do
    defaults = %{
      name: "Test Query #{System.unique_integer([:positive])}",
      description: "A test query for automated testing",
      statement: "SELECT 1 as result"
    }

    attrs = Map.merge(defaults, attrs)

    {:ok, query} = Storage.create_query(attrs)
    query
  end

  @doc """
  Creates a visualization fixture for testing.

  ## Examples

      viz = visualization_fixture(query)
      viz = visualization_fixture(query, %{name: "Custom Viz"})

  """
  def visualization_fixture(query, attrs \\ %{}) do
    defaults = %{
      name: "Viz #{System.unique_integer([:positive])}",
      position: 0,
      config: %{"chart" => "table"}
    }

    attrs = Map.merge(defaults, attrs)

    {:ok, viz} = Lotus.Viz.create_visualization(query, attrs)
    viz
  end

  @doc """
  Creates a dashboard fixture for testing.

  ## Examples

      dashboard = dashboard_fixture()
      dashboard = dashboard_fixture(%{name: "Custom Dashboard"})

  """
  def dashboard_fixture(attrs \\ %{}) do
    defaults = %{
      name: "Dashboard #{System.unique_integer([:positive])}",
      description: "A test dashboard"
    }

    attrs = Map.merge(defaults, attrs)

    {:ok, dashboard} = Dashboards.create_dashboard(attrs)
    dashboard
  end

  @doc """
  Creates a dashboard card fixture for testing.

  ## Examples

      card = dashboard_card_fixture(dashboard, %{card_type: :text})
      card = dashboard_card_fixture(dashboard, %{card_type: :query, query_id: query.id})

  """
  def dashboard_card_fixture(dashboard, attrs \\ %{}) do
    defaults = %{
      card_type: :text,
      position: 0,
      content: %{"text" => "Test content"}
    }

    attrs = Map.merge(defaults, attrs)

    {:ok, card} = Dashboards.create_dashboard_card(dashboard, attrs)
    card
  end

  @doc """
  Creates a dashboard filter fixture for testing.

  ## Examples

      filter = dashboard_filter_fixture(dashboard)
      filter = dashboard_filter_fixture(dashboard, %{name: "custom_filter"})

  """
  def dashboard_filter_fixture(dashboard, attrs \\ %{}) do
    defaults = %{
      name: "filter_#{System.unique_integer([:positive])}",
      label: "Test Filter",
      filter_type: :text,
      widget: :input,
      position: 0
    }

    attrs = Map.merge(defaults, attrs)

    {:ok, filter} = Dashboards.create_dashboard_filter(dashboard, attrs)
    filter
  end

  @doc """
  Creates a filter mapping fixture for testing.

  ## Examples

      mapping = filter_mapping_fixture(card, filter, "user_id")

  """
  def filter_mapping_fixture(card, filter, variable_name, opts \\ []) do
    {:ok, mapping} = Dashboards.create_filter_mapping(card, filter, variable_name, opts)
    mapping
  end
end
