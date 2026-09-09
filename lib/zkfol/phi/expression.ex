defmodule Zkfol.Phi.Expression do
  @moduledoc """
  I interpret source expressions using a walk's bindings, without allocating storage.

  A missing source variable is `{:unbound, name}`. An unresolved parameter already
  has an identity: a call argument retains it, while an expression can read its cell.

  ### Public API

  - `resolve/2`, `resolve!/2`: interpret an expression, reporting an unbound source variable.
  - `argument/2`: interpret a call argument, retaining an unresolved parameter's identity.
  - `solve/2`: interpret an expression or isolate its one unknown in a sum.
  """

  alias Zkfol.Ast
  alias Zkfol.Phi.{Cons, Value, Walk}

  @type result :: {:ok, Value.t()} | {:unbound, atom()}
  @type waiting :: {:waiting, [atom()]}

  @doc "I interpret a source expression; an unbound variable is a result, not a cell."
  @spec resolve(term(), Walk.t()) :: result()
  def resolve({:var, name}, walk) when not is_map_key(walk.env, name),
    do: {:unbound, name}

  def resolve({:var, name}, walk) do
    case Walk.fetch(walk, name) do
      :fresh -> {:unbound, name}
      fresh = {:fresh, _ref} -> resolve(fresh, walk)
      value -> {:ok, value}
    end
  end

  def resolve(fresh = {:fresh, _ref}, walk) do
    case Walk.follow(walk, fresh) do
      {:fresh, unread} -> {:ok, Ast.cell(unread)}
      value -> {:ok, value}
    end
  end

  def resolve({:papply, relation, fixed}, walk) do
    fixed
    |> Enum.reduce_while({:ok, []}, fn term, {:ok, values} ->
      case resolve(term, walk) do
        {:ok, value} -> {:cont, {:ok, [value | values]}}
        unbound -> {:halt, unbound}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, {:rel, relation, Enum.reverse(values)}}
      unbound -> unbound
    end
  end

  def resolve({op, a, b}, walk) when op in [:add, :mul, :cons] do
    with {:ok, a} <- resolve(a, walk),
         {:ok, b} <- resolve(b, walk) do
      value =
        case op do
          :add -> Ast.add(Value.scalar(a), Value.scalar(b))
          :mul -> Ast.mul(Value.scalar(a), Value.scalar(b))
          :cons -> Cons.new(a, b)
        end

      {:ok, value}
    end
  end

  def resolve(nil, _walk), do: {:ok, []}
  def resolve(value, walk), do: {:ok, Value.shaped(value, walk.shapes)}

  @doc "I require an expression's value, refusing an unbound source variable."
  @spec resolve!(term(), Walk.t()) :: Value.t()
  def resolve!(term, walk) do
    case resolve(term, walk) do
      {:ok, value} -> value
      {:unbound, name} -> throw({:refused, {:unbound_variable, %{variable: name}}})
    end
  end

  @doc "I pass a known value or unresolved parameter; an unknown expression passes a wildcard."
  @spec argument(term(), Walk.t()) :: Value.t()
  def argument({:var, name}, walk) do
    if Map.has_key?(walk.env, name), do: Walk.fetch(walk, name), else: :fresh
  end

  def argument(term, walk) do
    case resolve(term, walk) do
      {:ok, value} -> value
      {:unbound, _name} -> :fresh
    end
  end

  @doc "I isolate one unknown in a sum; the returned function computes it from the other side."
  @spec solve(term(), Walk.t()) ::
          {:ok, Value.t()} | {:free, atom(), (Value.scalar() -> Value.scalar())} | waiting()
  def solve({:var, name}, walk) when not is_map_key(walk.env, name),
    do: {:free, name, & &1}

  def solve({:add, a, b}, walk) do
    left = with {:ok, value} <- solve(a, walk), do: {:ok, Value.scalar(value)}

    case {left, solve(b, walk)} do
      {{:ok, a}, {:ok, b}} ->
        {:ok, Ast.add(a, Value.scalar(b))}

      {{:ok, a}, {:free, name, rebuild}} ->
        {:free, name, fn other -> rebuild.(Ast.add(other, Ast.mul(a, -1))) end}

      {{:free, name, rebuild}, {:ok, b}} ->
        {:free, name, fn other -> rebuild.(Ast.add(other, Ast.mul(Value.scalar(b), -1))) end}

      {{:free, a, _rebuild_a}, {:free, b, _rebuild_b}} ->
        {:waiting, Enum.uniq([a, b])}

      {waiting = {:waiting, _names}, _right} ->
        waiting

      {_left, waiting = {:waiting, _names}} ->
        waiting
    end
  end

  def solve(term, walk) do
    case resolve(term, walk) do
      {:ok, value} -> {:ok, value}
      {:unbound, name} -> {:waiting, [name]}
    end
  end
end
