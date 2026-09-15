defmodule Zkfol.Lang.Rel do
  @moduledoc "I am a named relation: clauses of one head shape."

  alias Zkfol.Lang.Term
  use TypedStruct

  typedstruct enforce: true do
    field(:name, atom())
    field(:arity, non_neg_integer())
    field(:clauses, [{[term()], [term()]}])
    field(:home, module() | nil, default: nil, enforce: false)
    # `phi` specializes lowering. `al` posts an additional constraint; a `:definition`
    # can also replace the clauses when asking for answers without a source derivation.
    field(:phi, {module(), atom()} | nil, default: nil, enforce: false)
    field(:al, Macro.t() | {:definition, Macro.t()} | nil, default: nil, enforce: false)
  end

  @doc "I am the callees my clauses name; a head-bound name is a passed relation, not a callee."
  @spec calls(t()) :: [Term.name()]
  def calls(%__MODULE__{clauses: clauses}),
    do:
      for(
        {head, body} <- clauses,
        bound = MapSet.new(Term.names(head)),
        {:call, q, _args} <- body,
        not match?({:var, _}, q) and not (is_atom(q) and MapSet.member?(bound, q)),
        uniq: true,
        do: q
      )

  @doc "I am the names my clauses hand to a call: a relation where one answers to them."
  @spec passes(t()) :: [Term.name()]
  def passes(%__MODULE__{clauses: clauses}),
    do:
      for(
        {head, body} <- clauses,
        bound = MapSet.new(Term.names(head)),
        {:call, _q, args} <- body,
        arg <- args,
        name <- passing(arg, bound),
        uniq: true,
        do: name
      )

  @spec passing(Term.t(), MapSet.t()) :: [Term.name()]
  defp passing(arg, bound) do
    case Term.passed(arg, bound) do
      {name, fixed} -> [name | Enum.flat_map(fixed, &passing(&1, bound))]
      nil -> []
    end
  end
end
