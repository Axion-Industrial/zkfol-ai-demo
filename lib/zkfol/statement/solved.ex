defmodule Zkfol.Statement.Solved do
  @moduledoc """
  I am the stage of a statement that has both a predicate and a witness
  modelling it, the predicate linked: every row numbered. Only I can be
  emitted and proved: `Zkfol.compile/2` reads its predicate and witness
  here. A run-produced witness carries its derivation and the
  allocation it was laid by; a hand-attached one carries neither.
  """

  use TypedStruct

  alias Zkfol.Alloc
  alias Zkfol.Ast
  alias Zkfol.Derivation
  alias Zkfol.Interpretation

  typedstruct enforce: true do
    field(:pred, Ast.pred())
    field(:witness, Interpretation.t())
    field(:derivation, Derivation.t() | nil, default: nil, enforce: false)
    field(:alloc, Alloc.t() | nil, default: nil, enforce: false)
  end
end
