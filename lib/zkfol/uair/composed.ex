defmodule Zkfol.Uair.Composed do
  @moduledoc """
  I am Section 4's lowering and the mode it leaves behind.
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
              lower: %{pos_integer() => pos_integer()},
              pairs: [{pos_integer(), pos_integer()}],
              results: %{{pos_integer(), pos_integer()} => pos_integer()}
            }

  @doc "I lower every pointer read: mu bit rows apiece, a result row per deref, on the witness."
  @spec lower(Ast.pred(), Interpretation.t(), pos_integer()) ::
          {:ok, Ast.pred(), Interpretation.t(), lowering()} | {:error, Refusal.t()}
  def lower(pred, witness, mu) do
    case Ast.pointer_reads(pred) do
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

          lower = Map.new(Enum.with_index(dynamic, arity + length(dynamic) * mu + 1))
          results = Map.new(Enum.with_index(pairs, arity + length(dynamic) * (mu + 1) + 1))

          {:ok, rewrite(pred, constraints(dynamic, bits, lower), results),
           extend(witness, dynamic, pairs, mu),
           %{dynamic: dynamic, bits: bits, lower: lower, pairs: pairs, results: results}}
        end
    end
  end

  @doc "I am the value rows the pointer query binds, unmentioned by the predicate."
  @spec value_rows(lowering()) :: [pos_integer()]
  def value_rows(:plain), do: []
  def value_rows(lowering), do: Enum.map(lowering.pairs, &elem(&1, 0))

  @doc "I name the lowering's rows in committed-column coordinates."
  @spec emitted(map(), %{pos_integer() => non_neg_integer()}) :: t()
  def emitted(lowering, cols), do: %__MODULE__{reads: reads(lowering, cols)}

  @doc """
  I name the Word-bounded rows: pointers and their lower-bound slacks. The bits
  spell `len - pointer`; the slack spells `pointer - 1`. Bounding the pointer
  itself also retains its Word bound at the backend’s exempt final row.
  """
  @spec bounded_rows(lowering()) :: [pos_integer()]
  def bounded_rows(:plain), do: []

  def bounded_rows(lowering),
    do: lowering.dynamic ++ Enum.map(lowering.dynamic, &Map.fetch!(lowering.lower, &1))

  # The order is load-bearing: asking whether a row is confined reads it.
  @spec admits([{pos_integer(), pos_integer()}], Interpretation.t()) ::
          :ok | {:error, Refusal.t()}
  defp admits(pairs, witness) do
    with :ok <- inside(pairs, witness), do: confined(pairs, witness)
  end

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

  # Definition 3.1(2): a dynamic pointer holds column indices.
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

  @spec constraints([pos_integer()], %{pos_integer() => [pos_integer()]}, map()) ::
          [Ast.pred()]
  defp constraints(dynamic, bits, lower) do
    Enum.flat_map(dynamic, fn a ->
      cube_index = Ast.add(Ast.len(), Ast.mul(Ast.cell(a), -1))

      spelled(Map.fetch!(bits, a), cube_index) ++
        [Ast.eq(Ast.cell(Map.fetch!(lower, a)), Ast.add(Ast.cell(a), -1))]
    end)
  end

  @spec rewrite(Ast.pred(), [Ast.pred()], %{{pos_integer(), pos_integer()} => pos_integer()}) ::
          Ast.pred()
  defp rewrite(pred, constraints, results) do
    pred
    |> Ast.branches()
    |> Enum.map(fn branch ->
      parts =
        branch
        |> Ast.postwalk(fn node ->
          case Ast.read(node) do
            {i, {:at, {:cell, j}, 1, 0}} when is_map_key(results, {i, j}) ->
              Ast.cell(results[{i, j}])

            _other ->
              node
          end
        end)
        |> Ast.conjuncts()

      Ast.conj(parts ++ constraints)
    end)
    |> Ast.disj()
  end

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

    lower_rows =
      for a <- dynamic,
          do: for(x <- 1..len, do: Interpretation.at(witness, a, x) - 1)

    Interpretation.new(Interpretation.rows(witness) ++ bit_rows ++ lower_rows ++ result_rows)
  end

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
