defmodule Examples.ELog do
  @moduledoc """
  I show the reads the journal affords over the ambient log: the
  surface and time axis of a redefinition, its lifeline, the thread of
  a proof from its intent to the report observed, and that a proof
  defines what it proves. I journal by hand or let the front door do
  it; every read is a pure function of a snapshot.
  """

  use ExExample

  import ExUnit.Assertions

  alias Examples.EFibonacci
  alias Examples.ELang
  alias Zkfol.Log
  alias Zkfol.Pipeline
  alias Zkfol.Prover
  alias Zkfol.Statement
  alias Zkfol.Uair

  @spec redefinition_keeps_the_lifeline() :: [Log.Event.t()]
  example redefinition_keeps_the_lifeline do
    first = Log.push({:define, :pedagogy, :v1})
    second = Log.push({:define, :pedagogy, :v2}, first)
    snap = Log.snapshot()

    assert Log.image(snap).pedagogy == :v2
    assert Log.definer(snap, :pedagogy) == second
    assert Log.image_down(snap, first).pedagogy == :v1

    lifeline = Log.lifeline(snap, :pedagogy)
    assert [%Log.Event{id: ^first}, %Log.Event{id: ^second}] = Enum.take(lifeline, -2)
    lifeline
  end

  @spec journaled_proving() :: Log.Ran.t()
  example journaled_proving do
    ran = Zkfol.compile(%Statement{rels: [ELang.fib()], args: [8]}, name: :fibonacci)
    snap = Log.snapshot()
    assert %Prover.Report{} = report = Log.report(snap, ran)

    # The intent rides ahead of the boundary, the report follows it.
    assert [
             %Log.Event{body: {:prove_requested, :fibonacci}},
             %Log.Event{body: {:proved, ^report}}
           ] = Log.thread(snap, ran.intended)

    # A proof defines what it proves: the image carries the report, the
    # lifeline runs from route through derivation and intent to observation.
    assert [
             %Log.Event{body: {:define, :fibonacci, %Pipeline{}}},
             %Log.Event{body: {:al_solved, _derivation}},
             %Log.Event{body: {:piped, _verdicts}},
             %Log.Event{body: {:prove_requested, :fibonacci}},
             %Log.Event{id: observation, body: {:proved, ^report}}
           ] = Enum.take(Log.lifeline(snap, :fibonacci), -5)

    assert Log.image(snap).fibonacci == report
    assert Log.definer(snap, :fibonacci) == observation

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
      Uair.prove(EFibonacci.fibonacci_predicate(), EFibonacci.fibonacci_witness())

    # The stale body is a bare map; a verdict actually heard is a Report.
    assert %Prover.Report{} = report
    report
  end

  @spec a_dead_prover_settles_its_debts() :: String.t()
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
