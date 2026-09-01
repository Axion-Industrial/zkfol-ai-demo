defmodule Zkfol do
  @moduledoc """
  I am the language's front door: one call takes a statement through a route to a proof,
  journalled, and returns the receipt.
  """

  alias Zkfol.Lang
  alias Zkfol.Log
  alias Zkfol.Pipeline
  alias Zkfol.Prover
  alias Zkfol.Query
  alias Zkfol.Refusal
  alias Zkfol.Statement
  alias Zkfol.Uair

  @typedoc "What a door takes: a statement, a root relation, or the relations in scope."
  @type target :: Statement.t() | Lang.Rel.t() | [Lang.Rel.t()]

  @doc "I am the whole act: define, run, verdicts, prove, receipt."
  @spec compile(target(), keyword()) :: Log.Ran.t()
  def compile(target, opts \\ []), do: taken(target, opts, &proved/2)

  @doc "I am the act up to emit: define, run, verdicts, emit, a receipt with no proof."
  @spec emit(target(), keyword()) :: Log.Ran.t()
  def emit(target, opts \\ []), do: taken(target, opts, &emitted/2)

  @spec taken(target(), keyword(), (Statement.t(), keyword() -> term())) :: Log.Ran.t()
  defp taken(target, opts, settle) do
    {args, opts} = Keyword.pop(opts, :args, [])
    acted(Statement.of(target, args: args), opts, settle)
  end

  @doc """
  I am the query door: no route, no proof, the relation run as AL
  runs it. Arguments bind in order, `:_` free: bound arguments enter
  the derivation's goal and select it, holes fill from the
  derivation, and the answer is the argument list unified. A free
  index searches upward, so the least index satisfying the bindings
  answers; a binding nothing derives refuses as the false statement
  it is.

  The answer comes as the query holding it: the first is already
  taken, `Zkfol.Query.next/1` steps to the rest, `taken/1` lists what
  crossed, `close/1` ends it. A binding nothing derives closes itself
  and refuses.

      {:ok, query} = Zkfol.eval(fib, [8, :_], [])
      Zkfol.Query.taken(query)  #=> [[8, 21]]

  `opts` ride through to `Zkfol.Query.open/3`; `:heap` bounds the
  derivation.
  """
  @spec eval(Lang.Rel.t() | [Lang.Rel.t()] | Statement.t(), [Statement.datum() | :_], keyword()) ::
          {:ok, Query.t()} | {:error, Refusal.t()}
  def eval(rels, arguments, opts \\ []) do
    with {:ok, query} <- Query.open(rels, arguments, opts) do
      case Query.next(query) do
        {:ok, _answer} ->
          {:ok, query}

        :exhausted ->
          Query.close(query)
          {:error, {:no_answer, %{}}}

        {:error, reason} ->
          Query.close(query)
          {:error, reason}
      end
    end
  end

  @doc """
  I am `eval/3` for a hand at the keyboard: the query itself, no tuple
  to unwrap, and a refusal raised with its own message.

      Zkfol.eval!(fib, [8, :_], [])   #=> %Zkfol.Query{}
  """
  @spec eval!(Lang.Rel.t() | [Lang.Rel.t()] | Statement.t(), [Statement.datum() | :_], keyword()) ::
          Query.t()
  def eval!(rels, arguments, opts \\ []) do
    case eval(rels, arguments, opts) do
      {:ok, query} -> query
      {:error, reason} -> raise Refusal.message(reason)
    end
  end

  @doc """
  I am every answer at `arguments`, lazily: a `Zkfol.Query` opened when
  the stream is first taken from, stepped once per element, and closed
  when it ends. Answers come in the clauses' own order.

      Zkfol.stream(fib, [:_, :_], []) |> Enum.take(2)  #=> [[1, 1], [2, 1]]

  The stream is answers and nothing else, so a refusal ends it as
  exhaustion does; `Zkfol.Query.next/1` is the door that says which.
  `opts` ride through to `Zkfol.Query.open/3`.
  """
  @spec stream(Lang.Rel.t() | [Lang.Rel.t()], [Statement.datum() | :_], keyword()) ::
          Enumerable.t()
  def stream(rels, arguments, opts \\ []) do
    Stream.resource(
      fn -> Query.open(rels, arguments, opts) end,
      fn
        {:ok, query} = opened ->
          case Query.next(query) do
            {:ok, answer} -> {[answer], opened}
            _ended -> {:halt, opened}
          end

        {:error, _reason} = refusal ->
          {:halt, refusal}
      end,
      fn
        {:ok, query} -> Query.close(query)
        {:error, _reason} -> :ok
      end
    )
  end

  # The act itself, up to whatever settles it: the two entry points
  # differ only in that last step.
  @spec acted(
          Statement.t(),
          keyword(),
          (Statement.t(), keyword() -> {:ok, pos_integer() | nil} | {:error, Refusal.t()})
        ) :: Log.Ran.t()
  defp acted(statement, opts, settle) do
    {pipeline, opts} = Keyword.pop(opts, :pipeline, Pipeline.default())
    {name, opts} = Keyword.pop_lazy(opts, :name, fn -> named(statement) end)
    {public, opts} = Keyword.pop(opts, :public, [])
    define = Log.push({:define, name, pipeline, public, statement})

    outcome = Pipeline.run(pipeline, statement, basedon: define)
    piped = Log.push({:piped, Pipeline.verdicts(pipeline, statement, outcome)}, define)

    settled =
      with {:ok, final, _trace} <- outcome,
           {:ok, opened} <- Statement.opened(final, public),
           do: settle.(opened, Keyword.merge(opts, name: name, basedon: piped))

    with {:error, refusal} <- settled, do: Log.push({:refused, refusal}, piped)

    %Log.Ran{defined: define}
  end

  @spec proved(Statement.t(), keyword()) :: {:ok, pos_integer()} | {:error, Refusal.t()}
  defp proved(final, opts) do
    prove = Keyword.put(opts, :claims, Statement.claims(final))

    with {:ok, _report, intent} <-
           Prover.prove(Statement.pred(final), Statement.witness(final), prove),
         do: {:ok, intent}
  end

  @spec emitted(Statement.t(), keyword()) :: {:ok, nil} | {:error, Refusal.t()}
  defp emitted(final, _opts) do
    with {:ok, _uair} <- Uair.emit(Statement.pred(final), Statement.witness(final)),
         do: {:ok, nil}
  end

  # A root relation lends the act its name.
  @spec named(Statement.t()) :: atom()
  defp named(%Statement{rels: [root | _rest]}), do: root.name
  defp named(_statement), do: :statement
end
