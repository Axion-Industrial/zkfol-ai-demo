defmodule Zkfol.Log.Run do
  @moduledoc """
  I recount runs of expressions through the compiler.

  In particular, I work through our journaling system to retrieve
  these logs.
  """

  use TypedStruct

  alias Zkfol.Log
  alias Zkfol.Log.Event
  alias Zkfol.Refusal
  alias Zkfol.Statement

  typedstruct enforce: true do
    field(:defined, pos_integer())
  end

  @doc "I take a ran id and return the defining moment or nil if it does not exist"
  @spec at(Log.t(), pos_integer()) :: t() | nil
  def at(log, defined) do
    case Log.body(log, defined) do
      {:define, _, _, _, %Log.Args{}} -> %__MODULE__{defined: defined}
      _ -> nil
    end
  end

  @doc "I run the given event and give back the resultant run."
  @spec replay(t()) :: t()
  def replay(%__MODULE__{defined: defined}) do
    {:define, name, pipeline, public, %Log.Args{} = args} = Log.define(defined)
    route = [name: name, pipeline: pipeline, public: public]
    apply(Zkfol, args.entry, [args.statement, route ++ args.opts])
  end

  @doc "Given a run, we skip the first `k` events."
  @spec stage(t(), non_neg_integer()) :: {:ok, Statement.t()} | {:error, Refusal.t()}
  def stage(%__MODULE__{defined: defined}, k), do: staged(Log.define(defined), k)

  @doc "I am the act's final statement, re-run and opened as the act opened it; nil if refused."
  @spec final_stage(t()) :: Statement.t() | nil
  def final_stage(%__MODULE__{defined: defined}) do
    {:define, _name, pipeline, public, _args} = define = Log.define(defined)

    with {:ok, statement} <- staged(define, length(pipeline.passes)),
         {:ok, opened} <- Statement.opened(statement, public) do
      opened
    else
      _refused -> nil
    end
  end

  @spec staged(Event.define(), non_neg_integer()) :: {:ok, Statement.t()} | {:error, Refusal.t()}
  defp staged({:define, _name, pipeline, _public, %Log.Args{statement: source}}, k) do
    shortened = %Zkfol.Pipeline{passes: Enum.take(pipeline.passes, k)}

    case Zkfol.Pipeline.run(shortened, source) do
      {:ok, statement, _trace} -> {:ok, statement}
      {:error, _pass, reason, _trace} -> {:error, reason}
    end
  end
end
