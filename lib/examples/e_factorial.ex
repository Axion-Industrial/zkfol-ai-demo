defmodule Examples.EFactorial do
  @moduledoc """
  I am the factorial statement: rows 1 = n, 2 = n!, 3 = pointer to n-1.
  My coefficient is the index cell itself, the shape the recurrence
  pass must refuse, and my reason for being in the corpus.
  """

  use ExExample

  import ExUnit.Assertions

  alias Zkfol.Ast
  alias Zkfol.Interpretation
  alias Zkfol.Range
  alias Zkfol.Semantics

  @spec factorial_predicate() :: Ast.pred()
  example factorial_predicate do
    n = Ast.cell(1)
    value = Ast.cell(2)

    Ast.disj([
      Ast.conj([Ast.eq(n, 1), Ast.eq(value, 1)]),
      Ast.conj([
        Ast.eq(n, Ast.add(Ast.cell(1, 3), 1)),
        Ast.eq(value, Ast.mul(n, Ast.cell(2, 3)))
      ])
    ])
  end

  @spec pointer_ranges() :: [Range.check()]
  example pointer_ranges do
    Range.pointer(3)
  end

  @spec rows_for(pos_integer()) :: [[non_neg_integer()]]
  example rows_for(n \\ 6) do
    [
      Enum.to_list(1..n),
      Enum.scan(1..n, &(&1 * &2)),
      Enum.map(1..n, &max(&1 - 1, 1))
    ]
  end

  @spec factorial_witness() :: Interpretation.t()
  example factorial_witness do
    witness = Interpretation.new(rows_for())
    assert Semantics.valid?(factorial_predicate(), pointer_ranges(), witness)
    witness
  end
end
