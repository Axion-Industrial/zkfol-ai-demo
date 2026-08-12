defmodule Zkfol.Log do
  @moduledoc """
  I am the command log: the only essential state of the system, an
  append-only mnesia table living with the node.

  Following Schueler's Update Reconsidered, events are immutable and
  union is the only operation on them: `push/2` is the one write, and
  it returns the event's id. What you hold is only ever `snapshot/0`, a
  value; every read is a pure function of one. The table is created
  once at boot (`Zkfol.Application`), so no write carries its own setup.

  A journaled pipeline act leaves a `Ran`: a receipt
  of ids whose trail is a query and whose stages are pure re-runs.
  """

  use TypedStruct

  alias Zkfol.Log.Ran

  @table :zkfol_log

  typedstruct module: Event, enforce: true do
    @moduledoc "I am one immutable event: what was furnished, based on which image."

    field(:id, pos_integer())
    field(:basedon, pos_integer() | nil)
    field(:body, term())
  end

  typedstruct do
    field(:events, [Event.t()], default: [])
  end

  # A ram-copies ordered_set: ids stay ascending for last/1, and the
  # table shares the node's lifetime. Starting mnesia is idempotent.
  @doc "I create the log's table if it is not there yet. The application calls me at boot."
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

  @doc """
  I append an event to the table and return its id. `basedon` names the
  event id whose image the caller was looking at; I never inspect it.
  """
  @spec push(term(), pos_integer() | nil) :: pos_integer()
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

  @doc "I am the table as a value, newest event first."
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

  @doc "I am event `id` and everything transitively based on it, oldest first."
  @spec thread(t(), pos_integer()) :: [Event.t()]
  def thread(log, id), do: descend(log, MapSet.new([id]))

  @doc "I am the trail `ran` left: its define event and everything based on it, oldest first."
  @spec trail(t(), Ran.t()) :: [Event.t()]
  def trail(log, %Ran{defined: defined}), do: thread(log, defined)

  @doc "I am the report settling `ran`'s intent, off its trail, or nil while none has landed."
  @spec report(t(), Ran.t()) :: Zkfol.Prover.Report.t() | nil
  def report(log, %Ran{defined: defined}) do
    log
    |> thread(defined)
    |> Enum.find_value(fn
      %Event{body: {:proved, report}} -> report
      _event -> nil
    end)
  end

  @doc "I am the first refusal on `ran`'s trail, nil where none stopped it."
  @spec refusal(t(), Ran.t()) :: Zkfol.Refusal.t() | nil
  def refusal(log, %Ran{defined: defined}),
    do: log |> thread(defined) |> Enum.flat_map(&refusals/1) |> List.first()

  @spec refusals(Event.t()) :: [Zkfol.Refusal.t()]
  defp refusals(%Event{body: {:piped, verdicts}}),
    do: for({_pass, {:errors, refusal}} <- verdicts, do: refusal)

  defp refusals(%Event{body: {:refused, refusal}}), do: [refusal]
  defp refusals(%Event{body: {:prove_failed, refusal}}), do: [refusal]
  defp refusals(_event), do: []

  # Oldest to newest, an event joins the thread when it is a root or is
  # based on one already in it; its own id then becomes a root too.
  @spec descend(t(), MapSet.t()) :: [Event.t()]
  defp descend(%__MODULE__{events: events}, roots) do
    events
    |> Enum.reverse()
    |> Enum.reduce({roots, []}, fn event, {ids, kept} ->
      if MapSet.member?(ids, event.id) or MapSet.member?(ids, event.basedon),
        do: {MapSet.put(ids, event.id), [event | kept]},
        else: {ids, kept}
    end)
    |> elem(1)
    |> Enum.reverse()
  end
end
