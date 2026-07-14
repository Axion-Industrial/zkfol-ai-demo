defmodule Examples.EDoubling do
  @moduledoc """
  I am the doubling rewrite's evidence: one predicate for every n, the
  oracle validating it, claims agreeing with the generic route, and
  refusal of the walk that leaves N.
  """

  use ExExample

  import ExUnit.Assertions

  alias Examples.EFacts
  alias Examples.EFibonacci
  alias Zkfol.Ast
  alias Zkfol.Doubling
  alias Zkfol.Facts
  alias Zkfol.Interpretation
  alias Zkfol.Semantics
  alias Zkfol.Statement

  @spec rewritten_fibonacci(pos_integer()) :: Statement.t()
  example rewritten_fibonacci(n \\ 8) do
    {:ok, statement} = Doubling.rewrite(EFibonacci.fibonacci_predicate(), n)

    assert Semantics.valid?(statement.pred, statement.ranges, statement.witness)
    statement
  end

  @spec one_predicate_for_every_n() :: Ast.pred()
  example one_predicate_for_every_n do
    small = rewritten_fibonacci(100)
    large = rewritten_fibonacci(10_000)

    assert small.pred == large.pred
    assert Interpretation.len(small.witness) == 7
    assert Interpretation.len(large.witness) == 14
    small.pred
  end

  @spec same_claim_as_the_generic_route() :: [{pos_integer(), integer()}]
  example same_claim_as_the_generic_route do
    for n <- [1, 2, 3, 4, 8, 20] do
      value = claimed(rewritten_fibonacci(n))

      assert value == EFibonacci.fib(n)
      {n, value}
    end
  end

  @spec logarithmic_at_ten_thousand() :: Statement.t()
  example logarithmic_at_ten_thousand do
    statement = rewritten_fibonacci(10_000)

    assert Interpretation.len(statement.witness) == 14
    assert claimed(statement) == EFibonacci.fib(10_000)
    statement
  end

  @doc "I read the claimed result out of a rewritten statement's witness."
  @spec claimed(Statement.t()) :: integer()
  def claimed(%Statement{witness: witness, claims: claims}) do
    {_name, row, column} = List.keyfind(claims, "claim_recurrence_n_exact", 0)
    Interpretation.at(witness, row, column)
  end

  @spec subtraction_is_refused() :: String.t()
  example subtraction_is_refused do
    # x(k) = x(k-1) - x(k-2): the facts accept the descriptor, but the
    # kernel walk leaves N, so the rewrite must refuse.
    step =
      Ast.conj([
        Ast.eq(Ast.cell(1), Ast.add(Ast.cell(1, 3), 1)),
        Ast.eq(Ast.cell(1), Ast.add(Ast.cell(1, 4), 2)),
        Ast.eq(Ast.cell(2), Ast.add(Ast.cell(2, 3), Ast.mul(-1, Ast.cell(2, 4))))
      ])

    pred = Ast.disj([EFacts.base_case(1, 1), EFacts.base_case(2, 2), step])
    assert {:ok, %{p: 1, q: -1}} = Facts.recurrence(pred)

    {:error, reason} = Doubling.rewrite(pred, 7)
    assert reason =~ "non-negative"
    reason
  end
end
