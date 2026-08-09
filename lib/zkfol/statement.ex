defmodule Zkfol.Statement do
  @moduledoc """
  I am one statement of the logic: its relations, the arguments of the
  instance, the range checks and claims that ride along, and the stage
  the pipeline has carried it to.

  The stage says what is known, so a pass states its precondition as a
  type rather than testing for absence: `:raw` has only relations,
  `Derived` carries the derivation the run established, and `Solved`
  carries the predicate it lowers to beside the witness modelling it.
  A stage that knows nothing is a bare atom; only the stages carrying
  data are structs. An answer is had at `Derived`; only a solved
  statement can be proved.
  """

  use TypedStruct

  alias Zkfol.Ast
  alias Zkfol.Interpretation
  alias Zkfol.Statement.Derived
  alias Zkfol.Statement.Solved

  @typedoc "How far the pipeline has carried a statement."
  @type stage :: :raw | Derived.t() | Solved.t()

  typedstruct enforce: true do
    field(:rels, [Zkfol.Lang.Rel.t()], default: [])
    field(:args, [integer() | :_], default: [])
    field(:claims, [Interpretation.claim()], default: [])
    field(:stage, stage(), default: :raw)
  end

  @doc "I am the predicate the statement's relations lower to, linked, once solved."
  @spec pred(t()) :: Ast.pred()
  def pred(%__MODULE__{stage: %Solved{pred: pred}}), do: pred

  @doc "I am the witness, once one models the predicate."
  @spec witness(t()) :: Interpretation.t()
  def witness(%__MODULE__{stage: %Solved{witness: witness}}), do: witness

  @doc "I am the lay a run produced, nil before one has or beside a hand-attached witness."
  @spec lay(t()) :: Zkfol.Lay.t() | nil
  def lay(%__MODULE__{stage: %Solved{lay: lay}}), do: lay
  def lay(%__MODULE__{}), do: nil

  @doc "I am the allocation, read off the lay."
  @spec alloc(t()) :: Zkfol.Alloc.t() | nil
  def alloc(%__MODULE__{} = statement),
    do: with(%Zkfol.Lay{} = lay <- lay(statement), do: lay.alloc)

  @doc "I am the derivation: the run's own once derived, the lay's once solved."
  @spec derivation(t()) :: Zkfol.Derivation.t() | nil
  def derivation(%__MODULE__{stage: %Derived{derivation: derivation}}), do: derivation

  def derivation(%__MODULE__{} = statement),
    do: with(%Zkfol.Lay{} = lay <- lay(statement), do: lay.derivation)

  @doc "I am the statement carrying `derivation`: what its relations established, unlaid."
  @spec derived(t(), Zkfol.Derivation.t()) :: t()
  def derived(%__MODULE__{} = statement, derivation),
    do: %{statement | stage: %Derived{derivation: derivation}}
end
