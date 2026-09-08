defmodule Zkfol.Phi.Walk do
  @moduledoc """
  I am what a walk of goals came to: the members it made and what they
  say, and the bindings, constraints and storage of one clause.
  Bank depths belong to storage; `env` holds only symbolic bindings.
  An impossible walk is `:dead`.

  ### Public API

  - `constrain/2`: retain the equations required by an observation.
  """

  use TypedStruct

  alias Zkfol.Alloc.Bank
  alias Zkfol.Alloc.Member
  alias Zkfol.Alloc.Site
  alias Zkfol.Alloc.Slot
  alias Zkfol.Ast

  typedstruct do
    field(:env, map(), default: %{})
    field(:banks, %{atom() => pos_integer()}, default: %{})
    field(:members, [Member.t() | Bank.t()], default: [])
    field(:predicates, [Ast.pred()], default: [])
    field(:eqs, [Ast.pred()], default: [])
    field(:sites, [{non_neg_integer(), Site.t()}], default: [])
    field(:slots, [Slot.t()], default: [])
  end

  @doc "I collect conjuncts in reverse order without copying the clause accumulated so far."
  @spec constrain(t(), [Ast.pred()]) :: t()
  def constrain(walk = %__MODULE__{}, eqs), do: %{walk | eqs: Enum.reverse(eqs, walk.eqs)}
end
