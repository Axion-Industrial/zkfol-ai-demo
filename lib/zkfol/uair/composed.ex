defmodule Zkfol.Uair.Composed do
  @moduledoc """
  I am Section 4's lowering and the mode it leaves behind. A pointer with
  no schedule cannot become a shift, so `lower/4` spells it out in mu bit
  rows, hands every deref through it a result row to read instead, and
  constrains the bits to reconstruct the pointer on every branch. Every
  row I add derives from the witness, so the oracle stays the judge.

  `emitted/2` then names those rows in committed-column coordinates,
  which is what zinc+'s pointer query binds. The bits spell the cube
  index of the address, `len - a(x)`, so the committed columns'
  reversed layout reads directly: result(x) = value at the spelled
  position.
  """

  use TypedStruct

  import Bitwise

  alias Zkfol.Ast
  alias Zkfol.Interpretation
  alias Zkfol.Refusal
  alias Zkfol.Uair

  typedstruct enforce: true do
    field(:reads, [Uair.read()], default: [])
  end

  @typedoc "What the lowering derived, or `:plain` when there was nothing to lower."
  @type lowering ::
          :plain
          | %{
              dynamic: [pos_integer()],
              bits: %{pos_integer() => [pos_integer()]},
              pairs: [{pos_integer(), pos_integer()}],
              results: %{{pos_integer(), pos_integer()} => pos_integer()}
            }

  @doc """
  I lower every pointer `schedules` left unscheduled: mu bit rows apiece,
  a result row per deref rewritten into the predicate, and the witness
  extended to carry both.
  """
  @spec lower(Ast.pred(), %{pos_integer() => pos_integer()}, Interpretation.t(), pos_integer()) ::
          {:ok, Ast.pred(), Interpretation.t(), lowering()} | {:error, Refusal.t()}
  def lower(pred, schedules, witness, mu) do
    case pred |> Ast.pointer_reads() |> Enum.reject(&is_map_key(schedules, &1)) do
      [] ->
        {:ok, pred, witness, :plain}

      dynamic ->
        pairs = Enum.filter(Ast.pointer_derefs(pred), fn {_i, j} -> j in dynamic end)

        with :ok <- admits(pairs, witness) do
          arity = Interpretation.arity(witness)

          bits =
            dynamic
            |> Enum.with_index()
            |> Map.new(fn {a, k} -> {a, Enum.map(1..mu, &(arity + k * mu + &1))} end)

          results = pairs |> Enum.with_index(arity + length(dynamic) * mu + 1) |> Map.new()

          {:ok, rewrite(pred, constraints(dynamic, bits, Interpretation.len(witness)), results),
           extend(witness, dynamic, pairs, mu),
           %{dynamic: dynamic, bits: bits, pairs: pairs, results: results}}
        end
    end
  end

  @doc """
  I am the value rows the pointer query will bind. `lower/4` rewrote each
  deref into a read of its result row, so the predicate no longer mentions
  these, and only I can ask for them to stay committed.
  """
  @spec value_rows(lowering()) :: [pos_integer()]
  def value_rows(:plain), do: []
  def value_rows(lowering), do: Enum.map(lowering.pairs, &elem(&1, 0))

  @doc "I name the lowering's rows in committed-column coordinates."
  @spec emitted(map(), %{pos_integer() => non_neg_integer()}) :: t()
  def emitted(lowering, cols), do: %__MODULE__{reads: reads(lowering, cols)}

  @doc """
  I am the rows Definition 3.1(2) bounds: the bits hold a pointer under `len`, the Word
  table over these rows holds it above zero.
  """
  @spec pointer_rows(lowering()) :: [pos_integer()]
  def pointer_rows(:plain), do: []
  def pointer_rows(lowering), do: lowering.dynamic

  # Holds that the pairs can be lowered against the witness at all:
  # every row they name exists, and every pointer row holds column
  # indices. The order is load-bearing, since asking whether a row is
  # confined reads it.
  @spec admits([{pos_integer(), pos_integer()}], Interpretation.t()) ::
          :ok | {:error, Refusal.t()}
  defp admits(pairs, witness) do
    with :ok <- inside(pairs, witness), do: confined(pairs, witness)
  end

  # The constraints spelling the source out in rows: each row holds a
  # bit, and their weighted sum reconstructs it.
  @spec spelled([pos_integer()], Ast.term_t()) :: [Ast.pred()]
  defp spelled(rows, source) do
    booleanity = for b <- rows, do: Ast.eq(Ast.mul(Ast.cell(b), Ast.cell(b)), Ast.cell(b))

    weighted =
      rows
      |> Enum.with_index()
      |> Enum.map(fn {b, nu} -> Ast.mul(Ast.cell(b), 1 <<< nu) end)

    booleanity ++ [Ast.eq(source, Enum.reduce(weighted, &Ast.add(&2, &1)))]
  end

  # Rows the lowering derives from must exist before it derives.
  @spec inside([{pos_integer(), pos_integer()}], Interpretation.t()) ::
          :ok | {:error, Refusal.t()}
  defp inside(pairs, witness) do
    Refusal.refute(
      pairs |> Enum.flat_map(&Tuple.to_list/1) |> Enum.uniq(),
      &(&1 > Interpretation.arity(witness)),
      &{:read_row_outside_witness, %{row: &1}}
    )
  end

  # Definition 3.1(2): a dynamic pointer holds column indices, the oracle judging.
  @spec confined([{pos_integer(), pos_integer()}], Interpretation.t()) ::
          :ok | {:error, Refusal.t()}
  defp confined(pairs, witness) do
    Refusal.refute(
      pairs |> Enum.map(&elem(&1, 1)) |> Enum.uniq(),
      fn a ->
        len = Interpretation.len(witness)
        witness |> Interpretation.rows() |> Enum.at(a - 1) |> Enum.any?(&(&1 not in 1..len))
      end,
      &{:pointer_row_outside_matrix, %{row: &1}}
    )
  end

  # Booleanity, reconstruction, and region per pointer, riding every
  # branch. The bits bound the address to the cube; the region product
  # bounds it to 1..len, where the derivation's columns actually are.
  @spec constraints([pos_integer()], %{pos_integer() => [pos_integer()]}, pos_integer()) ::
          [Ast.pred()]
  defp constraints(dynamic, bits, len) do
    Enum.flat_map(dynamic, fn a ->
      cube_index = Ast.add(Ast.len(), Ast.mul(Ast.cell(a), -1))
      spelled(Map.fetch!(bits, a), cube_index) ++ [in_region(a, len)]
    end)
  end

  # A pointer cell is a real column: it vanishes at some 1..len and
  # nowhere else, so no address reaches the padding the cube admits.
  @spec in_region(pos_integer(), pos_integer()) :: Ast.pred()
  defp in_region(a, len) do
    product =
      1..len
      |> Enum.map(&Ast.add(Ast.cell(a), -&1))
      |> Enum.reduce(&Ast.mul(&2, &1))

    Ast.eq(product, 0)
  end

  # Each dynamic deref becomes a plain read of its result row, and the bit
  # constraints ride every branch the way the scheduled bindings ride theirs.
  @spec rewrite(Ast.pred(), [Ast.pred()], %{{pos_integer(), pos_integer()} => pos_integer()}) ::
          Ast.pred()
  defp rewrite(pred, constraints, results) do
    pred
    |> Ast.branches()
    |> Enum.map(fn branch ->
      parts =
        branch
        |> Ast.postwalk(fn
          {:cell, i, j} when is_map_key(results, {i, j}) -> Ast.cell(Map.fetch!(results, {i, j}))
          node -> node
        end)
        |> Ast.conjuncts()

      Ast.conj(parts ++ constraints)
    end)
    |> Ast.disj()
  end

  # The derived rows: bits of each pointer, then one deref per pair.
  @spec extend(
          Interpretation.t(),
          [pos_integer()],
          [{pos_integer(), pos_integer()}],
          pos_integer()
        ) :: Interpretation.t()
  defp extend(witness, dynamic, pairs, mu) do
    len = Interpretation.len(witness)

    bit_rows =
      for a <- dynamic, nu <- 1..mu do
        for x <- 1..len, do: (len - Interpretation.at(witness, a, x)) |> bsr(nu - 1) |> band(1)
      end

    result_rows =
      for {i, a} <- pairs do
        for x <- 1..len, do: Interpretation.at(witness, i, Interpretation.at(witness, a, x))
      end

    Interpretation.new(Interpretation.rows(witness) ++ bit_rows ++ result_rows)
  end

  # The emitted coordinates of each composed read: what the pointer query will bind.
  @spec reads(map(), %{pos_integer() => non_neg_integer()}) :: [Uair.read()]
  defp reads(lowering, cols) do
    for {i, a} <- lowering.pairs do
      %{
        row: Map.fetch!(cols, a),
        value_row: Map.fetch!(cols, i),
        bit_rows: Enum.map(Map.fetch!(lowering.bits, a), &Map.fetch!(cols, &1)),
        result_row: Map.fetch!(cols, Map.fetch!(lowering.results, {i, a}))
      }
    end
  end
end
