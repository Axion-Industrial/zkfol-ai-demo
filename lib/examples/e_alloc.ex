defmodule Examples.EAlloc do
  @moduledoc "I am the linker's evidence: named predicates resolve to the regions' rows."

  use ExExample
  use Zkfol.Lang

  import ExUnit.Assertions

  alias Examples.EUser
  alias Zkfol.Al
  alias Zkfol.Alloc
  alias Zkfol.Ast
  alias Zkfol.Interpretation
  alias Zkfol.Lay
  alias Zkfol.Phi
  alias Zkfol.Phi.Cons
  alias Zkfol.Phi.View
  alias Zkfol.Prover
  alias Zkfol.Statement

  defrel held(0, 0)

  defrel held(n, value) do
    held(n - 1, previous)
    value = previous + n
  end

  defrel impossible_after(n, value) do
    held(n, value)
    1 = 2
  end

  defrel impossible_before(n, value) do
    1 = 2
    held(n, value)
  end

  defrel sum(a, b, c) do
    c = a + b
  end

  defrel erased(a, z) do
    z = 0 * a
  end

  @doc "An open scalar predicate proves different answers and refuses a wrong sum."
  @spec scalar_parameters_share_one_predicate() :: [Prover.Report.t()]
  example scalar_parameters_share_one_predicate do
    {:ok, pred, alloc} = Phi.compile(sum())
    linked = Alloc.link(pred, alloc)

    reports =
      for args <- [[3, 4, 7], [8, 5, 13]] do
        assert {:ok, ^pred, ^alloc} = Phi.compile(sum(), nil, args)
        {:ok, derivation} = Al.derived(sum(), args)
        witness = derivation |> Lay.of(alloc) |> Lay.witness()
        assert {:ok, report = %Prover.Report{}, _id} = Prover.prove(linked, witness)
        report
      end

    fact = {:sum, [8, 5, 14]}
    derivation = %Zkfol.Derivation{facts: [fact], clauses: [{fact, 0}]}
    forged = derivation |> Lay.of(alloc) |> Lay.witness()
    assert {:error, _refusal} = Prover.prove(linked, forged)
    reports
  end

  @doc "An operand erased by arithmetic owns no row; its private value does not affect the proof."
  @spec an_erased_operand_needs_no_row() :: [Prover.Report.t()]
  example an_erased_operand_needs_no_row do
    {:ok, pred, alloc} = Phi.compile(erased())
    assert [%Alloc.Slot{allocation: :none} | _rest] = Alloc.root(alloc).slots

    for value <- [3, 99] do
      {:ok, derivation} = Al.derived(erased(), [value, 0])
      witness = derivation |> Lay.of(alloc) |> Lay.witness()

      assert {:ok, report = %Prover.Report{}, _id} =
               Prover.prove(Alloc.link(pred, alloc), witness)

      report
    end
  end

  @doc "An impossible clause owns no callee or value rows, wherever the contradiction occurs."
  @spec impossible_clauses_allocate_nothing() :: [Alloc.t()]
  example impossible_clauses_allocate_nothing do
    for rel <- [impossible_after(), impossible_before()] do
      {:ok, pred, alloc} = Phi.compile(rel)
      assert Alloc.refs(alloc) == [{:in, rel.name}]
      linked = Alloc.link(pred, alloc)
      assert Zkfol.Semantics.valid?(linked, Interpretation.new([[0]]))
      refute Zkfol.Semantics.valid?(linked, Interpretation.new([[1]]))
      alloc
    end
  end

  @doc "Constructing and peeling structure retains the original cells."
  @spec constructed_values_share_cells() :: Cons.t()
  example constructed_values_share_cells do
    view = View.bank([{:input, 1}], 3)
    head = View.slice(view, 0)
    tail = View.shifted(view, 1)
    assert Cons.new(head, tail) == view

    cons = Cons.new(Ast.cell({:input, 2}), tail)
    assert %Cons{} = cons
    assert {:ok, Ast.cell({:input, 2}), tail, []} == Cons.peel(cons)
    cons
  end

  @doc "The allocation links Fibonacci's answer and opens that answer with its presence."
  @spec fibonacci_alloc() :: Alloc.t()
  example fibonacci_alloc do
    statement = EUser.fibonacci(6)
    alloc = Statement.alloc(statement)
    witness = Statement.witness(statement)
    answer = Ast.eq(Ast.cell({:fib, {:param, :v}}), EUser.fib(6))
    assert Zkfol.Semantics.holds?(Alloc.link(answer, alloc), witness, 6)

    {:ok, claims} = Lay.claims(Statement.lay(statement), [{:fib, :v}])

    opened =
      Map.new(claims, fn {name, row, column} ->
        {name, Interpretation.at(witness, row, column)}
      end)

    assert opened == %{"fib.v" => EUser.fib(6), "in" => 1}
    alloc
  end
end
