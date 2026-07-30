defmodule Zkfol.Uair do
  @moduledoc """
  I translate a statement to a UAIR and prove it on zinc+: Figure 2 over
  committed columns. `emit/3` is the artifact, a `t/0`; `prove/3` journals
  an intent, hands the UAIR to `Zkfol.Prover`, and waits on the log for
  the verdict.

  The trace runs in reverse, so a pointer's schedule becomes a forward
  shift. A pointer with no schedule has no shift to become, and lowers
  through `Zkfol.Uair.Composed` instead, which emits but cannot yet prove.
  """

  use TypedStruct

  import Bitwise

  alias Zkfol.Ast
  alias Zkfol.Interpretation
  alias Zkfol.Log
  alias Zkfol.Prover
  alias Zkfol.Refusal
  alias Zkfol.Semantics
  alias Zkfol.Uair.Composed
  alias Zkfol.Uair.Lookup
  alias Zkfol.Uair.Plain
  alias Zkfol.ZincPlus

  @typedoc "A UAIR is plain, carries BitPoly lookups, or is a Section 4 lowering."
  @type mode :: Plain.t() | Lookup.t() | Composed.t()

  @typedoc "One composed read: where the address bits live and where the dereference lands."
  @type read :: %{
          value_row: non_neg_integer(),
          bit_rows: [non_neg_integer()],
          result_row: non_neg_integer()
        }

  @typedoc "A lookup: a Word table on a pointer row, or a BitPoly table on a shadow column."
  @type lookup ::
          %{row: non_neg_integer(), table: {:word, pos_integer()}}
          | %{col: non_neg_integer(), table: {:bit_poly, pos_integer(), pos_integer()}}

  typedstruct enforce: true do
    field(:num_public, non_neg_integer())
    # The trace length proper: padding rows pass for data.
    field(:len, pos_integer())
    field(:claims, [{String.t(), non_neg_integer()}], default: [])
    field(:shifts, [{non_neg_integer(), pos_integer()}])
    field(:program, [{atom(), integer()}])
    field(:columns, [[integer()]])
    field(:mode, mode(), default: %Plain{})
  end

  # One addition of headroom under each cell width: narrow cells are i64,
  # wide cells 768 or 7040 bits, and values must be non-negative past i64, since
  # limbs carry no sign.
  @i64_bound Integer.pow(2, 62)
  @big_bound Integer.pow(2, 766)
  @huge_bound Integer.pow(2, 7038)

  @doc "I am the committed column count: the columns themselves say it."
  @spec num_cols(t()) :: non_neg_integer()
  def num_cols(%__MODULE__{columns: columns}), do: length(columns)

  @doc "I am the cube's width: the smallest that covers `len`, never under three."
  @spec num_vars(t() | pos_integer()) :: pos_integer()
  def num_vars(%__MODULE__{len: len}), do: num_vars(len)
  def num_vars(len) when is_integer(len), do: max(ceil_log2(len), 3)

  @doc """
  I prove `pred` against `witness` and journal it: an intent, then the
  report observed, a `Zkfol.Prover.Report`. `opts` takes `:name`,
  `:basedon`, `:claims`. I return `{:ok, report, id}`.
  """
  @spec prove(Ast.pred(), Interpretation.t(), keyword()) ::
          {:ok, Prover.Report.t(), pos_integer()} | {:error, Refusal.t()}
  def prove(pred, witness, opts \\ []) do
    with {:ok, uair} <- emit(pred, witness, Keyword.get(opts, :claims, [])) do
      prove_uair(uair, opts)
    end
  end

  @doc """
  I prove an already-emitted `uair`, journaling it and awaiting it
  through the log. `opts` takes `:name`, `:basedon`, and `:timeout`
  (milliseconds or `:infinity`, one minute by default).
  """
  @spec prove_uair(t(), keyword()) ::
          {:ok, Prover.Report.t(), pos_integer()} | {:error, Refusal.t()}
  def prove_uair(uair, opts \\ []) do
    id = Log.push({:prove_requested, Keyword.get(opts, :name)}, Keyword.get(opts, :basedon))
    filter = [%Prover.Settled{intent: id}]
    EventBroker.subscribe_me(filter)

    try do
      with :ok <- Prover.run(uair, id, opts),
           do: settled(id, Keyword.get(opts, :timeout, 60_000))
    after
      EventBroker.unsubscribe_me(filter)
      drained(id)
    end
  end

  # I wait on the log for the observation that settles intent `id`;
  # only that intent, so a verdict lingering from an abandoned wait
  # can never be heard as this one.
  @spec settled(pos_integer(), timeout()) ::
          {:ok, Prover.Report.t(), pos_integer()} | {:error, Refusal.t()}
  defp settled(id, timeout) do
    receive do
      %EventBroker.Event{body: %Log.Event{basedon: ^id, body: {:proved, report}}} ->
        {:ok, report, id}

      %EventBroker.Event{body: %Log.Event{basedon: ^id, body: {:prove_failed, reason}}} ->
        {:error, reason}
    after
      timeout -> {:error, {:prover_timeout, %{intent: id}}}
    end
  end

  # Whatever the subscription delivered and nobody consumed, drop.
  @spec drained(pos_integer()) :: :ok
  defp drained(id) do
    receive do
      %EventBroker.Event{body: %Log.Event{basedon: ^id}} -> drained(id)
    after
      0 -> :ok
    end
  end

  @doc "I queue the UAIR with the prover fitting its magnitude and return an id."
  @spec request(t(), keyword()) :: {:ok, pos_integer()} | {:error, Refusal.t()}
  def request(%__MODULE__{} = uair, opts \\ []) do
    values = List.flatten(uair.columns)

    with {:ok, bins, lookups} <- mode_payload(uair.mode),
         :ok <- non_negative(values) do
      queued =
        ZincPlus.prove_fol(%ZincPlus.Payload{
          num_cols: num_cols(uair),
          num_public: uair.num_public,
          shifts: uair.shifts,
          program: uair.program,
          cells: cells(uair, values),
          bins: bins,
          lookups: lookups,
          num_vars: num_vars(uair),
          tamper: Keyword.get(opts, :tamper, false)
        })

      # The backend answers in prose either way; it is read into a
      # refusal here so no caller has to tell a rejected proof from a
      # malformed lookup by matching on text.
      with {:error, said} <- queued, do: {:error, Refusal.from_backend(said)}
    end
  end

  # The shadow columns and lookup tuples the mode owes the NIF, or the
  # refusal that keeps it away.
  @spec mode_payload(mode()) ::
          {:ok, [[non_neg_integer()]], [ZincPlus.lookup()]} | {:error, Refusal.t()}
  defp mode_payload(%Plain{}), do: {:ok, [], []}
  defp mode_payload(%Composed{}), do: Composed.refusal()

  defp mode_payload(%Lookup{bin_columns: bins} = lookup),
    do: with({:ok, tuples} <- Lookup.tuples(lookup), do: {:ok, bins, tuples})

  # The widest value decides the transport; the limbing stays on this side
  # of the NIF, so Rust only unpacks what it is handed.
  @spec cells(t(), [integer()]) :: ZincPlus.cells()
  defp cells(uair, values) do
    cond do
      Enum.any?(values, &(&1 >= @big_bound)) -> {:huge, limbed(uair)}
      Enum.any?(values, &(&1 >= @i64_bound)) -> {:big, limbed(uair)}
      true -> {:i64, uair.columns}
    end
  end

  # Unsigned limbs have no negative; refuse before the NIF decode crashes.
  @spec non_negative([integer()]) :: :ok | {:error, Refusal.t()}
  defp non_negative(values),
    do: Refusal.refute(values, &(&1 < 0), &{:witness_value_negative, %{value: &1}})

  # Values as little-endian base-2^64 digits, the wide cells' transport.
  @spec limbed(t()) :: [[[non_neg_integer()]]]
  defp limbed(uair),
    do:
      for(
        col <- uair.columns,
        do: for(v <- col, do: v |> Integer.digits(1 <<< 64) |> Enum.reverse())
      )

  @doc "I am the UAIR of the statement: columns, claimed rows first, shifts, program."
  @spec emit(Ast.pred(), Interpretation.t(), [Interpretation.claim()]) ::
          {:ok, t()} | {:error, Refusal.t()}
  def emit(pred, witness, claims \\ []) do
    len = Interpretation.len(witness)
    num_vars = num_vars(len)
    # schedule calculates cells having a fixed relation backwords to a set previous column
    with {:ok, schedules} <- Ast.schedules(pred),
         pred = Ast.bind_pointers(pred, schedules),
         {:ok, pred, witness, lowering} <- Composed.lower(pred, schedules, witness, num_vars),
         poly = Ast.arithmetize(pred),
         refs = refs(poly, schedules) ++ Enum.map(Composed.value_rows(lowering), &{&1, nil}),
         {:ok, resolved} <- resolve_claims(claims, witness),
         :ok <- models(pred, witness) do
      public = claims |> Enum.map(&elem(&1, 1)) |> Enum.uniq()
      %{rows: rows, cols: cols, shifts: shifts, down: down} = slots(refs, public)
      x_col = if uses_x?(poly), do: map_size(cols)
      program = poly |> resolve(len, {cols, x_col}, schedules, down) |> postfix()

      {shifts, program, columns} =
        index_pin(x_col, len, num_vars, shifts, program, columns(witness, rows, len, num_vars))

      with :ok <- fits(columns),
           :ok <- constants_fit(program) do
        {:ok,
         %__MODULE__{
           num_public: length(public),
           len: len,
           claims: resolved,
           shifts: shifts,
           program: program,
           columns: columns,
           mode: emitted_mode(lowering, cols, num_vars)
         }}
      end
    end
  end

  # Positional slots from the cell refs: which rows become columns, and
  # the {col, offset} shifts.
  @spec slots([{pos_integer(), pos_integer() | nil}], [pos_integer()]) :: map()
  defp slots(refs, public) do
    referenced = refs |> Enum.map(fn {row, _} -> row end) |> Enum.uniq() |> Enum.sort()
    rows = public ++ (referenced -- public)
    cols = rows |> Enum.with_index() |> Map.new()

    shifts =
      for {row, offset} <- refs, offset != nil, uniq: true, do: {Map.get(cols, row), offset}

    shifts = Enum.sort(shifts)
    down = shifts |> Enum.with_index() |> Map.new()
    %{rows: rows, cols: cols, shifts: shifts, down: down}
  end

  # Validate each claim by resolving its value; out of range refuses.
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

  # A witness that is no model of the scheduled statement is refused
  # before it reaches the prover, with the failing column as reason.
  @spec models(Ast.pred(), Interpretation.t()) :: :ok | {:error, Refusal.t()}
  defp models(pred, witness) do
    Refusal.refute(
      1..Interpretation.len(witness),
      &(not Semantics.holds?(pred, witness, &1)),
      &{:witness_unsatisfies_schedule, %{column: &1}}
    )
  end

  # A Section 4 lowering names its reads and the Word lookups it owes;
  # anything else emits plain. The lookup mode is put on by the caller
  # that shadows a column.
  @spec emitted_mode(Composed.lowering(), %{pos_integer() => non_neg_integer()}, pos_integer()) ::
          mode()
  defp emitted_mode(:plain, _cols, _mu), do: %Plain{}
  defp emitted_mode(lowering, cols, mu), do: Composed.emitted(lowering, cols, mu)

  # Every cell reference in the polynomial: {row, nil} direct, or {row, shift}
  # through a scheduled pointer; the lowering has rewritten the dynamic ones away.
  @spec refs(Ast.ep(), %{pos_integer() => pos_integer()}) ::
          [{pos_integer(), pos_integer() | nil}]
  defp refs(poly, schedules) do
    Ast.reduce(poly, [], fn
      {:cell, i}, acc -> [{i, nil} | acc]
      {:cell, i, j}, acc -> [{i, Map.get(schedules, j)} | acc]
      _node, acc -> acc
    end)
  end

  # ep leaves resolved to up/down references; integers and add/mul pass through.
  # The index pin shares `postfix`, so the two lowerings differ only in the leaf.
  @spec resolve(Ast.ep(), pos_integer(), {map(), non_neg_integer() | nil}, map(), map()) :: pin()
  defp resolve(poly, len, {cols, x_col}, schedules, down) do
    Ast.postwalk(poly, fn
      :len -> len
      :x -> {:up, x_col}
      {:cell, i} -> {:up, Map.get(cols, i)}
      {:cell, i, j} -> {:down, Map.get(down, {Map.get(cols, i), Map.get(schedules, j)})}
      node -> node
    end)
  end

  # A resolved polynomial as postfix: bottom-up RPN, left ++ right ++ op.
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

  # The pin's leaves are raw trace references; the algebra over them is the
  # same canonicalising one the predicate uses.
  @typep pin :: Ast.poly({:up, non_neg_integer()} | {:down, non_neg_integer()})

  # X is a free committed column: nothing ties it to the reversed column
  # number, so a forge that slides X reads the accumulator out at the wrong
  # row. When X is present I add it and pin it. A forced ones column (one on
  # every constrained row, and over the last row through its head shift by
  # rows - len + 1) is a region indicator: one over columns len..2, zero at
  # column one and the padding. The pins then hold X to a strict decrement
  # over the real columns and to one at the boundary, so every selector
  # reads at the true row.
  @spec index_pin(
          non_neg_integer() | nil,
          pos_integer(),
          pos_integer(),
          [{non_neg_integer(), pos_integer()}],
          [{atom(), integer()}],
          [[integer()]]
        ) :: {[{non_neg_integer(), pos_integer()}], [{atom(), integer()}], [[integer()]]}
  defp index_pin(nil, _len, _num_vars, shifts, program, columns), do: {shifts, program, columns}

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
      # X decrements by one over columns len..2 ...
      square(Ast.mul(region, sub(sub(x, {:down, x_step}), 1))),
      # ... and is one at column one and every padding row.
      square(Ast.mul(sub(1, region), sub(x, 1)))
    ]

    {shifts ++ [{x_col, 1}, {ones_col, 1}, {ones_col, head}],
     Enum.reduce(pins, program, fn pin, acc -> acc ++ postfix(pin) ++ [{:add, 0}] end),
     columns ++ [padded(Enum.to_list(len..1//-1), 1, num_vars), List.duplicate(1, rows)]}
  end

  # Built through Ast's canonicalising constructors, so the pin folds its
  # constants the way the predicate does; only the leaves differ.
  @spec sub(pin(), pin()) :: pin()
  defp sub(a, b), do: Ast.add(a, Ast.mul(b, -1))

  @spec square(pin()) :: pin()
  defp square(a), do: Ast.mul(a, a)

  # Reversed, padded with the base column so every padding row satisfies
  # a base branch.
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

  @spec fits([[integer()]]) :: :ok | {:error, Refusal.t()}
  defp fits(columns) do
    Refusal.refute(
      List.flatten(columns),
      &(&1 >= @huge_bound or &1 < 0),
      &{:value_exceeds_cell, %{value: &1}}
    )
  end

  @spec constants_fit([{atom(), integer()}]) :: :ok | {:error, Refusal.t()}
  defp constants_fit(program) do
    Refusal.refute(
      program,
      &match?({:const, k} when abs(k) >= @i64_bound, &1),
      fn {:const, k} -> {:constant_exceeds_cell, %{constant: k}} end
    )
  end

  # The exact bit width: the smallest k with 2^k >= n, no float rounding.
  @spec ceil_log2(pos_integer()) :: non_neg_integer()
  defp ceil_log2(n) when n <= 1, do: 0
  defp ceil_log2(n), do: 1 + ceil_log2(div(n + 1, 2))
end
