defmodule Zkfol.Lay do
  @moduledoc """
  I am the lay as a value: how one allocation placed one derivation.
  The shape names the rows, the alloc numbers them, the derivation
  says what was established, and I add what only the placement knows:
  each fact's column, each pointer's weld, each consumption on its
  rows, each guard's slack, each reduction's quotient. The witness is
  my matrix; the arrows, aims, and regions are readings of me. Born
  in the solve's link-and-lay act, I ride
  `Zkfol.Statement.Solved`, so what a viewer draws is what a value
  holds.

  Everything cross-position is index-form -- the i-th entry speaks of
  the derivation's i-th fact -- so I ride the bridge whole. Reading
  me: `columns` says which trace column the i-th fact was dealt onto;
  `consumption` says, per fact, `{ptr_row, callee_index}` -- it
  consumed the callee-th fact through that committed pointer row;
  `slack` says, per fact, the room its fired clause's guards left --
  the k-th entry is what the k-th slack row holds at that fact's
  column, and a clause with fewer guards says less, so the rest pads;
  `quot` says the same of its reductions, the k-th entry the quotient
  the k-th mod site divided out;
  `welds` says `{ptr_row, k}` -- every consumption through that row
  lands exactly k columns back, so the pointer becomes a shift. The
  columns are arranged precisely so the welds hold: one is the
  choice, the other the property it achieves. The shape earns its
  seat beyond labels: `witness` reads its tags, pointer rows, and
  bank widths, `aims` its calls; only the named predicate inside it
  is baggage, kept so I describe the whole linked act.

  ### Public API

  - `of/4` — the placement computed once.
  - `witness/1` — my matrix as the laid interpretation.
  - `arrows/1` — one arrow per consumption between laid columns.
  - `aims/1` — each pointer row beside the caller entailing it.
  - `regions/1` — the alloc's banks by name and absolute rows.
  """

  use TypedStruct

  alias Zkfol.Al.Consumption
  alias Zkfol.Alloc
  alias Zkfol.Derivation
  alias Zkfol.Interpretation
  alias Zkfol.Lang
  alias Zkfol.Lang.Rel
  alias Zkfol.Refusal

  typedstruct enforce: true do
    field(:shape, Zkfol.Lang.shape())
    field(:alloc, Alloc.t())
    field(:derivation, Derivation.t())
    field(:columns, [pos_integer()])
    field(:welds, [{pos_integer(), pos_integer()}])
    field(:consumption, [[{pos_integer(), non_neg_integer()}]])
    field(:slack, [[integer()]])
    field(:quot, [[integer()]])
  end

  @doc """
  I compute the placement once: consumption on its rows, the welds
  measured off the edges, the columns arranged so welded consumers
  sit exactly k above their callees.
  """
  @spec of(Derivation.t(), Alloc.t(), Zkfol.Lang.shape(), [Rel.t()]) :: t()
  def of(%Derivation{facts: facts} = derivation, alloc, shape, members) do
    row = &(Alloc.offset(alloc, elem(&1, 0)) + elem(&1, 1))
    index = facts |> Enum.with_index() |> Map.new()
    fired = Consumption.fired(derivation, members, shape)

    consumption =
      Map.new(fired, fn {fact, ran} -> {fact, for({p, c} <- consumed(ran), do: {row.(p), c})} end)

    schedules = measured(consumption)
    position = facts |> arrange(consumption, schedules) |> Enum.with_index(1) |> Map.new()
    filled = for fact <- facts, do: filled(fact, Map.fetch!(fired, fact))

    %__MODULE__{
      shape: shape,
      alloc: alloc,
      derivation: derivation,
      columns: Enum.map(facts, &Map.fetch!(position, &1)),
      welds: Enum.sort(schedules),
      consumption:
        for fact <- facts do
          for {ptr, callee} <- Map.fetch!(consumption, fact), do: {ptr, Map.fetch!(index, callee)}
        end,
      slack: Enum.map(filled, &elem(&1, 0)),
      quot: Enum.map(filled, &elem(&1, 1))
    }
  end

  @doc """
  I am my matrix: each fact's tuple on its member's rows at its
  column, the tag row wearing its relation, each pointer holding the
  consumed column, each slack cell the room its guard left, each
  quotient cell what its reduction divided out, unread cells padding
  -- zero, or one on a pointer row, since an unread pointer still
  names a column. A cell unification left free reads zero.
  """
  @spec witness(t()) :: {:ok, Interpretation.t()} | {:error, Refusal.t()}
  def witness(%__MODULE__{alloc: alloc, shape: shape, derivation: derivation} = lay) do
    row = &(Alloc.offset(alloc, elem(&1, 0)) + elem(&1, 1))
    pointer_rows = pointer_rows(alloc, shape)
    slack_rows = region_rows(alloc, shape, :slack)
    quot_rows = region_rows(alloc, shape, :quot)

    columns =
      [derivation.facts, lay.consumption, lay.slack, lay.quot]
      |> Enum.zip()
      |> Enum.sort_by(fn {fact, _used, _spare, _quots} -> position_of(lay, fact) end)
      |> Enum.map(fn {{name, tuple} = _fact, used, spare, quots} ->
        cells = alloc |> Alloc.rows(name) |> Enum.zip(tuple) |> Map.new()

        cells =
          if shape.tags == %{},
            do: cells,
            else: Map.put(cells, row.({:tag, 1}), Map.fetch!(shape.tags, name))

        cells
        |> Map.merge(Map.new(used, fn {ptr, callee} -> {ptr, Enum.at(lay.columns, callee)} end))
        |> Map.merge(Map.new(Enum.zip(slack_rows, spare)))
        |> Map.merge(Map.new(Enum.zip(quot_rows, quots)))
      end)

    matrix =
      for r <- 1..Alloc.width(alloc) do
        for cells <- columns do
          cells
          |> Map.get(r, if(MapSet.member?(pointer_rows, r), do: 1, else: 0))
          |> Derivation.free_to_zero()
        end
      end

    with :ok <-
           Refusal.refute(
             List.flatten(matrix),
             &(&1 < 0),
             &{:witness_value_negative, %{value: &1}}
           ),
         do: Alloc.interpret(alloc, banks(matrix, alloc))
  end

  @doc """
  I am one arrow per consumption edge between laid columns: from the
  consumer's column to the consumed fact's, named by the pointer row
  it went through, wearing the weld k when the pointer welds.
  """
  @spec arrows(t()) :: [
          %{
            ptr: pos_integer(),
            from: pos_integer(),
            to: pos_integer(),
            to_row: pos_integer(),
            weld: pos_integer() | nil
          }
        ]
  def arrows(%__MODULE__{alloc: alloc, derivation: derivation} = lay) do
    schedules = Map.new(lay.welds)

    for {used, i} <- Enum.with_index(lay.consumption), {ptr, callee} <- used do
      %{
        ptr: ptr,
        from: Enum.at(lay.columns, i),
        to: Enum.at(lay.columns, callee),
        to_row: Alloc.offset(alloc, derivation.facts |> Enum.at(callee) |> elem(0)) + 1,
        weld: Map.get(schedules, ptr)
      }
    end
  end

  @doc """
  I am each pointer row beside the member entailing it: the caller,
  whose clause makes the call, so a viewer groups the pointer with
  the caller's bank while its label says the callee.
  """
  @spec aims(t()) :: [%{ptr: pos_integer(), member: atom()}]
  def aims(%__MODULE__{shape: %{pointers: []}}), do: []

  def aims(%__MODULE__{shape: shape, alloc: alloc}) do
    callers =
      for {name, per_clause} <- shape.calls, ptrs <- per_clause, {:ptr, n} <- ptrs, reduce: %{} do
        acc -> Map.put_new(acc, n, name)
      end

    for {row, i} <- Enum.with_index(Alloc.rows(alloc, :ptr), 1),
        member = callers[i],
        do: %{ptr: row, member: member}
  end

  @doc "I am the alloc's banks by name and absolute rows."
  @spec regions(t()) :: [%{name: atom(), first: pos_integer(), last: pos_integer()}]
  def regions(%__MODULE__{alloc: %Alloc{regions: regions} = alloc}) do
    for {name, _width} <- regions do
      rows = Alloc.rows(alloc, name)
      %{name: name, first: rows.first, last: rows.last}
    end
  end

  ############################################################
  #                   Private Implementation                 #
  ############################################################

  # What the fired clause consumed, on the pointers it went through.
  @spec consumed({Consumption.site(), [Derivation.fact()]} | nil) ::
          [{Zkfol.Ast.row_ref(), Derivation.fact()}]
  defp consumed(nil), do: []
  defp consumed({{_head, _body, ptrs}, used}), do: Enum.zip(ptrs, used)

  # What one fact left its committed banks to hold: the room each slack
  # site of the clause that fired leaves, and what each mod site
  # divided out. Both read where the clause bound its names -- the head
  # from the fact's own tuple, a call's outputs from the fact it
  # consumed.
  @spec filled(Derivation.fact(), {Consumption.site(), [Derivation.fact()]} | nil) ::
          {[integer()], [integer()]}
  defp filled(_fact, nil), do: {[], []}

  defp filled({_name, tuple}, {{head, body, _ptrs}, used}) do
    env = Map.merge(bound(head, tuple), returned(body, used))

    {for({op, t, u} <- Lang.slacks(body), do: gap(op, value(t, env), value(u, env))),
     for({_r, e, m} <- Lang.mods(body), do: div(value(e, env), m))}
  end

  # A head binds its variables to the fact's own tuple.
  @spec bound([term()], [term()]) :: %{atom() => integer()}
  defp bound(head, tuple) do
    Map.new(for {{:var, nm}, q} <- Enum.zip(head, tuple), do: {nm, Derivation.free_to_zero(q)})
  end

  # A call binds its outputs to the callee's tuple past the index.
  @spec returned([term()], [Derivation.fact()]) :: %{atom() => integer()}
  defp returned(body, used) do
    for({:call, _name, [_at | outs]} <- body, do: outs)
    |> Enum.zip(used)
    |> Enum.flat_map(fn {outs, {_name, tuple}} -> Enum.zip(outs, Enum.drop(tuple, 1)) end)
    |> Map.new(fn {{:var, nm}, q} -> {nm, Derivation.free_to_zero(q)} end)
  end

  @spec gap(atom(), integer(), integer()) :: integer()
  defp gap(:>, a, b), do: a - b - 1
  defp gap(:>=, a, b), do: a - b
  defp gap(:<, a, b), do: b - a - 1
  defp gap(:<=, a, b), do: b - a

  @spec value(term(), %{atom() => integer()}) :: integer()
  defp value(q, _env) when is_integer(q), do: q
  defp value({:var, nm}, env), do: Map.fetch!(env, nm)
  defp value({:add, t, u}, env), do: value(t, env) + value(u, env)
  defp value({:mul, t, u}, env), do: value(t, env) * value(u, env)

  @spec position_of(t(), Derivation.fact()) :: pos_integer()
  defp position_of(%__MODULE__{derivation: derivation} = lay, fact),
    do: Enum.at(lay.columns, Enum.find_index(derivation.facts, &(&1 == fact)))

  # The matrix cut along the regions it was laid on.
  @spec banks([[non_neg_integer()]], Alloc.t()) :: %{atom() => Interpretation.t()}
  defp banks(matrix, %Alloc{regions: regions} = alloc) do
    Map.new(regions, fn {name, width} ->
      {name, matrix |> Enum.slice(Alloc.offset(alloc, name), width) |> Interpretation.new()}
    end)
  end

  # An unread cell on a pointer row still names a column.
  @spec pointer_rows(Alloc.t(), Zkfol.Lang.shape()) :: MapSet.t()
  defp pointer_rows(_alloc, %{pointers: []}), do: MapSet.new()
  defp pointer_rows(alloc, _shape), do: alloc |> Alloc.rows(:ptr) |> MapSet.new()

  # A bank's rows in order, a clause's k-th site reading the k-th.
  @spec region_rows(Alloc.t(), Zkfol.Lang.shape(), atom()) :: [pos_integer()]
  defp region_rows(alloc, shape, sym) do
    if Map.get(shape, sym, 0) == 0, do: [], else: Enum.to_list(Alloc.rows(alloc, sym))
  end

  # A pointer welds when every consumption through it is the same
  # relation descending its first argument by one constant: measured
  # off the edges.
  @spec measured(%{Derivation.fact() => [{pos_integer(), Derivation.fact()}]}) ::
          %{pos_integer() => pos_integer()}
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

  @spec delta(Derivation.fact(), Derivation.fact()) :: integer() | nil
  defp delta({name, [ci | _]}, {name, [ui | _]}) when is_integer(ci) and is_integer(ui),
    do: ci - ui

  defp delta(_consumer, _callee), do: nil

  # A scheduled read welds its consumer exactly k above its callee;
  # the rest keeps callees below their callers.
  @spec arrange(
          [Derivation.fact()],
          %{Derivation.fact() => [{pos_integer(), Derivation.fact()}]},
          %{pos_integer() => pos_integer()}
        ) :: [Derivation.fact()]
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
  @spec walk(map(), Derivation.fact()) :: {Derivation.fact(), integer()}
  defp walk(forest, fact) do
    case forest do
      %{^fact => {parent, delta}} ->
        {root, above} = walk(forest, parent)
        {root, delta + above}

      _forest ->
        {fact, 0}
    end
  end
end

defimpl Inspect, for: Zkfol.Lay do
  import Inspect.Algebra

  def inspect(%Zkfol.Lay{} = lay, _opts) do
    welds = Enum.map_join(lay.welds, " ", fn {row, k} -> "C#{row} k=#{k}" end)

    regions =
      Enum.map_join(Zkfol.Lay.regions(lay), " ", fn %{name: name, first: first, last: last} ->
        "#{name}:#{first}-#{last}"
      end)

    concat([
      "#Zkfol.Lay<",
      "#{length(lay.columns)} columns · #{regions}",
      if(welds == "", do: "", else: " · welds " <> welds),
      ">"
    ])
  end
end
