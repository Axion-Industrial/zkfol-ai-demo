defmodule Zkfol.Prover do
  @moduledoc """
  I own the Zinc+ boundary: the one actor the NIF answers to. I queue a
  proof, and when the verdict lands I record it on the log as the
  intent's observation. Waiters hear of it through the log, not from me.

  ### Public API

  - `run/2`, `Settled`
  """

  use GenServer
  use EventBroker.DefFilter

  alias Zkfol.Log
  alias Zkfol.Uair

  # I match the log event that settles `intent`: its observation.
  deffilter Settled, intent: pos_integer() do
    %EventBroker.Event{body: %Zkfol.Log.Event{basedon: ^intent}} -> true
    _ -> false
  end

  @spec start_link(term()) :: GenServer.on_start()
  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @doc "I queue `uair` under `intent` and return once it is in flight."
  @spec run(map(), pos_integer()) :: :ok | {:error, String.t()}
  def run(uair, intent), do: GenServer.call(__MODULE__, {:run, uair, intent})

  @impl true
  def init(inflight) do
    # Trapping exits makes terminate/2 run on the way down: verdicts
    # owed at death still settle on the log, as failures.
    Process.flag(:trap_exit, true)
    {:ok, inflight}
  end

  @impl true
  def handle_call({:run, uair, intent}, _from, inflight) do
    case Uair.request(uair) do
      {:ok, req} -> {:reply, :ok, Map.put(inflight, req, {intent, uair.claims})}
      {:error, _reason} = error -> {:reply, error, inflight}
    end
  end

  @impl true
  def handle_info({:zinc_plus, req, result}, inflight) do
    case Map.pop(inflight, req) do
      {nil, inflight} ->
        {:noreply, inflight}

      {{intent, claims}, inflight} ->
        case result do
          {:ok, report} -> Log.push({:proved, Map.put(report, :claims, claims)}, intent)
          {:error, reason} -> Log.push({:prove_failed, reason}, intent)
        end

        {:noreply, inflight}
    end
  end

  @impl true
  def terminate(_reason, inflight) do
    for {_req, {intent, _claims}} <- inflight do
      Log.push({:prove_failed, "the prover died before the verdict"}, intent)
    end
  end
end
