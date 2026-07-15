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
end
