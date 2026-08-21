defmodule Examples.ELog do
  @moduledoc "I am the journal's evidence: every read a pure function of a snapshot."

  use ExExample

  import ExUnit.Assertions

  alias Examples.EUser
  alias Zkfol.Log
  alias Zkfol.Pipeline
  alias Zkfol.Prover
  alias Zkfol.Statement

  @spec journaled_proving() :: Log.Ran.t()
  example journaled_proving do
    source = %Statement{rels: [EUser.fib()], args: [8]}
    ran = Zkfol.compile(source, name: :fibonacci, public: [:r])
    snap = Log.snapshot()
    assert %Prover.Report{} = report = Log.report(snap, ran)

    assert report.claims == [{"kernel.r", EUser.fib(8)}, {"in", 1}]

    # The trail runs from route through derivation and intent to observation.
    assert [
             %Log.Event{body: {:define, :fibonacci, %Pipeline{}, [:r]}},
             %Log.Event{body: {:al_solved, _derivation}},
             %Log.Event{body: {:piped, _verdicts}},
             %Log.Event{body: {:prove_requested, :fibonacci}},
             %Log.Event{body: {:proved, ^report}}
           ] = Enum.take(Log.trail(snap, ran), -5)

    ran
  end

  # A verdict lingering from an abandoned wait is not this wait's.
  @spec stale_verdicts_are_not_heard() :: Prover.Report.t()
  example stale_verdicts_are_not_heard do
    stale = %EventBroker.Event{
      source_module: __MODULE__,
      body: %Log.Event{id: 1, basedon: 1, body: {:proved, %{stale: true}}}
    }

    send(self(), stale)

    {:ok, report, _id} =
      Prover.prove(Statement.pred(EUser.fibonacci()), Statement.witness(EUser.fibonacci()))

    # The stale body is a bare map; a verdict actually heard is a Report.
    assert %Prover.Report{} = report
    report
  end

  @spec a_dead_prover_settles_its_debts() :: Zkfol.Refusal.t()
  example a_dead_prover_settles_its_debts do
    intent = Log.push({:prove_requested, :doomed})
    filter = [%Prover.Settled{intent: intent}]
    EventBroker.subscribe_me(filter)

    # Fault injection: owe the prover a verdict, then bring it down.
    # The supervisor restarts it; the debt settles on the log first.
    :sys.replace_state(Prover, &Map.put(&1, 0, {intent, []}))
    GenServer.stop(Prover, :shutdown)

    assert_receive %EventBroker.Event{body: %Log.Event{body: {:prove_failed, reason}}}, 1_000
    EventBroker.unsubscribe_me(filter)

    assert {:prover_died, _} = reason
    reason
  end
end
