defmodule Zkfol.Derivation do
  @moduledoc """
  I am the extension a run established: the facts in callees-first
  order, the consumption between them, and the clause each fact fired.
  A fact is its own key: nothing outside me counts my positions.

  I am `Zkfol.Matrix`'s mirror: a relation plus its extension becomes
  an interpretation either way, mine derived by a run and its
  declared. `Zkfol.Lay` places me on the rows `Zkfol.Alloc` assigned.
  """

  use TypedStruct

  @typedoc "One established fact: the relation and its ground tuple."
  @type fact :: {atom(), [term()]}

  typedstruct enforce: true do
    field(:facts, [fact()])
    # Pairs, not maps: a tuple key cannot ride the bridge.
    field(:consumed, [{fact(), [fact()]}], default: [])
    field(:clauses, [{fact(), non_neg_integer() | nil}], default: [])
  end

  @doc """
  I am the derivation AL's journal carries, deduplicated: every fact
  the committed tree established, callees ahead of their callers, what
  each fact's calls consumed in body order, and the 0-based seq of the
  clause that established it. The tree's children are those calls,
  which flattening would lose.
  """
  @spec of(AL.t(), MapSet.t(), boolean()) :: t()
  def of(%AL{domino: %{trace: trace}, active_choicepoint: %{store: store}}, names, len?) do
    tree = trace |> Enum.reverse() |> AL.Trace.derivation_tree(store)
    nodes = tree |> List.wrap() |> Enum.flat_map(&walk(&1, names, len?, store))
    facts = nodes |> Enum.map(&elem(&1, 0)) |> Enum.uniq()
    digested = Map.new(nodes)
    ran = for fact <- facts, do: {fact, Map.fetch!(digested, fact)}

    %__MODULE__{
      facts: facts,
      consumed: for({fact, {callees, _clause}} <- ran, do: {fact, callees}),
      clauses: for({fact, {_callees, clause}} <- ran, do: {fact, clause})
    }
  end

  @doc "I am the facts one fact's calls consumed, in body order."
  @spec consumed(t(), fact()) :: [fact()]
  def consumed(%__MODULE__{consumed: consumed}, fact),
    do: consumed |> List.keyfind(fact, 0, {fact, []}) |> elem(1)

  @doc "I am the 0-based seq of the clause that established one fact."
  @spec clause(t(), fact()) :: non_neg_integer() | nil
  def clause(%__MODULE__{clauses: clauses}, fact),
    do: clauses |> List.keyfind(fact, 0, {fact, nil}) |> elem(1)

  @doc "I am what a run established of one relation: its last fact, the query's own."
  @spec root(t(), atom()) :: fact() | nil
  def root(%__MODULE__{facts: facts}, relation),
    do: facts |> Enum.reverse() |> Enum.find(&(elem(&1, 0) == relation))

  @doc "I am each fact beside what it consumed, in my order."
  @spec consumption(t()) :: [{fact(), [fact()]}]
  def consumption(%__MODULE__{consumed: consumed}), do: consumed

  # Post-order: a member node becomes its fact beside the facts of its
  # member children and the clause it fired, resolved through each
  # node's own bindings.
  @spec walk(map(), MapSet.t(), boolean(), map()) :: [
          {fact(), {[fact()], non_neg_integer() | nil}}
        ]
  defp walk(%{label: {_self, m, _args}, children: kids} = node, names, len?, store) do
    below = Enum.flat_map(kids, &walk(&1, names, len?, store))

    if MapSet.member?(names, m) do
      consumed =
        for %{label: {_self, k, _args}} = kid <- kids,
            MapSet.member?(names, k),
            do: fact_of(kid, len?, store)

      below ++ [{fact_of(node, len?, store), {consumed, node.clause}}]
    else
      below
    end
  end

  defp walk(_node, _names, _len?, _store), do: []

  @spec fact_of(map(), boolean(), map()) :: fact()
  defp fact_of(%{label: {_self, m, args}, derived: derived}, len?, store) do
    values = for arg <- args, do: arg |> resolved(derived) |> AL.Var.subst(store)
    {m, if(len?, do: Enum.drop(values, -1), else: values)}
  end

  # A sequence built one call at a time was journalled with its tail still open.
  @spec resolved(term(), map() | nil) :: term()
  defp resolved([head | tail], derived), do: [resolved(head, derived) | resolved(tail, derived)]

  defp resolved(term, derived) do
    case derived && Map.get(derived, term) do
      {:bound, value} -> resolved(value, derived)
      _open -> term
    end
  end

  @doc """
  I am the derivation beneath one fact: it and everything it consumed,
  transitively, in my order. Consumption is closed under me, so laying
  me yields a witness every column of which still holds.
  """
  @spec under(t(), fact()) :: t()
  def under(%__MODULE__{} = t, fact) do
    kept = reach([fact], t, MapSet.new())

    %__MODULE__{
      facts: Enum.filter(t.facts, &MapSet.member?(kept, &1)),
      consumed: Enum.filter(t.consumed, &MapSet.member?(kept, elem(&1, 0))),
      clauses: Enum.filter(t.clauses, &MapSet.member?(kept, elem(&1, 0)))
    }
  end

  @spec reach([fact()], t(), MapSet.t()) :: MapSet.t()
  defp reach([], _t, seen), do: seen

  defp reach([fact | rest], t, seen) do
    if MapSet.member?(seen, fact),
      do: reach(rest, t, seen),
      else: reach(consumed(t, fact) ++ rest, t, MapSet.put(seen, fact))
  end

  @doc "I fill a cell unification left free: a variable reads zero."
  @spec free_to_zero(term()) :: term()
  def free_to_zero(cell), do: if(AL.Var.var?(cell), do: 0, else: cell)
end

defimpl Inspect, for: Zkfol.Derivation do
  import Inspect.Algebra

  # fib(3, 2)<-{0,1} reads: this fact's calls consumed facts 0 and 1,
  # in body order. The numbers are positions in my own facts.
  def inspect(%Zkfol.Derivation{facts: facts} = derivation, _opts) do
    at = facts |> Enum.with_index() |> Map.new()

    lines =
      for {{name, tuple}, used} <- Zkfol.Derivation.consumption(derivation) do
        stated = "#{name}(#{cells(tuple)})"
        if used == [], do: stated, else: stated <> "<-{#{Enum.map_join(used, ",", &at[&1])}}"
      end

    concat(["#Zkfol.Derivation<", Enum.join(lines, " "), ">"])
  end

  defp cells(tuple), do: Enum.map_join(tuple, ", ", &inspect/1)
end
