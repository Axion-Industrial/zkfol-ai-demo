defmodule Zkfol.Log do
  @moduledoc """
  I am the command log: the only essential state of the system.

  Following Schueler's Update Reconsidered, events are immutable and
  union is the only operation on them: `push/3` appends, nothing
  rewrites. Every other datum in the system is derived, an image of
  some prefix of me, and is recomputed, never stored.

  ### Public API

  - `new/0`, `push/3`
  - `image/1`, `image_down/2`
  """

  use TypedStruct

  typedstruct module: Event, enforce: true do
    @moduledoc "I am one immutable event: what was furnished, based on which image."

    field(:id, non_neg_integer())
    field(:basedon, non_neg_integer() | nil)
    field(:body, term())
  end

  typedstruct do
    field(:events, [Event.t()], default: [])
  end

  @doc "I am the empty log."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  I append an event and return the grown log. `basedon` names the event id
  whose image the caller was looking at; I never inspect it.
  """
  @spec push(t(), term(), non_neg_integer() | nil) :: t()
  def push(%__MODULE__{events: events} = log, body, basedon \\ nil) do
    event = %Event{id: length(events) + 1, basedon: basedon, body: body}
    %{log | events: [event | events]}
  end

  @doc "I am the current surface: each name mapped to its latest definition."
  @spec image(t()) :: %{term() => term()}
  def image(%__MODULE__{events: events}), do: surface(events)

  @doc "I am the surface as it stood just after event `id`: the lifeline, navigable."
  @spec image_down(t(), non_neg_integer()) :: %{term() => term()}
  def image_down(%__MODULE__{events: events}, id) do
    events |> Enum.drop_while(&(&1.id > id)) |> surface()
  end

  @spec surface([Event.t()]) :: %{term() => term()}
  defp surface(events) do
    for %Event{body: {:define, name, value}} <- Enum.reverse(events), into: %{} do
      {name, value}
    end
  end
end
