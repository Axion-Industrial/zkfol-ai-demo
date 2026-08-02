defmodule Examples.EFace do
  @moduledoc """
  I am the face's evidence: a statement summarised as the facts a
  delta view compares, and rendered as bounded text with the witness
  elided, so a viewer never reads the structs themselves.
  """

  use ExExample

  import ExUnit.Assertions

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
    assert feed.len == 8
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
    assert Enum.map(feed.passes, & &1.name) == ["Lang", "Doubling", "Witness", "Accumulator"]
    assert Enum.map(feed.passes, & &1.verdict) == [:lowers, :rewrites, :declines, :declines]
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

    assert Enum.map(feed.passes, & &1.name) == ["Lang", "Doubling", "Witness", "Accumulator"]
    assert Enum.all?(feed.passes, &(&1.implements == ["run/2", "plan/2"]))
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
end
