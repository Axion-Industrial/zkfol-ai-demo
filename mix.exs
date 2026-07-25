defmodule Zkfol.MixProject do
  use Mix.Project

  def project do
    [
      app: :zkfol,
      version: "0.2.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      dialyzer: [
        plt_add_apps: [:ex_unit, :crypto, :mnesia],
        ignore_warnings: ".dialyzer_ignore.exs"
      ],
      deps: deps()
    ]
  end

  def application do
    [
      mod: {Zkfol.Application, []},
      extra_applications: [:logger, :crypto]
    ]
  end

  defp deps do
    [
      {:ex_example, "~> 0.1.2"},
      {:event_broker, "~> 1.1.1"},
      {:rustler, "~> 0.38.0", runtime: false},
      {:gt_bridge, "~> 0.19.1", override: true},
      {:al,
       git: "https://github.com/anoma/anoma-level-elixir-prototype.git",
       branch: "mariari/mnesia-dir-config-0.1.4"},
      {:typed_struct, "~> 0.3"},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end
end
