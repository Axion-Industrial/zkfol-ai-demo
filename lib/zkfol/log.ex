defmodule Zkfol.Log do
  @moduledoc """
  I am the session's log: what ran and what came of it, an append-only mnesia table in
  ram. Events are immutable, `push/2` the one write, every read a function of `snapshot/0`.
  """

  use TypedStruct

  alias Zkfol.Log.Run
  alias Zkfol.Log.Event

  @table :zkfol_log

  typedstruct do
    field(:events, [Event.t()], default: [])
  end

  # An ordered_set so ids stay ascending for last/1.
  @spec setup() :: :ok
  def setup do
    :ok = :mnesia.start()

    case :mnesia.create_table(@table,
           attributes: [:id, :basedon, :body],
           type: :ordered_set,
           ram_copies: [node()]
         ) do
      {:atomic, :ok} -> :ok
      {:aborted, {:already_exists, @table}} -> :ok
    end
  end

  @doc "I append an event based on `basedon` and return its id."
  @spec push(Event.body(), pos_integer() | nil) :: pos_integer()
  def push(body, basedon \\ nil) do
    {:atomic, event} =
      :mnesia.transaction(fn ->
        id =
          case :mnesia.last(@table) do
            :"$end_of_table" -> 1
            last -> last + 1
          end

        :ok = :mnesia.write({@table, id, basedon, body})
        %Event{id: id, basedon: basedon, body: body}
      end)

    EventBroker.event(%EventBroker.Event{source_module: __MODULE__, body: event})
    event.id
  end

  @doc "I provide a snapshot of the database as of the current timestamp"
  @spec snapshot() :: t()
  def snapshot do
    {:atomic, events} =
      :mnesia.transaction(fn ->
        :mnesia.foldl(
          fn {@table, id, basedon, body}, acc ->
            [%Event{id: id, basedon: basedon, body: body} | acc]
          end,
          [],
          @table
        )
      end)

    %__MODULE__{events: Enum.sort_by(events, & &1.id, :desc)}
  end

  @doc "I am the body of event `id`; nil when the log holds no such event."
  @spec body(t(), pos_integer()) :: term() | nil
  def body(%__MODULE__{events: events}, id) do
    Enum.find_value(events, fn
      %Event{id: ^id, body: body} -> body
      _event -> nil
    end)
  end

  @doc "I grab the thread of the relevant event id sent in"
  # Should we keep all 3 variants
  @spec thread(t(), pos_integer() | MapSet.t() | Run.t()) :: [Event.t()]
  def thread(log \\ snapshot(), roots)

  def thread(log, event_id) when is_integer(event_id) do
    thread(log, MapSet.new([event_id]))
  end

  def thread(log, %Run{defined: defined}) do
    thread(log, defined)
  end

  def thread(%__MODULE__{events: events}, roots) do
    chronological = Enum.reverse(events)
    ids = relevant_ids(chronological, roots)
    Enum.filter(chronological, &(&1.id in ids))
  end

  @doc "I give the proved report if there are any"
  @spec report(t(), Run.t() | pos_integer()) :: Zkfol.Prover.Report.t() | nil
  def report(log \\ snapshot(), run) do
    log
    |> thread(run)
    |> Enum.find_value(fn
      %Event{body: {:proved, report}} -> report
      _event -> nil
    end)
  end

  @doc "I return the first failed compilation of a specific run"
  @spec refusal(t(), Run.t() | pos_integer()) :: Zkfol.Refusal.t() | nil
  def refusal(log \\ snapshot(), run) do
    log |> thread(run) |> Stream.flat_map(&refusals/1) |> Enum.at(0)
  end

  @doc "I return the ids of the runs whose pipeline carried `module`."
  @spec module_runs(t(), module()) :: [pos_integer()]
  def module_runs(log \\ snapshot(), module)

  def module_runs(%__MODULE__{events: events}, module) do
    for %Event{id: id, body: {:define, _, %Zkfol.Pipeline{passes: passes}, _, _}} <- events,
        Enum.any?(passes, &match?({^module, _}, &1)) do
      id
    end
  end

  @doc "I am the define body that started `run`."
  @spec define(t(), Run.t() | pos_integer()) :: Event.define()
  def define(log \\ snapshot(), run)
  def define(log, %Run{defined: defined}), do: define(log, defined)
  def define(log, defined), do: {:define, _, _, _, _} = body(log, defined)

  # I grab all compilation attempts that ended in failure
  @spec refusals(Event.t()) :: [Zkfol.Refusal.t()]
  defp refusals(%Event{body: {:piped, verdicts}}) do
    for {_pass, {:errors, refusal}} <- verdicts do
      refusal
    end
  end

  defp refusals(%Event{body: {:refused, refusal}}), do: [refusal]
  defp refusals(%Event{body: {:prove_failed, refusal}}), do: [refusal]
  defp refusals(_event), do: []

  # events should be chronologically or else we lose
  @spec relevant_ids([Event.t()], MapSet.t(pos_integer())) :: MapSet.t(pos_integer())
  defp relevant_ids(events, roots) do
    Enum.reduce(events, roots, fn %{basedon: parent, id: id}, ids ->
      if parent in ids, do: MapSet.put(ids, id), else: ids
    end)
  end
end
