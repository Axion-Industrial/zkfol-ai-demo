defmodule Zkfol.Facts do
  @moduledoc """
  I read a statement back out of its syntax: which equalities pin cells,
  which schedule pointers, which one states the recurrence, and I assemble
  the descriptor that licenses the doubling rewrite. Statements outside the
  constant-coefficient order-2 class are refused with the reason.

  ### Public API

  - `recurrence/1`
  """

  use TypedStruct

  alias Zkfol.Ast

  # I describe x(k) = p·x(k-1) + q·x(k-2) with its base cases.
  typedstruct enforce: true do
    field(:index_row, pos_integer())
    field(:value_row, pos_integer())
    field(:p, integer())
    field(:q, integer())
    field(:initial, [{integer(), integer()}])
  end

  @typedoc "One classified equality."
  @type fact ::
          {:pin, pos_integer(), integer()}
          | {:schedule, pos_integer(), pos_integer(), integer()}
          | {:recurrence, pos_integer(), %{pos_integer() => integer()}}

  @typep atoms :: %{
           ({:direct, pos_integer()} | {:composed, pos_integer(), pos_integer()}) => integer()
         }

  @doc "I extract the order-2 descriptor from `pred`, or refuse with a reason."
  @spec recurrence(Ast.pred()) :: {:ok, t()} | {:error, String.t()}
  def recurrence(pred) do
    {steps, bases} = pred |> Ast.branches() |> Enum.split_with(&uses_pointer?/1)

    with {:ok, step} <- the_step(steps),
         {:ok, facts} <- classified(step),
         {:ok, index_row, value_row, coefficients} <- assembled(facts),
         {:ok, initial} <- base_cases(bases, index_row, value_row) do
      {:ok,
       %__MODULE__{
         index_row: index_row,
         value_row: value_row,
         p: coefficients[-1],
         q: coefficients[-2],
         initial: initial
       }}
    end
  end

  @spec uses_pointer?(Ast.pred()) :: boolean()
  defp uses_pointer?({:eq, t, u}), do: composed?(t) or composed?(u)

  defp uses_pointer?({tag, preds}) when tag in [:conj, :disj],
    do: Enum.any?(preds, &uses_pointer?/1)

  @spec composed?(Ast.term_t()) :: boolean()
  defp composed?({:cell, _i, _j}), do: true
  defp composed?({tag, t, u}) when tag in [:add, :mul], do: composed?(t) or composed?(u)
  defp composed?(_term), do: false

  @spec the_step([Ast.pred()]) :: {:ok, Ast.pred()} | {:error, String.t()}
  defp the_step([step]), do: {:ok, step}

  defp the_step(steps),
    do: {:error, "#{length(steps)} pointer-using branches; need exactly one step"}

  @spec classified(Ast.pred()) :: {:ok, [fact()]} | {:error, String.t()}
  defp classified(step) do
    with {:ok, eqs} <- equalities(step) do
      reduce_ok(eqs, &classify/1)
    end
  end

  @spec equalities(Ast.pred()) :: {:ok, [Ast.pred()]} | {:error, String.t()}
  defp equalities({:eq, _t, _u} = eq), do: {:ok, [eq]}

  defp equalities({:conj, preds}) do
    reduce_ok(preds, &equalities/1) |> ok_map(&List.flatten/1)
  end

  defp equalities(_pred), do: {:error, "branch is not a conjunction of equalities"}

  # --- one equality, as a linear form over cells, becomes one fact ---------

  @spec classify(Ast.pred()) :: {:ok, fact()} | {:error, String.t()}
  defp classify({:eq, t, u}) do
    with {:ok, left, lc} <- linear(t),
         {:ok, right, rc} <- linear(u) do
      interpret(merge(left, scale(right, -1)), lc - rc)
    end
  end

  @spec interpret(atoms(), integer()) :: {:ok, fact()} | {:error, String.t()}
  defp interpret(atoms, const) do
    with {:ok, row} <- the_row(atoms),
         sign when sign in [1, -1] <- atoms[{:direct, row}] || :missing do
      atoms |> Map.delete({:direct, row}) |> pointed(row, sign, const)
    else
      _ -> {:error, "equality does not constrain one direct cell with unit coefficient"}
    end
  end

  @spec pointed(atoms(), pos_integer(), integer(), integer()) ::
          {:ok, fact()} | {:error, String.t()}
  defp pointed(rest, row, sign, const) when rest == %{},
    do: {:ok, {:pin, row, -const * sign}}

  defp pointed(rest, row, sign, const) do
    case Map.to_list(rest) do
      [{{:composed, _row, ptr}, coeff}] when coeff == -sign ->
        {:ok, {:schedule, row, ptr, const * sign}}

      terms when const == 0 ->
        {:ok,
         {:recurrence, row, Map.new(terms, fn {{:composed, _r, ptr}, c} -> {ptr, -c * sign} end)}}

      _ ->
        {:error, "affine recurrence constants are outside the class"}
    end
  end

  @spec the_row(atoms()) :: {:ok, pos_integer()} | {:error, String.t()}
  defp the_row(atoms) do
    case atoms |> Map.keys() |> Enum.map(&elem(&1, 1)) |> Enum.uniq() do
      [row] -> {:ok, row}
      rows -> {:error, "equality mixes cell rows #{inspect(rows)}"}
    end
  end

  @spec linear(Ast.term_t()) :: {:ok, atoms(), integer()} | {:error, String.t()}
  defp linear(q) when is_integer(q), do: {:ok, %{}, q}
  defp linear({:cell, i}), do: {:ok, %{{:direct, i} => 1}, 0}
  defp linear({:cell, i, j}), do: {:ok, %{{:composed, i, j} => 1}, 0}

  defp linear({:add, t, u}) do
    with {:ok, left, lc} <- linear(t),
         {:ok, right, rc} <- linear(u),
         do: {:ok, merge(left, right), lc + rc}
  end

  defp linear({:mul, t, u}) do
    with {:ok, left, lc} <- linear(t),
         {:ok, right, rc} <- linear(u) do
      case {map_size(left), map_size(right)} do
        {0, _} ->
          {:ok, scale(right, lc), lc * rc}

        {_, 0} ->
          {:ok, scale(left, rc), lc * rc}

        _ ->
          {:error,
           "multiplication of two non-constant terms: outside the constant-coefficient class"}
      end
    end
  end

  defp linear(term), do: {:error, "term #{inspect(term)} is outside the recurrence class"}

  # --- assembly: schedules identify the index row; offsets name coefficients

  @spec assembled([fact()]) ::
          {:ok, pos_integer(), pos_integer(), %{integer() => integer()}} | {:error, String.t()}
  defp assembled(facts) do
    recurrences = for {:recurrence, _, _} = fact <- facts, do: fact
    schedules = for {:schedule, _, _, _} = fact <- facts, do: fact

    with {:ok, {:recurrence, value_row, by_ptr}} <- the_recurrence(recurrences, facts),
         {:ok, index_row} <- the_index_row(schedules, value_row, by_ptr),
         :ok <- consumed(schedules, index_row, by_ptr),
         {:ok, coefficients} <- by_offset(by_ptr, schedules, index_row) do
      {:ok, index_row, value_row, coefficients}
    end
  end

  # Every schedule must serve the recurrence: an equality this pass cannot
  # use may still constrain the witness, so it is refused, never dropped.
  @spec consumed([fact()], pos_integer(), %{pos_integer() => integer()}) ::
          :ok | {:error, String.t()}
  defp consumed(schedules, index_row, by_ptr) do
    case Enum.find(schedules, fn {:schedule, row, ptr, _} ->
           row != index_row or not is_map_key(by_ptr, ptr)
         end) do
      nil ->
        :ok

      {:schedule, row, ptr, _} ->
        {:error, "row #{row} is scheduled through pointer #{ptr}, outside the recurrence"}
    end
  end

  @spec the_recurrence([fact()], [fact()]) :: {:ok, fact()} | {:error, String.t()}
  defp the_recurrence([recurrence], facts) do
    if Enum.any?(facts, &match?({:pin, _, _}, &1)),
      do: {:error, "constant pin inside the inductive step"},
      else: {:ok, recurrence}
  end

  defp the_recurrence(recurrences, _facts),
    do: {:error, "expected exactly one recurrence equation, found #{length(recurrences)}"}

  @spec the_index_row([fact()], pos_integer(), %{pos_integer() => integer()}) ::
          {:ok, pos_integer()} | {:error, String.t()}
  defp the_index_row(schedules, value_row, by_ptr) do
    case for {:schedule, row, ptr, offset} <- schedules,
             offset != 0 and row != value_row and is_map_key(by_ptr, ptr),
             uniq: true,
             do: row do
      [index_row] -> {:ok, index_row}
      rows -> {:error, "schedules identify index rows #{inspect(rows)}; need exactly one"}
    end
  end

  @spec by_offset(%{pos_integer() => integer()}, [fact()], pos_integer()) ::
          {:ok, %{integer() => integer()}} | {:error, String.t()}
  defp by_offset(by_ptr, schedules, index_row) do
    pairs = for {:schedule, ^index_row, ptr, offset} <- schedules, uniq: true, do: {ptr, offset}
    offsets = Map.new(pairs)
    coefficients = Map.new(by_ptr, fn {ptr, coeff} -> {offsets[ptr], coeff} end)

    cond do
      map_size(offsets) < length(pairs) ->
        {:error, "a pointer is scheduled at two offsets"}

      map_size(coefficients) < map_size(by_ptr) ->
        {:error, "two pointers share one offset; their coefficients are not separable"}

      true ->
        case coefficients |> Map.keys() |> Enum.sort(:desc) do
          [-1, -2] ->
            {:ok, coefficients}

          other ->
            {:error, "pointer offsets #{inspect(other)}; the doubling rewrite needs -1 and -2"}
        end
    end
  end

  # --- base branches: strict pins, no conflicts, contiguous starts ---------

  @spec base_cases([Ast.pred()], pos_integer(), pos_integer()) ::
          {:ok, [{integer(), integer()}]} | {:error, String.t()}
  defp base_cases(bases, index_row, value_row) do
    with {:ok, pin_maps} <- reduce_ok(bases, &pins/1) do
      reduce_ok(pin_maps, &initial_value(&1, index_row, value_row))
      |> ok_map(&Enum.sort/1)
      |> ok_then(&distinct_indices/1)
    end
  end

  @spec pins(Ast.pred()) :: {:ok, %{pos_integer() => integer()}} | {:error, String.t()}
  defp pins(branch) do
    with {:ok, eqs} <- equalities(branch),
         {:ok, facts} <- reduce_ok(eqs, &classify/1),
         true <- Enum.all?(facts, &match?({:pin, _, _}, &1)),
         grouped = Enum.group_by(facts, &elem(&1, 1), &elem(&1, 2)),
         false <- Enum.any?(grouped, fn {_row, values} -> length(Enum.uniq(values)) > 1 end) do
      {:ok, Map.new(grouped, fn {row, [value | _]} -> {row, value} end)}
    else
      false -> {:error, "a pointer-free branch does not only pin cells"}
      true -> {:error, "a base branch pins one cell to conflicting values"}
      error -> error
    end
  end

  @spec initial_value(%{pos_integer() => integer()}, pos_integer(), pos_integer()) ::
          {:ok, {integer(), integer()}} | {:error, String.t()}
  defp initial_value(pins, index_row, value_row) do
    case pins do
      %{^index_row => index, ^value_row => value} -> {:ok, {index, value}}
      _ -> {:error, "a base branch does not pin both the index and value rows"}
    end
  end

  @spec distinct_indices([{integer(), integer()}]) ::
          {:ok, [{integer(), integer()}]} | {:error, String.t()}
  defp distinct_indices([{i, v}, {j, w}]) when j == i + 1, do: {:ok, [{i, v}, {j, w}]}

  defp distinct_indices(initial),
    do: {:error, "base cases #{inspect(initial)}; need two contiguous"}

  # --- tiny result plumbing -------------------------------------------------

  @spec merge(atoms(), atoms()) :: atoms()
  defp merge(a, b),
    do: Map.merge(a, b, fn _k, x, y -> x + y end) |> Map.reject(&(elem(&1, 1) == 0))

  @spec scale(atoms(), integer()) :: atoms()
  defp scale(lin, k), do: Map.new(lin, fn {atom, c} -> {atom, c * k} end)

  @spec reduce_ok([term()], (term() -> {:ok, term()} | {:error, String.t()})) ::
          {:ok, [term()]} | {:error, String.t()}
  defp reduce_ok(items, fun) do
    Enum.reduce_while(items, {:ok, []}, fn item, {:ok, acc} ->
      case fun.(item) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> ok_map(&Enum.reverse/1)
  end

  @spec ok_map({:ok, term()} | {:error, String.t()}, (term() -> term())) ::
          {:ok, term()} | {:error, String.t()}
  defp ok_map({:ok, value}, fun), do: {:ok, fun.(value)}
  defp ok_map(error, _fun), do: error

  @spec ok_then({:ok, term()} | {:error, String.t()}, (term() -> term())) :: term()
  defp ok_then({:ok, value}, fun), do: fun.(value)
  defp ok_then(error, _fun), do: error
end
