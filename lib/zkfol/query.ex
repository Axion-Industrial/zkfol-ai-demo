defmodule Zkfol.Query do
  @moduledoc """
  I am a query in flight: one process holding one stepping ask, handing
  out its answers one at a time.

  AL's search state is the continuation of the derivation and never
  leaves me: it stays behind messages, and only ground answers cross.
  I wear my own heap cap. A derivation that outgrows it kills me, and
  my caller reads the kill as a refusal.

  My handle carries my pid and my branch, so a caller can discard the
  branch even when the cap killed me before `terminate` could.

      {:ok, query} = Zkfol.Query.open(fib, [:_, :_], [])
      Zkfol.Query.next(query)    #=> {:ok, [1, 1]}
      Zkfol.Query.next(query)    #=> {:ok, [2, 1]}
      Zkfol.Query.close(query)

  ### Public API

  - `open/3`: fork a branch, install the question, hold the ask.
  - `next/1`: the next answer, the end of the search, or a refusal.
  - `taken/1`: every answer handed out so far, oldest first.
  - `statement/2`: answer `k` as a statement, ready to prove.
  - `close/1`: stop me and discard the branch.
  """

  use GenServer
  use TypedStruct

  alias Zkfol.Al
  alias Zkfol.Al.Ask
  alias Zkfol.Lang.Rel
  alias Zkfol.Statement
  alias Zkfol.Refusal

  @heap 256_000_000

  @typedoc "A query in flight: the process holding it, and the branch it runs on."
  typedstruct enforce: true do
    field(:pid, pid())
    field(:branch, AL.Branch.t())
  end

  ############################################################
  #                        Public API                        #
  ############################################################

  @doc """
  I open a query at `arguments`: the ask `Zkfol.Al.open/3` prepares,
  handed to a capped process of its own. Nothing derives until
  `next/1`, so the ask crosses without search state.

      {:ok, query} = open(Examples.EAl.tab(), [:_, :_], [])

  `arguments` read as `Zkfol.eval/3`'s do, `:_` free. `:heap` is the
  cap the query runs under, `:branch` what its branch forks from.
  """
  @spec open(Statement.t() | Rel.t() | [Rel.t()], [integer() | :_], keyword()) ::
          {:ok, t()} | {:error, Refusal.t()}
  def open(rels, arguments, opts) do
    with {:ok, ask} <- Al.open(rels, arguments, opts),
         {:ok, pid} <- GenServer.start(__MODULE__, {ask, opts}),
         do: {:ok, %__MODULE__{pid: pid, branch: ask.branch}}
  end

  @doc """
  I am the query's next answer: the argument list unified, the end of
  the search as `:exhausted`, or the refusal that stopped it. A cap
  that killed the query mid-search reads as a refusal too, and the
  query closes with it.
  """
  @spec next(t()) :: Ask.outcome()
  def next(%__MODULE__{pid: pid} = query) do
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

  @doc """
  I am answer `k` (1-based, the latest when unsaid) as a statement:
  the query's relations at that answer's arguments, ready for the
  prove-bound pipeline. An answer not yet taken I step forward to,
  and a search that ends before `k` answers nil.

      Zkfol.Query.statement(query, 10) |> Zkfol.compile()
  """
  @spec statement(t(), pos_integer() | :latest) :: Statement.t() | nil
  def statement(query, k \\ :latest)

  def statement(%__MODULE__{pid: pid}, k) do
    GenServer.call(pid, {:statement, k}, :infinity)
  catch
    :exit, _gone -> nil
  end

  @doc "I stop the query and discard its branch, however it ended."
  @spec close(t()) :: :ok
  def close(%__MODULE__{pid: pid, branch: branch}) do
    GenServer.stop(pid)
  catch
    :exit, _gone -> AL.Branch.discard(branch)
  end

  ############################################################
  #                    GenServer Callbacks                   #
  ############################################################

  @impl true
  def init({%Ask{} = ask, opts}) do
    Process.flag(:trap_exit, true)

    Process.flag(:max_heap_size, %{
      size: Keyword.get(opts, :heap, @heap),
      kill: true,
      error_logger: false
    })

    {:ok, {ask, []}}
  end

  @impl true
  def handle_call(:next, _from, {%Ask{} = ask, taken}) do
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
  def terminate(_reason, {%Ask{} = ask, _taken}), do: Al.close(ask)

  ############################################################
  #                   Private Implementation                 #
  ############################################################

  # statement(k) reaches for an answer not yet taken: step until it
  # exists or the search ends.
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
