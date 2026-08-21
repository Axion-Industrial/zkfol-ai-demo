defmodule Examples.EFace do
  @moduledoc """
  I am the face's evidence: a statement summarised as the facts a
  delta view compares, and rendered as bounded text with the witness
  elided, so a viewer never reads the structs themselves.
  """

  use ExExample

  import ExUnit.Assertions

  alias Examples.EAl
  alias Examples.EUser
  alias GtBridge.Phlow.Builder
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
    assert hd(feed.columns) == Enum.reverse(Enum.map(1..8, &EUser.fib/1))
    assert feed.kinds == [:scheduled, :scheduled, :ranged, :scheduled, :scheduled]
    assert Enum.all?(feed.columns, &(length(&1) == 8))
    assert feed.num_vars == 3

    assert length(feed.origins) == length(feed.columns)
    assert Enum.all?(feed.origins, &(String.starts_with?(&1, "C") or &1 in ["x", "ones"]))

    assert feed.degree == Ast.degree(Statement.pred(statement))
    assert feed.degree < ZincPlus.pcs_params().degree
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

  @doc "I compile my own act: a cached one's branch is already gone."
  @spec the_act_forwards_its_program() :: AL.Object.t()
  example the_act_forwards_its_program do
    ran = Zkfol.compile(%Statement{rels: [EUser.fib()], args: [8]})
    program = Face.program(Zkfol.Log.snapshot(), ran)

    assert %AL.Object{id: :zkfol, branch: branch} = program
    assert Enum.any?(AL.Branch.list(), &(&1.id == branch))
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

  @spec the_statement_rides_the_bridge_whole() :: Statement.t()
  example the_statement_rides_the_bridge_whole do
    statement = EUser.fibonacci()

    assert {:ok, _json} = Jexon.to_json(statement)
    statement
  end

  @spec the_stage_carries_its_derivation() :: %{atom() => term()}
  example the_stage_carries_its_derivation do
    feed = Face.derivation(EUser.fibonacci())

    assert %{fact: [:fib, 8, 21], consumes: [[:gt, 8, 2, 5], [:fib, 7, 13], [:fib, 6, 8]]} =
             List.last(feed.rows)

    assert %GtBridge.Phlow.ColumnedList{} = Face.derivation_view(EUser.fibonacci(), Builder)
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
  defp nodes(%{children: children} = node), do: [node | Enum.flat_map(children, &nodes/1)]
end
