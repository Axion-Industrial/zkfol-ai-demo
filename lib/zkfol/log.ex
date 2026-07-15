defmodule Zkfol.Log do
  @moduledoc """
  I am the command log: the only essential state of the system, an
  append-only mnesia table living with the node.

  Following Schueler's Update Reconsidered, events are immutable and
  union is the only operation on them: `push/2` is the one write, and
  it returns the event's id. What you hold is only ever `snapshot/0`, a
  value; every read is a pure function of one. The table is created
  once at boot (`Zkfol.Application`), so no write carries its own setup.

  A name is defined by a `{:define, name, value}` event, and equally by
  a proof observed under a named intent: the image is what is known,
  stated or proven.

  ### Public API

  - `setup/0`, `push/2`, `snapshot/0`, `events/0`
  - `image/1`, `image_down/2`, `definer/2`
  - `thread/2`, `lifeline/2`
  """

  use TypedStruct

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
    {:atomic, id} =
      :mnesia.transaction(fn ->
        id =
          case :mnesia.last(@table) do
            :"$end_of_table" -> 1
            last -> last + 1
          end

        :ok = :mnesia.write({@table, id, basedon, body})
        id
      end)

    id
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

  @doc "I list every event oldest first, to read or graph the log."
  @spec events() :: [Event.t()]
  def events, do: snapshot().events |> Enum.reverse()

  @doc "I am the current surface: each name mapped to its latest definition."
  @spec image(t()) :: %{term() => term()}
  def image(%__MODULE__{events: events}), do: surface(events)

  @doc "I am the surface as it stood just after event `id`: the time axis, navigable."
  @spec image_down(t(), pos_integer()) :: %{term() => term()}
  def image_down(%__MODULE__{events: events}, id) do
    events |> Enum.drop_while(&(&1.id > id)) |> surface()
  end

  @doc "I am the id of the event whose definition of `name` is the surface's, or nil."
  @spec definer(t(), term()) :: pos_integer() | nil
  def definer(%__MODULE__{events: events}, name) do
    events
    |> definitions()
    |> Enum.reverse()
    |> Enum.find_value(fn
      {^name, _value, id} -> id
      _definition -> nil
    end)
  end

  @doc "I am event `id` and everything transitively based on it, oldest first."
  @spec thread(t(), pos_integer()) :: [Event.t()]
  def thread(log, id), do: descend(log, MapSet.new([id]))

  @doc "I am `name`'s lifeline: its definitions and everything based on them, oldest first."
  @spec lifeline(t(), term()) :: [Event.t()]
  def lifeline(%__MODULE__{events: events} = log, name) do
    roots =
      for %Event{id: id, body: body} <- events,
          match?({:define, ^name, _}, body) or match?({:prove_requested, ^name}, body),
          into: MapSet.new(),
          do: id

    descend(log, roots)
  end

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

  @spec surface([Event.t()]) :: %{term() => term()}
  defp surface(events) do
    for {name, value, _id} <- definitions(events), into: %{}, do: {name, value}
  end

  # Oldest first: a define event is a definition, and so is a proved
  # observation, through the name its intent asked for. A proof defines
  # what it proves; a failure defines nothing.
  @spec definitions([Event.t()]) :: [{term(), term(), pos_integer()}]
  defp definitions(events) do
    chrono = Enum.reverse(events)

    named =
      for %Event{id: id, body: {:prove_requested, name}} <- chrono,
          name != nil,
          into: %{},
          do: {id, name}

    Enum.flat_map(chrono, fn
      %Event{id: id, body: {:define, name, value}} ->
        [{name, value, id}]

      %Event{id: id, basedon: from, body: {:proved, report}} when is_map_key(named, from) ->
        [{named[from], report, id}]

      _event ->
        []
    end)
  end
end
