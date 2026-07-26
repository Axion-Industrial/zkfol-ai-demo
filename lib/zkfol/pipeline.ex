defmodule Zkfol.Pipeline do
  @moduledoc """
  I am a pipeline as a value: my passes are data, the trace is a value.
  A pass is `{module, opts}`, the module taking a statement and its
  opts to the next statement or refusing with the reason. On a refusal
  I name the pass and keep the trace up to it. A pass's `plan/2` is
  its pure verdict on a statement, ahead of any act; `verdicts/3` asks
  those questions along a finished trace.
  """

  use TypedStruct

  alias Zkfol.Accumulator
  alias Zkfol.Doubling
  alias Zkfol.Refusal
  alias Zkfol.Statement
  alias Zkfol.Witness

  @doc "I take `statement` to the next statement, or refuse with the reason."
  @callback run(Statement.t(), keyword()) :: {:ok, Statement.t()} | {:error, Refusal.t()}

  @doc "I am my verdict on `statement` as it stands: a pure, cheap query, never an act."
  @callback plan(Statement.t(), keyword()) :: verdict()

  @typedoc "One member: the pass module and its options."
  @type pass :: {module(), keyword()}

  @typedoc "Each pass and the statement it produced, in order."
  @type trace :: [{module(), Statement.t()}]

  @typedoc """
  A pass's word on a statement: what it would do, with the delta where
  one earns it. Every pass declines a statement it is not for.
  """
  @type verdict ::
          :declines
          | :lowers
          | :rewrites
          | :solves
          | {:expands, Accumulator.layout()}
          | {:refuses, Refusal.t()}

  typedstruct enforce: true do
    field(:passes, [pass()])
  end

  @doc """
  I am the default route: lower the relations, try the doubling
  rewrite, derive the witness, and expand composed reads through the
  accumulator until zinc+ proves them natively.
  """
  @spec default() :: t()
  def default,
    do: %__MODULE__{
      passes: [{Zkfol.Lang, []}, {Doubling, []}, {Witness, []}, {Accumulator, []}]
    }

  @doc "I run `statement` through my passes, keeping every intermediate; `opts` ride under each pass's own."
  @spec run(t(), Statement.t(), keyword()) ::
          {:ok, Statement.t(), trace()} | {:error, module(), Refusal.t(), trace()}
  def run(%__MODULE__{passes: passes}, statement, opts \\ []) do
    Enum.reduce_while(passes, {statement, []}, fn {pass, own}, {current, trace} ->
      case pass.run(current, Keyword.merge(opts, own)) do
        {:ok, next} -> {:cont, {next, [{pass, next} | trace]}}
        {:error, reason} -> {:halt, {:error, pass, reason, Enum.reverse(trace)}}
      end
    end)
    |> case do
      {:error, _pass, _reason, _trace} = refusal -> refusal
      {final, trace} -> {:ok, final, Enum.reverse(trace)}
    end
  end

  @doc """
  I am the act's verdicts: the questions of `plan/2`, each put to the
  statement its pass actually received. Passes are pure, so asking
  again is observing. The caller journals me as `{:piped, verdicts}`,
  based on the event defining the route.
  """
  @spec verdicts(t(), Statement.t(), trace()) :: [{module(), verdict()}]
  def verdicts(%__MODULE__{passes: passes}, statement, trace) do
    stages = [statement | Enum.map(trace, &elem(&1, 1))]
    for {{pass, opts}, stage} <- Enum.zip(passes, stages), do: {pass, pass.plan(stage, opts)}
  end
end
