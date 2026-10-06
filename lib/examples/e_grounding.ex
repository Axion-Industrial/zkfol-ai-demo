defmodule Examples.EGrounding do
  @moduledoc """
  I am the grounding policy's evidence: a figure in the sources proves, a figure outside them
  is refused by the prover, and a forged pointer cannot reach a value that is not a source.
  """

  use ExExample

  import ExUnit.Assertions

  alias Zkfol.Harness.Context
  alias Zkfol.Harness.Figures
  alias Zkfol.Harness.Gate
  alias Zkfol.Harness.Gate.Release
  alias Zkfol.Harness.Gate.Withheld
  alias Zkfol.Harness.Grounding
  alias Zkfol.Harness.Statement
  alias Zkfol.Refusal
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

  @doc """
  A pointer forged to land on another public value, which the figure equals, is refused: the
  pointer is held inside the table, so a hash word is no source.
  """
  @spec forged_pointer_cannot_leave_the_table() :: Refusal.t()
  example forged_pointer_cannot_leave_the_table do
    {:ok, honest} = Grounding.statement("In 2023 revenue was 4,200,000.", @sources, context())
    [figures, pointers, table] = honest.rows
    policy_word = Enum.at(table, 0)

    forged = %{
      honest
      | rows: [List.replace_at(figures, 0, policy_word), List.replace_at(pointers, 0, 1), table]
    }

    assert {:error, {:verifier_rejected, _} = refusal} = Statement.prove(forged, prefix("forged"))
    refusal
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
