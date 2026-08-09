defmodule Zkfol.Prover do
  @moduledoc """
  I own the proving conversation: the one actor the NIF answers to,
  and the protocol callers speak to it. `prove/3` emits and proves;
  `prove_uair/2` journals an intent, queues the UAIR, and waits on
  the log for the verdict that settles it. When a verdict lands I
  record it as the intent's observation; waiters hear of it through
  the log, not from me.
  """

  use GenServer
  use EventBroker.DefFilter
  use TypedStruct

  alias Zkfol.Ast
  alias Zkfol.Interpretation
  alias Zkfol.Log
  alias Zkfol.Refusal
  alias Zkfol.Uair
  alias Zkfol.ZincPlus

  # I match the log event that settles `intent`: its observation.
  deffilter Settled, intent: pos_integer() do
    %EventBroker.Event{body: %Zkfol.Log.Event{basedon: ^intent}} -> true
    _ -> false
  end

  typedstruct module: Report, enforce: true do
    @moduledoc """
    I am the verdict as a value: the NIF's measurements and the claims
    the verifier read in the clear. I ride the log as the body of a
    `{:proved, report}` observation, and I exist only where the proof
    verified — a run that did not leaves `{:prove_failed, reason}`
    instead, so my existence is the verdict and no field restates it.
    """
    field(:prove_ms, float())
    field(:verify_ms, float())
    field(:num_vars, non_neg_integer())
    field(:public_cols, non_neg_integer())
    field(:proof_bytes, non_neg_integer())
    field(:backend, String.t())
    field(:claims, [{String.t(), non_neg_integer()}])
  end

  @spec start_link(term()) :: GenServer.on_start()
  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @doc """
  I prove `pred` against `witness` and journal it: an intent, then the
  report observed, a `Report`. `opts` takes `:name`, `:basedon`,
  `:claims`. I return `{:ok, report, id}`.
  """
  @spec prove(Ast.pred(), Interpretation.t(), keyword()) ::
          {:ok, Report.t(), pos_integer()} | {:error, Refusal.t()}
  def prove(pred, witness, opts \\ []) do
    with {:ok, uair} <- Uair.emit(pred, witness, Keyword.get(opts, :claims, [])) do
      prove_uair(uair, opts)
    end
  end

  @doc """
  I prove an already-emitted `uair`, journaling it and awaiting it
  through the log. `opts` takes `:name`, `:basedon`, and `:timeout`
  (milliseconds or `:infinity`, one minute by default).
  """
  @spec prove_uair(Uair.t(), keyword()) ::
          {:ok, Report.t(), pos_integer()} | {:error, Refusal.t()}
  def prove_uair(uair, opts \\ []) do
    id = Log.push({:prove_requested, Keyword.get(opts, :name)}, Keyword.get(opts, :basedon))
    filter = [%Settled{intent: id}]
    EventBroker.subscribe_me(filter)

    try do
      with :ok <- run(uair, id, opts),
           do: settled(id, Keyword.get(opts, :timeout, 60_000))
    after
      EventBroker.unsubscribe_me(filter)
      drained(id)
    end
  end

  # I wait on the log for the observation that settles intent `id`;
  # only that intent, so a verdict lingering from an abandoned wait
  # can never be heard as this one.
  @spec settled(pos_integer(), timeout()) ::
          {:ok, Report.t(), pos_integer()} | {:error, Refusal.t()}
  defp settled(id, timeout) do
    receive do
      %EventBroker.Event{body: %Log.Event{basedon: ^id, body: {:proved, report}}} ->
        {:ok, report, id}

      %EventBroker.Event{body: %Log.Event{basedon: ^id, body: {:prove_failed, reason}}} ->
        {:error, reason}
    after
      timeout -> {:error, {:prover_timeout, %{intent: id}}}
    end
  end

  # Whatever the subscription delivered and nobody consumed, drop.
  @spec drained(pos_integer()) :: :ok
  defp drained(id) do
    receive do
      %EventBroker.Event{body: %Log.Event{basedon: ^id}} -> drained(id)
    after
      0 -> :ok
    end
  end

  # Queue the uair under its intent, returning once it is in flight.
  @spec run(Uair.t(), pos_integer(), keyword()) :: :ok | {:error, Refusal.t()}
  defp run(uair, intent, opts), do: GenServer.call(__MODULE__, {:run, uair, intent, opts})

  @impl true
  def init(inflight) do
    # Trapping exits makes terminate/2 run on the way down: verdicts
    # owed at death still settle on the log, as failures.
    Process.flag(:trap_exit, true)
    {:ok, inflight}
  end

  @impl true
  def handle_call({:run, uair, intent, opts}, _from, inflight) do
    case ZincPlus.request(uair, opts) do
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
          {:ok, report} ->
            Log.push({:proved, struct!(Report, Map.put(report, :claims, claims))}, intent)

          {:error, reason} ->
            Log.push({:prove_failed, Refusal.from_backend(reason)}, intent)
        end

        {:noreply, inflight}
    end
  end

  @impl true
  def terminate(_reason, inflight) do
    for {_req, {intent, _claims}} <- inflight do
      Log.push({:prove_failed, {:prover_died, %{}}}, intent)
    end
  end
end
