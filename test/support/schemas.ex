defmodule Lotus.Test.Schemas do
  @moduledoc """
  Test schemas for fixtures.
  """

  defmodule User do
    @moduledoc false
    use Ecto.Schema

    @primary_key {:id, :id, autogenerate: true}
    @foreign_key_type :id

    schema "test_users" do
      field(:name, :string)
      field(:email, :string)
      field(:age, :integer)
      field(:active, :boolean, default: true)
      field(:metadata, :map)

      has_many(:posts, Lotus.Test.Schemas.Post, foreign_key: :user_id)

      timestamps()
    end
  end

  defmodule Post do
    @moduledoc false
    use Ecto.Schema

    @primary_key {:id, :id, autogenerate: true}
    @foreign_key_type :id

    schema "test_posts" do
      field(:title, :string)
      field(:content, :string)
      field(:published, :boolean, default: false)
      field(:published_at, :utc_datetime)
      field(:view_count, :integer, default: 0)
      field(:tags, {:array, :string}, default: [])

      belongs_to(:user, Lotus.Test.Schemas.User)

      timestamps()
    end
  end
end
