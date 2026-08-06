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

  alias Zkfol.Al.Consumption
  alias Zkfol.Alloc
  alias Zkfol.Ast
  alias Zkfol.Interpretation
  alias Zkfol.Lang.Rel
  alias Zkfol.Refusal

  @typep fact :: {atom(), [term()]}

  @doc """
  I am the banks `facts` fill, one per region `alloc` assigned
  `shape`'s names: a member's own extension, the tag's column, the
  pointers' positions. `Zkfol.Alloc` stacks me beside whatever else
  the statement declares, and the oracle judges the stack.
  """
  @spec lay([fact()], Alloc.t(), Zkfol.Lang.shape(), [Rel.t()], Ast.pred()) ::
          {:ok, %{atom() => Interpretation.t()}} | {:error, Refusal.t()}
  def lay(facts, alloc, shape, members, pred) do
    row = &(Alloc.offset(alloc, elem(&1, 0)) + elem(&1, 1))

    # Consumption speaks in the names Lang gave; everything below me
    # is rows, so the pointers land on theirs first.
    consumption =
      facts
      |> Consumption.of(members, shape)
      |> Map.new(fn {fact, used} -> {fact, for({p, c} <- used, do: {row.(p), c})} end)

    schedules =
      case Ast.schedules(pred) do
        {:ok, schedules} -> schedules
        {:error, _reason} -> %{}
      end

    order = arrange(facts, consumption, schedules)
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
