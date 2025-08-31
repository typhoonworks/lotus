defmodule Lotus.Cache.Key do
  @moduledoc false

  @spec result(binary(), map() | list(), keyword()) :: binary()
  def result(sql, bound, opts) do
    repo = Keyword.fetch!(opts, :data_repo)
    path = Keyword.get(opts, :search_path, "") || ""
    version = Keyword.get(opts, :lotus_version, Lotus.version())

    digest_input =
      case bound do
        %{} = vars -> vars
        list when is_list(list) -> %{__params__: list}
      end

    digest =
      :crypto.hash(
        :sha256,
        [sql, ?|, :erlang.term_to_binary(digest_input), ?|, repo, ?|, path, ?|, version]
      )
      |> Base.encode16(case: :lower)

    "result:#{repo}:#{digest}"
  end
end
