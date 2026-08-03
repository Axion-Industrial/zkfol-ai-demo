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
  alias Zkfol.Statement

  @spec a_statement_summarises_to_its_facts() :: %{atom() => term()}
  example a_statement_summarises_to_its_facts do
    summary = Face.summary(EUser.fibonacci())

    assert %{rels: 1, arity: 2, branches: 3, claims: 0, witness: "4 rows", args: [8]} = summary
    summary
  end

  @spec a_raw_statement_has_only_its_source_facts() :: %{atom() => term()}
  example a_raw_statement_has_only_its_source_facts do
    summary = Face.summary(%Statement{rels: [EUser.fib()], args: [8]})

    assert %{rels: 1, arity: 2, branches: nil, witness: nil} = summary
    summary
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
    assert feed.kinds == [:scheduled, :scheduled, :plain, :plain, :scheduled, :scheduled]
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
    assert Enum.map(feed.passes, & &1.name) == ["Lang", "Doubling", "Witness"]
    assert Enum.map(feed.passes, & &1.verdict) == [:lowers, :rewrites, :declines]
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

    assert Enum.map(feed.passes, & &1.name) == ["Lang", "Doubling", "Witness"]
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

  @doc "I label every branch off the relations and judge every column."
  @spec the_judgement_is_derived() :: %{atom() => term()}
  example the_judgement_is_derived do
    source = %Statement{rels: [EAl.pick(), EAl.tab()], args: [:_, 41]}
    {:ok, statement, _trace} = Zkfol.Pipeline.run(EUser.plain(), source)

    %{labels: labels, evals: evals} = feed = Face.judgement(statement)

    assert labels == ["pick rule", "tab(1,10)", "tab(2,20)", "tab(3,40)", "tab(4,40)"]

    # Every column of a valid witness is answered by exactly one branch.
    for x <- 0..1 do
      assert Enum.count(evals, &(Enum.at(&1, x) == 0)) == 1
    end

    # The equations ride along as the paper writes them, judged term
    # by term: pick's read of tab, and the tag claim beside it.
    assert "C3(C6(X)) = 3" in hd(feed.terms)
    assert "C5(X) = 1" in hd(feed.terms)
    assert feed.term_evals |> hd() |> hd() |> Enum.sum() == 1682

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
    assert feed.rows == ["pick x", "pick v", "tab 1", "tab 2", "tag", "ptr 3"]

    feed
  end
end
