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
  alias Zkfol.Witness

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

  @spec factorial_witness(pos_integer()) :: Interpretation.t()
  example factorial_witness(n \\ 6) do
    {:ok, witness} = Witness.generate(factorial_predicate(), n)
    assert Semantics.valid?(factorial_predicate(), pointer_ranges(), witness)
    witness
  end
end
