defmodule Examples.EAlloc do
  @moduledoc "I am the linker's evidence: named predicates resolve to the regions' rows."

  use ExExample

  import ExUnit.Assertions

  alias Examples.EUser
  alias Zkfol.Alloc
  alias Zkfol.Ast
  alias Zkfol.Interpretation
  alias Zkfol.Lay
  alias Zkfol.Statement

  @spec successor_alloc() :: Alloc.t()
  example successor_alloc do
    alloc = Alloc.new(a: 1, b: 1)

    assert Alloc.rows(alloc, :a) == 1..1
    assert Alloc.rows(alloc, :b) == 2..2
    alloc
  end

  @spec linking_resolves_names_to_rows() :: Ast.pred()
  example linking_resolves_names_to_rows do
    phi = Ast.eq(Ast.cell({:b, 1}), Ast.add(Ast.cell({:a, 1}), 1))
    linked = Alloc.link(phi, successor_alloc())

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
