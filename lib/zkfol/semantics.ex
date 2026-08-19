defmodule Zkfol.Semantics do
  @moduledoc """
  I am the integer semantics of the logic: Figure 3 of the paper.

  Zero is the one true value; non-zero values are flavours of false.
  Equality is the square of the difference, conjunction is sum,
  disjunction is product. Predicates therefore never go negative
  (Lemma 2.17), which is what makes conjunction-as-sum sound over Z.
  A term and a predicate evaluate by the same rules to one integer,
  so a single `eval/3` serves both.
  """

  alias Zkfol.Ast
  alias Zkfol.Interpretation

  @typedoc "What I evaluate under: one matrix, or Definition 2.16's ς as a map of them."
  @type interpretation :: Interpretation.t() | %{atom() => Interpretation.t()}

  @doc """
  I evaluate a term or predicate at column `x` under `itp`; for a
  predicate 0 means true. A named cell looks its symbol up in the
  family; a bare row reads the one matrix.
  """
  @spec eval(Ast.term_t() | Ast.pred(), interpretation(), pos_integer()) :: integer() | :error
  def eval(node, itp, x) do
    Ast.postwalk(node, fn
      q when is_integer(q) ->
        q

      :x ->
        x

      :len ->
        Interpretation.len(itp)

      {:len, sym} ->
        itp |> named(sym) |> Interpretation.len()

      {:cell, {sym, i}} ->
        itp |> named(sym) |> Interpretation.at(i, x)

      {:cell, i} ->
        Interpretation.at(itp, i, x)

      {:cell, {s, i}, {t, j}} ->
        Interpretation.at(named(itp, s), i, Interpretation.at(named(itp, t), j, x))

      {:cell, i, j} ->
        Interpretation.at(itp, i, Interpretation.at(itp, j, x))

      {:add, a, b} ->
        a + b

      {:mul, a, b} ->
        a * b

      {:reify, v} ->
        v

      {:natural, v} ->
        if v >= 0, do: 0, else: 1

      {:eq, a, b} ->
        (a - b) * (a - b)

      {:conj, vs} ->
        Enum.sum(vs)

      {:disj, vs} ->
        Enum.product(vs)
    end)
  rescue
    # The one cell Definition 2.16 does not define; a symbol ς does not interpret.
    ArgumentError -> :error
  end

  # The named symbol's matrix; a miss, or a lone matrix asked by name,
  # is the undefined cell's error.
  @spec named(interpretation(), atom()) :: Interpretation.t()
  defp named(family, sym) when is_map(family) and not is_struct(family) do
    Map.get(family, sym) || raise(ArgumentError, "no interpretation for #{sym}")
  end

  defp named(_single, sym), do: raise(ArgumentError, "no interpretation for #{sym}")

  @doc "I am the judgement: `itp` satisfies `phi` exactly when `phi` is 0 at every column."
  @spec valid?(Ast.pred(), Interpretation.t()) :: boolean()
  def valid?(phi, itp), do: Enum.all?(1..Interpretation.len(itp), &holds?(phi, itp, &1))

  @doc "I am true when `phi` holds at column `x` under `itp`; an undefined cell holds nothing."
  @spec holds?(Ast.pred(), Interpretation.t(), pos_integer()) :: boolean()
  def holds?(phi, itp, x), do: eval(phi, itp, x) == 0
end
