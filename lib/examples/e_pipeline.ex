defmodule Examples.EPipeline do
  @moduledoc """
  I am the pipeline's evidence: generation fills the witness slot, the
  doubled route walks through the front door and leaves its receipt,
  the emit act leaves a receipt with no proof, the trail replays the
  act off the log, and a refusal names its pass.
  """

  use ExExample

  import ExUnit.Assertions

  alias Examples.EUser
  alias Zkfol.Doubling
  alias Zkfol.Log
  alias Zkfol.Pipeline
  alias Zkfol.Prover
  alias Zkfol.Refusal
  alias Zkfol.Statement
  alias Zkfol.Witness

  @spec generation_fills_the_slot() :: Statement.t()
  example generation_fills_the_slot do
    source = %Statement{rels: [EUser.fib()]}
    pipeline = %Pipeline{passes: [{Witness, args: [8]}, {Zkfol.Lang, []}]}

    {:ok, statement, trace} = Pipeline.run(pipeline, source)

    # The run answers first; the witness slot opens when the lowering
    # lays the derivation it established.
    assert Statement.witness(statement) == Statement.witness(EUser.fibonacci(8))

    assert [
             {Witness, %Statement{stage: %Statement.Derived{}} = derived},
             {Zkfol.Lang, ^statement}
           ] =
             trace

    assert Statement.derivation(derived) == Statement.derivation(statement)
    statement
  end

  @spec the_link_follows_the_solve() :: Statement.t()
  example the_link_follows_the_solve do
    source = %Statement{rels: [EUser.regs()], args: [5]}

    {:ok, statement, trace} = Pipeline.run(Pipeline.default(), source)

    assert [_doubling, {Witness, %Statement{stage: %Statement.Derived{}}} | _rest] = trace

    assert %Statement.Solved{lay: %Zkfol.Lay{alloc: alloc, shape: shape}, pred: linked} =
             statement.stage

    assert shape.members == [:regs]
    assert Statement.alloc(statement) == alloc
    assert Enum.to_list(Zkfol.Alloc.rows(alloc, :regs)) == [1, 2, 3]
    assert alloc.slots == %{regs: [:x, :a, :b]}
    assert {:ok, ^linked} = Zkfol.Alloc.link(shape.pred, alloc)
    statement
  end

  @spec claimless_no_relations_refuses_uniformly() :: Refusal.t()
  example claimless_no_relations_refuses_uniformly do
    {:error, reason} = Witness.run(%Statement{rels: []}, [])

    assert {:no_relations, _} = reason
    reason
  end

  @spec doubled_through_the_pipeline() :: Log.Ran.t()
  example doubled_through_the_pipeline do
    pipeline = %Pipeline{passes: [{Doubling, []}, {Zkfol.Lang, []}]}
    source = %Statement{rels: [EUser.fib()], args: [100]}

    # One call is the whole act: the route defined, the derivation on
    # its trail, the verdicts piped, the proof intended on top.
    ran = Zkfol.compile(source, pipeline: pipeline, name: :doubled_fibonacci)

    assert %Log.Ran{pipeline: ^pipeline, source: ^source} = ran

    report = Log.report(Log.snapshot(), ran)
    assert %Prover.Report{claims: [{_claim, value}, {_position, _walked}]} = report
    assert value == EUser.fib(100)
    ran
  end

  @spec the_trail_replays_the_act() :: [Log.Event.t()]
  example the_trail_replays_the_act do
    ran = doubled_through_the_pipeline()
    trail = Log.trail(Log.snapshot(), ran)

    # The trail's event shapes are ELog's claim; here the act replays:
    # the verdicts off the trail, the stages re-run from the source.
    assert Enum.find_value(trail, fn
             %Log.Event{body: {:piped, verdicts}} -> verdicts
             _event -> nil
           end) == [{Doubling, :rewrites}, {Zkfol.Lang, :declines}]

    # A stage is a re-run, never a record: 0 the source, 1 doubled,
    # 2 the same again, the lowering having nothing left to do.
    assert Log.stage(ran, 0) == {:ok, ran.source}
    assert {:ok, %Statement{claims: [_exact, _position]} = doubled} = Log.stage(ran, 1)
    assert Statement.pred(doubled) != nil
    assert {:ok, %Statement{stage: %Statement.Solved{}}} = Log.stage(ran, 2)

    trail
  end

  @spec emit_leaves_a_receipt_without_a_proof() :: Log.Ran.t()
  example emit_leaves_a_receipt_without_a_proof do
    pipeline = %Pipeline{passes: [{Doubling, []}, {Zkfol.Lang, []}]}
    source = %Statement{rels: [EUser.fib()], args: [100]}

    # The same act stops at the emitted UAIR: the route defined, the
    # derivation on its trail, the verdicts piped, and no proof on top.
    ran = Zkfol.emit(source, pipeline: pipeline, name: :emitted_fibonacci)

    assert %Log.Ran{pipeline: ^pipeline, source: ^source} = ran

    trail = Log.trail(Log.snapshot(), ran)

    # The trail ends at the piped verdicts: define, derivation, piped,
    # and nothing proved, since emit never asked the prover.
    assert [
             %Log.Event{id: defined, body: {:define, :emitted_fibonacci, ^pipeline}},
             %Log.Event{basedon: defined, body: {:al_solved, %{name: :fib_kernel}}},
             %Log.Event{basedon: defined, body: {:piped, verdicts}}
           ] = trail

    assert verdicts == [{Doubling, :rewrites}, {Zkfol.Lang, :declines}]

    # No intent, so no report ever settles off the log.
    assert Log.report(Log.snapshot(), ran) == nil

    ran
  end

  @spec a_refusal_names_its_pass() :: Refusal.t()
  example a_refusal_names_its_pass do
    source = %Statement{rels: [EUser.fib()], args: [0]}

    {:error, Doubling, refusal, []} =
      Pipeline.run(%Pipeline{passes: [{Doubling, []}, {Zkfol.Lang, []}]}, source)

    assert {:precedes_base_case, %{n: 0, base: 1}} = refusal
    refusal
  end

  @spec outside_the_class_passes_through() :: Statement.t()
  example outside_the_class_passes_through do
    source = %Statement{rels: [EUser.regs()], args: [5]}

    {:ok, statement, trace} = Pipeline.run(Pipeline.default(), source)

    # The doubling try declined, the run derived, the lowering laid
    # what it established: the statement rides on.
    assert [
             {Doubling, ^source},
             {Zkfol.Witness, %Statement{stage: %Statement.Derived{}}},
             {Zkfol.Lang, solved}
           ] = trace

    assert statement == solved
    assert Statement.witness(statement) == Statement.witness(EUser.registers(5))
    statement
  end
end
