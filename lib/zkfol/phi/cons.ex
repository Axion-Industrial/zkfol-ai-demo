defmodule Zkfol.Phi.Cons do
  @moduledoc """
  I am a constructed pair of symbolic values; I allocate no cells.

  ### Public API

  - `new/2`: construct a pair, retaining a view when its peeled head is restored.
  - `peel/1`: observe a pair, view or stored node, with the equations its head requires.
  """

  use TypedStruct

  alias Zkfol.Phi.{Ref, View}

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

  @doc "I expose existing values without copying their cells."
  @spec peel(Zkfol.Phi.Value.t()) ::
          {:ok, Zkfol.Phi.Value.t(), Zkfol.Phi.Value.t(), [Zkfol.Ast.pred()]} | :dead
  def peel(%__MODULE__{head: head, tail: tail}), do: {:ok, head, tail, []}
  def peel([head | tail]), do: {:ok, head, tail, []}

  def peel(view = %View{col: col}) when col != nil do
    with {:ok, pins} <- View.peeled(view),
         do: {:ok, View.slice(view, 0), View.shifted(view, 1), pins}
  end

  def peel(%Ref{} = ref),
    do:
      {:ok, %Ref{id: Ref.read(:head, ref)}, %Ref{id: Ref.read(:tail, ref)},
       [Zkfol.Ast.eq(Ref.read(:tag, ref), 2)]}

  def peel(_other), do: :dead
end
