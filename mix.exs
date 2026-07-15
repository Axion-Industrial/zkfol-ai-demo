defmodule Zkfol.MixProject do
  use Mix.Project

  def project do
    [
      app: :zkfol,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      dialyzer: [plt_add_apps: [:ex_unit, :crypto, :mnesia]],
      deps: deps()
    ]
  end

  def application do
    [
      mod: {Zkfol.Application, []},
      extra_applications: [:logger, :crypto, :mnesia]
    ]
  end

  defp deps do
    [
      {:ex_example, "~> 0.1.2"},
      {:rustler, "~> 0.38.0", runtime: false},
      {:gt_bridge, "~> 0.18.1"},
      {:typed_struct, "~> 0.3"},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end
end
