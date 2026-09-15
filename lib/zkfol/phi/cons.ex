defmodule Zkfol.Phi.Cons do
  @moduledoc """
  I am a constructed pair of symbolic values; I allocate no cells.

  ### Public API

  - `new/2`: construct a pair, retaining a view when its peeled head is restored.
  """

  use TypedStruct

  alias Zkfol.Phi.View

  typedstruct enforce: true do
    field(:head, Zkfol.Phi.Value.t())
    field(:tail, Zkfol.Phi.Value.t())
  end

  @doc "I pair existing values; restoring a view's preceding cell restores the view."
  @spec new(Zkfol.Phi.Value.t(), Zkfol.Phi.Value.t()) :: t() | View.t()
  def new(head, tail = %View{col: col}) when col != nil do
    if View.slice(tail, -1) == head,
      do: View.shifted(tail, -1),
      else: %__MODULE__{head: head, tail: tail}
  end

  def new(head, tail), do: %__MODULE__{head: head, tail: tail}
end
