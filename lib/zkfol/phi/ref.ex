defmodule Zkfol.Phi.Ref do
  @moduledoc """
  I am a stored term's identity; observing it names reads in the term graph.

  ### Public API

  - `of/1`: retain an identity or name the node realizing a value.
  - `read/2`: observe a field through a shared staging row.
  """
  use TypedStruct
  alias Zkfol.Ast

  typedstruct enforce: true do
    field(:id, Ast.term_t())
  end

  @doc "I retain an identity or name the node which realizes a symbolic value."
  @spec of(Zkfol.Phi.Value.t()) :: t()
  def of(ref = %__MODULE__{}), do: ref
  def of([]), do: %__MODULE__{id: 1}
  def of(value), do: %__MODULE__{id: Ast.cell({Zkfol.Nodes, {:node, value}})}

  @doc "I observe one field, sharing the staging row of a nonlocal identity."
  @spec read(:tag | :value | :head | :tail, t()) :: Ast.term_t()
  def read(field, %__MODULE__{id: id}) do
    pointer =
      case id do
        {:cell, row} -> row
        other -> {Zkfol.Nodes, {:read, other}}
      end

    Ast.cell({Zkfol.Nodes, field}, pointer)
  end
end
