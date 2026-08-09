defmodule Zkfol do
  @moduledoc """
  I am the language's front door: one call takes a statement through a
  route to a proof and returns the receipt. I journal the route as its
  define first, run the passes with that id threaded through their
  opts so the derivations land on the trail, journal the verdicts, and
  prove the result under the statement's claims. The `Zkfol.Log.Ran` I
  return replays the whole act, its report riding the trail's proved
  event; a pass that errs leaves its refusal among the piped verdicts,
  and the receipt still walks the trail. `opts` takes `:pipeline` and
  `:name`; the rest ride through to the prover.

      ran = Zkfol.compile(%Zkfol.Statement{rels: [fib], args: [100]})
      Zkfol.Log.report(Zkfol.Log.snapshot(), ran).prove_ms

  I stop one step short in `emit/2`: the same act to the emitted UAIR,
  no proof, a receipt whose trail just ends at the verdicts.

      ran = Zkfol.emit(%Zkfol.Statement{rels: [fib], args: [100]})
      Zkfol.Log.trail(Zkfol.Log.snapshot(), ran)
  """

  alias Zkfol.Al
  alias Zkfol.Interpretation
  alias Zkfol.Lang
  alias Zkfol.Log
  alias Zkfol.Pipeline
  alias Zkfol.Prover
  alias Zkfol.Query
  alias Zkfol.Refusal
  alias Zkfol.Statement
  alias Zkfol.Uair

  @doc "I am the whole act: define, run, verdicts, prove, receipt."
  @spec compile(Statement.t(), keyword()) :: Log.Ran.t()
  def compile(%Statement{} = statement, opts \\ []), do: acted(statement, opts, &proved/2)

  @doc "I am the act up to emit: define, run, verdicts, emit, a receipt with no proof."
  @spec emit(Statement.t(), keyword()) :: Log.Ran.t()
  def emit(%Statement{} = statement, opts \\ []), do: acted(statement, opts, &emitted/2)

  @doc """
  I am the query door: no route, no proof, the relation run as AL
  runs it. Arguments bind in order, `:_` free: bound arguments enter
  the derivation's goal and select it, holes fill from the
  derivation, and the answer is the argument list unified. A free
  index searches upward, so the least index satisfying the bindings
  answers; a binding nothing derives refuses as the false statement
  it is.

      Zkfol.eval(fib, [8, :_], [])   #=> {:ok, [8, 21]}
      Zkfol.eval(fib, [:_, 21], [])  #=> {:ok, [8, 21]}

  `opts` ride through to `Zkfol.Al.solve/3`; `:heap` bounds the
  derivation.
  """
  @spec eval(Lang.Rel.t() | [Lang.Rel.t()] | Statement.t(), [integer() | :_], keyword()) ::
          {:ok, [integer()]} | {:error, Refusal.t()}
  def eval(rels, arguments, opts \\ []) do
    with {:ok, witness} <- Al.solve(rels, arguments, opts),
         do: {:ok, answer(witness, arguments)}
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
  @spec stream(Lang.Rel.t() | [Lang.Rel.t()], [integer() | :_], keyword()) :: Enumerable.t()
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

  # Argument i is row i at the derivation's last column; the
  # derivation already satisfied every bound argument, so only the
  # holes read.
  @spec answer(Interpretation.t(), [integer() | :_]) :: [integer()]
  defp answer(%Interpretation{} = witness, arguments) do
    col = Interpretation.len(witness)

    for {argument, row} <- Enum.with_index(arguments, 1),
        do: if(argument == :_, do: Interpretation.at(witness, row, col), else: argument)
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
    define = Log.push({:define, name, pipeline})

    outcome = Pipeline.run(pipeline, statement, basedon: define)
    piped = Log.push({:piped, Pipeline.verdicts(pipeline, statement, outcome)}, define)

    # Whatever settles, settles onto the trail; the receipt is the same.
    with {:ok, final, _trace} <- outcome,
         do: settle.(final, Keyword.merge(opts, name: name, basedon: piped))

    %Log.Ran{pipeline: pipeline, source: statement, defined: define}
  end

  @spec proved(Statement.t(), keyword()) :: {:ok, pos_integer()} | {:error, Refusal.t()}
  defp proved(final, opts) do
    prove = Keyword.put(opts, :claims, final.claims)

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
