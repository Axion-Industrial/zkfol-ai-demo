defmodule Zkfol.Derivation do
  @moduledoc """
  I am the extension a run established: the facts in callees-first
  order, the consumption between them, and the clause each fact fired,
  position as identity; no argument is the count.

  I am `Zkfol.Matrix`'s mirror: a relation plus its extension becomes
  an interpretation either way, mine derived by a run and its
  declared. `Zkfol.Lay` places me on the rows `Zkfol.Alloc` assigned.
  """

  use TypedStruct

  @typedoc "One established fact: the relation and its ground tuple."
  @type fact :: {atom(), [term()]}

  typedstruct enforce: true do
    field(:facts, [fact()])
    field(:edges, [[non_neg_integer()]], default: [])
    field(:clauses, [non_neg_integer() | nil], default: [])
  end

  @doc """
  I am the derivation AL's journal carries, deduplicated: every fact
  the committed tree established, callees ahead of their callers, and
  `edges` and `clauses` beside `facts` position by position: the k-th
  edge entry is the indices of the facts the k-th fact's calls
  consumed, in body order; the k-th clause entry is the 0-based seq of
  the clause that established it. The tree's children are those calls,
  which flattening would lose. Indices, so I ride the bridge whole.
  """
  @spec of([map()] | map(), MapSet.t(), boolean()) :: t()
  def of(tree, names, len? \\ false) do
    nodes = tree |> List.wrap() |> Enum.flat_map(&walk(&1, names, len?))
    facts = nodes |> Enum.map(&elem(&1, 0)) |> Enum.uniq()
    index = facts |> Enum.with_index() |> Map.new()
    digested = Map.new(nodes)
    ran = Enum.map(facts, &Map.fetch!(digested, &1))

    %__MODULE__{
      facts: facts,
      edges: for({callees, _clause} <- ran, do: for(callee <- callees, do: index[callee])),
      clauses: for({_callees, clause} <- ran, do: clause)
    }
  end

  @doc "I am each fact beside what it consumed, the edges resolved back to facts."
  @spec consumption(t()) :: [{fact(), [fact()]}]
  def consumption(%__MODULE__{facts: facts, edges: edges}) do
    arr = List.to_tuple(facts)
    Enum.zip(facts, for(callees <- edges, do: for(i <- callees, do: elem(arr, i))))
  end

  # Post-order: a member node becomes its fact beside the facts of its
  # member children and the clause it fired, resolved through each
  # node's own bindings.
  @spec walk(map(), MapSet.t(), boolean()) :: [{fact(), {[fact()], non_neg_integer() | nil}}]
  defp walk(%{label: {_self, m, _args}, children: kids} = node, names, len?) do
    below = Enum.flat_map(kids, &walk(&1, names, len?))

    if MapSet.member?(names, m),
      do:
        below ++
          [
            {fact_of(node, len?),
             {for(kid <- kids, fact = member_fact(kid, names, len?), do: fact), node.clause}}
          ],
      else: below
  end

  defp walk(_node, _names, _len?), do: []

  @spec member_fact(map(), MapSet.t(), boolean()) :: fact() | nil
  defp member_fact(%{label: {_self, m, _args}} = node, names, len?),
    do: if(MapSet.member?(names, m), do: fact_of(node, len?))

  defp member_fact(_node, _names, _len?), do: nil

  @spec fact_of(map(), boolean()) :: fact()
  defp fact_of(%{label: {_self, m, args}, derived: derived}, len?) do
    values = Enum.map(args, &resolved(&1, derived))
    {m, if(len?, do: Enum.drop(values, -1), else: values)}
  end

  @spec resolved(term(), map() | nil) :: term()
  defp resolved(term, derived) do
    case derived && Map.get(derived, term) do
      {:bound, value} -> value
      _other -> term
    end
  end

  @doc """
  I am the derivation beneath one fact: it and everything it consumed,
  transitively, in my order. Consumption is closed under me, so laying
  me yields a witness every column of which still holds.
  """
  @spec under(t(), fact()) :: t()
  def under(%__MODULE__{facts: facts, edges: edges, clauses: clauses}, fact) do
    index = facts |> Enum.with_index() |> Map.new()
    kept = reach([Map.fetch!(index, fact)], edges, MapSet.new())

    renumber =
      0..(length(facts) - 1) |> Enum.filter(&(&1 in kept)) |> Enum.with_index() |> Map.new()

    %__MODULE__{
      facts: for({f, i} <- Enum.with_index(facts), i in kept, do: f),
      edges:
        for {callees, i} <- Enum.with_index(edges), i in kept do
          for c <- callees, do: Map.fetch!(renumber, c)
        end,
      clauses: for({c, i} <- Enum.with_index(clauses), i in kept, do: c)
    }
  end

  @spec reach([non_neg_integer()], [[non_neg_integer()]], MapSet.t()) :: MapSet.t()
  defp reach([], _edges, seen), do: seen

  defp reach([i | rest], edges, seen) do
    if MapSet.member?(seen, i),
      do: reach(rest, edges, seen),
      else: reach(Enum.at(edges, i) ++ rest, edges, MapSet.put(seen, i))
  end

  @doc "I fill a cell unification left free: a variable reads zero."
  @spec free_to_zero(term()) :: term()
  def free_to_zero({:"$fresh", _name, _scope}), do: 0
  def free_to_zero(a) when is_atom(a), do: if(AL.Var.var?(a), do: 0, else: a)
  def free_to_zero(cell), do: cell
end

defimpl Inspect, for: Zkfol.Derivation do
  import Inspect.Algebra

  # fib(3, 2)<-{0,1} reads: this fact's calls consumed facts 0 and 1,
  # in body order. The numbers index my own facts.
  def inspect(%Zkfol.Derivation{facts: facts, edges: edges}, _opts) do
    lines =
      facts
      |> Enum.zip(edges)
      |> Enum.map(fn
        {{name, tuple}, []} -> "#{name}(#{Enum.join(tuple, ", ")})"
        {{name, tuple}, used} -> "#{name}(#{Enum.join(tuple, ", ")})<-{#{Enum.join(used, ",")}}"
      end)

    concat(["#Zkfol.Derivation<", Enum.join(lines, " "), ">"])
  end
end
