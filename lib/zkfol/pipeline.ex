defmodule Zkfol.Pipeline do
  @moduledoc """
  I am a pipeline as a value: my passes are data, the trace is a value.
  A pass is `{module, opts}`, the module taking a statement and its
  opts to the next statement or refusing with the reason. On a refusal
  I name the pass and keep the trace up to it.

  ### Public API

  - `run/2`, `default/0`
  """

  use TypedStruct

  alias Zkfol.Doubling
  alias Zkfol.Statement

  @doc "I take `statement` to the next statement, or refuse with the reason."
  @callback run(Statement.t(), keyword()) :: {:ok, Statement.t()} | {:error, String.t()}

  @typedoc "One member: the pass module and its options."
  @type pass :: {module(), keyword()}

  @typedoc "Each pass and the statement it produced, in order."
  @type trace :: [{module(), Statement.t()}]

  typedstruct enforce: true do
    field(:passes, [pass()])
  end

  @doc "I am the default route: try the doubling rewrite."
  @spec default() :: t()
  def default, do: %__MODULE__{passes: [{Doubling, []}]}

  @doc "I run `statement` through my passes, keeping every intermediate."
  @spec run(t(), Statement.t()) ::
          {:ok, Statement.t(), trace()} | {:error, module(), String.t(), trace()}
  def run(%__MODULE__{passes: passes}, statement) do
    Enum.reduce_while(passes, {statement, []}, fn {pass, opts}, {current, trace} ->
      case pass.run(current, opts) do
        {:ok, next} -> {:cont, {next, [{pass, next} | trace]}}
        {:error, reason} -> {:halt, {:error, pass, reason, Enum.reverse(trace)}}
      end
    end)
    |> case do
      {:error, _pass, _reason, _trace} = refusal -> refusal
      {final, trace} -> {:ok, final, Enum.reverse(trace)}
    end
  end
end
