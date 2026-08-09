defmodule Examples.EAlloc do
  @moduledoc """
  I am the linker's evidence: named predicates resolve to the rows
  the regions assign, single-symbol statements link by identity, the
  witness assembles through the same value, and the linked pair
  proves on zinc+ end to end.
  """

  use ExExample

  import ExUnit.Assertions

  alias Zkfol.Alloc
  alias Zkfol.Ast
  alias Zkfol.Interpretation
  alias Zkfol.Prover
  alias Zkfol.Semantics
  alias Zkfol.Uair

  @spec successor_alloc() :: Alloc.t()
  example successor_alloc do
    alloc = Alloc.new([a: 1, b: 1], public: [:a])

    assert Alloc.rows(alloc, :a) == 1..1
    assert Alloc.rows(alloc, :b) == 2..2
    alloc
  end

  @spec named_phi() :: Ast.pred()
  example named_phi do
    Ast.eq(Ast.cell({:b, 1}), Ast.add(Ast.cell({:a, 1}), 1))
  end

  @spec linking_resolves_names_to_rows() :: Ast.pred()
  example linking_resolves_names_to_rows do
    {:ok, linked} = Alloc.link(named_phi(), successor_alloc())

    assert {:eq, {:cell, 2}, {:add, {:cell, 1}, 1}} = linked
    linked
  end

  @spec linking_numeric_is_identity() :: Ast.pred()
  example linking_numeric_is_identity do
    phi = Ast.eq(Ast.cell(1), Ast.add(Ast.x(), -1))
    {:ok, linked} = Alloc.link(phi, successor_alloc())

    assert linked == phi
    linked
  end

  @spec linking_refuses_what_no_region_holds() :: Zkfol.Refusal.t()
  example linking_refuses_what_no_region_holds do
    {:error, unallocated} = Alloc.link(Ast.eq(Ast.cell({:zzz, 1}), 0), successor_alloc())
    assert {:symbol_not_allocated, %{symbol: :zzz}} = unallocated

    {:error, outside} = Alloc.link(Ast.eq(Ast.cell({:a, 2}), 0), successor_alloc())
    assert {:row_outside_region, %{symbol: :a, row: 2}} = outside
    outside
  end

  @spec named_len_folds_or_refuses() :: Ast.pred()
  example named_len_folds_or_refuses do
    phi = Ast.eq(Ast.len(:a), 3)
    {:ok, linked} = Alloc.link(phi, successor_alloc(), %{a: 3})

    assert {:eq, 3, 3} = linked
    assert {:error, {:unknown_length, %{symbol: :a}}} = Alloc.link(phi, successor_alloc())
    linked
  end

  @spec interpret_stacks_regions_in_order() :: Interpretation.t()
  example interpret_stacks_regions_in_order do
    family = %{a: Interpretation.new([[1, 2, 3]]), b: Interpretation.new([[2, 3, 4]])}
    {:ok, itp} = Alloc.interpret(successor_alloc(), family)

    assert Interpretation.rows(itp) == [[1, 2, 3], [2, 3, 4]]

    for {sym, bank} <- family,
        do: assert(Alloc.region(itp, successor_alloc(), sym) == bank)

    itp
  end

  @spec interpret_pads_short_regions_with_their_base() :: Interpretation.t()
  example interpret_pads_short_regions_with_their_base do
    family = %{a: Interpretation.new([[7]]), b: Interpretation.new([[2, 3, 4]])}
    {:ok, itp} = Alloc.interpret(successor_alloc(), family)

    assert Interpretation.rows(itp) == [[7, 7, 7], [2, 3, 4]]
    itp
  end

  @spec interpret_refuses_what_disagrees() :: Zkfol.Refusal.t()
  example interpret_refuses_what_disagrees do
    family = %{a: Interpretation.new([[1], [2]]), b: Interpretation.new([[2]])}
    {:error, lied} = Alloc.interpret(successor_alloc(), family)
    assert {:region_shape_mismatch, %{symbol: :a}} = lied

    {:error, missing} = Alloc.interpret(successor_alloc(), %{a: Interpretation.new([[1]])})
    assert {:region_uninterpreted, %{symbol: :b}} = missing
    missing
  end

  @spec claims_resolve_by_name() :: [Interpretation.claim()]
  example claims_resolve_by_name do
    {:ok, claims} = Alloc.claims(successor_alloc(), [{"out", {:b, 1}, 3}])

    assert claims == [{"out", 2, 3}]
    claims
  end

  @spec a_linked_statement_proves() :: Prover.Report.t()
  example a_linked_statement_proves do
    alloc = successor_alloc()
    family = %{a: Interpretation.new([[1, 2, 3]]), b: Interpretation.new([[2, 3, 4]])}

    {:ok, linked} = Alloc.link(named_phi(), alloc)
    {:ok, witness} = Alloc.interpret(alloc, family)
    {:ok, claims} = Alloc.claims(alloc, [{"out", {:b, 1}, 3}])

    assert Semantics.valid?(linked, witness)

    {:ok, uair} = Uair.emit(linked, witness, claims)
    {:ok, report, _id} = Prover.prove_uair(uair, name: :linked_successor)

    assert %Prover.Report{} = report
    report
  end
end
