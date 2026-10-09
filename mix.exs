defmodule ZkfolAiDemo.MixProject do
  use Mix.Project

  def project do
    [
      app: :zkfol_ai_demo,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      dialyzer: [plt_add_apps: [:ex_unit, :crypto, :inets, :ssl, :public_key]],
      deps: deps()
    ]
  end

  def application do
    [
      mod: {ZkfolAiDemo.Application, []},
      extra_applications: [:logger, :crypto, :inets, :ssl, :public_key]
    ]
  end

  # zkFOL is a git dependency. The branch carries the proof export and the standalone
  # verifier this demo needs; until it is merged, the demo points at it.
  defp deps do
    [
      {:zkfol,
       git: "https://github.com/Axion-Industrial/zkfol-ai-demo.git",
       branch: "zkfol-ai/with-strings"},
      {:ex_example, "~> 0.1.2"},
      {:typed_struct, "~> 0.3"},
      {:gt_bridge, "~> 0.20.1", override: true},
      {:al, git: "https://github.com/anoma/AL-Ex.git", tag: "0.3.0"},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end
end
