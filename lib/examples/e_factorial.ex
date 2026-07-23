defmodule Examples.EFactorial do
  @moduledoc """
  I am the factorial statement: rows 1 = n, 2 = n!, 3 = pointer to n-1.
  My coefficient is the index cell itself, the shape the recurrence
  pass must refuse, and my reason for being in the corpus.
  """

  use ExExample

  import ExUnit.Assertions

  alias Zkfol.Al
  alias Zkfol.Ast
  alias Zkfol.Interpretation
  alias Zkfol.Range
  alias Zkfol.Semantics

  @spec factorial_predicate() :: Ast.pred()
  example factorial_predicate do
    rel = Examples.EFacts.factorial()
    {:ok, %{pred: pred}} = Zkfol.Lang.compile(rel, [rel])
    pred
  end

  @spec pointer_ranges() :: [Range.check()]
  example pointer_ranges do
    Range.pointer(3)
  end

  @spec factorial_witness(pos_integer()) :: Interpretation.t()
  example factorial_witness(n \\ 6) do
    {:ok, witness} = Al.solve(Examples.EFacts.factorial(), [n])
    assert Semantics.valid?(factorial_predicate(), pointer_ranges(), witness)
    witness
  end
end
