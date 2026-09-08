defmodule Zkfol.Facts do
  @moduledoc """
  I am the order-2 descriptor read off a relation's clauses: the base
  values from its facts, the coefficients from its step equation, and
  the modulus when the step reduces.
  """

  use TypedStruct

  alias Zkfol.Lang.Rel
  alias Zkfol.Refusal

  typedstruct enforce: true do
    field(:p, integer())
    field(:q, integer())
    field(:initial, [{pos_integer(), integer()}])
    field(:mod, pos_integer() | nil, default: nil, enforce: false)
  end

  @doc "I extract the order-2 descriptor from `rel`'s clauses, or refuse with a reason."
  @spec recurrence(Rel.t()) :: {:ok, t()} | {:error, Refusal.t(Refusal.restructure())}
  def recurrence(%Rel{arity: 2, name: name, clauses: clauses}) do
    {facts, steps} = Enum.split_with(clauses, fn {_head, body} -> body == [] end)

    with {:ok, initial} <- initials(facts),
         {:ok, step} <- the_step(steps),
         {:ok, p, q, mod} <- coefficients(name, step),
         do: {:ok, %__MODULE__{p: p, q: q, initial: initial, mod: mod}}
  end

  def recurrence(%Rel{name: name, arity: arity}),
    do: {:error, {:not_an_index_relation, %{relation: name, arity: arity}}}

  @spec initials([{[term()], [term()]}]) ::
          {:ok, [{pos_integer(), integer()}]} | {:error, Refusal.t(Refusal.restructure())}
  defp initials(facts) do
    with :ok <-
           Refusal.refute(
             facts,
             fn {[k, v], _} -> not (is_integer(k) and is_integer(v)) end,
             fn {head, _} -> {:fact_not_ground, %{fact: head}} end
           ) do
      initial = Enum.map(facts, fn {[k, v], _} -> {k, v} end)

      case Enum.sort(initial) do
        [{a, _x1}, {b, _x2}] = pair when b == a + 1 -> {:ok, pair}
        found -> {:error, {:facts_not_consecutive, %{indices: Enum.map(found, &elem(&1, 0))}}}
      end
    end
  end

  @spec the_step([{[term()], [term()]}]) ::
          {:ok, {atom(), [term()]}} | {:error, Refusal.t(Refusal.restructure())}
  defp the_step([{[{:var, _index}, {:var, out}], body}]), do: {:ok, {out, body}}
  defp the_step([{head, _body}]), do: {:error, {:step_head_not_indexed, %{head: head}}}
  defp the_step(steps), do: {:error, {:step_clauses, %{clauses: length(steps)}}}

  @spec coefficients(atom(), {atom(), [term()]}) ::
          {:ok, integer(), integer(), pos_integer() | nil}
          | {:error, Refusal.t(Refusal.restructure())}
  defp coefficients(name, {out, body}) do
    offsets =
      for {:call, ^name, [{:add, {:var, _index}, k}, {:var, v}]} <- body, do: {k, v}

    with {:ok, back_one, back_two} <- history(offsets),
         [{rhs, mod}] <- for(goal <- body, defined = defines(goal, out), do: defined),
         {:ok, coefficients} <- linear(rhs, %{}) do
      case Map.keys(coefficients) -- [back_one, back_two] do
        [] -> {:ok, coefficients[back_one] || 0, coefficients[back_two] || 0, mod}
        vars -> {:error, {:step_beyond_history, %{extra: vars}}}
      end
    else
      {:error, reason} -> {:error, reason}
      _eqs -> {:error, {:step_needs_an_equation, %{}}}
    end
  end

  @spec defines(term(), atom()) :: {term(), pos_integer() | nil} | nil
  defp defines({:eq, {:var, out}, rhs}, out), do: {rhs, nil}

  defp defines({:call, :mod, [rhs, m, {:var, out}, _q]}, out) when is_integer(m), do: {rhs, m}

  defp defines(_goal, _out), do: nil

  @spec history([{integer(), atom()}]) ::
          {:ok, atom(), atom()} | {:error, Refusal.t(Refusal.restructure())}
  defp history(offsets) do
    case Enum.sort(offsets, :desc) do
      [{-1, back_one}, {-2, back_two}] -> {:ok, back_one, back_two}
      found -> {:error, {:not_order_two, %{offsets: Enum.map(found, &elem(&1, 0))}}}
    end
  end

  @spec linear(term(), %{atom() => integer()}) ::
          {:ok, %{atom() => integer()}} | {:error, Refusal.t(Refusal.restructure())}
  defp linear({:var, v}, acc), do: scaled(v, 1, acc)
  defp linear({:mul, {:var, v}, c}, acc) when is_integer(c), do: scaled(v, c, acc)
  defp linear({:mul, c, {:var, v}}, acc) when is_integer(c), do: scaled(v, c, acc)

  defp linear({:add, a, b}, acc) do
    with {:ok, acc} <- linear(a, acc), do: linear(b, acc)
  end

  defp linear(term, _acc),
    do: {:error, {:step_not_linear, %{term: term}}}

  @spec scaled(atom(), integer(), %{atom() => integer()}) :: {:ok, %{atom() => integer()}}
  defp scaled(v, c, acc), do: {:ok, Map.update(acc, v, c, &(&1 + c))}
end
