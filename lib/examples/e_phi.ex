defmodule Examples.EPhi do
  @moduledoc """
  I expose the compiler's intermediate values. Start with `grid/0`, `row/0`,
  `empty/0`, `bound/0`, and `constrained/0`: each returns the value the next uses.
  `walk/0` gives Fibonacci's actual lowering; `walk/2` takes another program.
  """

  use ExExample
  import ExUnit.Assertions

  alias Examples.EUser
  alias Zkfol.Ast
  alias Zkfol.Lang.Rel
  alias Zkfol.Phi
  alias Zkfol.Phi.{Cons, View, Walk}
  alias Zkfol.Pipeline
  alias Zkfol.Statement
  alias Zkfol.Witness

  @doc "I describe one nine-by-nine bank; no puzzle values are needed to name its cells."
  @spec grid() :: View.t()
  example grid do
    View.bank(for(r <- 1..9, do: {:puzzle, r}), 9)
  end

  @doc "I select the first source row, still referring to the grid's own cells."
  @spec row() :: View.t()
  example row do
    View.slice(grid(), 0)
  end

  @doc "I am a walk before any pattern has bound a name or required an equation."
  @spec empty() :: Walk.t()
  example empty do
    %Walk{}
  end

  @doc "I bind [x | xs]: x reads the first cell, xs starts one cell later with one fewer cell."
  @spec bound() :: Walk.t()
  example bound do
    head = {:cons, {:var, :x}, {:var, :xs}}
    walk = Phi.match([head], [row()], empty())
    assert walk.env.x == View.cell(grid(), [0, 0])
    assert walk.env.xs == View.shifted(row(), 1)
    assert View.count(walk.env.xs) == View.count(row()) - 1
    assert walk.banks == %{} and walk.slots == [] and walk.eqs == []
    walk
  end

  @doc "I repeat x against the second cell: their values must agree, their accesses remain distinct."
  @spec constrained() :: Walk.t()
  example constrained do
    walk = Phi.match([{:var, :x}], [View.cell(grid(), [0, 1])], bound())
    assert walk.env == bound().env
    assert walk.eqs == [Ast.eq(bound().env.x, View.cell(grid(), [0, 1]))]
    assert walk.banks == bound().banks and walk.slots == bound().slots
    walk
  end

  @doc "I run a statement through Witness and Phi and return the lowering it retained."
  @spec walk(Rel.t() | [Rel.t()], [Statement.datum() | :_]) :: Walk.t()
  example walk(target \\ EUser.fib(), args \\ [8]) do
    pipeline = %Pipeline{passes: [{Witness, []}, {Phi, []}]}
    {:ok, statement, _trace} = Pipeline.run(pipeline, Statement.of(target, args: args))
    %Walk{} = Statement.lowering(statement)
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
end
