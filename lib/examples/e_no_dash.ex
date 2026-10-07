defmodule Examples.ENoDash do
  @moduledoc "I am the examples of the no-dash relation, proved on a clean text and refused on a dashed one."

  use ExExample

  import ExUnit.Assertions

  alias Zkfol.Log
  alias Zkfol.Pipeline
  alias Zkfol.Prover
  alias Zkfol.Statement
  alias ZkfolAiDemo.NoDash

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
end
