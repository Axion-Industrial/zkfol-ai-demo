defmodule Zkfol do
  @moduledoc """
  I am the language's front door: one call takes a statement through a
  route to a proof and returns the receipt. I journal the route as its
  define first, run the passes with that id threaded through their
  opts so the derivations land on the trail, journal the verdicts, and
  prove the result under the statement's claims. The `Zkfol.Log.Ran` I
  return replays the whole act, its report riding the trail's proved
  event; a refusal at any stage is a value naming the stage. `opts`
  takes `:pipeline` and `:name`; the rest ride through to the prover.

      ran = Zkfol.compile(%Zkfol.Statement{rels: [fib], args: [100]})
      Zkfol.Log.report(Zkfol.Log.snapshot(), ran).prove_ms

  I stop one step short in `emit/2`: the same act to the emitted UAIR,
  no proof, a receipt whose trail just ends at the verdicts.

      ran = Zkfol.emit(%Zkfol.Statement{rels: [fib], args: [100]})
      Zkfol.Log.trail(Zkfol.Log.snapshot(), ran)
  """

  alias Zkfol.Log
  alias Zkfol.Pipeline
  alias Zkfol.Prover
  alias Zkfol.Refusal
  alias Zkfol.Statement
  alias Zkfol.Uair

  @doc "I am the whole act: define, run, verdicts, prove, receipt."
  @spec compile(Statement.t(), keyword()) :: Log.Ran.t() | {:error, Refusal.t()}
  def compile(%Statement{} = statement, opts \\ []), do: acted(statement, opts, &proved/2)

  @doc "I am the act up to emit: define, run, verdicts, emit, a receipt with no proof."
  @spec emit(Statement.t(), keyword()) :: Log.Ran.t() | {:error, Refusal.t()}
  def emit(%Statement{} = statement, opts \\ []), do: acted(statement, opts, &emitted/2)

  # The act itself, up to whatever settles it: the two entry points
  # differ only in that last step.
  @spec acted(
          Statement.t(),
          keyword(),
          (Statement.t(), keyword() -> {:ok, pos_integer() | nil} | {:error, Refusal.t()})
        ) :: Log.Ran.t() | {:error, Refusal.t()}
  defp acted(statement, opts, settle) do
    {pipeline, opts} = Keyword.pop(opts, :pipeline, Pipeline.default())
    {name, opts} = Keyword.pop_lazy(opts, :name, fn -> named(statement) end)
    define = Log.push({:define, name, pipeline})

    with {:ok, final, trace} <- Pipeline.run(pipeline, statement, basedon: define),
         piped = Log.push({:piped, Pipeline.verdicts(pipeline, statement, trace)}, define),
         {:ok, _settled} <- settle.(final, Keyword.merge(opts, name: name, basedon: piped)) do
      %Log.Ran{pipeline: pipeline, source: statement, defined: define}
    else
      {:error, pass, reason, _trace} -> {:error, Refusal.by(reason, pass)}
      {:error, reason} -> {:error, Refusal.by(reason, Prover)}
    end
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
