defmodule Zkfol.Log.Ran do
  @moduledoc """
  I am the receipt of one journaled act: the route, the source, and
  the defining event's id. I keep no history: `stage/2` and
  `final_stage/1` re-run from the source, and `story/2` and `acts/2`
  rebuild what an act came to from the log itself.
  """

  use TypedStruct

  alias Zkfol.Log
  alias Zkfol.Refusal
  alias Zkfol.Statement

  typedstruct enforce: true do
    field(:pipeline, Zkfol.Pipeline.t())
    field(:source, Statement.t())
    field(:defined, pos_integer())
    field(:public, [Zkfol.Lay.opening()], default: [])
  end

  @doc """
  I am the statement after the act's first `k` passes, re-run from the
  source: passes are pure, so a stage is recomputed, never stored.
  Stage 0 is the source itself.
  """
  @spec stage(t(), non_neg_integer()) :: {:ok, Statement.t()} | {:error, Refusal.t()}
  def stage(%__MODULE__{pipeline: pipeline, source: source}, k) do
    shortened = %Zkfol.Pipeline{passes: Enum.take(pipeline.passes, k)}

    case Zkfol.Pipeline.run(shortened, source) do
      {:ok, statement, _trace} -> {:ok, statement}
      {:error, _pass, reason, _trace} -> {:error, reason}
    end
  end

  @doc """
  I am the act's final statement, re-run from the source, so a holder
  has the struct itself and every view it wears; nil when a pass
  refused and there is no final stage to hold.
  """
  @spec final_stage(t()) :: Statement.t() | nil
  def final_stage(%__MODULE__{pipeline: pipeline, public: public} = ran) do
    with {:ok, statement} <- stage(ran, length(pipeline.passes)),
         {:ok, opened} <- Statement.opened(statement, public) do
      opened
    else
      _refused -> nil
    end
  end

  @doc "I am one act's story off the log: route, verdicts, intent, what settled it, the trail."
  @spec story(Log.t(), t() | pos_integer()) :: %{atom() => term()}
  def story(snap, %__MODULE__{defined: defined}), do: story(snap, defined)

  def story(snap, defined) when is_integer(defined) do
    trail = Log.thread(snap, defined)
    feed = %{route: nil, passes: [], intent: nil, report: nil, failure: nil}

    trail
    |> Enum.reduce(feed, fn %Log.Event{body: body}, feed -> read(body, feed) end)
    |> Map.put(
      :trail,
      Enum.map(trail, &%{id: &1.id, basedon: &1.basedon, body: inspect(&1.body)})
    )
  end

  @doc "I am every journaled act whose route carried `module`, with its verdict and settling."
  @spec acts(Log.t(), module()) :: [%{atom() => term()}]
  def acts(snap, module) do
    for %Log.Event{id: defined, body: {:define, route, %Zkfol.Pipeline{passes: passes}, _public}} <-
          snap.events,
        Enum.any?(passes, &match?({^module, _opts}, &1)) do
      thread = Log.thread(snap, defined)

      verdict =
        Enum.find_value(thread, fn
          %Log.Event{body: {:piped, verdicts}} ->
            Enum.find_value(verdicts, fn
              {^module, verdict} -> to_string(word(verdict))
              _other -> nil
            end)

          _event ->
            nil
        end)

      %{defined: defined, route: route, verdict: verdict, settled: settled(thread)}
    end
  end

  @spec read(term(), map()) :: map()
  defp read({:define, name, _pipeline, _public}, feed), do: %{feed | route: name}
  defp read({:prove_requested, name}, feed), do: %{feed | intent: name}
  defp read({:proved, report}, feed), do: %{feed | report: Map.from_struct(report)}
  defp read({:prove_failed, reason}, feed), do: %{feed | failure: inspect(reason)}

  defp read({:piped, verdicts}, feed) do
    passes =
      for {{pass, verdict}, index} <- Enum.with_index(verdicts, 1) do
        %{index: index, name: pass |> Module.split() |> List.last(), verdict: word(verdict)}
      end

    failure =
      Enum.find_value(verdicts, feed.failure, fn
        {_pass, {:errors, refusal}} -> Refusal.message(refusal)
        {_pass, _verdict} -> nil
      end)

    %{feed | passes: passes, failure: failure}
  end

  defp read(_body, feed), do: feed

  @spec word(Zkfol.Pipeline.verdict()) :: atom()
  defp word({:errors, _refusal}), do: :errors
  defp word(verdict), do: verdict

  @spec settled([Log.Event.t()]) :: String.t()
  defp settled(thread) do
    cond do
      Enum.any?(thread, &match?(%Log.Event{body: {:proved, _report}}, &1)) -> "proved"
      Enum.any?(thread, &match?(%Log.Event{body: {:prove_failed, _reason}}, &1)) -> "failed"
      Enum.any?(thread, &match?(%Log.Event{body: {:prove_requested, _name}}, &1)) -> "unsettled"
      Enum.any?(thread, &erred?/1) -> "erred"
      Enum.any?(thread, &match?(%Log.Event{body: {:piped, _verdicts}}, &1)) -> "emitted"
      true -> "halted"
    end
  end

  @spec erred?(Log.Event.t()) :: boolean()
  defp erred?(%Log.Event{body: {:piped, verdicts}}),
    do: Enum.any?(verdicts, &match?({_pass, {:errors, _refusal}}, &1))

  defp erred?(_event), do: false
end
