defmodule Zkfol.Matrix do
  @moduledoc """
  I am the matrix metaclass: a declared shape and the reading of an
  extensional relation's facts as dense data (an absent cell reads 0,
  the sentinel). An object is a relation whose clauses are facts and
  whose layout is me; an object with no facts is an existential the
  prover fills.

  ### Public API

  - `new/3` — declare a shape, facts optional.
  - `extensional?/1`, `shape/1`, `data/1` — read the object back.
  """

  use TypedStruct

  alias Zkfol.Interpretation
  alias Zkfol.Lang.Rel

  typedstruct enforce: true do
    field(:rows, pos_integer())
    field(:cols, pos_integer())
  end

  @typedoc "One fact: 0-based row, 0-based column, the value."
  @type fact :: {non_neg_integer(), non_neg_integer(), non_neg_integer()}

  @doc "I declare a `{rows, cols}` matrix named `name` with `facts`."
  @spec new(atom(), {pos_integer(), pos_integer()}, [fact()]) :: Rel.t()
  def new(name, {rows, cols}, facts \\ []) do
    %Rel{
      name: name,
      arity: 3,
      clauses: for({r, c, v} <- facts, do: {[r, c, v], []}),
      layout: %__MODULE__{rows: rows, cols: cols}
    }
  end

  @doc "I say whether the object carries facts (extensional) or is prover-filled."
  @spec extensional?(Rel.t()) :: boolean()
  def extensional?(%Rel{clauses: clauses}), do: clauses != []

  @doc "I am the declared {rows, cols}."
  @spec shape(Rel.t()) :: {pos_integer(), pos_integer()}
  def shape(%Rel{layout: %__MODULE__{rows: rows, cols: cols}}), do: {rows, cols}

  @doc "I read the facts densely: an absent cell is 0, the sentinel."
  @spec data(Rel.t()) :: Interpretation.t()
  def data(%Rel{layout: %__MODULE__{rows: rows, cols: cols}} = rel) do
    by_index = Map.new(facts(rel), fn {r, c, v} -> {{r, c}, v} end)

    Interpretation.new(
      for r <- 0..(rows - 1), do: for(c <- 0..(cols - 1), do: Map.get(by_index, {r, c}, 0))
    )
  end

  @spec facts(Rel.t()) :: [fact()]
  defp facts(%Rel{arity: 3, clauses: clauses}), do: for({[r, c, v], []} <- clauses, do: {r, c, v})
  defp facts(%Rel{arity: 2, clauses: clauses}), do: for({[i, v], []} <- clauses, do: {0, i, v})
end
