import Config

import Cachex.Spec

config :lotus,
  cache: %{
    adapter: Lotus.Cache.Cachex,
    namespace: "lotus_dev",
    cachex_opts: [router: router(module: Cachex.Router.Ring, options: [monitor: true])]
  }
