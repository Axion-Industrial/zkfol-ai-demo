defmodule Zkfol.Log.Ran do
  @moduledoc "I am the receipt of one journaled act: the id of its define event."

  use TypedStruct

  alias Zkfol.Log
  alias Zkfol.Refusal
  alias Zkfol.Statement

  typedstruct enforce: true do
    field(:defined, pos_integer())
  end

  @typedoc "The define event's body: the act's name, its route, the openings, and the source."
  @type define :: {:define, atom(), Zkfol.Pipeline.t(), [Zkfol.Lay.opening()], Statement.t()}

  @doc "I am the statement after the act's first `k` passes, re-run; stage 0 is the source."
  @spec stage(t(), non_neg_integer()) :: {:ok, Statement.t()} | {:error, Refusal.t()}
  def stage(%__MODULE__{defined: defined}, k), do: staged(define(defined), k)

  @doc "I am the act's final statement, re-run and opened as the act opened it; nil if refused."
  @spec final_stage(t()) :: Statement.t() | nil
  def final_stage(%__MODULE__{defined: defined}) do
    {:define, _name, pipeline, public, _source} = define = define(defined)

    with {:ok, statement} <- staged(define, length(pipeline.passes)),
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
    for %Log.Event{
          id: defined,
          body: {:define, route, %Zkfol.Pipeline{passes: passes}, _public, _source}
        } <- snap.events,
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

  @spec define(pos_integer()) :: define()
  defp define(defined) do
    [%Log.Event{body: {:define, _name, _pipeline, _public, _source} = define} | _trail] =
      Log.thread(Log.snapshot(), defined)

    define
  end

  @spec staged(define(), non_neg_integer()) :: {:ok, Statement.t()} | {:error, Refusal.t()}
  defp staged({:define, _name, pipeline, _public, source}, k) do
    shortened = %Zkfol.Pipeline{passes: Enum.take(pipeline.passes, k)}

    case Zkfol.Pipeline.run(shortened, source) do
      {:ok, statement, _trace} -> {:ok, statement}
      {:error, _pass, reason, _trace} -> {:error, reason}
    end
  end

  @spec read(term(), map()) :: map()
  defp read({:define, name, _pipeline, _public, _source}, feed), do: %{feed | route: name}
  defp read({:prove_requested, name}, feed), do: %{feed | intent: name}
  defp read({:proved, report}, feed), do: %{feed | report: Map.from_struct(report)}
  defp read({:prove_failed, reason}, feed), do: %{feed | failure: inspect(reason)}
  defp read({:refused, refusal}, feed), do: %{feed | failure: Refusal.message(refusal)}

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
      Enum.any?(thread, &match?(%Log.Event{body: {:refused, _refusal}}, &1)) -> "refused"
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
