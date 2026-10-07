import Config

# AL keeps its store in the host's cwd; these programs and packages seed a fresh image.
# Its file projection of the store would land in src/, the GT package, so it stays off.
config :al,
  transaction_programs: [AL.TransactionProgram.Bootstrap, AL.TransactionProgram.PackageSystem],
  package_channels: [{:builtin, {:priv, "packages"}}],
  package_environment: [:elixir_process, :mapset, :interval, :constraints],
  serialisation_dir: nil

# AL's MCP server sits off its 3031 default: 3030 next door is the GT MCP server.
config :al, AL.MCP, port: 3033

# Tests keep their own store, apart from a live node's log, and serve nothing.
if config_env() == :test do
  System.put_env("AL_MNESIA_DISTRIBUTED", "false")
  config :al, mnesia_dir: ".mnesiastore-test/"
  config :al, AL.MCP, enabled: false
end
