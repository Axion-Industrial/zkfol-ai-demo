defmodule Zkfol.Statement.Lowered do
  @moduledoc """
  I am the stage of a statement whose relations have become a predicate.
  The predicate says what must hold; no witness models it yet, so
  `Zkfol.Witness` searches for one and carries me to
  `Zkfol.Statement.Solved`.
  """

  use TypedStruct

  alias Zkfol.Ast
  alias Zkfol.Interpretation
  alias Zkfol.Statement.Solved

  typedstruct enforce: true do
    field(:pred, Ast.pred())
  end

  @doc "I am the same predicate, now with a witness that models it."
  @spec solved(t(), Interpretation.t()) :: Solved.t()
  def solved(%__MODULE__{pred: pred}, witness),
    do: %Solved{pred: pred, witness: witness}
end
