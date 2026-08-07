defmodule Zkfol.Al.Consumption do
  @moduledoc """
  I put each consumption edge on the pointer it went through: the
  derivation says what a fact's calls consumed, and the clause that
  fired -- the first whose head admits the tuple and whose calls line
  up with what was consumed -- says through which pointer each came.
  I exist because the journal does not yet name the fired clause;
  when each call node carries it, I am a lookup, deleted.
  """

  alias Zkfol.Derivation
  alias Zkfol.Lang.Rel

  @doc "I am each fact's consumption: its call sites' pointer names beside the facts they used."
  @spec of(Derivation.t(), [Rel.t()], Zkfol.Lang.shape()) ::
          %{Derivation.fact() => [{Zkfol.Ast.row_ref(), Derivation.fact()}]}
  def of(%Derivation{} = derivation, members, shape) do
    sites = clause_sites(members, shape)

    derivation
    |> Derivation.consumption()
    |> Map.new(fn {fact, used} -> {fact, consumed(fact, sites, used)} end)
  end

  # The fired clause pairs its pointers with the consumed facts in
  # body order; a fact clause consumed nothing and needs no pairing.
  @spec consumed(Derivation.fact(), map(), [Derivation.fact()]) ::
          [{Zkfol.Ast.row_ref(), Derivation.fact()}]
  defp consumed(_fact, _sites, []), do: []

  defp consumed({name, tuple}, sites, used) do
    sites
    |> Map.fetch!(name)
    |> Enum.find_value([], fn {head, calls} ->
      if admits?(head, tuple) and calls_line_up?(calls, used),
        do: Enum.zip(Enum.map(calls, &elem(&1, 1)), used)
    end)
  end

  @spec admits?([term()], [term()]) :: boolean()
  defp admits?(head, tuple) do
    head
    |> Enum.zip(tuple)
    |> Enum.reduce_while(%{}, fn
      {{:var, nm}, value}, env ->
        case env do
          %{^nm => ^value} -> {:cont, env}
          %{^nm => _other} -> {:halt, :mismatch}
          _env -> {:cont, Map.put(env, nm, value)}
        end

      {literal, value}, env ->
        if literal == value, do: {:cont, env}, else: {:halt, :mismatch}
    end)
    |> Kernel.!=(:mismatch)
  end

  @spec calls_line_up?([{atom(), Zkfol.Ast.row_ref()}], [Derivation.fact()]) :: boolean()
  defp calls_line_up?(calls, used) do
    length(calls) == length(used) and
      calls |> Enum.zip(used) |> Enum.all?(fn {{callee, _ptr}, {name, _t}} -> callee == name end)
  end

  # Each member's clauses beside their pointers, calls in body order.
  @spec clause_sites([Rel.t()], Zkfol.Lang.shape()) ::
          %{atom() => [{[term()], [{atom(), Zkfol.Ast.row_ref()}]}]}
  defp clause_sites(members, shape) do
    Map.new(members, fn rel ->
      per_clause =
        rel.clauses
        |> Enum.zip(Map.fetch!(shape.calls, rel.name))
        |> Enum.map(fn {{head, body}, ptrs} ->
          callees = for {:call, callee, _cargs} <- body, do: callee
          {head, Enum.zip(callees, ptrs)}
        end)

      {rel.name, per_clause}
    end)
  end
end
