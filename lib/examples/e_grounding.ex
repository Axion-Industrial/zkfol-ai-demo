defmodule Examples.EGrounding do
  @moduledoc """
  I am the grounding policy's evidence: a figure in the sources proves, a figure outside them
  is refused by the prover, and the sources a proof was made against are the ones it binds.
  """

  use ExExample

  import ExUnit.Assertions

  alias ZkfolAiDemo.Context
  alias ZkfolAiDemo.Figures
  alias ZkfolAiDemo.Gate
  alias ZkfolAiDemo.Gate.Release
  alias ZkfolAiDemo.Gate.Withheld
  alias ZkfolAiDemo.Grounding
  alias ZkfolAiDemo.Statement
  alias Zkfol.Verifier
  alias Zkfol.Verifier.Request

  @sources [
    "Revenue was $4,200,000 in 2023, up 12.5% on 2022. Headcount: 310.",
    "Costs were 3.1 million."
  ]

  @doc "Every example writes files and starts a process, so none is cached."
  @spec rerun?(term()) :: boolean()
  def rerun?(_example), do: true

  @doc "Figures are read as integers: formatting differences vanish, and 3.5 is not 35."
  @spec figures() :: [non_neg_integer()]
  example figures do
    assert {:ok, [a, b, c]} = Figures.extract("1,234.50 and 1234.5 and 1234.50")
    assert a == b and b == c

    {:ok, [three_and_a_half, thirty_five]} = Figures.extract("3.5 then 35")
    assert three_and_a_half != thirty_five

    assert Figures.extract("&#52;2") == Figures.extract("42")
    assert {:ok, []} = Figures.extract("no digits at all")
    assert {:error, {:figure_exceeds_cell, _}} = Figures.extract("1234567890123456")
    [a, three_and_a_half, thirty_five]
  end

  @doc "An output whose every figure is in the sources is released, with a verifiable proof."
  @spec grounded_output_is_released() :: Release.t()
  example grounded_output_is_released do
    out = "In 2023 revenue was 4,200,000, up 12.5%, with 310 staff."

    assert {:released, %Release{} = release} =
             Gate.release(Grounding.statement(out, @sources, context()), prefix("grounded"))

    # The verifier reports the source table it was shown, so it can be pinned.
    assert release.accepted.bindings["sources"] =~ ~r/^[0-9a-f]+$/
    release
  end

  @doc "A figure outside the sources reaches the real prover, which cannot prove it."
  @spec ungrounded_figure_is_refused_by_the_prover() :: Withheld.t()
  example ungrounded_figure_is_refused_by_the_prover do
    out = "Revenue was 4,200,001 in 2023."

    assert {:withheld, %Withheld{stage: :prove, reason: {:verifier_rejected, _}} = withheld} =
             Gate.release(Grounding.statement(out, @sources, context()), prefix("ungrounded"))

    withheld
  end

  @doc "The sources are public and pinned: a proof made against other sources does not verify."
  @spec proof_against_other_sources_is_rejected() :: String.t()
  example proof_against_other_sources_is_rejected do
    %Release{request: request} = grounded_output_is_released()
    {:ok, other} = Grounding.statement("In 2023 revenue was 4,200,000.", ["4,200,000"], context())
    pins = request.pins |> File.read!() |> JSON.decode!()
    pins = Map.put(pins, "sources", Statement.pins(other)["sources"])

    assert {:error, {:verifier_rejected, %{said: said}}} =
             Verifier.verify(%{request | pins: Verifier.pin(pins, request.pins <> ".other")})

    assert said =~ "sources"
    said
  end

  @doc "Nothing to ground is grounded: an output with no figures proves."
  @spec output_without_figures_is_released() :: Release.t()
  example output_without_figures_is_released do
    assert {:released, %Release{} = release} =
             Gate.release(Grounding.statement("No figures.", @sources, context()), prefix("none"))

    assert {:ok, _} = Verifier.verify(%Request{release.request | pins: nil})
    release
  end

  @spec context() :: Context.t()
  defp context,
    do: Context.new("claude-opus-5-5", "Report only what the sources say.", "Summarise.")

  @spec prefix(String.t()) :: Path.t()
  defp prefix(name) do
    dir = Path.join(System.tmp_dir!(), "zkfol-grounding-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    Path.join(dir, name)
  end
end
