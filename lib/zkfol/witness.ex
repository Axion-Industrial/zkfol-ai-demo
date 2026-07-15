defmodule Zkfol.Witness do
  @moduledoc """
  I am the generating semantics: seeds in, witness out. A scheduled
  statement is a transcribed computation, so I run it rather than solve
  it: columns in order, reading branches before base ones, and within
  the branch every equation with one evaluable side and a lone unknown
  cell on the other assigns that cell, until the column closes. A cell
  no branch pins is filled by its schedule, or with zero when the
  statement never reads it; a read cell I cannot derive is the prover's
  knowledge, refused by name so the caller seeds it. Every witness is
  seeds plus trace, and I derive the trace.

  The oracle judges each generated column, so what I return is a model
  of the statement. Range checks stay with the caller.

  ### Public API

  - `generate/3`, `run/2`
  """

  @behaviour Zkfol.Pipeline

  alias Zkfol.Ast
  alias Zkfol.Interpretation
  alias Zkfol.Semantics
  alias Zkfol.Statement
  alias Zkfol.Uair

  @typedoc "Prover knowledge: the cell at row, column carries the value."
  @type seeds :: %{{pos_integer(), pos_integer()} => non_neg_integer()}

  @doc """
  I am generation as a pass: I fill a nil witness from `:len` and
  `:seeds`; a witness already provided passes through untouched.
  """
  @impl Zkfol.Pipeline
  @spec run(Statement.t(), keyword()) :: {:ok, Statement.t()} | {:error, String.t()}
  def run(%Statement{witness: nil, pred: pred} = statement, opts) do
    with {:ok, witness} <-
           generate(pred, Keyword.fetch!(opts, :len), Keyword.get(opts, :seeds, %{})),
         do: {:ok, %{statement | witness: witness}}
  end

  def run(statement, _opts), do: {:ok, statement}

  @typep cells :: %{pos_integer() => integer()}
  @typep columns :: %{pos_integer() => cells()}

  @typep env :: %{
           optional(:x) => pos_integer(),
           optional(:columns) => columns(),
           pred: Ast.pred(),
           len: pos_integer(),
           seeds: seeds(),
           schedules: %{pos_integer() => pos_integer()},
           rows: Range.t(),
           read: MapSet.t(pos_integer()),
           branches: [Ast.pred()]
         }

  @doc "I derive the witness of `pred` over `len` columns from `seeds`, or refuse with the reason."
  @spec generate(Ast.pred(), pos_integer(), seeds()) ::
          {:ok, Interpretation.t()} | {:error, String.t()}
  def generate(pred, len, seeds \\ %{}) do
    with {:ok, schedules} <- Uair.schedules(pred),
         env = %{
           pred: pred,
           len: len,
           seeds: seeds,
           schedules: schedules,
           rows: 1..arity(pred),
           read: read_rows(pred),
           branches: pred |> Ast.branches() |> Enum.sort_by(&(not reads?(&1)))
         },
         {:ok, columns} <- trace(1, %{}, env) do
      deliver(columns, env)
    end
  end

  @spec trace(pos_integer(), columns(), env()) :: {:ok, columns()} | {:error, String.t()}
  defp trace(x, columns, %{len: len}) when x > len, do: {:ok, columns}

  defp trace(x, columns, env) do
    with {:ok, cells} <- column(Map.merge(env, %{x: x, columns: columns})),
         do: trace(x + 1, Map.put(columns, x, cells), env)
  end

  # The first branch whose equations close over the known cells wins the
  # column; what it leaves unpinned is filled or refused.
  @spec column(env()) :: {:ok, cells()} | {:error, String.t()}
  defp column(%{x: x} = env) do
    planted = for {{i, ^x}, value} <- env.seeds, into: %{}, do: {i, value}

    env.branches
    |> Enum.find_value(fn branch -> close(Ast.conjuncts(branch), planted, env) end)
    |> case do
      nil -> {:error, "no branch completes column #{x}"}
      cells -> fill(cells, env)
    end
  end

  # Passes learn assignments until nothing new arrives; the branch
  # claims the column only when every equation then holds.
  @spec close([Ast.pred()], cells(), env()) :: cells() | nil
  defp close(equations, cells, env) do
    learned = Enum.reduce(equations, cells, &learn(&1, &2, env))

    cond do
      learned != cells -> close(equations, learned, env)
      Enum.all?(equations, &holds?(&1, cells, env)) -> cells
      true -> nil
    end
  end

  # An equation with one known side and a lone unknown cell on the
  # other defines that cell; an unknown nested under arithmetic would
  # ask for inversion, and anything else teaches nothing.
  @spec learn(Ast.pred(), cells(), env()) :: cells()
  defp learn({:eq, {:cell, i}, u}, cells, env) when not is_map_key(cells, i) do
    case value(u, cells, env) do
      nil -> cells
      v -> Map.put(cells, i, v)
    end
  end

  defp learn({:eq, t, {:cell, i}}, cells, env) when not is_map_key(cells, i) do
    case value(t, cells, env) do
      nil -> cells
      v -> Map.put(cells, i, v)
    end
  end

  defp learn(_pred, cells, _env), do: cells

  @spec holds?(Ast.pred(), cells(), env()) :: boolean()
  defp holds?({:eq, t, u}, cells, env),
    do: match?({v, v} when not is_nil(v), {value(t, cells, env), value(u, cells, env)})

  defp holds?(_pred, _cells, _env), do: false

  # nil is the unknown: an unassigned cell, a dereference outside the
  # trace or off schedule, and any arithmetic over either.
  @spec value(Ast.term_t(), cells(), env()) :: integer() | nil
  defp value(q, _cells, _env) when is_integer(q), do: q
  defp value(:x, _cells, env), do: env.x
  defp value(:len, _cells, env), do: env.len
  defp value({:cell, i}, cells, _env), do: cells[i]

  defp value({:cell, i, j}, _cells, env) do
    case env.schedules do
      %{^j => offset} -> Map.get(env.columns, env.x - offset, %{})[i]
      _unscheduled -> nil
    end
  end

  defp value({op, t, u}, cells, env) when op in [:add, :mul] do
    with a when is_integer(a) <- value(t, cells, env),
         b when is_integer(b) <- value(u, cells, env) do
      if op == :add, do: a + b, else: a * b
    end
  end

  defp value(_reified, _cells, _env), do: nil

  # An unpinned cell the statement reads is knowledge, not padding.
  @spec fill(cells(), env()) :: {:ok, cells()} | {:error, String.t()}
  defp fill(cells, env) do
    unpinned = fn i -> not is_map_key(cells, i) and not is_map_key(env.schedules, i) end

    case Enum.find(env.rows, &(unpinned.(&1) and &1 in env.read)) do
      nil -> {:ok, Map.new(env.rows, &{&1, Map.get(cells, &1) || filler(&1, env)})}
      i -> {:error, "row #{i} at column #{env.x} is the prover's knowledge: seed it"}
    end
  end

  @spec filler(pos_integer(), env()) :: non_neg_integer()
  defp filler(i, env) do
    case env.schedules do
      %{^i => offset} -> max(env.x - offset, 1)
      _schedules -> 0
    end
  end

  @spec deliver(columns(), env()) :: {:ok, Interpretation.t()} | {:error, String.t()}
  defp deliver(columns, env) do
    matrix = for i <- env.rows, do: for(x <- 1..env.len, do: columns[x][i])

    case matrix |> List.flatten() |> Enum.find(&(&1 < 0)) do
      nil ->
        witness = Interpretation.new(matrix)

        case Enum.find(1..env.len, &(Semantics.eval(env.pred, witness, &1) != 0)) do
          nil -> {:ok, witness}
          x -> {:error, "the generated column #{x} does not satisfy the statement"}
        end

      value ->
        {:error, "the generated witness contains #{value}; interpretations are non-negative"}
    end
  end

  @spec arity(Ast.pred()) :: pos_integer()
  defp arity(pred) do
    Ast.reduce(pred, 1, fn
      {:cell, i}, acc -> max(i, acc)
      {:cell, i, j}, acc -> max(max(i, j), acc)
      _node, acc -> acc
    end)
  end

  @spec read_rows(Ast.pred()) :: MapSet.t(pos_integer())
  defp read_rows(pred) do
    Ast.reduce(pred, MapSet.new(), fn
      {:cell, i, _j}, acc -> MapSet.put(acc, i)
      _node, acc -> acc
    end)
  end

  @spec reads?(Ast.pred()) :: boolean()
  defp reads?(branch) do
    Ast.reduce(branch, false, fn
      {:cell, _i, _j}, _acc -> true
      _node, acc -> acc
    end)
  end
end
