defmodule Zkfol.Statement do
  @moduledoc """
  I am one statement of the logic: the predicate with its range checks
  and claims, and the witness once provided. A nil witness is the empty
  slot of the existential: construct me with one, or let it be filled.
  """

  use TypedStruct

  alias Zkfol.Ast
  alias Zkfol.Interpretation
  alias Zkfol.Range

  typedstruct enforce: true do
    field(:pred, Ast.pred())
    field(:ranges, [Range.check()], default: [])
    field(:witness, Interpretation.t() | nil, default: nil)
    field(:claims, [Interpretation.claim()], default: [])
  end
end
