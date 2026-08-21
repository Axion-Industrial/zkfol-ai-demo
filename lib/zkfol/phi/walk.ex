defmodule Zkfol.Phi.Walk do
  @moduledoc """
  I am what a walk of goals came to: the members it made and what they
  say, the equations and sites of the clause being said, the rows it
  spent, the env its goals bound, and whether a conjunct died.

  ### Public API

  - `join/2`: one walk then another.
  - `dead/1`: the walk of a conjunct nothing can hold.
  """

  use TypedStruct

  alias Zkfol.Alloc.Member
  alias Zkfol.Alloc.Site
  alias Zkfol.Alloc.Slot
  alias Zkfol.Ast

  typedstruct do
    field(:env, map(), default: %{})
    field(:members, [Member.t()], default: [])
    field(:saids, [{atom(), Ast.pred()}], default: [])
    field(:eqs, [Ast.pred()], default: [])
    field(:sites, [{non_neg_integer(), Site.t() | nil}], default: [])
    field(:spent, [Slot.t()], default: [])
    field(:dead?, boolean(), default: false)
  end

  @doc "I am one walk then another: the later's env and death, the rest appended."
  @spec join(t(), t()) :: t()
  def join(%__MODULE__{} = a, %__MODULE__{} = b) do
    %__MODULE__{
      env: b.env,
      members: a.members ++ b.members,
      saids: a.saids ++ b.saids,
      eqs: a.eqs ++ b.eqs,
      sites: a.sites ++ b.sites,
      spent: a.spent ++ b.spent,
      dead?: a.dead? or b.dead?
    }
  end

  @doc "I am the walk of a conjunct nothing can hold: it says nothing and lays nothing."
  @spec dead(map()) :: t()
  def dead(env), do: %__MODULE__{env: env, dead?: true}
end
