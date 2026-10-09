defmodule Examples.ENoDash do
  @moduledoc "I am the examples of the no-dash relation, proved on a clean text and refused on a dashed one."

  use ExExample

  import ExUnit.Assertions

  alias Zkfol.Log
  alias Zkfol.Pipeline
  alias Zkfol.Prover
  alias Zkfol.Statement
  alias ZkfolAiDemo.Derivation
  alias ZkfolAiDemo.NoDash
  alias ZkfolAiDemo.Text

  @clean "Autumn arrives quietly, and the light grows thin."
  # Built from its codepoint: this project refuses the character itself in a file.
  @dashed "Autumn arrives " <> <<8212::utf8>> <> " quietly."

  @doc "A text with no em dash derives, and the real prover proves and verifies it."
  @spec clean_text_is_proved() :: Prover.Report.t()
  example clean_text_is_proved do
    ran = Zkfol.compile(NoDash.no_dash(), args: [NoDash.text(@clean)])

    assert %Prover.Report{} = report = Log.report(Log.snapshot(), ran)
    assert report.proof_bytes > 0
    report
  end

  @doc "A text with an em dash has no derivation: the relation has no answer, so nothing is proved."
  @spec dashed_text_has_no_answer() :: Zkfol.Refusal.t()
  example dashed_text_has_no_answer do
    source = Statement.of(NoDash.no_dash(), args: [NoDash.text(@dashed)])

    assert {:error, _pass, {:no_answer, _detail} = refusal, _trace} =
             Pipeline.run(Pipeline.default(), source)

    refusal
  end

  @doc "One dash anywhere is enough: the same text, a character apart, goes from proved to refused."
  @spec one_character_decides() :: :ok
  example one_character_decides do
    for text <- [@clean, @dashed] do
      source = Statement.of(NoDash.no_dash(), args: [NoDash.text(text)])
      assert match?({:ok, _, _}, Pipeline.run(Pipeline.default(), source)) == (text == @clean)
    end

    :ok
  end

  @doc "The policy a proof names is this file: its hash is SHA-256 of the source, recomputable by anyone."
  @spec policy_hash_is_the_file_hash() :: binary()
  example policy_hash_is_the_file_hash do
    source = Path.expand("../zkfol_ai_demo/no_dash.ex", __DIR__)
    assert NoDash.source_hash() == :crypto.hash(:sha256, File.read!(source))
    NoDash.source_hash()
  end

  @doc """
  The compiler unrolls the rule at every codepoint and stops at its budget: the longest text
  it derives is `Text.capacity/0` codepoints, and one more is refused by the compiler itself.
  """
  @spec capacity_is_what_the_compiler_derives() :: Zkfol.Refusal.t()
  example capacity_is_what_the_compiler_derives do
    text = fn n -> NoDash.text(String.duplicate("a", n)) end

    assert {:ok, %Derivation{}} = Derivation.run(NoDash.no_dash(), [text.(Text.capacity())])

    assert {:error, {:unroll_budget, _detail} = refusal} =
             Derivation.run(NoDash.no_dash(), [text.(Text.capacity() + 1)])

    refusal
  end

  @doc "A text the rule does not hold of has no derivation, and the nearest one that does is the same text with a space."
  @spec repair_is_the_nearest_compliant_text() :: [non_neg_integer()]
  example repair_is_the_nearest_compliant_text do
    repaired = NoDash.repaired(NoDash.text(@dashed))

    assert Derivation.run(NoDash.no_dash(), [NoDash.text(@dashed)]) == :no_answer
    assert {:ok, %Derivation{}} = Derivation.run(NoDash.no_dash(), [repaired])
    assert List.to_string(repaired) == "Autumn arrives   quietly."
    repaired
  end
end
