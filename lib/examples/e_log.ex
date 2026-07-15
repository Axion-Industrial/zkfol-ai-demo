defmodule Examples.ELog do
  @moduledoc """
  I show the reads the journal affords over the ambient log: the
  surface and time axis of a redefinition, its lifeline, the thread of
  a proof from its intent to the report observed, and that a proof
  defines what it proves. I do the journaling here; every read is a
  pure function of a snapshot.
  """

  use ExExample

  import ExUnit.Assertions

  alias Examples.EFibonacci
  alias Zkfol.Log
  alias Zkfol.Prover
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

  @spec journaled_proving() :: map()
  example journaled_proving do
    pred = EFibonacci.fibonacci_predicate()
    define = Log.push({:define, :fibonacci, pred})

    {:ok, report, id} =
      Uair.prove(pred, EFibonacci.fibonacci_witness(), name: :fibonacci, basedon: define)

    # The intent rides ahead of the boundary, the report follows it.
    assert [
             %Log.Event{body: {:prove_requested, :fibonacci}},
             %Log.Event{body: {:proved, ^report}}
           ] =
             Log.thread(Log.snapshot(), id)

    # A proof defines what it proves: the image carries the report, the
    # lifeline runs from statement through intent to observation.
    snap = Log.snapshot()

    assert [
             %Log.Event{body: {:define, :fibonacci, _pred}},
             %Log.Event{body: {:prove_requested, :fibonacci}},
             %Log.Event{id: observation, body: {:proved, ^report}}
           ] = Enum.take(Log.lifeline(snap, :fibonacci), -3)

    assert Log.image(snap).fibonacci == report
    assert Log.definer(snap, :fibonacci) == observation

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

    assert reason =~ "died"
    reason
  end
end
