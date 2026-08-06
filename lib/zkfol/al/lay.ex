defmodule Zkfol.Al.Lay do
  @moduledoc """
  I lay the derivation's facts as the witness: one column per fact,
  a member's rows carrying its tuple, the tag row wearing its
  relation, each call site's pointer row holding the consumed fact's
  position, unread cells padding. Position is identity; no argument
  is the count. The oracle judges every column.

  I am the linker's work done here: when `Zkfol.Alloc` receives the
  layout, I cross the boundary.
  """

  alias Zkfol.Al.Consumption
  alias Zkfol.Ast
  alias Zkfol.Interpretation
  alias Zkfol.Lang.Rel
  alias Zkfol.Refusal
  alias Zkfol.Semantics

  @typep fact :: {atom(), [term()]}

  @doc "I am the witness of `facts` under `table`'s layout, judged against `pred`."
  @spec lay([fact()], map(), [Rel.t()], Ast.pred()) ::
          {:ok, Interpretation.t()} | {:error, Refusal.t()}
  def lay(facts, table, members, pred) do
    consumption = Consumption.of(facts, members, table)

    schedules =
      case Ast.schedules(pred) do
        {:ok, schedules} -> schedules
        {:error, _reason} -> %{}
      end

    order = arrange(facts, consumption, schedules)
    position = order |> Enum.with_index(1) |> Map.new()
    pointer_rows = table.pointers |> Map.values() |> MapSet.new()

    columns =
      Enum.map(order, fn {name, tuple} = fact ->
        cells = table.rows |> Map.fetch!(name) |> Enum.zip(tuple) |> Map.new()

        cells =
          if table.tag,
            do: Map.put(cells, table.tag, Map.fetch!(table.tags, name)),
            else: cells

        pointers =
          Map.new(consumption[fact], fn {row, callee} -> {row, Map.fetch!(position, callee)} end)

        Map.merge(cells, pointers)
      end)

    # A cell still a variable is a row the relation holds at any value:
    # unification left it free, so the witness fills it arbitrarily.
    matrix =
      for row <- 1..table.width do
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
           ) do
      witness = Interpretation.new(matrix)

      if Semantics.valid?(pred, witness),
        do: {:ok, witness},
        else: {:error, {:witness_invalid, %{}}}
    end
  end

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
