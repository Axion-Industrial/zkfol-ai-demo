defmodule Zkfol.Semantics do
  @moduledoc """
  I am the integer semantics of the logic: Figure 3 of the paper.

  Zero is the one true value; non-zero values are flavours of false.
  Equality is the square of the difference, conjunction is sum,
  disjunction is product. Predicates therefore never go negative
  (Lemma 2.17), which is what makes conjunction-as-sum sound over Z.
  A term and a predicate evaluate by the same rules to one integer,
  so a single `eval/3` serves both.

  ### Public API

  - `eval/3`
  - `valid?/3`
  """

  alias Zkfol.Ast
  alias Zkfol.Interpretation
  alias Zkfol.Range

  @doc "I evaluate a term or predicate at column `x` under `itp`; for a predicate 0 means true."
  @spec eval(Ast.term_t() | Ast.pred(), Interpretation.t(), pos_integer()) :: integer()
  def eval(node, itp, x) do
    Ast.postwalk(node, fn
      q when is_integer(q) -> q
      :x -> x
      :len -> Interpretation.len(itp)
      {:cell, i} -> Interpretation.at(itp, i, x)
      {:cell, i, j} -> Interpretation.at(itp, i, Interpretation.at(itp, j, x))
      {:add, a, b} -> a + b
      {:mul, a, b} -> a * b
      {:reify, v} -> v
      {:eq, a, b} -> (a - b) * (a - b)
      {:conj, vs} -> Enum.sum(vs)
      {:disj, vs} -> Enum.product(vs)
    end)
  end

  @doc """
  I am the judgement: `itp` satisfies `phi` under range checks `ranges`
  exactly when every range check holds and `phi` is 0 at every column.
  """
  @spec valid?(Ast.pred(), [Range.check()], Interpretation.t()) :: boolean()
  def valid?(phi, ranges, itp) do
    Enum.all?(ranges, &Range.holds?(&1, itp)) and
      Enum.all?(1..Interpretation.len(itp), &holds?(phi, itp, &1))
  end

  @doc """
  I am true when `phi` holds at column `x` under `itp`. A pointer that
  leaves the matrix -- Definition 2.16 has no such cell -- makes me
  false rather than raising, so I am total over any interpretation.
  """
  @spec holds?(Ast.pred(), Interpretation.t(), pos_integer()) :: boolean()
  def holds?(phi, itp, x) do
    eval(phi, itp, x) == 0
  rescue
    ArgumentError -> false
  end
end
