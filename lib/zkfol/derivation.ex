defmodule Zkfol.Derivation do
  @moduledoc """
  I am the extension a run established, laid as a region: one column
  per fact, a member's rows carrying its tuple, the tag row wearing
  its relation, each call site's pointer row holding the consumed
  fact's position, unread cells padding. Position is identity; no
  argument is the count. The oracle judges every column.

  I am `Zkfol.Matrix`'s mirror: a relation plus its extension becomes
  an interpretation either way, mine derived by a run and its
  declared. `Zkfol.Alloc` stacks what we each produce.

  I lay on the rows `Zkfol.Alloc` assigned the names `Zkfol.Lang`
  compiled; neither of us counts rows on its own.
  """

  use TypedStruct

  alias Zkfol.Al.Consumption
  alias Zkfol.Alloc
  alias Zkfol.Interpretation
  alias Zkfol.Lang.Rel
  alias Zkfol.Refusal

  @typedoc "One established fact: the relation and its ground tuple."
  @type fact :: {atom(), [term()]}

  typedstruct enforce: true do
    field(:facts, [fact()])
    field(:edges, [[non_neg_integer()]], default: [])
  end

  @doc """
  I am the derivation AL's journal carries, deduplicated: every fact
  the committed tree established, callees ahead of their callers, and
  `edges` beside `facts` position by position -- the k-th entry the
  indices of the facts the k-th fact's calls consumed, in body order.
  The tree's children are those calls; flattening is what would lose
  them. Indices, so I ride the bridge whole.
  """
  @spec of([map()] | map(), MapSet.t(), boolean()) :: t()
  def of(tree, names, len? \\ false) do
    nodes = tree |> List.wrap() |> Enum.flat_map(&walk(&1, names, len?))
    facts = nodes |> Enum.map(&elem(&1, 0)) |> Enum.uniq()
    index = facts |> Enum.with_index() |> Map.new()
    consumed = Map.new(nodes)

    %__MODULE__{
      facts: facts,
      edges: for(fact <- facts, do: for(callee <- Map.fetch!(consumed, fact), do: index[callee]))
    }
  end

  @doc "I am each fact beside what it consumed, the edges resolved back to facts."
  @spec consumption(t()) :: [{fact(), [fact()]}]
  def consumption(%__MODULE__{facts: facts, edges: edges}) do
    arr = List.to_tuple(facts)
    Enum.zip(facts, for(callees <- edges, do: for(i <- callees, do: elem(arr, i))))
  end

  # Post-order: a member node becomes its fact beside the facts of its
  # member children, resolved through each node's own bindings.
  @spec walk(map(), MapSet.t(), boolean()) :: [{fact(), [fact()]}]
  defp walk(%{label: {_self, m, _args}, children: kids} = node, names, len?) do
    below = Enum.flat_map(kids, &walk(&1, names, len?))

    if MapSet.member?(names, m),
      do:
        below ++
          [
            {fact_of(node, len?),
             for(kid <- kids, fact = member_fact(kid, names, len?), do: fact)}
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
  I am the banks `facts` fill, one per region `alloc` assigned
  `shape`'s names: a member's own extension, the tag's column, the
  pointers' positions. `Zkfol.Alloc` stacks me beside whatever else
  the statement declares, and the oracle judges the stack.
  """
  @spec lay(t(), Alloc.t(), Zkfol.Lang.shape(), [Rel.t()]) ::
          {:ok, %{atom() => Interpretation.t()}} | {:error, Refusal.t()}
  def lay(%__MODULE__{} = derivation, alloc, shape, members) do
    row = &(Alloc.offset(alloc, elem(&1, 0)) + elem(&1, 1))
    {consumption, order, _schedules} = welded(derivation, alloc, shape, members)
    position = order |> Enum.with_index(1) |> Map.new()
    pointer_rows = pointer_rows(alloc, shape)

    columns =
      Enum.map(order, fn {name, tuple} = fact ->
        cells = alloc |> Alloc.rows(name) |> Enum.zip(tuple) |> Map.new()

        cells =
          if shape.tags == %{},
            do: cells,
            else: Map.put(cells, row.({:tag, 1}), Map.fetch!(shape.tags, name))

        pointers =
          Map.new(consumption[fact], fn {ptr, callee} -> {ptr, Map.fetch!(position, callee)} end)

        Map.merge(cells, pointers)
      end)

    # A cell still a variable is a row the relation holds at any value:
    # unification left it free, so the witness fills it arbitrarily.
    matrix =
      for row <- 1..Alloc.width(alloc) do
        for cells <- columns do
          cells
          |> Map.get(row, if(MapSet.member?(pointer_rows, row), do: 1, else: 0))
          |> free_to_zero()
        end
      end

    with :ok <-
           Refusal.refute(
             List.flatten(matrix),
             &(&1 < 0),
             &{:witness_value_negative, %{value: &1}}
           ),
         do: {:ok, banks(matrix, alloc)}
  end

  @doc """
  I am each consumption edge as an arrow between laid columns: from
  the consumer's column to the consumed fact's, named by the pointer
  row it went through, wearing the weld k when the pointer welds.
  A viewer draws me over the witness the same lay produced.
  """
  @spec arrows(t(), Alloc.t(), Zkfol.Lang.shape(), [Rel.t()]) :: [
          %{
            ptr: pos_integer(),
            from: pos_integer(),
            to: pos_integer(),
            to_row: pos_integer(),
            weld: pos_integer() | nil
          }
        ]
  def arrows(%__MODULE__{facts: facts} = derivation, alloc, shape, members) do
    {consumption, order, schedules} = welded(derivation, alloc, shape, members)
    position = order |> Enum.with_index(1) |> Map.new()

    for fact <- facts, {ptr, callee} <- Map.fetch!(consumption, fact) do
      %{
        ptr: ptr,
        from: Map.fetch!(position, fact),
        to: Map.fetch!(position, callee),
        to_row: Alloc.offset(alloc, elem(callee, 0)) + 1,
        weld: Map.get(schedules, ptr)
      }
    end
  end

  # Consumption on its rows, the measured schedules, and the laid
  # order: what lay and arrows share, computed once each.
  @spec welded(t(), Alloc.t(), Zkfol.Lang.shape(), [Rel.t()]) ::
          {%{fact() => [{pos_integer(), fact()}]}, [fact()], %{pos_integer() => pos_integer()}}
  defp welded(%__MODULE__{facts: facts} = derivation, alloc, shape, members) do
    row = &(Alloc.offset(alloc, elem(&1, 0)) + elem(&1, 1))

    # Consumption names the pointer each edge went through; everything
    # below me is rows, so they land on theirs first.
    consumption =
      derivation
      |> Consumption.of(members, shape)
      |> Map.new(fn {fact, used} -> {fact, for({p, c} <- used, do: {row.(p), c})} end)

    schedules = measured(consumption)
    {consumption, arrange(facts, consumption, schedules), schedules}
  end

  # The matrix cut along the regions it was laid on, so what I made
  # reads back as banks by name.
  @spec banks([[non_neg_integer()]], Alloc.t()) :: %{atom() => Interpretation.t()}
  defp banks(matrix, %Alloc{regions: regions} = alloc) do
    Map.new(regions, fn {name, width} ->
      {name, matrix |> Enum.slice(Alloc.offset(alloc, name), width) |> Interpretation.new()}
    end)
  end

  # An unread cell on a pointer row still names a column, so it pads
  # with one rather than zero.
  @spec pointer_rows(Alloc.t(), Zkfol.Lang.shape()) :: MapSet.t()
  defp pointer_rows(_alloc, %{pointers: []}), do: MapSet.new()
  defp pointer_rows(alloc, _shape), do: alloc |> Alloc.rows(:ptr) |> MapSet.new()

  # A pointer welds when every consumption through it is the same
  # relation descending its first argument by one constant: measured
  # off the edges, where the old encoding inferred it from the
  # predicate's syntax.
  @spec measured(%{fact() => [{pos_integer(), fact()}]}) :: %{pos_integer() => pos_integer()}
  defp measured(consumption) do
    consumption
    |> Enum.flat_map(fn {consumer, used} ->
      for {ptr, callee} <- used, do: {ptr, consumer, callee}
    end)
    |> Enum.group_by(&elem(&1, 0), fn {_ptr, consumer, callee} -> delta(consumer, callee) end)
    |> Enum.flat_map(fn {ptr, deltas} ->
      case Enum.uniq(deltas) do
        [k] when is_integer(k) and k > 0 -> [{ptr, k}]
        _varying -> []
      end
    end)
    |> Map.new()
  end

  @spec delta(fact(), fact()) :: integer() | nil
  defp delta({name, [ci | _]}, {name, [ui | _]}) when is_integer(ci) and is_integer(ui),
    do: ci - ui

  defp delta(_consumer, _callee), do: nil

  # A scheduled read welds its consumer exactly k above its callee;
  # the rest keeps callees below their callers.
  @spec arrange([fact()], %{fact() => [{pos_integer(), fact()}]}, %{
          pos_integer() => pos_integer()
        }) :: [fact()]
  defp arrange(facts, consumption, schedules) do
    welds =
      for fact <- facts,
          {row, callee} <- Map.fetch!(consumption, fact),
          k = Map.get(schedules, row),
          is_integer(k),
          do: {fact, callee, k}

    forest = Map.new(welds, fn {consumer, callee, k} -> {callee, {consumer, -k}} end)

    walked = Enum.map(facts, &{walk(forest, &1), &1})
    roots = for {{root, _delta}, _fact} <- walked, uniq: true, do: root
    grouped = Enum.group_by(walked, fn {{root, _delta}, _fact} -> root end)

    Enum.flat_map(roots, fn root ->
      grouped
      |> Map.fetch!(root)
      |> Enum.sort_by(fn {{_root, delta}, _fact} -> delta end)
      |> Enum.map(fn {_walked, fact} -> fact end)
    end)
  end

  # pos(fact) = pos(root) + delta, the forest carrying the deltas.
  @spec walk(map(), fact()) :: {fact(), integer()}
  defp walk(forest, fact) do
    case forest do
      %{^fact => {parent, delta}} ->
        {root, above} = walk(forest, parent)
        {root, delta + above}

      _forest ->
        {fact, 0}
    end
  end

  @doc "I fill a cell unification left free: a variable reads zero."
  @spec free_to_zero(term()) :: term()
  def free_to_zero({:"$fresh", _name, _scope}), do: 0
  def free_to_zero(a) when is_atom(a), do: if(AL.Var.var?(a), do: 0, else: a)
  def free_to_zero(cell), do: cell
end
