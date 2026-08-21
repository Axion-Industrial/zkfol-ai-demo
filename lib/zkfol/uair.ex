defmodule Zkfol.Uair do
  @moduledoc "I am the UAIR of a statement: Figure 2 over committed columns."

  use TypedStruct

  import Bitwise

  alias Zkfol.Ast
  alias Zkfol.Interpretation
  alias Zkfol.Refusal
  alias Zkfol.Semantics
  alias Zkfol.Uair.Composed
  alias Zkfol.Uair.Plain
  alias Zkfol.ZincPlus

  @typedoc "A UAIR is plain, or is a Section 4 lowering."
  @type mode :: Plain.t() | Composed.t()

  @typedoc "One composed read: where the address bits live and where the dereference lands."
  @type read :: %{
          row: non_neg_integer(),
          value_row: non_neg_integer(),
          bit_rows: [non_neg_integer()],
          result_row: non_neg_integer()
        }

  @typedoc """
  What a read is to the trace: a shift back, a pointer through a row, a tie to a named
  cell, or aimed at an address no shift reaches.
  """
  @type kind ::
          {:shift, non_neg_integer()}
          | :pointer
          | {:tie, {pos_integer(), pos_integer()}}
          | {:aimed, Ast.address()}

  @typedoc """
  A group as the selections it makes: its values, and the cells of each selection. A group
  at the running column makes one a column, so a forged presence at any column meets it.
  """
  @type stood :: {[integer()], [[{pos_integer(), pos_integer()}]]}

  @typedoc "One cell the statement fixes: its row, its column, and the row its value fills."
  @type tie :: {pos_integer(), pos_integer(), {:broadcast, pos_integer()}}

  # 32 bits in byte chunks, so width over chunk stays the power of two the backend takes.
  @word_width 32
  @word_chunk 8

  typedstruct enforce: true do
    field(:num_public, non_neg_integer())
    # The trace length proper: padding rows pass for data.
    field(:len, pos_integer())
    field(:claims, [{String.t(), non_neg_integer()}], default: [])
    field(:shifts, [{non_neg_integer(), pos_integer()}])
    field(:program, [{atom(), integer()}])
    field(:degree, non_neg_integer())
    field(:columns, [[integer()]])
    field(:mode, mode(), default: %Plain{})
    field(:rows, [pos_integer() | :x | :ones], default: [])
    field(:word_lookups, [ZincPlus.lookup()], default: [])
    field(:selected_lookups, [ZincPlus.Selected.t()], default: [])
    field(:point_ties, [ZincPlus.Tie.t()], default: [])
  end

  @doc "I am the committed column count: the columns themselves say it."
  @spec num_cols(t()) :: non_neg_integer()
  def num_cols(%__MODULE__{columns: columns}), do: length(columns)

  @doc "I am the cube's width: the smallest that covers `len`, never under three."
  @spec num_vars(t() | pos_integer()) :: pos_integer()
  def num_vars(%__MODULE__{len: len}), do: num_vars(len)
  def num_vars(len) when is_integer(len), do: max(ceil_log2(len), 3)

  @doc "I am the UAIR of the statement: columns, claimed rows first, shifts, program."
  @spec emit(Ast.pred(), Interpretation.t(), [Interpretation.claim()]) ::
          {:ok, t()} | {:error, Refusal.t()}
  def emit(pred, witness, claims \\ []) do
    public = claims |> Enum.map(&elem(&1, 1)) |> Enum.uniq()

    with :ok <- models(pred, witness),
         {pred, witness} = materialized(pred, witness),
         len = Interpretation.len(witness),
         num_vars = num_vars(len),
         {:ok, stood} <- stood(pred, len),
         witness = filled(witness, stood),
         naturals = natural_rows(pred),
         kind = &kind(&1, Interpretation.arity(witness), len),
         {pred, witness, ties} = addressed(stripped(pred), witness, kind, len),
         through = for({i, _address} = read <- reads(pred), kind.(read) == :pointer, do: i),
         {pred, witness, public} =
           twinned(pred, witness, public, through ++ rows(stood) ++ naturals),
         {:ok, pred, witness, lowering} <- Composed.lower(pred, witness, num_vars),
         poly = Ast.arithmetize(pred),
         unread =
           Composed.value_rows(lowering) ++
             naturals ++ rows(stood) ++ for({i, _c, _target} <- ties, do: i),
         refs = refs(poly, kind) ++ Enum.map(unread, &{&1, 0}),
         {:ok, resolved} <- resolve_claims(claims, witness),
         :ok <- models(pred, witness) do
      %{rows: rows, cols: cols, shifts: shifts, down: down} = slots(refs, public)
      origins = rows ++ if(uses_x?(poly), do: [:x, :ones], else: [])
      x_col = if uses_x?(poly), do: map_size(cols)
      program = poly |> resolve(len, {cols, x_col}, down, kind) |> postfix()

      {shifts, program, columns} =
        index_pin(x_col, len, num_vars, shifts, program, columns(witness, rows, len, num_vars))

      with :ok <- ZincPlus.fits(columns),
           :ok <- ZincPlus.constants_fit(program) do
        {:ok,
         %__MODULE__{
           num_public: length(public),
           len: len,
           claims: resolved,
           shifts: shifts,
           program: program,
           degree: Ast.degree(pred),
           columns: columns,
           mode: emitted_mode(lowering, cols),
           rows: origins,
           word_lookups:
             for i <- naturals ++ Composed.bounded_rows(lowering) do
               {Map.fetch!(cols, i), @word_width, @word_chunk}
             end,
           selected_lookups: selected(stood, cols, len),
           point_ties:
             for {i, c, {:broadcast, row}} <- ties do
               %ZincPlus.Tie{
                 column: Map.fetch!(cols, i),
                 row: len - c,
                 target: {:broadcast, Map.fetch!(cols, row)}
               }
             end
         }}
      end
    end
  end

  ############################################################
  #                      Reads and rows                      #
  ############################################################

  @spec kind(Ast.read(), pos_integer(), pos_integer()) :: kind()
  defp kind({_i, {:at, :x, 1, add}}, _arity, _len) when add <= 0, do: {:shift, -add}
  defp kind({_i, {:at, {:cell, _j}, 1, 0}}, _arity, _len), do: :pointer

  defp kind({i, {:at, _base, 0, c}}, arity, len) when i in 1..arity//1 and c in 1..len//1,
    do: {:tie, {i, c}}

  defp kind({_i, address}, _arity, _len), do: {:aimed, address}

  @spec reads(Ast.pred() | Ast.term_t()) :: [Ast.read()]
  defp reads(node) do
    node
    |> Ast.reduce([], fn n, acc -> if read = Ast.read(n), do: [read | acc], else: acc end)
    |> Enum.reverse()
  end

  # A value the polynomial cannot read in place gets a committed row of its own.
  @spec rowed(
          Ast.pred(),
          Interpretation.t(),
          [leaf],
          (leaf, pos_integer() -> integer()),
          (Ast.pred(), %{leaf => pos_integer()} -> Ast.pred())
        ) :: {Ast.pred(), Interpretation.t(), %{leaf => pos_integer()}}
        when leaf: var
  defp rowed(pred, witness, leaves, held, rewrite) do
    rows = leaves |> Enum.with_index(Interpretation.arity(witness) + 1) |> Map.new()
    stored = for leaf <- leaves, do: for(x <- 1..Interpretation.len(witness), do: held.(leaf, x))
    {rewrite.(pred, rows), Interpretation.new(Interpretation.rows(witness) ++ stored), rows}
  end

  # A naturality over an expression takes a row of its own, pinned beside the obligation.
  @spec materialized(Ast.pred(), Interpretation.t()) :: {Ast.pred(), Interpretation.t()}
  defp materialized(pred, witness) do
    terms = pred |> bounded() |> Enum.reject(&Ast.read/1)

    {pred, witness, _rows} =
      rowed(pred, witness, terms, &natural_value(&1, witness, &2), fn pred, rows ->
        Ast.postwalk(pred, fn
          {:natural, t} when is_map_key(rows, t) ->
            Ast.conj([Ast.eq(Ast.cell(rows[t]), t), Ast.natural(Ast.cell(rows[t]))])

          node ->
            node
        end)
      end)

    {pred, witness}
  end

  @spec natural_value(Ast.term_t(), Interpretation.t(), pos_integer()) :: non_neg_integer()
  defp natural_value(term, witness, x) do
    with v when is_integer(v) and v >= 0 <- Semantics.eval(term, witness, x),
         do: v,
         else: (_ -> 0)
  end

  @spec bounded(Ast.pred()) :: [Ast.term_t()]
  defp bounded(pred) do
    pred
    |> Ast.reduce([], fn
      {:natural, t}, acc -> [t | acc]
      _node, acc -> acc
    end)
    |> Enum.uniq()
  end

  # After `materialized/2` every bounded term names a read.
  @spec natural_rows(Ast.pred()) :: [pos_integer()]
  defp natural_rows(pred),
    do: pred |> bounded() |> Enum.map(&elem(Ast.read(&1), 0)) |> Enum.uniq() |> Enum.sort()

  # A tie's row holds the cell at every column; an aimed row the column, pinned by its branch.
  @spec addressed(Ast.pred(), Interpretation.t(), (Ast.read() -> kind()), pos_integer()) ::
          {Ast.pred(), Interpretation.t(), [tie()]}
  defp addressed(pred, witness, kind, len) do
    leaves =
      for(read <- reads(pred), {tag, _} = leaf <- [kind.(read)], tag in [:tie, :aimed], do: leaf)
      |> Enum.uniq()
      |> Enum.sort()

    {pred, witness, rows} =
      rowed(pred, witness, leaves, &held(&1, witness, &2, len), &readdressed(&1, &2, kind))

    {pred, witness, for({{:tie, {i, c}}, row} <- rows, do: {i, c, {:broadcast, row}})}
  end

  @spec held(kind(), Interpretation.t(), pos_integer(), pos_integer()) :: integer()
  defp held({:tie, {i, c}}, witness, _x, _len), do: Interpretation.at(witness, i, c)

  # The column an address names, held to the trace: off it, the edge.
  defp held({:aimed, address}, witness, x, len),
    do: address |> Semantics.column(witness, x) |> max(1) |> min(len)

  # A row is pinned only in the conjunction reading it: elsewhere its column may leave the trace.
  @spec readdressed(Ast.pred(), %{kind() => pos_integer()}, (Ast.read() -> kind())) ::
          Ast.pred()
  defp readdressed(pred, rows, kind) do
    taken = for {{:aimed, address}, row} <- rows, into: %{}, do: {row, address}

    Ast.postwalk(pred, fn
      {:conj, parts} ->
        {:conj, parts ++ pins(parts, taken)}

      node ->
        with {i, _address} = read <- Ast.read(node),
             leaf when is_map_key(rows, leaf) <- kind.(read) do
          rerouted(leaf, i, rows[leaf])
        else
          _reachable -> node
        end
    end)
  end

  @spec rerouted(kind(), pos_integer(), pos_integer()) :: Ast.term_t()
  defp rerouted({:tie, _cell}, _i, row), do: Ast.cell(row)
  defp rerouted({:aimed, _address}, i, row), do: Ast.cell(i, row)

  @spec pins([Ast.pred()], %{pos_integer() => Ast.address()}) :: [Ast.pred()]
  defp pins(parts, taken) do
    for part <- parts,
        not match?({tag, _preds} when tag in [:conj, :disj], part),
        {_i, {:at, {:cell, row}, _mul, _add}} <- reads(part),
        is_map_key(taken, row),
        uniq: true,
        do: Ast.eq(Ast.cell(row), Ast.naming(taken[row]))
  end

  # A claimed row a lookup or pointer touches hands its claim to a twin: those bind witness only.
  @spec twinned(Ast.pred(), Interpretation.t(), [pos_integer()], [pos_integer()]) ::
          {Ast.pred(), Interpretation.t(), [pos_integer()]}
  defp twinned(pred, witness, public, touched) do
    claimed = Enum.filter(public, &(&1 in touched))

    {pred, witness, twins} =
      rowed(pred, witness, claimed, &Interpretation.at(witness, &1, &2), &bonded/2)

    {pred, witness, Enum.map(public, &Map.get(twins, &1, &1))}
  end

  @spec bonded(Ast.pred(), %{pos_integer() => pos_integer()}) :: Ast.pred()
  defp bonded(pred, twins) when map_size(twins) == 0, do: pred

  defp bonded(pred, twins) do
    bonds = for {i, twin} <- twins, do: Ast.eq(Ast.cell(twin), Ast.cell(i))
    pred |> Ast.branches() |> Enum.map(&Ast.conj(Ast.conjuncts(&1) ++ bonds)) |> Ast.disj()
  end

  ############################################################
  #                          Groups                          #
  ############################################################

  @spec stood(Ast.pred(), pos_integer()) :: {:ok, [stood()]} | {:error, Refusal.t()}
  defp stood(pred, len) do
    Refusal.map(groups(pred), fn {cells, values} ->
      with {:ok, selections} <- Refusal.map(1..len, &standing(cells, &1, len)),
           do: {:ok, {values, Enum.uniq(selections)}}
    end)
  end

  @spec groups(Ast.pred()) :: [{[Ast.term_t()], [integer()]}]
  defp groups(pred) do
    pred
    |> Ast.reduce([], fn
      {:permutes, cells, values}, acc -> [{cells, values} | acc]
      _node, acc -> acc
    end)
    |> Enum.reverse()
    |> Enum.uniq()
  end

  # A selection is public structure, so its address is the column's own and inside the trace.
  @spec standing([Ast.term_t()], pos_integer(), pos_integer()) ::
          {:ok, [{pos_integer(), pos_integer()}]} | {:error, Refusal.t()}
  defp standing(cells, x, len) do
    Refusal.map(cells, fn cell ->
      case Ast.read(cell) do
        {i, {:at, :x, mul, add}} when (mul * x + add) in 1..len//1 -> {:ok, {i, mul * x + add}}
        _elsewhere -> {:error, {:selection_outside_trace, %{cell: cell, column: x}}}
      end
    end)
  end

  @spec rows([stood()]) :: [pos_integer()]
  defp rows(stood),
    do: for({_values, selections} <- stood, {i, _c} <- Enum.concat(selections), uniq: true, do: i)

  # A selection fails only where the group's branch does not answer; there its cells are padding.
  @spec filled(Interpretation.t(), [stood()]) :: Interpretation.t()
  defp filled(witness, stood) do
    fills =
      for {values, selections} <- stood,
          cells <- selections,
          Enum.sort(for {i, c} <- cells, do: Interpretation.at(witness, i, c)) !=
            Enum.sort(values),
          {cell, value} <- Enum.zip(cells, values),
          into: %{},
          do: {cell, value}

    Interpretation.new(
      for {row, i} <- Enum.with_index(Interpretation.rows(witness), 1) do
        for {held, c} <- Enum.with_index(row, 1), do: Map.get(fills, {i, c}, held)
      end
    )
  end

  # A cell stands at `len - c` of its column; a table is one group.
  @spec selected([stood()], %{pos_integer() => non_neg_integer()}, pos_integer()) ::
          [ZincPlus.Selected.t()]
  defp selected(stood, cols, len) do
    for {values, selections} <- Enum.group_by(stood, &elem(&1, 0), &elem(&1, 1)) do
      selections = Enum.concat(selections)
      columns = for({i, _c} <- Enum.concat(selections), uniq: true, do: cols[i]) |> Enum.sort()
      slots = columns |> Enum.with_index() |> Map.new()

      %ZincPlus.Selected{
        columns: columns,
        values: values,
        selections:
          for(cells <- selections, do: for({i, c} <- cells, do: {slots[cols[i]], len - c}))
      }
    end
  end

  @spec stripped(Ast.pred()) :: Ast.pred()
  defp stripped(pred) do
    Ast.postwalk(pred, fn
      {:conj, parts} -> {:conj, Enum.reject(parts, &obligation?/1)}
      node -> node
    end)
  end

  @spec obligation?(Ast.pred()) :: boolean()
  defp obligation?({:natural, _t}), do: true
  defp obligation?({:permutes, _rows, _values}), do: true
  defp obligation?(_pred), do: false

  @spec models(Ast.pred(), Interpretation.t()) :: :ok | {:error, Refusal.t()}
  defp models(pred, witness) do
    Refusal.refute(
      1..Interpretation.len(witness),
      &(not Semantics.holds?(pred, witness, &1)),
      &{:witness_unsatisfies_schedule, %{column: &1}}
    )
  end

  ############################################################
  #                        The program                       #
  ############################################################

  @spec slots([{pos_integer(), non_neg_integer()}], [pos_integer()]) :: map()
  defp slots(refs, public) do
    referenced = refs |> Enum.map(fn {row, _} -> row end) |> Enum.uniq() |> Enum.sort()
    rows = public ++ (referenced -- public)
    cols = rows |> Enum.with_index() |> Map.new()

    shifts =
      for {row, offset} <- refs, offset > 0, uniq: true, do: {Map.get(cols, row), offset}

    shifts = Enum.sort(shifts)
    down = shifts |> Enum.with_index() |> Map.new()
    %{rows: rows, cols: cols, shifts: shifts, down: down}
  end

  @spec resolve_claims([Interpretation.claim()], Interpretation.t()) ::
          {:ok, [{String.t(), non_neg_integer()}]} | {:error, Refusal.t()}
  defp resolve_claims(claims, witness) do
    Enum.reduce_while(claims, {:ok, []}, fn {name, row, x}, {:ok, acc} ->
      case Interpretation.fetch(witness, row, x) do
        {:ok, value} ->
          {:cont, {:ok, [{name, value} | acc]}}

        :error ->
          {:halt, {:error, {:claim_outside_witness, %{claim: name, row: row, column: x}}}}
      end
    end)
    |> case do
      {:ok, resolved} -> {:ok, Enum.reverse(resolved)}
      error -> error
    end
  end

  @spec emitted_mode(Composed.lowering(), %{pos_integer() => non_neg_integer()}) :: mode()
  defp emitted_mode(:plain, _cols), do: %Plain{}
  defp emitted_mode(lowering, cols), do: Composed.emitted(lowering, cols)

  # The pin's shift is zero-filled, so a forward read has no lowering.
  @spec refs(Ast.ep(), (Ast.read() -> kind())) :: [{pos_integer(), non_neg_integer()}]
  defp refs(poly, kind) do
    for {i, _address} = read <- reads(poly) do
      {:shift, k} = kind.(read)
      {i, k}
    end
  end

  @spec resolve(
          Ast.ep(),
          pos_integer(),
          {map(), non_neg_integer() | nil},
          map(),
          (Ast.read() -> kind())
        ) :: pin()
  defp resolve(poly, len, {cols, x_col}, down, kind) do
    Ast.postwalk(poly, fn
      :len ->
        len

      :x ->
        {:up, x_col}

      node ->
        with {i, _address} = read <- Ast.read(node),
             do: shifted(kind.(read), Map.get(cols, i), down),
             else: (nil -> node)
    end)
  end

  @spec shifted(kind(), non_neg_integer(), map()) :: pin()
  defp shifted({:shift, 0}, col, _down), do: {:up, col}
  defp shifted({:shift, k}, col, down), do: {:down, Map.get(down, {col, k})}

  @spec postfix(pin()) :: [{atom(), integer()}]
  defp postfix(k) when is_integer(k), do: [{:const, k}]
  defp postfix({:up, c}), do: [{:up, c}]
  defp postfix({:down, i}), do: [{:down, i}]
  defp postfix({:add, a, b}), do: postfix(a) ++ postfix(b) ++ [{:add, 0}]
  defp postfix({:mul, a, b}), do: postfix(a) ++ postfix(b) ++ [{:mul, 0}]

  @spec uses_x?(Ast.ep()) :: boolean()
  defp uses_x?(poly) do
    Ast.reduce(poly, false, fn
      :x, _acc -> true
      _node, acc -> acc
    end)
  end

  @typep pin :: Ast.poly({:up, non_neg_integer()} | {:down, non_neg_integer()})

  # X is a free committed column; the pins stop a forge sliding it.
  @spec index_pin(
          non_neg_integer() | nil,
          pos_integer(),
          pos_integer(),
          [{non_neg_integer(), pos_integer()}],
          [{atom(), integer()}],
          [[integer()]]
        ) :: {[{non_neg_integer(), pos_integer()}], [{atom(), integer()}], [[integer()]]}
  defp index_pin(nil, _len, _num_vars, shifts, program, columns), do: {shifts, program, columns}

  # One column is no region: X is one at every row.
  defp index_pin(x_col, 1, num_vars, shifts, program, columns) do
    {shifts, program ++ postfix(square(sub({:up, x_col}, 1))) ++ [{:add, 0}],
     columns ++ [List.duplicate(1, 1 <<< num_vars)]}
  end

  defp index_pin(x_col, len, num_vars, shifts, program, columns) do
    rows = 1 <<< num_vars
    ones_col = x_col + 1
    head = rows - len + 1
    # The three new shifts sort last, after every witness-column shift.
    x_step = length(shifts)
    ones_step = x_step + 1
    ones_head = x_step + 2

    x = {:up, x_col}
    ones = {:up, ones_col}
    region = {:down, ones_head}

    pins = [
      # ones is one on every constrained row, and constant so its last
      # row, which the head shift reads, is one too.
      square(sub(ones, 1)),
      square(sub(ones, {:down, ones_step})),
      square(Ast.mul(region, sub(sub(x, {:down, x_step}), 1))),
      square(Ast.mul(sub(1, region), sub(x, 1)))
    ]

    {shifts ++ [{x_col, 1}, {ones_col, 1}, {ones_col, head}],
     Enum.reduce(pins, program, fn pin, acc -> acc ++ postfix(pin) ++ [{:add, 0}] end),
     columns ++ [padded(Enum.to_list(len..1//-1), 1, num_vars), List.duplicate(1, rows)]}
  end

  @spec sub(pin(), pin()) :: pin()
  defp sub(a, b), do: Ast.add(a, Ast.mul(b, -1))

  @spec square(pin()) :: pin()
  defp square(a), do: Ast.mul(a, a)

  # Padded with the base column so every padding row satisfies a base branch.
  @spec columns(Interpretation.t(), [pos_integer()], pos_integer(), pos_integer()) ::
          [[non_neg_integer()]]
  defp columns(witness, rows, len, num_vars) do
    for i <- rows do
      values = for x <- len..1//-1, do: Interpretation.at(witness, i, x)
      padded(values, Interpretation.at(witness, i, 1), num_vars)
    end
  end

  @spec padded([integer()], integer(), pos_integer()) :: [integer()]
  defp padded(values, base, num_vars),
    do: values ++ List.duplicate(base, (1 <<< num_vars) - length(values))

  # Integer-only, so no float rounding decides the width.
  @spec ceil_log2(pos_integer()) :: non_neg_integer()
  defp ceil_log2(n) when n <= 1, do: 0
  defp ceil_log2(n), do: 1 + ceil_log2(div(n + 1, 2))
end
