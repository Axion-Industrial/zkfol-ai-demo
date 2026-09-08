import Config

# AL keeps its store in the host's cwd; these packages seed a fresh image.
config :al,
  packages: [
    AL.Package.Bootstrap,
    AL.Package.ElixirProcess,
    AL.Package.Mapset,
    AL.Package.Interval,
    AL.Package.Constraints,
    AL.Package.Equations
  ]

# Tests keep their own store, apart from a live node's log.
if config_env() == :test do
  System.put_env("AL_MNESIA_DISTRIBUTED", "false")
  config :al, mnesia_dir: ".mnesiastore-test/"
end
