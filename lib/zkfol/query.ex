defmodule Zkfol.Query do
  @moduledoc """
  I am a query in flight: one heap-capped process holding one stepping ask, handing out
  its answers one at a time.

  ### Public API

  - `open/3`: install the question on its branch, hold the ask.
  - `next/1`: the next answer, the end of the search, or a refusal.
  - `taken/1`: every answer handed out so far, oldest first.
  - `statement/2`: answer `k` as a statement, ready to prove.
  - `close/1`: stop me and retract what I posted.
  """

  use GenServer
  use TypedStruct

  alias Zkfol.Al
  alias Zkfol.Al.Ask
  alias Zkfol.Lang.Rel
  alias Zkfol.Statement
  alias Zkfol.Refusal

  @typedoc "A query in flight: the process holding it, and the ask it holds, unstepped."
  typedstruct enforce: true do
    field(:pid, pid())
    field(:ask, Ask.t())
  end

  ############################################################
  #                        Public API                        #
  ############################################################

  @doc "I open a query at `arguments`, `:_` free; `opts` takes `:heap` and `:branch`."
  @spec open(Statement.t() | Rel.t() | [Rel.t()], [Zkfol.Statement.datum() | :_], keyword()) ::
          {:ok, t()} | {:error, Refusal.t()}
  def open(rels, arguments, opts) do
    with {:ok, ask} <- Al.open(rels, arguments, opts),
         {:ok, pid} <- GenServer.start(__MODULE__, ask) do
      {:ok, %__MODULE__{pid: pid, ask: ask}}
    end
  end

  @doc "I am the query's next answer, `:exhausted`, or the refusal that stopped it."
  @spec next(t()) :: Ask.outcome()
  def next(query = %__MODULE__{pid: pid}) do
    GenServer.call(pid, :next, :infinity)
  catch
    :exit, _killed ->
      close(query)
      {:error, {:heap_exhausted, %{said: "the query exceeded its heap"}}}
  end

  @doc "I am every answer this query has handed out, oldest first."
  @spec taken(t()) :: [Ask.answer()]
  def taken(%__MODULE__{pid: pid}) do
    GenServer.call(pid, :taken, :infinity)
  catch
    :exit, _gone -> []
  end

  @doc "I am answer `k` (the latest when unsaid) as a statement, nil when the search ends first."
  @spec statement(t(), pos_integer() | :latest) :: Statement.t() | nil
  def statement(query, k \\ :latest)

  def statement(%__MODULE__{pid: pid}, k) do
    GenServer.call(pid, {:statement, k}, :infinity)
  catch
    :exit, _gone -> nil
  end

  @doc "I stop the query and retract what it posted, however it ended."
  @spec close(t()) :: :ok | {:error, Refusal.t()}
  def close(%__MODULE__{pid: pid, ask: ask}) do
    GenServer.stop(pid)
  catch
    :exit, _gone -> Al.close(ask)
  end

  ############################################################
  #                    GenServer Callbacks                   #
  ############################################################

  @impl true
  def init(ask = %Ask{}) do
    Process.flag(:trap_exit, true)
    Process.flag(:max_heap_size, %{size: ask.heap, kill: true, error_logger: false})
    {:ok, {ask, []}}
  end

  @impl true
  def handle_call(:next, _from, {ask = %Ask{}, taken}) do
    {outcome, ask} = Al.step(ask)

    case outcome do
      {:ok, answer} -> {:reply, outcome, {ask, [answer | taken]}}
      _no_answer -> {:reply, outcome, {ask, taken}}
    end
  end

  def handle_call(:taken, _from, {ask, taken}), do: {:reply, Enum.reverse(taken), {ask, taken}}

  def handle_call({:statement, k}, _from, {ask, taken}) do
    {ask, taken} = advanced(ask, taken, k)
    {:reply, do_statement(ask, Enum.reverse(taken), k), {ask, taken}}
  end

  @impl true
  def terminate(_reason, {ask = %Ask{}, _taken}), do: Al.close(ask)

  ############################################################
  #                   Private Implementation                 #
  ############################################################

  @spec advanced(Ask.t(), [Ask.answer()], pos_integer() | :latest) ::
          {Ask.t(), [Ask.answer()]}
  defp advanced(ask, taken, k) when k == :latest or length(taken) >= k, do: {ask, taken}

  defp advanced(ask, taken, k) do
    case Al.step(ask) do
      {{:ok, answer}, ask} -> advanced(ask, [answer | taken], k)
      {_ended, ask} -> {ask, taken}
    end
  end

  @spec do_statement(Ask.t(), [Ask.answer()], pos_integer() | :latest) :: Statement.t() | nil
  defp do_statement(ask, answers, :latest), do: do_statement(ask, answers, length(answers))

  defp do_statement(%Ask{rels: rels}, answers, k) do
    case Enum.at(answers, k - 1) do
      nil -> nil
      answer -> %Statement{rels: rels, args: answer}
    end
  end
end
