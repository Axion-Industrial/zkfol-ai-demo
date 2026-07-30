defmodule Zkfol.Pipeline do
  @moduledoc """
  I am a pipeline as a value: my passes are data, the trace is a value.
  A pass is `{module, opts}`, the module taking a statement and its
  opts to the next statement or refusing with the reason. On a refusal
  I name the pass and keep the trace up to it. `plan/2` asks every
  pass, purely and ahead of any act, what it would do; `verdicts/3`
  asks the same questions along a finished trace, one vocabulary for
  the predicted and the observed.
  """

  use TypedStruct

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
          | {:refuses, Refusal.t()}

  typedstruct enforce: true do
    field(:passes, [pass()])
  end

  @doc """
  I am the default route: lower the relations, try the doubling
  rewrite, and derive the witness. Composed reads emit as they are;
  zinc+'s pointer query proves them natively.
  """
  @spec default() :: t()
  def default,
    do: %__MODULE__{passes: [{Zkfol.Lang, []}, {Doubling, []}, {Witness, []}]}

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
  I am the route asked ahead of the run: every pass's verdict on
  `statement` as it stands, the potential trace as data.

      Pipeline.plan(Pipeline.default(), statement)
  """
  @spec plan(t(), Statement.t()) :: [{module(), verdict()}]
  def plan(%__MODULE__{passes: passes}, statement),
    do: for({pass, opts} <- passes, do: {pass, pass.plan(statement, opts)})

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
