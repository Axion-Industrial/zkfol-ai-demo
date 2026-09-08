defmodule Examples.EFace do
  @moduledoc "I am the face's evidence: what a viewer reads, derived from the structs."

  use ExExample

  import ExUnit.Assertions

  alias Examples.EAl
  alias Examples.ESudoku
  alias Examples.EUser
  alias GtBridge.Phlow.Builder
  alias GtBridge.Phlow.ColumnedList
  alias GtBridge.Phlow.Empty
  alias Zkfol.Ast
  alias Zkfol.Face
  alias Zkfol.Interpretation
  alias Zkfol.Statement
  alias Zkfol.ZincPlus

  @spec a_statement_summarises_to_its_facts() :: %{atom() => term()}
  example a_statement_summarises_to_its_facts do
    summary = Face.summary(EUser.fibonacci())

    assert %{rels: 3, arity: 2, branches: 4, claims: 0, witness: "2 rows", args: [8]} = summary

    raw = Face.summary(%Statement{rels: [EUser.fib()], args: [8]})
    assert %{rels: 1, arity: 2, branches: nil, witness: nil} = raw
    summary
  end

  @doc "Generated term rows retain printable labels in the layout feed."
  @spec constructed_terms_have_a_layout_feed() :: %{atom() => term()}
  example constructed_terms_have_a_layout_feed do
    lay = Statement.lay(Examples.ENodes.reverse_proves())
    feed = Face.lay(lay)

    assert length(feed.rows) == Zkfol.Alloc.width(lay.alloc)
    assert Enum.any?(feed.rows, &String.contains?(&1, "{:read,"))
    assert Enum.all?(feed.witness, &(length(&1) == length(feed.rows)))
    feed
  end

  @doc "Join's facts and uses navigate to their sources across scalar, bank and heap layouts."
  @spec a_join_keeps_its_sources() :: [%{atom() => term()}]
  example a_join_keeps_its_sources do
    {:ok, sudoku, _trace} =
      Zkfol.Pipeline.run(EUser.plain(), %Statement{
        rels: [ESudoku.families()],
        args: ESudoku.act()
      })

    for statement <- [EUser.fibonacci(), sudoku, Examples.ENodes.reverse_proves()] do
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

  @doc "I am the pinned code's own parameters, not a copy of them."
  @spec the_code_answers_its_parameters() :: %{atom() => term()}
  example the_code_answers_its_parameters do
    pcs = Face.pcs()

    assert pcs == ZincPlus.pcs_params()
    assert pcs.rep_factor > 1
    assert pcs.column_openings > 0
    assert pcs.degree > 0
    assert pcs.backend =~ "zinc-plus"
    pcs
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

  @doc "I am a declared object as its own cells, the holes included."
  @spec an_object_shows_its_cells() :: %{atom() => term()}
  example an_object_shows_its_cells do
    feed = ESudoku.puzzle() |> Face.object_view(Builder) |> ColumnedList.as_dict()

    assert feed.title == "Object"
    assert Enum.map(feed.columns, & &1.title) == ["fact", "r" | Enum.map(0..15, &to_string/1)]
    assert length(feed.items) == 9 + 16

    assert hd(feed.items) ==
             ["puzzle(1)", "0" | List.duplicate("_", 9) ++ List.duplicate("", 7)]

    assert Enum.at(feed.items, 9) == ["puzzle(2)", "0" | Enum.map(1..16, &to_string/1)]
    assert %Empty{} = Face.object_view(EUser.fib(), Builder)
    feed
  end

  @spec the_act_reads_off_the_log() :: %{atom() => term()}
  example the_act_reads_off_the_log do
    ran = EUser.compiled()
    feed = Face.act(Zkfol.Log.snapshot(), ran)

    assert feed.route == :fib
    assert Enum.map(feed.passes, & &1.name) == ["Doubling", "Witness", "Phi"]
    assert Enum.map(feed.passes, & &1.verdict) == [:rewrites, :declines, :declines]
    assert %{backend: backend} = feed.report
    assert is_binary(backend)
    assert length(feed.trail) >= 4
    feed
  end

  @doc "The program rides its branch: an act finds it on its trail, a query on its ask."
  @spec the_program_on_its_branch() :: AL.Object.t()
  example the_program_on_its_branch do
    ran = Zkfol.compile(EUser.fib(), args: [8])
    snap = Zkfol.Log.snapshot()

    assert %AL.Object{id: :zkfol, branch: branch} = program = Face.program(snap, ran)

    assert Enum.any?(
             Zkfol.Log.thread(snap, ran.defined),
             &match?(
               %Zkfol.Log.Event{body: {:al_solved, %{branch: ^branch}}},
               &1
             )
           )

    query = Zkfol.eval!(EUser.fib(), [8, :_])
    assert %AL.Object{id: :zkfol} = Zkfol.Al.program(query.ask.branch.id)
    Zkfol.Query.close(query)

    refused = Zkfol.emit(%Statement{rels: []}, name: :nothing)
    assert Face.program(Zkfol.Log.snapshot(), refused) == nil
    program
  end

  @spec the_route_as_a_structure() :: %{atom() => term()}
  example the_route_as_a_structure do
    feed = Face.route(Zkfol.Pipeline.default())

    assert Enum.map(feed.passes, & &1.name) == ["Doubling", "Witness", "Phi"]
    assert Enum.all?(feed.passes, &(&1.implements == ["verb/0", "run/2"]))
    assert Enum.all?(feed.passes, &String.starts_with?(&1.says, "I "))
    feed
  end

  @spec the_text_elides_the_witness() :: String.t()
  example the_text_elides_the_witness do
    text = Face.text(EUser.fibonacci())

    assert text =~ "…elided…"
    refute text =~ "Interpretation"
    text
  end

  @doc "I send an object through GT's result encoder and recover the same object."
  @spec bridged(object) :: object when object: var
  def bridged(object) do
    %{"exid" => id} = object |> GtBridge.Eval.encode_result() |> Jason.decode!()
    assert {:ok, ^object} = GtBridge.ObjectRegistry.get(id)
    GtBridge.ObjectRegistry.remove(id)
    object
  end

  @spec the_statement_rides_the_bridge_whole() :: Statement.t()
  example the_statement_rides_the_bridge_whole do
    statement = EUser.fibonacci()

    assert bridged(statement) == statement
    statement
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
      assert Enum.count(feed.evals, &(Enum.at(&1, x - 1) == 0)) >= length(Ast.conjuncts(pred))
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
