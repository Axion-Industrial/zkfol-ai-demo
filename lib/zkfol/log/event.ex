defmodule Zkfol.Log.Event do
  use TypedStruct

  alias Zkfol.Log.Args
  alias Zkfol.Pipeline
  alias Zkfol.Prover.Report
  alias Zkfol.Refusal

  @typedoc "A compile: its name, pipeline, the openings made public, and the entry arguments."
  @type define :: {:define, atom(), Pipeline.t(), [Zkfol.Lay.opening()], Args.t()}

  @typedoc "Every body the log records; each is based on the event that led to it."
  @type body ::
          define()
          | {:piped, [{module(), Pipeline.result()}]}
          | {:refused, Refusal.t()}
          | {:prove_requested, atom() | nil}
          | {:proved, Report.t()}
          | {:prove_failed, Refusal.t()}
          | {:al_solved, %{name: atom(), count: non_neg_integer(), program: AL.Object.t()}}

  typedstruct enforce: true do
    @moduledoc "I represent a finished event"

    field(:id, pos_integer())
    field(:basedon, pos_integer() | nil)
    field(:body, body())
  end
end
