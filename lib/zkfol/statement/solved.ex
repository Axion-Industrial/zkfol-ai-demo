defmodule Zkfol.Statement.Solved do
  @moduledoc """
  I am the stage of a statement that has both a predicate and a witness
  modelling it. Only I can be emitted and proved: `Zkfol.compile/2`
  reads its predicate and witness here.
  """

  use TypedStruct

  alias Zkfol.Ast
  alias Zkfol.Interpretation

  typedstruct enforce: true do
    field(:pred, Ast.pred())
    field(:witness, Interpretation.t())
  end
end
