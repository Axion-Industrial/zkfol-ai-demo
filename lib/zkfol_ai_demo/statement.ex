defmodule ZkfolAiDemo.Statement do
  @moduledoc """
  I am a statement ready to prove: a relation derived at its arguments, the rows to commit,
  and the public values the proof binds.

  Every statement goes through the real prover, true or false. The emitter will not emit a
  witness that breaks the predicate, so I emit the derivation's own witness and then put the
  real rows in the committed columns. For a true statement the two are the same and it proves.
  A false one has no derivation, so it is built on a derivation of the nearest arguments the
  relation does hold of, and reaches the prover with the real rows, which cannot be proved.

  The public values are laid in one more row after the derivation's rows. I add a read of that
  row to the predicate, which is what keeps the emitter from dropping it. Cells the derivation
  opened are public too, so a verifier is shown what the relation was run against.

  ### Public API

  - `prove/2` proves a statement and writes the portable proof.
  - `commit/1` is the commitment a proof of the statement would carry, without proving.
  - `pins/1` is what a verifier is asked to hold the proof to, as hex by binding name.
  - `uair/1` is the emitted UAIR, and where each binding sits in it.
  """

  use TypedStruct

  alias Zkfol.Ast
  alias Zkfol.Interpretation
  alias Zkfol.Prover
  alias Zkfol.Refusal
  alias Zkfol.Uair
  alias Zkfol.ZincPlus
  alias Zkfol.ZincPlus.Binding
  alias ZkfolAiDemo.Bindings
  alias ZkfolAiDemo.Derivation

  typedstruct enforce: true do
    @typedoc """
    What is proved: `derivation` of a relation, with `rows` committed in place of its own, and
    the `public` values bound beside the cells it opened. The `output` is released if the proof
    verifies, and a `manifest` describes the run.
    """
    field(:derivation, Derivation.t())
    field(:rows, [[integer()]])
    field(:public, [{String.t(), [non_neg_integer()]}])
    field(:output, String.t())
    field(:manifest, map())
  end

  @doc """
  I prove the statement and write `<prefix>.proof` and `<prefix>.public.json`. Only a proof
  that verifies is written.
  """
  @spec prove(t(), Path.t()) :: {:ok, Prover.Report.t()} | {:error, Refusal.t()}
  def prove(%__MODULE__{} = statement, prefix) do
    with {:ok, uair, bindings} <- uair(statement),
         {:ok, report, _id} <-
           Prover.prove_uair(uair, export: prefix, bindings: bindings, timeout: 300_000),
         do: {:ok, report}
  end

  @doc "I am the commitment a proof of this statement would carry to its witness, as hex."
  @spec commit(t()) :: {:ok, String.t()} | {:error, Refusal.t()}
  def commit(%__MODULE__{} = statement) do
    with {:ok, uair, _bindings} <- uair(statement), do: ZincPlus.commit(uair)
  end

  @doc "I am the value a verifier is asked to hold each binding to, as hex by its name."
  @spec pins(t()) :: %{String.t() => String.t()}
  def pins(%__MODULE__{derivation: derivation, public: public}) do
    named = for {name, words} <- public, into: %{}, do: {name, Bindings.hex(words)}
    Map.merge(named, Derivation.pinned(derivation))
  end

  @doc "I am the emitted UAIR with the real rows committed, and where each binding sits."
  @spec uair(t()) :: {:ok, Uair.t(), [Binding.t()]} | {:error, Refusal.t()}
  def uair(%__MODULE__{derivation: %Derivation{} = derivation} = statement) do
    arity = length(derivation.rows)
    width = derivation.rows |> hd() |> length()
    {row, placed, claims} = Bindings.place(statement.public, width, arity + 1)
    claims = claims ++ derivation.claims
    pred = Ast.conj([derivation.pred, Ast.natural(Ast.cell(arity + 1))])

    with {:ok, uair} <- Uair.emit(pred, Interpretation.new(derivation.rows ++ [row]), claims) do
      {:ok, %{uair | columns: committed(uair, derivation.rows, statement.rows)},
       placed ++ opened(derivation, claims, width)}
    end
  end

  # The cells the derivation opened sit in the public columns after the one for the public
  # values, in the order their rows are first claimed.
  @spec opened(Derivation.t(), [Interpretation.claim()], pos_integer()) :: [Binding.t()]
  defp opened(%Derivation{opened: nil}, _claims, _width), do: []

  defp opened(%Derivation{opened: name, claims: opened}, claims, width) do
    columns = claims |> Enum.map(&elem(&1, 1)) |> Enum.uniq() |> Enum.with_index() |> Map.new()
    [%Binding{name: name, cells: for({_l, row, x} <- opened, do: {columns[row], width - x})}]
  end

  # Each committed column that holds a row the real statement changed takes the real one. A
  # column lists x from the last cell down to the first, then the emitter's own padding.
  @spec committed(Uair.t(), [[integer()]], [[integer()]]) :: [[integer()]]
  defp committed(%Uair{columns: columns, rows: rows}, derived, real) do
    changed =
      for {{own, cells}, row} <- Enum.with_index(Enum.zip(derived, real), 1),
          own != cells,
          into: %{},
          do: {row, cells}

    for {column, row} <- Enum.zip(columns, rows) do
      case Map.fetch(changed, row) do
        {:ok, cells} -> Enum.reverse(cells) ++ Enum.drop(column, length(cells))
        :error -> column
      end
    end
  end
end
