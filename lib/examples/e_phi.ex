defmodule Examples.EPhi do
  @moduledoc "I am the lowering's evidence: the order of a clause's goals is no contract."

  use ExExample
  import ExUnit.Assertions

  alias Zkfol.Lang.Rel
  alias Zkfol.Phi
  alias Zkfol.Pipeline
  alias Zkfol.Statement
  alias Zkfol.Witness

  @doc "I write output = middle * 2 before the equation that establishes middle."
  @spec equations() :: Rel.t()
  example equations do
    %Rel{
      name: :afterward,
      arity: 2,
      clauses: [
        {[{:var, :input}, {:var, :output}],
         [
           {:eq, {:var, :output}, {:mul, {:var, :middle}, 2}},
           {:eq, {:var, :middle}, {:add, {:var, :input}, 1}}
         ]}
      ]
    }
  end

  @doc "I derive and lay the same answer in either goal order, on the same predicate and allocation."
  @spec scheduled_equations() :: Statement.t()
  example scheduled_equations do
    relation = equations()
    [{head, goals}] = relation.clauses
    reversed = %{relation | clauses: [{head, Enum.reverse(goals)}]}
    assert {:ok, predicate, allocation} = Phi.compile(relation)
    assert Phi.compile(reversed) == {:ok, predicate, allocation}
    pipeline = %Pipeline{passes: [{Witness, []}, {Phi, []}]}

    statements =
      for relation <- [relation, reversed] do
        {:ok, statement, _trace} = Pipeline.run(pipeline, Statement.of(relation, args: [3, :_]))

        assert Zkfol.Derivation.root(Statement.derivation(statement), :afterward) ==
                 {:afterward, [3, 8]}

        assert Zkfol.Semantics.valid?(Statement.pred(statement), Statement.witness(statement))
        statement
      end

    hd(statements)
  end
end
