defmodule Examples.EPassed do
  @moduledoc "I am the passed reading's evidence: a prim reads the same through a handed name."

  use ExExample
  use Zkfol.Lang

  import ExUnit.Assertions

  alias Examples.EAst
  alias Examples.EUser
  alias Zkfol.{Al, Alloc, Derivation, Lay, Prover}
  alias Zkfol.Phi
  alias Zkfol.Pipeline
  alias Zkfol.Semantics
  alias Zkfol.Statement

  defrel counted(xs) do
    each(xs, natural)
  end

  @spec passed_reading() :: Statement.t()
  example passed_reading do
    {:ok, statement, _trace} =
      Pipeline.run(EUser.plain(), %Statement{rels: [counted()], args: [[3, 0, 7]]})

    assert Semantics.valid?(Statement.pred(statement), Statement.witness(statement))
    statement
  end

  defrel narrow(x) do
    all_distinct(x)
  end

  defrel pick(i, x, v) do
    nth(i, x, v)
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

  defrel reads(xs, i, first, selected) do
    nth(1, [42], constant)
    constant = 42
    nth(1, xs, first)
    nth(i, xs, selected)
  end

  @doc "Stored terms share one read predicate across private indices, beside an optimized read."
  @spec stored_indexed_reads() :: [Lay.t()]
  example stored_indexed_reads do
    {:ok, pred, alloc} = Phi.compile(reads(), nil, [[9, [4, 5], 7], 1, :_, :_])
    linked = Alloc.link(pred, alloc)

    for {xs, i} <- [{[9, [4, 5], 7], 1}, {[11, [6, 8], 13], 3}] do
      assert {:ok, ^pred, ^alloc} = Phi.compile(reads(), nil, [xs, i, :_, :_])
      {:ok, derivation} = Al.derived(reads(), [xs, i, :_, :_])
      assert Derivation.root(derivation, :reads) == {:reads, [xs, i, hd(xs), Enum.at(xs, i - 1)]}
      lay = Lay.of(derivation, alloc)
      witness = Lay.witness(lay)
      assert Semantics.valid?(linked, witness)
      assert {:ok, %Prover.Report{}, _id} = Prover.prove(linked, witness)

      for {parameter, wrong} <- [{4, 1}, {2, 0}, {2, length(xs) + 1}] do
        {:ok, [{_name, row, column} | _cells]} = Lay.claims(lay, [parameter])

        forged = EAst.tamper(witness, row, column, wrong)

        refute Semantics.valid?(linked, forged)
        assert {:error, _refusal} = Prover.prove(linked, forged)
      end

      lay
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
        Pipeline.run(EUser.plain(), %Statement{rels: [combined()], args: [xs, :_]})

      assert Derivation.root(Statement.derivation(statement), :combined) ==
               {:combined, [xs, 3 + Enum.sum(xs)]}

      assert {:ok, %Prover.Report{}, _id} =
               Prover.prove(Statement.pred(statement), Statement.witness(statement))

      statement
    end
  end
end
