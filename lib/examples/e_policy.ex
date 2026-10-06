defmodule Examples.EPolicy do
  @moduledoc """
  I am the policy predicate's evidence: a canonical text matrix is proved and verified by a
  separate process, and a dash is refused by the prover itself.
  """

  use ExExample

  import ExUnit.Assertions

  alias Zkfol.Harness.Canon
  alias Zkfol.Harness.Canon.Result
  alias Zkfol.Harness.Policy
  alias Zkfol.Interpretation
  alias Zkfol.Prover
  alias Zkfol.Refusal
  alias Zkfol.Uair
  alias Zkfol.Verifier
  alias Zkfol.Verifier.Accepted
  alias Zkfol.Verifier.Request

  @words ~w(harvest lantern meadow copper river station window garden pencil orchard
            ladder market bridge candle valley ribbon harbour quarry thistle compass
            blanket furnace timber pebble anchor meadowlark saddle cobbler fennel)

  @doc "Every example writes files and starts a process, so none is cached."
  @spec rerun?(term()) :: boolean()
  def rerun?(_example), do: true

  @doc "I am a synthetic text of `words` words, the same every time."
  @spec prose(pos_integer()) :: String.t()
  def prose(words),
    do: Enum.map_join(1..words, " ", &Enum.at(@words, rem(&1 * 7, length(@words))))

  @doc "A clean text proves, and a process given only the two files accepts the proof."
  @spec clean_text_proves() :: {Prover.Report.t(), Accepted.t()}
  example clean_text_proves do
    {:ok, %Result{} = canon} = Canon.run("The harvest was good, and well-kept.", policy())
    {report, request} = proved(canon, "clean")
    assert {:ok, %Accepted{} = accepted} = Verifier.verify(request)
    {report, accepted}
  end

  @doc "A text with a dash gets no witness at all: the emitter refuses it before the prover."
  @spec dash_gets_no_witness() :: Refusal.t()
  example dash_gets_no_witness do
    {:ok, %Result{} = canon} = Canon.run("The harvest -- or so they said.", policy())
    assert {:error, refusal = {:witness_unsatisfies_schedule, _}} = emit(canon)
    refusal
  end

  @doc """
  A dash forced into the trace past the emitter reaches the real prover, which cannot make a
  proof of it: it fails, and nothing is written.
  """
  @spec forged_dash_is_refused_by_the_prover() :: Refusal.t()
  example forged_dash_is_refused_by_the_prover do
    {:ok, %Result{} = canon} = Canon.run("The harvest was good.", policy())
    {:ok, uair} = emit(canon)
    banned = Policy.bound(policy()) + 1

    # The cell alone, and the cell with the slack a forger would try to match it.
    forgeries = [
      forge(uair, [{0, 5, banned}]),
      forge(uair, [{0, 5, banned}, {1, 5, 0}])
    ]

    for {forged, n} <- Enum.with_index(forgeries) do
      prefix = prefix("forged#{n}")

      assert {:error, {:verifier_rejected, _}} =
               Prover.prove_uair(forged, export: prefix, timeout: 120_000)

      refute File.exists?(prefix <> ".proof")
    end

    {:error, refusal} = Prover.prove_uair(hd(forgeries))
    refusal
  end

  @doc "About three thousand words of text fit six rows, and prove in well under a second."
  @spec three_thousand_words() :: Prover.Report.t()
  example three_thousand_words do
    {:ok, %Result{} = canon} = Canon.run(prose(3000), policy())
    assert canon.layout.rows == 6
    {report, request} = proved(canon, "three-thousand")
    assert {:ok, %Accepted{}} = Verifier.verify(request)
    report
  end

  @spec policy() :: Policy.t()
  defp policy, do: Policy.load()

  @spec emit(Result.t()) :: {:ok, Uair.t()} | {:error, Refusal.t()}
  defp emit(%Result{matrix: matrix, layout: layout}),
    do: Uair.emit(Policy.pred(policy(), layout.rows), Interpretation.new(matrix))

  @spec proved(Result.t(), String.t()) :: {Prover.Report.t(), Request.t()}
  defp proved(canon, name) do
    {:ok, uair} = emit(canon)
    prefix = prefix(name)
    assert {:ok, %Prover.Report{} = report, _id} = Prover.prove_uair(uair, export: prefix)
    {report, %Request{proof: prefix <> ".proof", public: prefix <> ".public.json"}}
  end

  @spec forge(Uair.t(), [{non_neg_integer(), non_neg_integer(), integer()}]) :: Uair.t()
  defp forge(uair, cells) do
    columns =
      Enum.reduce(cells, uair.columns, fn {col, row, value}, columns ->
        List.update_at(columns, col, &List.replace_at(&1, row, value))
      end)

    %{uair | columns: columns}
  end

  @spec prefix(String.t()) :: Path.t()
  defp prefix(name) do
    dir = Path.join(System.tmp_dir!(), "zkfol-policy-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    Path.join(dir, name)
  end
end
