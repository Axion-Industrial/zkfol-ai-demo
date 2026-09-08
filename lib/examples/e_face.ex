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
  alias Zkfol.Face
  alias Zkfol.Log
  alias Zkfol.Statement

  @spec a_statement_summarises_to_its_facts() :: %{atom() => term()}
  example a_statement_summarises_to_its_facts do
    summary = Face.summary(EUser.fibonacci())

    assert %{rels: 1, arity: 2, branches: 3, claims: 0, witness: "5 rows", args: [8]} = summary

    raw = Face.summary(%Statement{rels: [EUser.fib()], args: [8]})
    assert %{rels: 1, arity: 2, branches: nil, witness: nil} = raw
    summary
  end

  @doc "I am the pinned code's own parameters, not a copy of them."
  @spec the_code_answers_its_parameters() :: %{atom() => term()}
  example the_code_answers_its_parameters do
    pcs = Face.pcs()

    # The inverse rate and the proximity sample count are the backend's
    # to state: a column of 2^mu cells encodes to rep_factor times that.
    assert pcs.rep_factor > 1
    assert pcs.column_openings > 0
    assert pcs.degree > 0
    assert pcs.backend =~ "zinc-plus"
    pcs
  end

  @spec the_grid_feed_is_settled() :: %{atom() => term()}
  example the_grid_feed_is_settled do
    statement = EUser.fibonacci()

    {:ok, uair} =
      Zkfol.Uair.emit(Statement.pred(statement), Statement.witness(statement), statement.claims)

    feed = Face.grid(uair)

    # Oriented at the source: trace order with the padding cut, so the
    # n row counts 1..len, and every row's kind named off the shifts.
    assert feed.traces_order
    assert hd(feed.columns) == Enum.to_list(1..8)
    # The fibonacci guard x > 1 range-checks its slack column, so that
    # committed column reads :ranged off the word_lookups; the rest are
    # plain or shifted, taking no read of their own.
    assert feed.kinds == [:scheduled, :scheduled, :plain, :plain, :ranged, :scheduled, :scheduled]
    assert feed.word_lookups == [{4, 32, 8}]
    assert :ranged in feed.kinds
    assert Enum.all?(feed.columns, &(length(&1) == 8))
    assert feed.num_vars == 3

    # Every committed column says which interpretation row it carries.
    assert length(feed.origins) == length(feed.columns)
    assert Enum.all?(feed.origins, &(String.starts_with?(&1, "C") or &1 in ["x", "ones"]))
    feed
  end

  @spec the_act_reads_off_the_log() :: %{atom() => term()}
  example the_act_reads_off_the_log do
    ran = EUser.compiled()
    feed = Face.act(Zkfol.Log.snapshot(), ran)

    assert feed.route == :fib
    assert Enum.map(feed.passes, & &1.name) == ["Doubling", "Witness", "Lang"]
    assert Enum.map(feed.passes, & &1.verdict) == [:rewrites, :declines, :declines]
    assert %{backend: backend} = feed.report
    assert is_binary(backend)
    assert length(feed.trail) >= 4
    feed
  end

  @spec the_emit_spawn_is_the_struct() :: Zkfol.Uair.t()
  example the_emit_spawn_is_the_struct do
    uair = Face.emitted(EUser.compiled())
    assert %Zkfol.Uair{} = uair
    uair
  end

  @spec the_route_as_a_structure() :: %{atom() => term()}
  example the_route_as_a_structure do
    feed = Face.route(Zkfol.Pipeline.default())

    assert Enum.map(feed.passes, & &1.name) == ["Doubling", "Witness", "Lang"]
    assert Enum.all?(feed.passes, &(&1.implements == ["verb/0", "run/2"]))
    assert Enum.all?(feed.passes, &String.starts_with?(&1.says, "I "))
    feed
  end

  @spec a_pass_is_described_by_what_exists() :: %{atom() => term()}
  example a_pass_is_described_by_what_exists do
    snap = Zkfol.Log.snapshot()
    doubling = Face.pass(snap, Zkfol.Doubling)

    assert doubling.implements
    assert Enum.all?(doubling.acts, &match?(%{defined: _id, route: _r, settled: _s}, &1))

    refute Face.pass(snap, Zkfol.Ast).implements
    doubling
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

    assert %{fact: [:fib, 8, 21], consumes: [[:fib, 7, 13], [:fib, 6, 8]], fan_in: 0} =
             List.last(feed.rows)

    assert feed.extents == %{fib: 8}
    assert feed.edges == 12

    ran = Zkfol.emit(%Statement{rels: [EUser.regs()], args: [5]})
    logged = ran |> Log.Ran.final_stage() |> Face.derivation()

    assert length(logged.rows) == 5
    assert %{fact: [:regs, 5, _a, _b], consumes: [[:regs, 4, _, _]]} = List.last(logged.rows)
    feed
  end

  @spec the_judgement_draws_the_weld_arrows() :: %{atom() => term()}
  example the_judgement_draws_the_weld_arrows do
    feed = Face.judgement(EUser.fibonacci())

    assert feed.regions == [
             %{name: :fib, first: 1, last: 2},
             %{name: :ptr, first: 3, last: 4},
             %{name: :slack, first: 5, last: 5}
           ]

    assert length(feed.arrows) == 12
    assert %{ptr: 3, from: 8, to: 7, to_row: 1, weld: 1} in feed.arrows
    assert %{ptr: 4, from: 8, to: 6, to_row: 1, weld: 2} in feed.arrows

    assert feed.aims == [%{ptr: 3, member: :fib}, %{ptr: 4, member: :fib}]
    feed
  end

  @spec a_fact_carries_its_own_lay() :: Statement.t()
  example a_fact_carries_its_own_lay do
    sub = Statement.under(EUser.fibonacci(), 4)

    assert %Statement{stage: %Zkfol.Statement.Solved{}} = sub
    assert length(Statement.derivation(sub).facts) == 4
    assert Zkfol.Interpretation.len(Statement.witness(sub)) == 4
    assert Zkfol.Semantics.valid?(Statement.pred(sub), Statement.witness(sub))

    assert Statement.under(EUser.fibonacci(), 99) == nil

    {:ok, picked, _trace} =
      Zkfol.Pipeline.run(EUser.plain(), %Statement{rels: [EAl.pick()], args: [:_, 41]})

    leaf = Statement.under(picked, 1)

    assert hd(leaf.rels).name == :tab
    assert Zkfol.Alloc.width(Statement.alloc(leaf)) == 2
    assert Zkfol.Interpretation.rows(Statement.witness(leaf)) == [[3], [40]]
    sub
  end

  @doc "I label every branch off the relations and judge every column."
  @spec the_judgement_is_derived() :: %{atom() => term()}
  example the_judgement_is_derived do
    source = %Statement{rels: [EAl.pick()], args: [:_, 41]}
    {:ok, statement, _trace} = Zkfol.Pipeline.run(EUser.plain(), source)

    %{labels: labels, evals: evals} = feed = Face.judgement(statement)

    assert labels == ["pick rule", "tab(1,10)", "tab(2,20)", "tab(3,40)", "tab(4,40)"]

    # Every column of a valid witness is answered by exactly one branch.
    for x <- 0..1 do
      assert Enum.count(evals, &(Enum.at(&1, x) == 0)) == 1
    end

    # The equations ride along as the paper writes them: pick's read
    # of tab, and the tag claim beside it.
    assert "C3(C6(X)) = 3" in hd(feed.terms)
    assert "C5(X) = 1" in hd(feed.terms)

    # Each equation carries its computation as a tree, down to the
    # pointer a composed cell reads through: the read of tab really is
    # 3 = 3 at the fact's column, through pointer cell C6.
    read = feed.trees |> hd() |> hd() |> hd()
    assert %{text: "C3(C6(X)) = 3", value: 0} = read

    assert %{role: "left", text: "C3(C6(X))", value: 3} = hd(read.children)

    assert %{role: "pointer", text: "C6(X)", value: 1, at: 1} =
             read.children |> hd() |> Map.get(:children) |> hd()

    # A cell knows which column it reads, so a viewer can hop from any
    # value to the judgement that forced it: the read lands on column 1.
    assert %{at: 1} = hd(read.children)

    # And each branch remembers the clause it was lowered from.
    assert hd(feed.sources) == "pick(x, v) do tab(3, w); v = w + 1 end"
    assert Enum.at(feed.sources, 3) == "tab(3, 40)"

    assert feed.witness |> hd() |> Enum.take(4) == [0, 0, 3, 40]

    # And every witness row wears its meaning: the members' head
    # variables, the tag, the pointer by its target.
    assert feed.rows ==
             [
               "C1 · pick x",
               "C2 · pick v",
               "C3 · tab 1",
               "C4 · tab 2",
               "C5 · tag",
               "C6 · ptr tab 3"
             ]

    feed
  end
end
