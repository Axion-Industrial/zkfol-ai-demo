defmodule Zkfol.Harness.Run do
  @moduledoc """
  I am one agent run's state: the folder it may read, the allowlist its actions are checked
  against, the events that have happened so far, and what it has read and tried.

  `events` holds only what happened. An action the gate blocked is in `attempts`, not in
  `events`, since it never ran.

  ### Public API

  - `new/2` starts a run over a folder and an allowlist.
  - `documents/1` is the folder's files, in the order that numbers them.
  """

  use TypedStruct

  alias Zkfol.Harness.Allowlist
  alias Zkfol.Harness.Context
  alias Zkfol.Harness.Trace.Event

  typedstruct module: Attempt, enforce: true do
    @typedoc "An action the agent tried: what it asked for, and whether the gate let it run."
    field(:tool, String.t())
    field(:input, map())
    field(:events, [Zkfol.Harness.Trace.Event.t()])
    field(:verdict, :sent | :blocked)
    field(:detail, String.t())
  end

  typedstruct enforce: true do
    field(:docs, Path.t())
    field(:out, Path.t())
    field(:allowlist, Allowlist.t())
    field(:context, Context.t() | nil, default: nil)
    field(:events, [Event.t()], default: [])
    field(:reads, %{String.t() => String.t()}, default: %{})
    field(:attempts, [Attempt.t()], default: [])
    field(:actions, non_neg_integer(), default: 0)
  end

  @doc "I start a run over the folder `docs`, writing proofs under `out`."
  @spec new(Path.t(), Path.t()) :: {:ok, t()} | {:error, Zkfol.Refusal.t()}
  def new(docs, out) do
    File.mkdir_p!(out)

    with {:ok, allowlist} <- Allowlist.load(),
         do: {:ok, %__MODULE__{docs: docs, out: out, allowlist: allowlist}}
  end

  @doc "I am the folder's files in sorted order: a file's place in it, from 1, is its document number."
  @spec documents(t()) :: [String.t()]
  def documents(%__MODULE__{docs: docs}) do
    docs
    |> File.ls!()
    |> Enum.sort()
    |> Enum.filter(&regular?(Path.join(docs, &1)))
    |> Enum.take(8)
  end

  @spec regular?(Path.t()) :: boolean()
  defp regular?(path), do: match?({:ok, %File.Stat{type: :regular}}, File.lstat(path))
end
