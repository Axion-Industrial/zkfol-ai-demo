defmodule Examples.EPassed do
  @moduledoc "I am the passed reading's evidence: a prim reads the same through a handed name."

  use ExExample
  use Zkfol.Lang

  import ExUnit.Assertions

  alias Zkfol.{Al, Alloc, Derivation, Lay, Prover}
  alias Zkfol.Phi
  alias Zkfol.Pipeline
  alias Zkfol.Semantics
  alias Zkfol.Statement
  alias Zkfol.Witness

  defrel counted(xs) do
    each(natural, xs)
  end

  @spec passed_reading() :: Statement.t()
  example passed_reading do
    plain = %Pipeline{passes: [{Witness, []}, {Phi, []}]}

    {:ok, statement, _trace} =
      Pipeline.run(plain, %Statement{rels: [counted()], args: [[3, 0, 7]]})

    assert Semantics.valid?(Statement.pred(statement), Statement.witness(statement))
    statement
  end

  defrel narrow(x) do
    all_distinct(x)
  end

  defrel pick(i, x, v) do
    nth(i, x, v)
  end

  @doc "A reading handed less than the cells it wants refuses, naming the cell it was handed."
  @spec a_cell_is_not_the_cells() :: Zkfol.Refusal.t()
  example a_cell_is_not_the_cells do
    assert {:error, {:unliftable_term, %{term: {:cell, _ref}, relation: :all_distinct}}} =
             Phi.lower(narrow(), [narrow()])

    {:error, refusal} = Phi.lower(pick(), [pick()])
    assert {:unliftable_term, %{term: {:cell, _ref}, relation: :nth}} = refusal
    refusal
  end

  @doc "One compiled read accepts different private indices and values, but rejects wrong answers."
  @spec cached_indexed_read() :: [Zkfol.Interpretation.t()]
  example cached_indexed_read do
    {:ok, empty, allocation} = Phi.compile(pick(), [pick()], [1, [], :_])
    fact = {:pick, [1, [], 10]}
    attempted = %Derivation{facts: [fact], clauses: [{fact, 0}]}
    witness = attempted |> Lay.of(allocation) |> Lay.witness()
    assert {:error, _refusal} = Prover.prove(Alloc.link(empty, allocation), witness)

    {:ok, pred, alloc} = Phi.compile(pick(), [pick()], [1, [10, 20], :_])
    linked = Alloc.link(pred, alloc)

    for {i, xs} <- [{1, [10, 20]}, {2, [10, 20]}, {1, [30, 40]}, {2, [30, 40]}] do
      {:ok, again, layout} = Phi.compile(pick(), [pick()], [i, xs, :_])
      assert Alloc.link(again, layout) == linked
      {:ok, derivation} = Al.derived(pick(), [i, xs, :_])
      assert Derivation.root(derivation, :pick) == {:pick, [i, xs, Enum.at(xs, i - 1)]}
      witness = derivation |> Lay.of(alloc) |> Lay.witness()
      assert {:ok, %Prover.Report{}, _id} = Prover.prove(linked, witness)

      for args <- [[i, xs, Enum.at(xs, 2 - i)], [0, xs, hd(xs)], [3, xs, hd(xs)]] do
        fact = {:pick, args}
        forged = %Derivation{facts: [fact], clauses: [{fact, 0}]}
        witness = forged |> Lay.of(alloc) |> Lay.witness()
        refute Semantics.valid?(linked, witness)
        assert {:error, _refusal} = Prover.prove(linked, witness)
      end

      witness
    end
  end

  defrel total([], 0)

  defrel total([h | t], sum) do
    h > 0
    total(t, rest)
    sum = h + rest
  end

  defrel combined(xs, sum) do
    with_total(xs, total, sum)
  end

  defrel with_total(xs, f, sum) do
    f([1, 2], a)
    total(xs, b)
    sum = a + b
  end

  @doc "A literal sum and a private list's sum compose, including when both calls return the same fact."
  @spec sums_compose() :: [Statement.t()]
  example sums_compose do
    for xs <- [[4, 5], [1, 2], [7, 8, 9]] do
      {:ok, statement, _trace} =
        Pipeline.run(Examples.EUser.plain(), %Statement{rels: [combined()], args: [xs, :_]})

      assert Derivation.root(Statement.derivation(statement), :combined) ==
               {:combined, [xs, 3 + Enum.sum(xs)]}

      assert {:ok, %Prover.Report{}, _id} =
               Prover.prove(Statement.pred(statement), Statement.witness(statement))

      statement
    end
  end
end
