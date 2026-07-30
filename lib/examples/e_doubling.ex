defmodule Examples.EDoubling do
  @moduledoc """
  I am the doubling rewrite's evidence: one predicate for every n, the
  oracle validating it, claims agreeing with the generic route, the
  witness arriving late from its goal, the try leaving other statements
  alone, the position claim's absence keeping n private, and refusal
  of the walk that leaves N.
  """

  use ExExample

  import ExUnit.Assertions

  alias Examples.EFacts
  alias Examples.EUser
  alias Zkfol.Ast
  alias Zkfol.Refusal
  alias Zkfol.Doubling
  alias Zkfol.Facts
  alias Zkfol.Interpretation
  alias Zkfol.Pipeline
  alias Zkfol.Semantics
  alias Zkfol.Statement
  alias Zkfol.Uair

  @spec rewritten_fibonacci(pos_integer()) :: Statement.t()
  example rewritten_fibonacci(n \\ 8) do
    {:ok, statement} = Doubling.rewrite(EUser.fib(), n)
    witness = Statement.witness(statement)

    assert Enum.all?(statement.ranges, &Zkfol.Range.holds?(&1, witness))

    assert Enum.all?(
             1..Interpretation.len(witness),
             &Semantics.holds?(Statement.pred(statement), witness, &1)
           )

    statement
  end

  @spec one_predicate_for_every_n() :: Ast.pred()
  example one_predicate_for_every_n do
    small = rewritten_fibonacci(100)
    large = rewritten_fibonacci(10_000)

    assert Statement.pred(small) == Statement.pred(large)
    assert Interpretation.len(Statement.witness(small)) == 7
    assert Interpretation.len(Statement.witness(large)) == 14
    Statement.pred(small)
  end

  @spec same_claim_as_the_generic_route() :: [{pos_integer(), integer()}]
  example same_claim_as_the_generic_route do
    for n <- [1, 2, 3, 4, 8, 20] do
      value = claimed(rewritten_fibonacci(n))

      assert value == EUser.fib(n)
      {n, value}
    end
  end

  @spec logarithmic_at_ten_thousand() :: Statement.t()
  example logarithmic_at_ten_thousand do
    statement = rewritten_fibonacci(10_000)

    assert Interpretation.len(Statement.witness(statement)) == 14
    assert claimed(statement) == EUser.fib(10_000)
    statement
  end

  @spec proves_with_its_claims() :: map()
  example proves_with_its_claims do
    statement = rewritten_fibonacci(100)

    {:ok, report, _id} =
      Uair.prove(Statement.pred(statement), Statement.witness(statement),
        claims: statement.claims,
        name: :doubled_fibonacci
      )

    assert [{_claim, value}, {_position, walked}] = report.claims
    assert value == EUser.fib(100)
    assert walked == 98
    report
  end


  @spec the_try_leaves_other_statements_alone() :: Statement.t()
  example the_try_leaves_other_statements_alone do
    source = %Statement{stage: %Statement.Lowered{pred: Statement.pred(EUser.power())}}

    {:ok, statement, trace} = Pipeline.run(%Pipeline{passes: [{Doubling, []}]}, source)

    assert statement == source
    assert [{Doubling, ^source}] = trace
    statement
  end

  @spec unclaimed_position_keeps_n_private() :: map()
  example unclaimed_position_keeps_n_private do
    pipeline = %Pipeline{passes: [{Doubling, private: true}]}
    source = %Statement{rels: [EUser.fib()], args: [100]}

    {:ok, statement, _trace} = Pipeline.run(pipeline, source)

    {:ok, uair} =
      Uair.emit(Statement.pred(statement), Statement.witness(statement), statement.claims)

    assert uair.num_public == 1
    {:ok, report, _id} = Uair.prove_uair(uair, name: :private_n)
    assert [{_claim, value}] = report.claims
    assert value == EUser.fib(100)
    report
  end

  @doc "I read the claimed result out of a rewritten statement's witness: the head claim."
  @spec claimed(Statement.t()) :: integer()
  def claimed(%Statement{stage: %Statement.Solved{witness: witness}, claims: [claim | _rest]}) do
    {_name, row, column} = claim
    Interpretation.at(witness, row, column)
  end

  @spec subtraction_is_refused() :: Refusal.t()
  example subtraction_is_refused do
    # x(k) = x(k-1) - x(k-2): the facts accept the descriptor, but the
    # kernel walk leaves N, so the rewrite must refuse.
    assert {:ok, %{p: 1, q: -1}} = Facts.recurrence(EFacts.sub())

    {:error, reason} = Doubling.rewrite(EFacts.sub(), 7)
    assert {:witness_value_negative, _} = reason
    reason
  end
end
