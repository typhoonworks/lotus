defmodule Lotus.Cache.Key do
  @moduledoc false

  @spec result(binary(), map(), keyword()) :: binary()
  def result(sql, bound_vars_map, opts) do
    repo = Keyword.fetch!(opts, :data_repo)
    path = Keyword.get(opts, :search_path, "public")
    version = Keyword.get(opts, :lotus_version, Lotus.version())

    digest =
      :crypto.hash(
        :sha256,
        [sql, ?|, :erlang.term_to_binary(bound_vars_map), ?|, repo, ?|, path, ?|, version]
      )
      |> Base.encode16(case: :lower)

    "result:#{repo}:#{digest}"
  end

  @spec var_options(binary(), keyword()) :: binary()
  def var_options(sql, opts) do
    repo = Keyword.fetch!(opts, :data_repo)
    digest = :crypto.hash(:sha256, [sql, ?|, repo]) |> Base.encode16(case: :lower)
    "varopts:#{repo}:#{digest}"
  end
end
