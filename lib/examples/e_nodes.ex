defmodule Examples.ENodes do
  @moduledoc "I exercise constructed terms across calls, their sharing, and their proof obligations."
  use ExExample
  use Zkfol.Lang
  import ExUnit.Assertions

  alias Zkfol.Phi.{Ref, View}

  alias Zkfol.{
    Alloc,
    Ast,
    Derivation,
    Interpretation,
    Lay,
    Pipeline,
    Prover,
    Semantics,
    Statement,
    Uair
  }

  defrel joined([], ys, ys)

  defrel joined([h | t], ys, [h | zs]) do
    joined(t, ys, zs)
  end

  defrel rev([], [])

  defrel rev([h | t], r) do
    rev(t, rt)
    joined(rt, [h], r)
  end

  defrel tree(0, 0)

  defrel tree([l, r], s) do
    tree(l, sl)
    tree(r, sr)
    s = sl + sr + 1
  end

  defrel red(0, 0)
  defrel red(1, 1)

  defrel red([[1, x], _y], v) do
    red(x, v)
  end

  defrel red([[[0, x], y], z], v) do
    red([[x, z], [y, z]], v)
  end

  defrel terms(0)
  defrel terms([_h | _t])

  defrel bridge(xs, s) do
    tree(xs, s)
  end

  defrel same(x, y) do
    identical(x, y)
  end

  defrel identical(x, x)

  @doc "A bridge proves the original bank at every addressed column."
  @spec a_view_keeps_its_source_cells() :: Statement.t()
  example a_view_keeps_its_source_cells do
    statement = solved(bridge(), [[0, 0], :_])
    alloc = Statement.alloc(statement)
    witness = Statement.witness(statement)
    suffix = Alloc.row(alloc, {Zkfol.Nodes, {:suffix, {:"bridge xs", :scalar}}})

    for x <- 1..Interpretation.len(witness), Interpretation.at(witness, suffix, x) != 1 do
      forged =
        witness
        |> Interpretation.rows()
        |> List.update_at(suffix - 1, &List.replace_at(&1, x - 1, 1))
        |> Interpretation.new()

      refute Semantics.valid?(Statement.pred(statement), forged)
    end

    assert {:ok, %Prover.Report{}, _id} = Prover.prove(Statement.pred(statement), witness)
    statement
  end

  @doc "A one-field record stays a record when a bank is realized as nodes."
  @spec record_bank_as_nodes() :: Lay.t()
  example record_bank_as_nodes do
    values = [[1], [2]]
    view = View.bank(:input, %View.Record{width: 1}, length(values))

    member = %Alloc.Member{
      name: :bridge,
      relation: :bridge,
      steps: nil,
      sites: %{0 => []},
      slots: [
        %Alloc.Slot{name: :xs, allocation: {:bank, :input, view.col}},
        %Alloc.Slot{name: :copy, allocation: {:node, {:bridge, :copy}}}
      ]
    }

    predicate =
      Ast.disj([
        Ast.eq(Ast.cell({:in, :bridge}), 0),
        Ast.eq(Ref.of(view).id, Ast.cell({:bridge, :copy}))
      ])

    {predicate, members} =
      Zkfol.Nodes.lower(predicate, [member, %Alloc.Bank{name: :input, depth: 1}])

    alloc = Alloc.numbered(members, :bridge)
    fact = {:bridge, [values, values]}
    derivation = %Derivation{facts: [fact], clauses: [{fact, 0}]}
    lay = Lay.of(derivation, alloc)
    predicate = Alloc.link(predicate, alloc)
    assert {:ok, %Prover.Report{}, _id} = Prover.prove(predicate, Lay.witness(lay))

    flattened = {:bridge, [values, [1, 2]]}
    forged = %Derivation{facts: [flattened], clauses: [{flattened, 0}]}
    refute Semantics.valid?(predicate, forged |> Lay.of(alloc) |> Lay.witness())
    lay
  end

  @doc "A rank-three value keeps every scalar; a two-axis bank cannot represent it."
  @spec a_cube_keeps_every_cell() :: Statement.t()
  example a_cube_keeps_every_cell do
    cube = [[[1, 2], [3, 4]], [[5, 6], [7, 8]]]
    wrong = [[[1, 2], [99, 100]], [[5, 6], [101, 102]]]
    statement = solved(same(), [cube, :_])
    fact = {:same, [cube, wrong]}
    derivation = %Derivation{facts: [fact], clauses: [{fact, 0}]}
    forged = derivation |> Lay.of(Statement.alloc(statement)) |> Lay.witness()
    refute Semantics.valid?(Statement.pred(statement), forged)

    assert {:ok, %Prover.Report{}, _id} =
             Prover.prove(Statement.pred(statement), Statement.witness(statement))

    statement
  end

  @doc "An expression-named row cannot be silently used in a different frame."
  @spec a_generated_identity_keeps_its_frame() :: Zkfol.Refusal.t()
  example a_generated_identity_keeps_its_frame do
    ref = %Zkfol.Phi.Ref{id: Ast.at({Zkfol.Nodes, {:node, 7}}, :x, 1, 1)}

    assert {:refused, refusal = {:unliftable_term, _}} =
             catch_throw(Zkfol.Nodes.lower(Ast.eq(ref.id, 1), []))

    refusal
  end

  @doc "Reverse allocates its constructed tails across calls; the source list remains a bank."
  @spec reverse_proves() :: Statement.t()
  example reverse_proves do
    statement = solved(rev(), [[1, 2, 3], :_])
    assert Statement.bank(statement, :"rev a1") |> List.first() |> Enum.take(4) == [0, 3, 2, 1]

    assert {:ok, %Prover.Report{}, _id} =
             Prover.prove(Statement.pred(statement), Statement.witness(statement))

    statement
  end

  @doc "A parameter alternates between a scalar and a nested pair without flattening either."
  @spec tree_proves() :: Statement.t()
  example tree_proves do
    statement = solved(tree(), [[[0, 0], 0], :_])

    assert {:ok, %Prover.Report{}, _id} =
             Prover.prove(Statement.pred(statement), Statement.witness(statement))

    statement
  end

  @doc "S constructs [[x,z],[y,z]] for a recursive call; both applications prove."
  @spec sk_proves() :: [Statement.t()]
  example sk_proves do
    statements =
      for term <- [[[1, 0], 1], [[1, 1], 0], [[[0, 1], 1], 0]] do
        statement = solved(red(), [term, :_])

        assert {:ok, %Prover.Report{}, _id} =
                 Prover.prove(Statement.pred(statement), Statement.witness(statement))

        statement
      end

    [zero, one, _constructed] = statements
    assert Statement.pred(zero) == Statement.pred(one)
    assert Statement.alloc(zero) == Statement.alloc(one)
    statements
  end

  @doc "Equal subterms share an identity, and even unread children must be real earlier nodes."
  @spec children_are_shared_and_bounded() :: Statement.t()
  example children_are_shared_and_bounded do
    statement = solved(terms(), [[[1, 2], [1, 2]]])
    alloc = Statement.alloc(statement)
    witness = Statement.witness(statement)
    [%Alloc.Slot{allocation: {:node, root}}] = Alloc.root(alloc).slots
    id = Interpretation.at(witness, Alloc.row(alloc, root), 1)
    head = Alloc.row(alloc, {Zkfol.Nodes, :head})
    tail = Alloc.row(alloc, {Zkfol.Nodes, :tail})
    next = Interpretation.at(witness, tail, id)
    assert Interpretation.at(witness, head, id) == Interpretation.at(witness, head, next)

    for {row, value} <- [{head, 0}, {tail, 0}, {head, id}, {tail, id}] do
      forged =
        witness
        |> Interpretation.rows()
        |> List.update_at(row - 1, &List.replace_at(&1, id - 1, value))
        |> Interpretation.new()

      refute Semantics.valid?(Statement.pred(statement), forged)
      assert {:error, _refusal} = Uair.emit(Statement.pred(statement), forged)
    end

    statement
  end

  @doc "Opening a term binds its reachable scalar values, not merely its identity."
  @spec opening_binds_structure() :: Uair.t()
  example opening_binds_structure do
    statement = children_are_shared_and_bounded()
    witness = Statement.witness(statement)
    {:ok, claims} = Lay.claims(Statement.lay(statement), [1])
    values = for {name, row, x} <- claims, String.ends_with?(name, ".value"), do: {row, x}
    assert length(values) == 2
    {:ok, uair} = Uair.emit(Statement.pred(statement), witness, claims)
    assert {:ok, %Prover.Report{}, _id} = Prover.prove_uair(uair)
    [{row, x} | _] = values
    # Alter a public scalar throughout its declared column; the saved opening must reject it.
    column = Enum.find_index(uair.rows, &(&1 == row))
    forged = List.update_at(uair.columns, column, &List.replace_at(&1, uair.len - x, 9))
    assert {:error, _refusal} = Prover.prove_uair(%{uair | columns: forged})
    uair
  end

  @spec solved(Zkfol.Lang.Rel.t(), [term()]) :: Statement.t()
  defp solved(rel, args) do
    {:ok, statement, _trace} =
      Pipeline.run(Examples.EUser.plain(), %Statement{rels: [rel], args: args})

    assert Semantics.valid?(Statement.pred(statement), Statement.witness(statement))
    assert Examples.EFace.bridged(statement) == statement
    statement
  end
end
