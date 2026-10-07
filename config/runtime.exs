import Config

if config_env() != :test and Node.alive?() do
  System.put_env("AL_MNESIA_DISTRIBUTED", "false")
  config :al, mnesia_dir: System.get_env("AL_MNESIA_DIR") || ".mnesiastore-#{node()}/"
end
