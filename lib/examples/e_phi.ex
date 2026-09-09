defmodule Examples.EPhi do
  @moduledoc """
  I expose the compiler's intermediate values. Start with `grid/0`, `row/0`,
  `empty/0`, `bound/0`, and `constrained/0`: each returns the value the next uses.
  `cell/0` and `rows/0` expose the grid's trace addresses.
  `parameters/0`, `matched_parameters/0`, and `shared_tail/0` follow a relation's
  declarations through matching an element and sharing the remaining sequence.
  `unresolved/0`, `aliased/0`, and `resolved_alias/0` follow a parameter's identity
  until it shares a record access. `allocated/0` and `constrained_allocation/0`
  separate choosing storage from requiring its value.
  `prepared_primitive/0`, `waiting_equation/0`, and `ready_equation/0` expose a
  primitive's output and the binding its equation needs. `equations/0` and
  `scheduled_equations/0` show dependencies resolving despite reversed goal order.
  `walk/0` gives Fibonacci's actual lowering; `walk/2` takes another program.
  """

  use ExExample
  import ExUnit.Assertions

  alias Examples.EUser
  alias Zkfol.Ast
  alias Zkfol.Lang.Rel
  alias Zkfol.Phi
  alias Zkfol.Phi.{Cons, Expression, View, Walk}
  alias Zkfol.Pipeline
  alias Zkfol.Statement
  alias Zkfol.Witness

  @doc "I describe one nine-by-nine bank; no puzzle values are needed to name its cells."
  @spec grid() :: View.t()
  example grid do
    View.bank(:puzzle, %View.Record{width: 9}, 9)
  end

  @doc "I name the trace cell for source position [2, 2]; I do not read its puzzle value."
  @spec cell() :: Ast.term_t()
  example cell do
    View.cell(grid(), [2, 2])
  end

  @doc "I name the grid's component rows in storage; these are addresses, not source row values."
  @spec rows() :: [Ast.row_ref()]
  example rows do
    View.rows(grid())
  end

  @doc "I select the first source row, still referring to the grid's own cells."
  @spec row() :: [Ast.term_t()]
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
    assert walk.env.xs == tl(row())
    assert walk.parameters == %{} and walk.slots == [] and walk.eqs == []
    walk
  end

  @doc "I repeat x against the second cell: their values must agree, their accesses remain distinct."
  @spec constrained() :: Walk.t()
  example constrained do
    walk = Phi.match([{:var, :x}], [View.cell(grid(), [0, 1])], bound())
    assert walk.env == bound().env
    assert walk.eqs == [Ast.eq(bound().env.x, View.cell(grid(), [0, 1]))]
    assert walk.parameters == bound().parameters and walk.slots == bound().slots
    walk
  end

  @doc "I declare total's input sequence; its answer waits for the clauses to bind it."
  @spec parameters() :: Walk.t()
  example parameters do
    relation = EUser.total()
    {_counter, walk} = Phi.parameters(relation, [:fresh, :fresh], %{total: relation})
    walk
  end

  @doc "I match [h | t]: h reads the head cell and t refers to the remaining sequence."
  @spec matched_parameters() :: Walk.t()
  example matched_parameters do
    before = parameters()
    input = before.env[{:total, {:param, :a1}}]
    answer = {:fresh, {:total, {:param, :s}}}
    {head, _body} = List.last(EUser.total().clauses)
    walk = Phi.match(head, [input, answer], before)

    assert Walk.banks(walk) == Walk.banks(before)
    assert walk.env.h == View.slice(input, 0)
    assert walk.env.t == View.shifted(input, 1)
    walk
  end

  @doc "I bind another parameter to the matched tail's access, with no storage of its own."
  @spec shared_tail() :: Walk.t()
  example shared_tail do
    tail = matched_parameters().env.t
    ref = {:continuation, {:param, :xs}}
    walk = Walk.bind(empty(), ref, tail)

    assert walk.env[ref] == tail
    assert walk.parameters[ref] == :none
    assert Walk.banks(walk) == [] and walk.slots == []
    walk
  end

  @doc "I declare a sequence whose elements have not yet been observed."
  @spec record_parameters() :: Walk.t()
  example record_parameters do
    relation = EUser.rows()
    {_counter, walk} = Phi.parameters(relation, [:fresh, :fresh], %{rows: relation})
    assert Walk.fetch(walk, {:rows, {:param, :a1}}).element == :unknown
    walk
  end

  @doc "I match [[a, b] | t], establishing a two-field record for every element of the sequence."
  @spec matched_record() :: Walk.t()
  example matched_record do
    before = record_parameters()
    input = Walk.fetch(before, {:rows, {:param, :a1}})
    {head, _body} = List.last(EUser.rows().clauses)
    walk = Phi.match(head, [input, {:fresh, {:rows, {:param, :s}}}], before)
    assert Walk.fetch(walk, :t).element == %View.Record{width: 2}
    walk
  end

  @doc "I hand the tail to a new walk; it can read the next record without owning its bank."
  @spec shared_record() :: Walk.t()
  example shared_record do
    tail = Walk.fetch(matched_record(), :t)
    {head, _body} = List.last(EUser.rows().clauses)
    walk = Phi.match(head, [tail, :fresh], empty())
    assert Walk.fetch(walk, :a) == View.cell(tail, [0, 0])
    assert Walk.fetch(walk, :b) == View.cell(tail, [0, 1])
    assert Walk.banks(walk) == [] and walk.slots == []
    walk
  end

  @doc "I bind a source name to an unresolved parameter: passing it retains its identity."
  @spec unresolved() :: Walk.t()
  example unresolved do
    ref = {:result, {:param, :answer}}
    walk = Phi.match([{:var, :answer}], [{:fresh, ref}], empty())

    assert Expression.resolve({:var, :missing}, walk) == {:waiting, [:missing]}
    assert Expression.argument({:var, :answer}, walk) == {:fresh, ref}
    assert Expression.resolve({:var, :answer}, walk) == {:ok, Ast.cell(ref)}
    assert walk.parameters == %{} and walk.slots == [] and walk.eqs == []
    walk
  end

  @doc "I make two parameters refer to the same unresolved value."
  @spec aliased() :: Walk.t()
  example aliased do
    next = {:continuation, {:param, :answer}}
    first = Walk.fetch(unresolved(), :answer)
    walk = Phi.match([{:fresh, next}], [first], unresolved())

    assert Walk.fetch(walk, :answer) == {:fresh, next}
    assert Expression.argument({:var, :answer}, walk) == {:fresh, next}
    assert walk.parameters == %{} and walk.slots == [] and walk.eqs == []
    walk
  end

  @doc "I resolve the alias to a record tail; both names share its access and known shape."
  @spec resolved_alias() :: Walk.t()
  example resolved_alias do
    tail = Walk.fetch(matched_record(), :t)
    walk = Phi.match([{:var, :answer}], [tail], aliased())

    assert Walk.fetch(walk, :answer) == tail
    assert Expression.resolve({:var, :answer}, walk) == {:ok, tail}
    assert walk.parameters == %{{:continuation, {:param, :answer}} => :none}
    assert Walk.banks(walk) == [] and walk.slots == [] and walk.eqs == []
    walk
  end

  @doc "I choose a parameter cell for a scalar; choosing storage alone imposes no equation."
  @spec allocated() :: Walk.t()
  example allocated do
    ref = {:result, {:param, :answer}}
    walk = Walk.allocate(unresolved(), ref, 7)

    assert Walk.fetch(walk, :answer) == {:count, 7, Ast.cell(ref)}
    assert walk.parameters == %{ref => {:cell, ref}}
    assert walk.eqs == []
    walk
  end

  @doc "I constrain the allocated answer to equal seven; its storage stays the same."
  @spec constrained_allocation() :: Walk.t()
  example constrained_allocation do
    walk = Phi.match([{:var, :answer}], [7], allocated())
    assert walk.parameters == allocated().parameters
    assert walk.eqs == [Ast.eq(Ast.cell({:result, {:param, :answer}}), 7)]
    walk
  end

  @doc "I prepare a primitive with an existing input and a repeated output name; it gets one cell."
  @spec prepared_primitive() :: Walk.t()
  example prepared_primitive do
    args = [{:var, :x}, {:var, :remainder}, {:var, :remainder}]
    {[input, output, output], walk} = Phi.prepare(args, bound(), :primitive, [0])

    assert input == Walk.fetch(bound(), :x)
    assert Walk.fetch(walk, :remainder) == output
    assert length(walk.slots) == 1 and walk.eqs == []
    walk
  end

  @doc "I need offset before I can constrain the primitive's remainder to twice that offset."
  @spec waiting_equation() :: Expression.waiting()
  example waiting_equation do
    waiting =
      Phi.equate({:var, :remainder}, {:mul, {:var, :offset}, 2}, prepared_primitive())

    assert waiting == {:waiting, [:offset]}
    waiting
  end

  @doc "I bind offset; the same equation can now constrain the prepared output."
  @spec ready_equation() :: Walk.t()
  example ready_equation do
    {:waiting, [:offset]} = waiting_equation()
    before = Phi.match([{:var, :offset}], [7], prepared_primitive())
    walk = Phi.equate({:var, :remainder}, {:mul, {:var, :offset}, 2}, before)

    assert walk.eqs == [Ast.eq(Walk.fetch(walk, :remainder), 14)]
    assert walk.slots == before.slots
    walk
  end

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
    view = View.bank(:input, :scalar, 3)
    head = View.slice(view, 0)
    tail = View.shifted(view, 1)
    assert Cons.new(head, tail) == view

    cons = Cons.new(Ast.cell({:input, 2}), tail)
    assert %Cons{} = cons
    assert {:ok, Ast.cell({:input, 2}), tail, []} == Cons.peel(cons)
    cons
  end
end
