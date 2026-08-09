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

  Everything cross-position is index-form, the i-th entry speaking of
  the derivation's i-th fact, so I ride the bridge whole. Reading me:
  `columns` says which trace column the i-th fact was dealt onto;
  `consumption` says, per fact, `{ptr_row, callee_index}`: it
  consumed the callee-th fact through that committed pointer row;
  `slack` says, per fact, the room its fired clause's guards left,
  the k-th entry what the k-th slack row holds at that fact's column,
  a clause with fewer guards saying less and the rest padding;
  `quot` says the same of its reductions, the k-th entry the quotient
  the k-th mod site divided out;
  `welds` says `{ptr_row, k}`: every consumption through that row
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

  alias Zkfol.Alloc
  alias Zkfol.Derivation
  alias Zkfol.Interpretation
  alias Zkfol.Lang
  alias Zkfol.Lang.Rel
  alias Zkfol.Refusal

  @typep site :: {[term()], [term()], [Zkfol.Ast.row_ref()]}

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
  sit exactly k above their callees. The derivation names the clause
  each fact fired, so its site is a lookup.
  """
  @spec of(Derivation.t(), Alloc.t(), Zkfol.Lang.shape(), [Rel.t()]) :: t()
  def of(
        %Derivation{facts: facts, edges: edges, clauses: clauses} = derivation,
        alloc,
        shape,
        members
      ) do
    arr = List.to_tuple(facts)
    sites = sites(members, shape)

    fired =
      Enum.zip_with(facts, clauses, fn {name, _tuple}, clause ->
        sites |> Map.fetch!(name) |> Enum.at(clause)
      end)

    consumption =
      Enum.zip_with(fired, edges, fn {_head, _body, ptrs}, callees ->
        for {p, callee} <- Enum.zip(ptrs, callees), do: {row(alloc, p), callee}
      end)

    schedules = measured(consumption, arr)

    filled =
      Enum.zip_with([facts, fired, edges], fn [fact, site, callees] ->
        filled(fact, site, for(i <- callees, do: elem(arr, i)))
      end)

    %__MODULE__{
      shape: shape,
      alloc: alloc,
      derivation: derivation,
      columns: arrange(consumption, schedules),
      welds: Enum.sort(schedules),
      consumption: consumption,
      slack: Enum.map(filled, &elem(&1, 0)),
      quot: Enum.map(filled, &elem(&1, 1))
    }
  end

  @doc """
  I am my matrix: each fact's tuple on its member's rows at its
  column, the tag row wearing its relation, each pointer holding the
  consumed column, each slack cell the room its guard left, each
  quotient cell what its reduction divided out. An unread cell pads
  zero, or one on a pointer row, since an unread pointer still names
  a column. A cell unification left free reads zero.
  """
  @spec witness(t()) :: {:ok, Interpretation.t()} | {:error, Refusal.t()}
  def witness(%__MODULE__{alloc: alloc, shape: shape, derivation: derivation} = lay) do
    pointer_rows = pointer_rows(alloc, shape)
    slack_rows = region_rows(alloc, shape, :slack)
    quot_rows = region_rows(alloc, shape, :quot)
    placed = List.to_tuple(lay.columns)

    columns =
      [derivation.facts, lay.consumption, lay.slack, lay.quot, lay.columns]
      |> Enum.zip()
      |> Enum.sort_by(fn {_fact, _used, _spare, _quots, column} -> column end)
      |> Enum.map(fn {{name, tuple}, used, spare, quots, _column} ->
        cells = alloc |> Alloc.rows(name) |> Enum.zip(tuple) |> Map.new()

        cells =
          if shape.tags == %{},
            do: cells,
            else: Map.put(cells, row(alloc, {:tag, 1}), Map.fetch!(shape.tags, name))

        cells
        |> Map.merge(Map.new(used, fn {ptr, callee} -> {ptr, elem(placed, callee)} end))
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
    placed = List.to_tuple(lay.columns)
    facts = List.to_tuple(derivation.facts)

    for {used, i} <- Enum.with_index(lay.consumption), {ptr, callee} <- used do
      %{
        ptr: ptr,
        from: elem(placed, i),
        to: elem(placed, callee),
        to_row: Alloc.offset(alloc, facts |> elem(callee) |> elem(0)) + 1,
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

  # Each member's clauses as call sites, its calls' pointer names in
  # body order, so the clause the derivation names indexes into them.
  @spec sites([Rel.t()], Zkfol.Lang.shape()) :: %{atom() => [site()]}
  defp sites(members, shape) do
    Map.new(members, fn rel ->
      {rel.name,
       rel.clauses
       |> Enum.zip(Map.fetch!(shape.calls, rel.name))
       |> Enum.map(fn {{head, body}, ptrs} -> {head, body, ptrs} end)}
    end)
  end

  # What one fact left its committed banks to hold: the room each slack
  # site of the clause that fired leaves, and what each mod site
  # divided out, read where that clause bound its names.
  @spec filled(Derivation.fact(), site(), [Derivation.fact()]) :: {[integer()], [integer()]}
  defp filled({_name, tuple}, {_head, body, _ptrs} = site, used) do
    env = env(site, tuple, used)

    {for({op, t, u} <- Lang.slacks(body), do: gap(op, ground(t, env), ground(u, env))),
     for({_r, e, m} <- Lang.mods(body), do: div(ground(e, env), m))}
  end

  # Where the fired clause bound its names: the head against the fact's
  # own tuple, each call's outputs against the tuple it consumed past
  # the index.
  @spec env(site(), [term()], [Derivation.fact()]) :: %{atom() => term()}
  defp env({head, body, _ptrs}, tuple, used) do
    outputs =
      for({:call, _name, [_at | outs]} <- body, do: outs)
      |> Enum.zip(used)
      |> Enum.flat_map(fn {outs, {_name, consumed}} -> Enum.zip(outs, Enum.drop(consumed, 1)) end)

    Map.merge(
      Map.new(for {{:var, nm}, q} <- Enum.zip(head, tuple), do: {nm, Derivation.free_to_zero(q)}),
      Map.new(outputs, fn {{:var, nm}, q} -> {nm, Derivation.free_to_zero(q)} end)
    )
  end

  # A site the placement fills is ground: the clause fired on it.
  @spec ground(term(), %{atom() => term()}) :: integer()
  defp ground(term, env) do
    {:ok, q} = Lang.value(term, env)
    q
  end

  @spec gap(atom(), integer(), integer()) :: integer()
  defp gap(:>, a, b), do: a - b - 1
  defp gap(:>=, a, b), do: a - b
  defp gap(:<, a, b), do: b - a - 1
  defp gap(:<=, a, b), do: b - a

  # The absolute row a {symbol, offset} reference lands on.
  @spec row(Alloc.t(), {atom(), pos_integer()}) :: pos_integer()
  defp row(alloc, {sym, i}), do: Alloc.offset(alloc, sym) + i

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
  @spec measured([[{pos_integer(), non_neg_integer()}]], tuple()) ::
          %{pos_integer() => pos_integer()}
  defp measured(consumption, facts) do
    consumption
    |> Enum.with_index()
    |> Enum.flat_map(fn {used, i} ->
      for {ptr, callee} <- used, do: {ptr, i, callee}
    end)
    |> Enum.group_by(&elem(&1, 0), fn {_ptr, i, j} -> delta(elem(facts, i), elem(facts, j)) end)
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
  # the rest keeps callees below their callers. The i-th answer is the
  # i-th fact's column.
  @spec arrange([[{pos_integer(), non_neg_integer()}]], %{pos_integer() => pos_integer()}) ::
          [pos_integer()]
  defp arrange(consumption, schedules) do
    forest =
      Map.new(
        for {used, i} <- Enum.with_index(consumption),
            {ptr, callee} <- used,
            k = Map.get(schedules, ptr),
            is_integer(k),
            do: {callee, {i, -k}}
      )

    {walked, _seen} =
      Enum.map_reduce(0..(length(consumption) - 1)//1, %{}, fn i, seen ->
        {place, seen} = walk(forest, i, seen)
        {{place, i}, seen}
      end)

    roots = for {{root, _delta}, _i} <- walked, uniq: true, do: root
    grouped = Enum.group_by(walked, fn {{root, _delta}, _i} -> root end)

    position =
      roots
      |> Enum.flat_map(fn root ->
        grouped |> Map.fetch!(root) |> Enum.sort_by(fn {{_root, delta}, _i} -> delta end)
      end)
      |> Enum.with_index(1)
      |> Map.new(fn {{_place, i}, column} -> {i, column} end)

    Enum.map(0..(length(consumption) - 1)//1, &Map.fetch!(position, &1))
  end

  # pos(i) = pos(root) + delta, the forest carrying the deltas and
  # `seen` each place once, so a chain walks its length, not its
  # square.
  @spec walk(map(), non_neg_integer(), map()) ::
          {{non_neg_integer(), integer()}, map()}
  defp walk(forest, i, seen) do
    case seen do
      %{^i => place} ->
        {place, seen}

      _seen ->
        case forest do
          %{^i => {parent, delta}} ->
            {{root, above}, seen} = walk(forest, parent, seen)
            place = {root, delta + above}
            {place, Map.put(seen, i, place)}

          _forest ->
            {{i, 0}, seen}
        end
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
