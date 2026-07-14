defmodule Zkfol.Uair do
  @moduledoc """
  I translate a statement to a UAIR and prove it on Zinc+: Figure 2 over
  committed columns. The trace is reversed so pointer schedules become
  forward shifts, padded with base-case rows so the uniform constraint
  holds everywhere. Each read pointer row is committed and bound to its
  schedule inside every reading branch, so the old crossbar's pointer
  confinement survives in-circuit. Statements with non-affine pointers,
  ambiguous or forward schedules, or constants past the program's i64
  cells are refused with the reason, as is a witness that does not
  satisfy the scheduled statement.

  Claimed rows ride public columns: the verifier reads them in the
  clear, so the claim is checked, not trusted. The claimed value is
  derived from the witness, never supplied. Range checks stay with the
  oracle: the pinned zinc-plus leaves lookup groups unimplemented.

  Proving is asynchronous underneath: `request/1` queues the UAIR and
  returns an id, and the verdict arrives as `{:zinc_plus, id, result}`.

  ### Public API

  - `prove/3`, `emit/3`
  - `request/1`, `await/1`
  - `schedules/1`
  """

  import Bitwise

  alias Zkfol.Ast
  alias Zkfol.Enrich
  alias Zkfol.Interpretation
  alias Zkfol.Semantics
  alias Zkfol.ZincPlus

  # One addition of headroom under each cell width: narrow cells are i64,
  # wide cells 768 or 7040 bits, and values must be non-negative past i64, since
  # limbs carry no sign.
  @i64_bound Integer.pow(2, 62)
  @big_bound Integer.pow(2, 766)
  @huge_bound Integer.pow(2, 7038)

  @doc "I prove `pred` against `witness` on Zinc+ and return the report."
  @spec prove(Ast.pred(), Interpretation.t(), [Interpretation.claim()]) ::
          {:ok, map()} | {:error, String.t()}
  def prove(pred, witness, claims \\ []) do
    with {:ok, uair} <- emit(pred, witness, claims),
         {:ok, id} <- request(uair),
         {:ok, report} <- await(id) do
      {:ok, Map.put(report, :claims, uair.claims)}
    end
  end

  @doc "I queue the UAIR with the prover fitting its magnitude and return an id."
  @spec request(map()) :: {:ok, pos_integer()} | {:error, String.t()}
  def request(uair) do
    values = List.flatten(uair.columns)

    with :ok <- non_negative(values) do
      {prover, columns} =
        cond do
          Enum.any?(values, &(&1 >= @big_bound)) -> {&ZincPlus.prove_fol_huge/6, limbed(uair)}
          Enum.any?(values, &(&1 >= @i64_bound)) -> {&ZincPlus.prove_fol_big/6, limbed(uair)}
          true -> {&ZincPlus.prove_fol/6, uair.columns}
        end

      prover.(uair.num_cols, uair.num_public, uair.shifts, uair.program, columns, uair.num_vars)
    end
  end

  @doc "I await the verdict addressed to `id`."
  @spec await(pos_integer()) :: {:ok, map()} | {:error, String.t()}
  def await(id) do
    receive do
      {:zinc_plus, ^id, result} -> result
    end
  end

  # Wide cells transport as unsigned limbs, so a negative value has no
  # encoding: refused here rather than crashing the decode across the NIF.
  @spec non_negative([integer()]) :: :ok | {:error, String.t()}
  defp non_negative(values) do
    case Enum.find(values, &(&1 < 0)) do
      nil -> :ok
      value -> {:error, "witness value #{value} is negative; cells carry no sign"}
    end
  end

  # Values as little-endian base-2^64 digits, the wide cells' transport.
  @spec limbed(map()) :: [[[non_neg_integer()]]]
  defp limbed(uair),
    do:
      for(
        col <- uair.columns,
        do: for(v <- col, do: v |> Integer.digits(1 <<< 64) |> Enum.reverse())
      )

  @doc "I am the UAIR of the statement: columns, claimed rows first, shifts, program."
  @spec emit(Ast.pred(), Interpretation.t(), [Interpretation.claim()]) ::
          {:ok, map()} | {:error, String.t()}
  def emit(pred, witness, claims \\ []) do
    len = Interpretation.len(witness)
    # schedule calculates cells having a fixed relation backwords to a set previous column
    with {:ok, schedules} <- schedules(pred),
         pred = bind_pointers(pred, schedules),
         :ok <- scheduled?(pred, schedules),
         poly = Enrich.enrich(pred),
         refs = refs(poly, schedules),
         {:ok, resolved} <- resolve_claims(claims, witness),
         :ok <- models(pred, witness) do
      public = claims |> Enum.map(&elem(&1, 1)) |> Enum.uniq()
      %{rows: rows, cols: cols, shifts: shifts, down: down} = slots(refs, public)
      num_vars = max(ceil_log2(len), 3)
      x_col = if uses_x?(poly), do: map_size(cols)
      columns = columns(witness, rows, len, num_vars) ++ index_column(x_col, len, num_vars)
      program = compile(poly, len, {cols, x_col}, schedules, down)

      with :ok <- fits(columns),
           :ok <- constants_fit(program) do
        {:ok,
         %{
           num_cols: length(columns),
           num_public: length(public),
           claims: resolved,
           shifts: shifts,
           program: program,
           columns: columns,
           num_vars: num_vars
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

  @doc """
  I am the affine pointer schedules for the rows the predicate reads
  through: an index row constrained to a pointed index row plus a
  constant names the offset, a pointer bound to X declares its own,
  and a branch guarded eq(X, k) that pins a read row corroborates it.
  Ambiguity refuses: conflicting offsets and offsets that do not look
  back have no shift.
  """
  @spec schedules(Ast.pred()) ::
          {:ok, %{pos_integer() => pos_integer()}} | {:error, String.t()}
  def schedules(pred) do
    read = pred |> pointer_reads() |> Enum.uniq()

    # Relate cell i to itself in a different column/recursion
    syntax =
      pred
      |> Ast.branches()
      |> Enum.flat_map(&parts/1)
      |> Enum.flat_map(fn
        {:eq, {:cell, i}, {:add, {:cell, i, j}, k}} when is_integer(k) -> [{j, k}]
        {:eq, {:cell, i}, {:add, k, {:cell, i, j}}} when is_integer(k) -> [{j, k}]
        # A pointer bound to X by a constant declares its own schedule.
        {:eq, {:cell, j}, {:add, :x, k}} when is_integer(k) -> [{j, -k}]
        _part -> []
      end)

    # If we fix a computation at a column, we know more info about what m must be.
    # We note this as j may be a pointer
    pins =
      for branch <- Ast.branches(pred),
          parts = parts(branch),
          {:eq, :x, k} when is_integer(k) <- parts,
          {:eq, {:cell, j}, m} when is_integer(m) <- parts,
          # We simply note how many rows we must look
          do: {j, k - m}

    by_row =
      (syntax ++ pins)
      # Filter for pointer chases
      |> Enum.filter(fn {j, _} -> j in read end)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Map.new(fn {j, offsets} -> {j, Enum.uniq(offsets)} end)

    # A row with more than one offset demonstrates a conflict.
    case Enum.find(by_row, fn {_j, offsets} -> not match?([_], offsets) end) do
      nil ->
        {:ok,
         by_row
         |> Enum.filter(fn {_j, [offset]} -> offset > 0 end)
         |> Map.new(fn {j, [offset]} -> {j, offset} end)}

      {j, offsets} ->
        {:error, "pointer row #{j} has conflicting schedule offsets #{inspect(offsets)}"}
    end
  end

  # We pin the cells inside the conjunctions with the schedules we've found.
  # Meaning we add these constraints, if we confirm they are indeed there and
  # not already bound.
  @spec bind_pointers(Ast.pred(), %{pos_integer() => pos_integer()}) :: Ast.pred()
  defp bind_pointers(pred, schedules) do
    pred
    |> Ast.branches()
    |> Enum.map(fn branch ->
      parts = parts(branch)
      # Only a pin to a constant or an explicit X-binding already fixes
      # the row to its schedule; an equality to another cell does not,
      # and must not skip the binding.
      pinned =
        Enum.flat_map(parts, fn
          {:eq, {:cell, j}, m} when is_integer(m) -> [j]
          {:eq, {:cell, j}, {:add, :x, m}} when is_integer(m) -> [j]
          _part -> []
        end)

      bindings =
        for j <- branch |> pointer_reads() |> Enum.uniq() |> Enum.sort(),
            j not in pinned,
            is_map_key(schedules, j),
            do: Ast.eq(Ast.cell(j), Ast.add(Ast.x(), -Map.get(schedules, j)))

      Ast.conj(parts ++ bindings)
    end)
    |> Ast.disj()
  end

  @spec pointer_reads(Ast.pred()) :: [pos_integer()]
  defp pointer_reads(pred) do
    Ast.reduce(pred, [], fn
      {:cell, _i, j}, acc -> [j | acc]
      _node, acc -> acc
    end)
  end

  # A claim names a cell the verifier reads in the clear, so it must land
  # inside the witness. Validating a claim and resolving its value are the
  # same read, so I do both at once; an out-of-range claim refuses.
  @spec resolve_claims([Interpretation.claim()], Interpretation.t()) ::
          {:ok, [{String.t(), non_neg_integer()}]} | {:error, String.t()}
  defp resolve_claims(claims, witness) do
    Enum.reduce_while(claims, {:ok, []}, fn {name, row, x}, {:ok, acc} ->
      case Interpretation.fetch(witness, row, x) do
        {:ok, value} ->
          {:cont, {:ok, [{name, value} | acc]}}

        :error ->
          {:halt,
           {:error, "claim #{inspect(name)} names cell (#{row}, #{x}) outside the witness"}}
      end
    end)
    |> case do
      {:ok, resolved} -> {:ok, Enum.reverse(resolved)}
      error -> error
    end
  end

  # A witness that is no model of the scheduled statement is refused
  # before it reaches the prover, with the failing column as reason.
  @spec models(Ast.pred(), Interpretation.t()) :: :ok | {:error, String.t()}
  defp models(pred, witness) do
    case Enum.find(1..Interpretation.len(witness), &(not Semantics.holds?(pred, witness, &1))) do
      nil -> :ok
      x -> {:error, "the witness does not satisfy the scheduled statement at column #{x}"}
    end
  end

  defp parts({:conj, preds}), do: Enum.flat_map(preds, &parts/1)
  defp parts(pred), do: [pred]

  # The detector: every dereferenced pointer must have landed a schedule, else
  # the deref has no shift to lower to (and no lookup fallback at this zinc+ rev).
  @spec scheduled?(Ast.pred(), %{pos_integer() => pos_integer()}) :: :ok | {:error, String.t()}
  defp scheduled?(pred, schedules) do
    case pred |> pointer_reads() |> Enum.uniq() |> Enum.reject(&is_map_key(schedules, &1)) do
      [] -> :ok
      unscheduled -> {:error, "pointer rows #{inspect(unscheduled)} have no affine schedule"}
    end
  end

  # Every cell reference in the polynomial: {row, nil} direct, or {row, shift}
  # through a pointer, which scheduled?/2 has guaranteed carries an offset.
  @spec refs(Ast.ep(), %{pos_integer() => pos_integer()}) ::
          [{pos_integer(), pos_integer() | nil}]
  defp refs(poly, schedules) do
    Ast.reduce(poly, [], fn
      {:cell, i}, acc -> [{i, nil} | acc]
      {:cell, i, j}, acc -> [{i, Map.get(schedules, j)} | acc]
      _node, acc -> acc
    end)
  end

  # The polynomial as a postfix program over up and down references. postwalk is
  # bottom-up, so t and u arrive already compiled: RPN is left ++ right ++ op.
  # An ep has no reify, so the clauses below are the whole language.
  @spec compile(Ast.ep(), pos_integer(), {map(), non_neg_integer() | nil}, map(), map()) ::
          [{atom(), integer()}]
  defp compile(poly, len, {cols, x_col}, schedules, down) do
    Ast.postwalk(poly, fn
      q when is_integer(q) -> [{:const, q}]
      :len -> [{:const, len}]
      :x -> [{:up, x_col}]
      {:cell, i} -> [{:up, Map.get(cols, i)}]
      {:cell, i, j} -> [{:down, Map.get(down, {Map.get(cols, i), Map.get(schedules, j)})}]
      {tag, t, u} when tag in [:add, :mul] -> t ++ u ++ [{tag, 0}]
    end)
  end

  @spec uses_x?(Ast.ep()) :: boolean()
  defp uses_x?(poly) do
    Ast.reduce(poly, false, fn
      :x, _acc -> true
      _node, acc -> acc
    end)
  end

  @spec index_column(non_neg_integer() | nil, pos_integer(), pos_integer()) :: [[integer()]]
  defp index_column(nil, _len, _num_vars), do: []
  defp index_column(_col, len, num_vars), do: [padded(Enum.to_list(len..1//-1), 1, num_vars)]

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

  @spec fits([[integer()]]) :: :ok | {:error, String.t()}
  defp fits(columns) do
    case columns |> List.flatten() |> Enum.find(&(&1 >= @huge_bound or &1 < 0)) do
      nil -> :ok
      value -> {:error, "witness value #{value} does not fit 7040-bit cells"}
    end
  end

  @spec constants_fit([{atom(), integer()}]) :: :ok | {:error, String.t()}
  defp constants_fit(program) do
    case Enum.find(program, &match?({:const, k} when abs(k) >= @i64_bound, &1)) do
      nil -> :ok
      {:const, k} -> {:error, "predicate constant #{k} does not fit the program's i64 cells"}
    end
  end

  # The exact bit width: the smallest k with 2^k >= n, no float rounding.
  @spec ceil_log2(pos_integer()) :: non_neg_integer()
  defp ceil_log2(n) when n <= 1, do: 0
  defp ceil_log2(n), do: 1 + ceil_log2(div(n + 1, 2))
end
