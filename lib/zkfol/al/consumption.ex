defmodule Zkfol.Al.Consumption do
  @moduledoc """
  I name the clause that fired: the derivation says what a fact's
  calls consumed, and the first clause whose head admits the tuple and
  whose calls line up with what was consumed is the one that ran. From
  it come the pointers each consumption went through, and the guards
  whose slack the placement fills. I exist because the journal does
  not yet name the fired clause; when each call node carries it, I am
  a lookup, deleted.
  """

  alias Zkfol.Derivation
  alias Zkfol.Lang.Rel

  @typedoc "A clause as a call site: its head, its body, and its calls' pointer names in body order."
  @type site :: {[term()], [term()], [Zkfol.Ast.row_ref()]}

  @doc """
  I am each fact's fired clause beside the facts it consumed: the
  first clause whose head admits the tuple and whose calls line up
  with what was consumed, nothing when no clause of the relation does.
  """
  @spec fired(Derivation.t(), [Rel.t()], Zkfol.Lang.shape()) ::
          %{Derivation.fact() => {site(), [Derivation.fact()]} | nil}
  def fired(%Derivation{} = derivation, members, shape) do
    sites = clause_sites(members, shape)

    derivation
    |> Derivation.consumption()
    |> Map.new(fn {{name, tuple} = fact, used} ->
      {fact,
       sites
       |> Map.fetch!(name)
       |> Enum.find_value(fn {head, body, _ptrs} = site ->
         if admits?(head, tuple) and calls_line_up?(body, used), do: {site, used}
       end)}
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

  @spec calls_line_up?([term()], [Derivation.fact()]) :: boolean()
  defp calls_line_up?(body, used) do
    callees = for {:call, callee, _cargs} <- body, do: callee

    length(callees) == length(used) and
      callees |> Enum.zip(used) |> Enum.all?(fn {callee, {name, _t}} -> callee == name end)
  end

  # Each member's clauses beside their pointers, calls in body order.
  @spec clause_sites([Rel.t()], Zkfol.Lang.shape()) :: %{atom() => [site()]}
  defp clause_sites(members, shape) do
    Map.new(members, fn rel ->
      per_clause =
        rel.clauses
        |> Enum.zip(Map.fetch!(shape.calls, rel.name))
        |> Enum.map(fn {{head, body}, ptrs} -> {head, body, ptrs} end)

      {rel.name, per_clause}
    end)
  end
end
