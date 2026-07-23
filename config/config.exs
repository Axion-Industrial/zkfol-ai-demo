import Config

# AL keeps its store in the host's cwd; these packages seed a fresh image.
config :al,
  packages: [
    AL.Package.Bootstrap,
    AL.Package.Users,
    AL.Package.ElixirProcess,
    AL.Package.Constraints,
    AL.Package.Equations
  ]

# Tests keep their own store, apart from a live node's log.
if config_env() == :test do
  config :al, mnesia_dir: ".mnesiastore-test/"
end
