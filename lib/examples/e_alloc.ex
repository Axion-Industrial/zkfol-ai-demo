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

  defrel delegated(n, value) do
    held(n, value)
  end

  defrel choose(0) do
    nth(1, [1], 2)
  end

  defrel choose(1)

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

  @doc "An impossible lookup clause does not prevent another clause from answering."
  @spec a_dead_lookup_clause() :: Prover.Report.t()
  example a_dead_lookup_clause do
    {:ok, derivation} = Al.derived(choose(), [1])
    {:ok, pred, alloc} = Phi.compile(choose(), nil, [1])
    witness = derivation |> Lay.of(alloc) |> Lay.witness()
    assert {:ok, report, _id} = Prover.prove(Alloc.link(pred, alloc), witness)
    assert {:error, {:no_answer, _}} = Al.derived(choose(), [0])
    report
  end

  @doc "Private scalars share one predicate, directly or through a call; a wrong sum is refused."
  @spec scalar_parameters_share_one_predicate() :: [Prover.Report.t()]
  example scalar_parameters_share_one_predicate do
    reports =
      Enum.flat_map(
        [{sum(), [[3, 4, 7], [8, 5, 13]]}, {delegated(), [[8, 36], [9, 45]]}],
        fn {rel, answers} ->
          {:ok, pred, alloc} = Phi.compile(rel)

          for args <- answers do
            assert {:ok, ^pred, ^alloc} = Phi.compile(rel, nil, args)
            {:ok, derivation} = Al.derived(rel, args)
            witness = derivation |> Lay.of(alloc) |> Lay.witness()

            assert {:ok, report = %Prover.Report{}, _id} =
                     Prover.prove(Alloc.link(pred, alloc), witness)

            report
          end
        end
      )

    {:ok, pred, alloc} = Phi.compile(sum())
    fact = {:sum, [8, 5, 14]}
    derivation = %Zkfol.Derivation{facts: [fact], clauses: [{fact, 0}]}
    forged = derivation |> Lay.of(alloc) |> Lay.witness()
    assert {:error, _refusal} = Prover.prove(Alloc.link(pred, alloc), forged)
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

  @spec fibonacci_alloc() :: Alloc.t()
  example fibonacci_alloc do
    alloc = Statement.alloc(EUser.fibonacci(6))

    assert Alloc.refs(alloc) == [{:fib, {:param, :v}}, {:in, :fib}]
    assert Alloc.rows(alloc, :fib) == 1..1
    assert Alloc.rows(alloc, :in) == 2..2
    alloc
  end

  @spec linking_resolves_names_to_rows() :: Ast.pred()
  example linking_resolves_names_to_rows do
    phi = Ast.eq(Ast.cell({:in, :fib}), Ast.add(Ast.cell({:fib, {:param, :v}}), 1))
    linked = Alloc.link(phi, fibonacci_alloc())

    assert {:eq, {:cell, 2}, {:add, {:cell, 1}, 1}} = linked
    linked
  end

  @spec claim_on_a_member_opens_its_presence() :: [Interpretation.claim()]
  example claim_on_a_member_opens_its_presence do
    {:ok, claims} = Lay.claims(Statement.lay(EUser.fibonacci(6)), [{:fib, :v}])

    assert claims == [{"fib.v", 1, 6}, {"in", 2, 6}]
    claims
  end
end
