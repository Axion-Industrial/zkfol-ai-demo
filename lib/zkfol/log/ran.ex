defmodule Zkfol.Log.Ran do
  @moduledoc """
  I am the receipt of one journaled act: the route, the source, and
  the defining event's id. I keep no history: `stage/2` and
  `final_stage/1` re-run from the source, and the readings that need
  the log stay on `Zkfol.Log`.
  """

  use TypedStruct

  alias Zkfol.Refusal
  alias Zkfol.Statement

  typedstruct enforce: true do
    field(:pipeline, Zkfol.Pipeline.t())
    field(:source, Statement.t())
    field(:defined, pos_integer())
  end

  @doc """
  I am the statement after the act's first `k` passes, re-run from the
  source: passes are pure, so a stage is recomputed, never stored.
  Stage 0 is the source itself.
  """
  @spec stage(t(), non_neg_integer()) :: {:ok, Statement.t()} | {:error, Refusal.t()}
  def stage(%__MODULE__{pipeline: pipeline, source: source}, k) do
    shortened = %Zkfol.Pipeline{passes: Enum.take(pipeline.passes, k)}

    case Zkfol.Pipeline.run(shortened, source) do
      {:ok, statement, _trace} -> {:ok, statement}
      {:error, _pass, reason, _trace} -> {:error, reason}
    end
  end

  @doc """
  I am the act's final statement, re-run from the source, so a holder
  has the struct itself and every view it wears; nil when a pass
  refused and there is no final stage to hold.
  """
  @spec final_stage(t()) :: Statement.t() | nil
  def final_stage(%__MODULE__{pipeline: pipeline} = ran) do
    case stage(ran, length(pipeline.passes)) do
      {:ok, statement} -> statement
      {:error, _reason} -> nil
    end
  end
end
