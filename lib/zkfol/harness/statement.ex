defmodule Zkfol.Harness.Statement do
  @moduledoc """
  I am a statement ready to prove: a predicate, the witness rows it is about, and the public
  values the proof binds.

  Every statement goes through the real prover, true or false. The emitter will not emit a
  witness that breaks the predicate, so I emit a stand-in that satisfies it and then put the
  real rows in the committed columns. A true statement has a stand-in equal to its rows and
  proves. A false one reaches the prover with the real rows, and the prover cannot produce a
  proof that verifies.

  ### Public API

  - `prove/2` proves a statement and writes the portable proof.
  - `commit/1` is the commitment a proof of the statement would carry, without proving.
  """

  use TypedStruct

  alias Zkfol.Ast
  alias Zkfol.Harness.Bindings
  alias Zkfol.Interpretation
  alias Zkfol.Prover
  alias Zkfol.Refusal
  alias Zkfol.Uair
  alias Zkfol.ZincPlus
  alias Zkfol.ZincPlus.Binding

  typedstruct enforce: true do
    @typedoc """
    What is proved (`pred` over `rows`, with `stand_in` satisfying it), what the proof binds
    (`public`), what a verifier is asked to hold it to (`pins`, hex by binding name), and the
    `output` released if it verifies, with a `manifest` describing the run. The public values
    are laid in one more row after `rows`, and `pred` must read that row.
    """
    field(:pred, Ast.pred())
    field(:rows, [[non_neg_integer()]])
    field(:stand_in, [[non_neg_integer()]])
    field(:public, [{String.t(), [non_neg_integer()]}])
    field(:pins, %{String.t() => String.t()})
    field(:output, String.t())
    field(:manifest, map())
  end

  @doc """
  I prove the statement and write `<prefix>.proof` and `<prefix>.public.json`. Only a proof
  that verifies is written.
  """
  @spec prove(t(), Path.t()) ::
          {:ok, Prover.Report.t()} | {:error, Refusal.t()}
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

  @doc "I am the emitted UAIR with the real rows committed, and where each binding sits."
  @spec uair(t()) :: {:ok, Uair.t(), [Binding.t()]} | {:error, Refusal.t()}
  def uair(%__MODULE__{} = statement) do
    arity = length(statement.rows)
    width = statement.rows |> hd() |> length()
    {row, bindings, claims} = Bindings.place(statement.public, width, arity + 1)

    with {:ok, uair} <-
           Uair.emit(statement.pred, Interpretation.new(statement.stand_in ++ [row]), claims) do
      {:ok, %{uair | columns: committed(uair, statement.rows)}, bindings}
    end
  end

  # Each committed column that holds one of the statement's own rows takes the real one. A
  # column lists x from the last cell down to the first, and its padding repeats the first.
  @spec committed(Uair.t(), [[non_neg_integer()]]) :: [[integer()]]
  defp committed(%Uair{columns: columns, rows: rows}, real) do
    for {column, row} <- Enum.zip(columns, rows) do
      case if(is_integer(row), do: Enum.at(real, row - 1)) do
        nil -> column
        cells -> Enum.reverse(cells) ++ List.duplicate(hd(cells), length(column) - length(cells))
      end
    end
  end
end
