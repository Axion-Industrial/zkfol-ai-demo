defmodule Zkfol.Pipeline do
  @moduledoc """
  I am a pipeline as a value: my passes are data, the trace is a value.
  A pass is `{module, opts}`, the module taking a statement and its
  opts to the next statement or refusing with the reason. On a refusal
  I name the pass and keep the trace up to it. `verdicts/3` reads each
  pass's verdict off a finished trace: an unchanged statement was
  declined, a changed one earned the pass's verb.
  """

  use TypedStruct

  alias Zkfol.Doubling
  alias Zkfol.Refusal
  alias Zkfol.Statement
  alias Zkfol.Witness

  @doc "I take `statement` to the next statement, or refuse with the reason."
  @callback run(Statement.t(), keyword()) :: {:ok, Statement.t()} | {:error, Refusal.t()}

  @doc "I am the verb of my act: what a run of mine that changed the statement did."
  @callback verb() :: verdict()

  @typedoc "One member: the pass module and its options."
  @type pass :: {module(), keyword()}

  @typedoc "Each pass and the statement it produced, in order."
  @type trace :: [{module(), Statement.t()}]

  @typedoc "What a run came to: the final statement or the erring pass, the trace either way."
  @type outcome ::
          {:ok, Statement.t(), trace()} | {:error, module(), Refusal.t(), trace()}

  @typedoc """
  A pass's word on a statement it ran: every pass declines a
  statement it is not for.
  """
  @type verdict :: :declines | :lowers | :rewrites | :solves | {:errors, Refusal.t()}

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

  @doc """
  I run `statement` through my passes, keeping every intermediate;
  `opts` ride under each pass's own. The statement enters carrying its
  whole program: relations its roots reach gather from their homes.
  """
  @spec run(t(), Statement.t(), keyword()) :: outcome()
  def run(%__MODULE__{passes: passes}, statement, opts \\ []) do
    statement = %{statement | rels: Zkfol.Lang.gathered(statement.rels)}

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
  I am the act's verdicts, read off its trace: a pass that returned
  its input declined it, one that changed it did what its verb names,
  and for a pass that erred, the run's own refusal as
  `{:errors, refusal}`. The caller journals me as `{:piped, verdicts}`,
  based on the event defining the route.
  """
  @spec verdicts(t(), Statement.t(), outcome()) :: [{module(), verdict()}]
  def verdicts(%__MODULE__{passes: passes}, statement, {:ok, _final, trace}),
    do: observed(passes, statement, trace)

  def verdicts(%__MODULE__{passes: passes}, statement, {:error, pass, reason, trace}),
    do: observed(passes, statement, trace) ++ [{pass, {:errors, reason}}]

  # The verdicts of the passes the trace shows ran: declined where the
  # statement rode through unchanged, the verb where it changed.
  @spec observed([pass()], Statement.t(), trace()) :: [{module(), verdict()}]
  defp observed(passes, statement, trace) do
    stages = [statement | Enum.map(trace, &elem(&1, 1))]

    for {{pass, _opts}, [input, output]} <-
          Enum.zip(passes, Enum.chunk_every(stages, 2, 1, :discard)),
        do: {pass, if(output == input, do: :declines, else: pass.verb())}
  end
end
