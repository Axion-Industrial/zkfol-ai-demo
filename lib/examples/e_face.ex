defmodule Examples.EFace do
  @moduledoc "I am the face's evidence: what a viewer reads, derived from the structs."

  use ExExample

  import ExUnit.Assertions

  alias Examples.EAl
  alias Examples.ESudoku
  alias Examples.EUser
  alias GtBridge.Phlow.Builder
  alias GtBridge.Phlow.ColumnedList
  alias Zkfol.Ast
  alias Zkfol.Face
  alias Zkfol.Interpretation
  alias Zkfol.Statement
  alias Zkfol.ZincPlus

  @doc "Join's facts and uses navigate to their sources across scalar, bank and heap layouts."
  @spec a_join_keeps_its_sources() :: [%{atom() => term()}]
  example a_join_keeps_its_sources do
    {:ok, sudoku, _trace} =
      Zkfol.Pipeline.run(EUser.plain(), %Statement{
        rels: [ESudoku.families()],
        args: ESudoku.act()
      })

    for statement <- [EUser.fibonacci(), sudoku, Examples.ENodes.reverse()] do
      lay = Statement.lay(statement)
      feed = Face.stands(lay)
      facts = Enum.map(feed.facts, &Enum.fetch!(lay.derivation.facts, &1.index))

      assert length(feed.stands) == length(lay.stands)

      for {row, stand} <- Enum.zip(feed.stands, lay.stands) do
        assert Enum.fetch!(facts, row.fact) == stand.fact
        assert row.member == stand.member
        assert length(row.uses) == length(stand.uses)

        for {use, {site, fact}} <- Enum.zip(row.uses, stand.uses) do
          assert Enum.fetch!(facts, use.fact) == fact
          assert [name, index] = use.site
          assert name == stand.member
          member = Zkfol.Alloc.member(lay.alloc, name)
          sites = member.sites |> Map.values() |> Enum.concat() |> Enum.uniq()
          assert Enum.fetch!(sites, index) == site
        end
      end

      feed
    end
  end

  @doc "The slack row a guard range-checks reads :ranged; the rest are plain or shifted."
  @spec the_grid_feed_is_settled() :: %{atom() => term()}
  example the_grid_feed_is_settled do
    statement = EUser.fibonacci()

    {:ok, uair} =
      Zkfol.Uair.emit(
        Statement.pred(statement),
        Statement.witness(statement),
        Statement.claims(statement)
      )

    feed = Face.grid(uair)

    assert feed.len == 8
    assert hd(feed.columns) == Enum.reverse(Enum.map(1..8, &EUser.fib/1)) ++ List.duplicate(1, 8)
    assert feed.kinds == [:scheduled, :scheduled, :ranged, :scheduled, :scheduled]
    assert Enum.all?(feed.columns, &(length(&1) == 16))
    assert feed.num_vars == 4

    assert length(feed.origins) == length(feed.columns)
    assert Enum.all?(feed.origins, &(String.starts_with?(&1, "C") or &1 in ["x", "ones"]))

    assert feed.degree == Ast.degree(Statement.pred(statement))
    assert feed.degree < ZincPlus.pcs_params().degree
    feed
  end

  @doc "I send an object through GT's result encoder and recover the same object."
  @spec bridged(object) :: object when object: var
  def bridged(object) do
    %{"exid" => id} = object |> GtBridge.Eval.encode_result() |> Jason.decode!()
    assert {:ok, ^object} = GtBridge.ObjectRegistry.get(id)
    GtBridge.ObjectRegistry.remove(id)
    object
  end

  @spec the_stage_carries_its_derivation() :: %{atom() => term()}
  example the_stage_carries_its_derivation do
    statement = EUser.fibonacci()
    feed = Face.derivation(statement)

    assert %{fact: [:fib, 8, 21], consumes: [[:gt, 8, 2, 5], [:fib, 7, 13], [:fib, 6, 8]]} =
             List.last(feed.rows)

    assert %GtBridge.Phlow.ColumnedList{} = Face.derivation_view(statement, Builder)
    lowering = statement |> Face.lowering_view(Builder) |> ColumnedList.as_dict()
    [_, _, recursive] = lowering.rawItems
    assert [recursive.matched.env.x, recursive.matched.env.v] == recursive.accesses
    assert recursive.before.env[{:fib, {:param, :x}}] == recursive.matched.env.x
    assert Map.has_key?(recursive.compiled.env, :v1) and Map.has_key?(recursive.compiled.env, :v2)
    steps = recursive |> Face.steps_view(Builder) |> ColumnedList.as_dict()
    assert List.last(steps.rawItems) == recursive.compiled
    assert bridged(lowering) == lowering
    feed
  end

  @doc "What the judgement feed says is what the oracle and the lay say."
  @spec the_judgement_is_derived() :: %{atom() => term()}
  example the_judgement_is_derived do
    source = %Statement{rels: [EAl.hop_rel()], args: [5]}
    {:ok, statement, _trace} = Zkfol.Pipeline.run(EUser.plain(), source)
    pred = Statement.pred(statement)
    witness = Statement.witness(statement)
    len = Interpretation.len(witness)
    branches = pred |> Ast.conjuncts() |> Enum.flat_map(&Ast.branches/1)

    feed = Face.judgement(statement)

    raw = Face.judgement(%Statement{rels: [EAl.pick()]})
    assert Map.keys(raw) == Map.keys(feed)
    assert raw |> Map.values() |> Enum.all?(&(&1 == []))

    assert length(feed.labels) == length(branches)
    assert length(feed.sources) in [0, length(branches)]
    assert length(feed.rows) == Zkfol.Alloc.width(Statement.alloc(statement))

    for x <- 1..len do
      assert Enum.at(feed.holds, x - 1) == Zkfol.Semantics.holds?(pred, witness, x)
    end

    for branch <- feed.trees, column <- branch, goal <- column, node <- nodes(goal) do
      case Enum.map(node.children, &Map.get(&1, :role)) do
        ["left", "right"] ->
          [left, right] = node.children
          assert node.value == 0 == (left.value == right.value)

        ["pointer"] ->
          assert node.at == hd(node.children).value

        _other ->
          :ok
      end
    end

    assert feed.aims |> Enum.map(& &1.ptr) |> Enum.sort() == Ast.pointer_reads(pred)

    for %{ptr: ptr, from: from, to: to} <- feed.arrows do
      assert from in 1..len and to in 1..len
      if ptr, do: assert(Interpretation.at(witness, ptr, from) == to)
    end

    feed
  end

  @spec nodes(%{atom() => term()}) :: [%{atom() => term()}]
  defp nodes(node = %{children: children}), do: [node | Enum.flat_map(children, &nodes/1)]
end
