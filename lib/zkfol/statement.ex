defmodule Zkfol.Statement do
  @moduledoc """
  I am one statement of the logic: its relations, the arguments of the
  instance, the range checks and claims that ride along, and the stage
  the pipeline has carried it to.

  The stage says what is known, so a pass states its precondition as a
  type rather than testing for absence: `:raw` has only relations,
  `Lowered` carries the predicate they lower to, and `Solved` carries a
  witness that models it. A stage that knows nothing is a bare atom;
  only the stages carrying data are structs. Only a solved statement
  can be proved.
  """

  use TypedStruct

  alias Zkfol.Ast
  alias Zkfol.Interpretation
  alias Zkfol.Statement.Lowered
  alias Zkfol.Statement.Solved

  @typedoc "How far the pipeline has carried a statement."
  @type stage :: :raw | Lowered.t() | Solved.t()

  typedstruct enforce: true do
    field(:rels, [Zkfol.Lang.Rel.t()], default: [])
    field(:args, [integer() | :_], default: [])
    field(:claims, [Interpretation.claim()], default: [])
    field(:stage, stage(), default: :raw)
  end

  @doc "I am the predicate, once the statement has been lowered to one."
  @spec pred(t()) :: Ast.pred()
  def pred(%__MODULE__{stage: %Lowered{pred: pred}}), do: pred
  def pred(%__MODULE__{stage: %Solved{pred: pred}}), do: pred

  @doc "I am the witness, once one models the predicate."
  @spec witness(t()) :: Interpretation.t()
  def witness(%__MODULE__{stage: %Solved{witness: witness}}), do: witness

  @doc "I am the statement lowered to `pred`."
  @spec lowered(t(), Ast.pred()) :: t()
  def lowered(%__MODULE__{} = statement, pred),
    do: %{statement | stage: %Lowered{pred: pred}}
end
