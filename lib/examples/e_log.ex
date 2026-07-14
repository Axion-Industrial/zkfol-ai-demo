defmodule Examples.ELog do
  @moduledoc """
  I show the command log: push is the only write, images are the only reads,
  and earlier surfaces stay reachable.
  """

  use ExExample

  import ExUnit.Assertions

  alias Examples.EFibonacci
  alias Examples.EPower
  alias Zkfol.Interpretation
  alias Zkfol.Log
  alias Zkfol.Uair

  @spec defined_power() :: Log.t()
  example defined_power do
    log =
      Log.new()
      |> Log.push({:define, :power, EPower.power_predicate()})
      |> Log.push({:define, :power_ranges, EPower.pointer_ranges()})

    assert %{power: _, power_ranges: _} = Log.image(log)
    log
  end

  @spec redefinition_keeps_the_lifeline() :: Log.t()
  example redefinition_keeps_the_lifeline do
    log = Log.push(defined_power(), {:define, :power, :revised}, 2)

    assert Log.image(log).power == :revised
    assert Log.image_down(log, 2).power == EPower.power_predicate()
    log
  end

  @spec journaled_proving() :: Log.t()
  example journaled_proving do
    pred = EFibonacci.fibonacci_predicate()

    # The intent is journaled before the boundary is crossed: an intent
    # with no observation is crash forensics, not a gap.
    log =
      Log.new()
      |> Log.push({:define, :fibonacci, pred})
      |> Log.push({:prove_requested, %{name: "fibonacci n=8"}}, 1)

    {:ok, report} = Uair.prove(pred, Interpretation.new(EFibonacci.rows_for(8)))
    log = Log.push(log, {:proved, %{report: report}}, 2)

    %Log.Event{body: {:proved, observed}, basedon: intent_id} =
      Enum.find(log.events, &match?(%Log.Event{body: {:proved, _}}, &1))

    %Log.Event{body: {:prove_requested, _intent}, basedon: defined} =
      Enum.find(log.events, &(&1.id == intent_id))

    assert observed.report.proved
    assert %Log.Event{body: {:define, _, _}} = Enum.find(log.events, &(&1.id == defined))
    log
  end
end
