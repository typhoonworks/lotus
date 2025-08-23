defmodule Lotus.Fixtures do
  @moduledoc """
  Test fixtures for database tests.
  """

  alias Lotus.Test.Repo
  alias Lotus.Test.Schemas
  alias Lotus.Storage

  def insert_user(attrs \\ %{}) do
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
      |> Repo.insert()

    user
  end

  def insert_post(user_id, attrs \\ %{}) do
    defaults = %{
      title: "Post #{System.unique_integer([:positive])}",
      content: "This is test content.",
      user_id: user_id,
      published: false,
      view_count: 0,
      tags: ["test"]
    }

    attrs = Map.merge(defaults, attrs)

    {:ok, post} =
      struct(Schemas.Post, attrs)
      |> Repo.insert()

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
end
