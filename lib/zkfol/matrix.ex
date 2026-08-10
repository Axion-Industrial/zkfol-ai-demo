defmodule Zkfol.Matrix do
  @moduledoc """
  I am the matrix metaclass: a declared shape, a publicity, and the
  reading of an extensional relation's facts as dense data (an absent
  cell reads 0, the sentinel). An object is a relation whose clauses
  are facts and whose layout is me; an object with no facts is an
  existential the prover fills.

  ### Public API

  - `new/4` — declare a shape, facts optional.
  - `from_rows/3` — the dense object of runtime rows.
  - `list/3` — one row, arity 2.
  - `extensional?/1`, `shape/1`, `data/1` — read the object back.
  """

  use TypedStruct

  alias Zkfol.Interpretation
  alias Zkfol.Lang.Rel

  typedstruct enforce: true do
    field(:rows, pos_integer())
    field(:cols, pos_integer())
    field(:public, boolean(), default: false)
  end

  @typedoc "One fact: 0-based row, 0-based column, the value."
  @type fact :: {non_neg_integer(), non_neg_integer(), non_neg_integer()}

  @doc "I declare a `{rows, cols}` matrix named `name` with `facts`; `opts[:public]` opens it."
  @spec new(atom(), {pos_integer(), pos_integer()}, [fact()], keyword()) :: Rel.t()
  def new(name, {rows, cols}, facts \\ [], opts \\ []) do
    %Rel{
      name: name,
      arity: 3,
      clauses: for({r, c, v} <- facts, do: {[r, c, v], []}),
      layout: %__MODULE__{rows: rows, cols: cols, public: Keyword.get(opts, :public, false)}
    }
  end

  @doc "I build the dense object of `rows`: every cell a fact."
  @spec from_rows(atom(), [[non_neg_integer()]], keyword()) :: Rel.t()
  def from_rows(name, rows, opts \\ []) do
    facts =
      for {row, r} <- Enum.with_index(rows), {v, c} <- Enum.with_index(row), do: {r, c, v}

    new(name, {length(rows), length(hd(rows))}, facts, opts)
  end

  @doc "I am a list: one row, `{index, value}` facts, arity 2."
  @spec list(atom(), [non_neg_integer()] | pos_integer(), keyword()) :: Rel.t()
  def list(name, values, opts \\ [])

  def list(name, values, opts) when is_list(values) do
    rel = from_rows(name, [values], opts)
    %{rel | arity: 2, clauses: for({[_r, c, v], []} <- rel.clauses, do: {[c, v], []})}
  end

  def list(name, n, opts) when is_integer(n), do: %{new(name, {1, n}, [], opts) | arity: 2}

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
