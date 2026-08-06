defmodule Zkfol.Al.Consumption do
  @moduledoc """
  I recover who consumed what, by value: the clause that fired is
  the first whose head admits the fact's tuple and whose every call
  finds its fact, unambiguous because the facts are committed-only.
  I exist because the journal does not yet say which clause fired;
  when each call node carries its clause and locals, I am a lookup,
  deleted.
  """

  alias Zkfol.Lang.Rel

  @typep fact :: {atom(), [term()]}

  @doc "I am each fact's consumption: its call sites' pointer rows beside the facts they used."
  @spec of([fact()], [Rel.t()], map()) :: %{fact() => [{pos_integer(), fact()}]}
  def of(facts, members, shape) do
    sites = clause_sites(members, shape)
    by_name = Enum.group_by(facts, &elem(&1, 0))
    Map.new(facts, &{&1, consumed(&1, sites, by_name)})
  end

  @spec consumed(fact(), map(), %{atom() => [fact()]}) :: [{pos_integer(), fact()}]
  defp consumed({name, tuple}, sites, by_name) do
    sites
    |> Map.fetch!(name)
    |> Enum.find_value([], fn {head, calls} ->
      case head_env(head, tuple) do
        {:ok, env} -> match_calls(calls, env, by_name)
        :mismatch -> nil
      end
    end)
  end

  @spec head_env([term()], [term()]) :: {:ok, %{atom() => term()}} | :mismatch
  defp head_env(head, tuple) do
    head
    |> Enum.zip(tuple)
    |> Enum.reduce_while({:ok, %{}}, fn
      {{:var, nm}, value}, {:ok, env} ->
        case env do
          %{^nm => ^value} -> {:cont, {:ok, env}}
          %{^nm => _other} -> {:halt, :mismatch}
          _env -> {:cont, {:ok, Map.put(env, nm, value)}}
        end

      {literal, value}, {:ok, env} ->
        if literal == value, do: {:cont, {:ok, env}}, else: {:halt, :mismatch}
    end)
  end

  @spec match_calls([{atom(), [term()], pos_integer()}], map(), %{atom() => [fact()]}) ::
          [{pos_integer(), fact()}] | nil
  defp match_calls(calls, env, by_name) do
    pairs =
      Enum.map(calls, fn {callee, cargs, row} -> {row, find_fact(callee, cargs, env, by_name)} end)

    if Enum.all?(pairs, fn {_row, fact} -> fact end), do: pairs
  end

  @spec find_fact(atom(), [term()], map(), %{atom() => [fact()]}) :: fact() | nil
  defp find_fact(callee, cargs, env, by_name) do
    pins =
      cargs
      |> Enum.with_index()
      |> Enum.flat_map(fn {carg, at} ->
        case eval_arg(carg, env) do
          {:ok, value} -> [{at, value}]
          :free -> []
        end
      end)

    by_name
    |> Map.get(callee, [])
    |> Enum.find(fn {_name, tuple} ->
      Enum.all?(pins, fn {at, value} -> Enum.at(tuple, at) == value end)
    end)
  end

  @spec eval_arg(term(), %{atom() => term()}) :: {:ok, integer()} | :free
  defp eval_arg(q, _env) when is_integer(q), do: {:ok, q}

  defp eval_arg({:var, nm}, env) do
    case env do
      %{^nm => value} when is_integer(value) -> {:ok, value}
      _env -> :free
    end
  end

  defp eval_arg({op, t, u}, env) when op in [:add, :mul] do
    with {:ok, a} <- eval_arg(t, env),
         {:ok, b} <- eval_arg(u, env),
         do: {:ok, if(op == :add, do: a + b, else: a * b)},
         else: (_free -> :free)
  end

  defp eval_arg(_q, _env), do: :free

  # Each member's clauses beside their pointer rows, calls in body
  # order, as Lang allocated them.
  @spec clause_sites([Rel.t()], map()) ::
          %{atom() => [{[term()], [{atom(), [term()], pos_integer()}]}]}
  defp clause_sites(members, shape) do
    Map.new(members, fn rel ->
      per_clause =
        rel.clauses
        |> Enum.zip(Map.fetch!(shape.calls, rel.name))
        |> Enum.map(fn {{head, body}, rows} ->
          calls = for {:call, callee, cargs} <- body, do: {callee, cargs}
          {head, Enum.zip_with(calls, rows, fn {callee, cargs}, row -> {callee, cargs, row} end)}
        end)

      {rel.name, per_clause}
    end)
  end
end
