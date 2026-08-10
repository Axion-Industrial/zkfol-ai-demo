defmodule Zkfol.Al.Consumption do
  @moduledoc """
  I name the clause that fired: the derivation says what a fact's
  calls consumed, and the first clause whose head admits the tuple,
  whose calls line up with what was consumed, and whose ground
  equations hold is the one that ran. From it come the pointers each
  consumption went through, and the guards whose slack the placement
  fills. I exist because the journal does not yet name the fired
  clause; when each call node carries it, I am a lookup, deleted.

  ### Public API

  - `fired/3` — each fact's clause beside what it consumed.
  - `env/3` — where that clause bound its names.
  """

  alias Zkfol.Derivation
  alias Zkfol.Lang
  alias Zkfol.Lang.Rel

  @typedoc "A clause as a call site: its head, its body, and its calls' pointer names in body order."
  @type site :: {[term()], [term()], [Zkfol.Ast.row_ref()]}

  @doc """
  I am each fact's fired clause beside the facts it consumed: the
  first clause whose head admits the tuple, whose calls line up with
  what was consumed, and whose ground equations hold, nothing when no
  clause of the relation does.
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
         if admits?(head, tuple) and calls_line_up?(body, used) and settled?(site, tuple, used),
           do: {site, used}
       end)}
    end)
  end

  @doc """
  I am where a fired clause bound its names: the head against the
  fact's own tuple, each call's outputs against the tuple it
  consumed past the index. Whoever reads a clause's sites against
  what ran reads me first.
  """
  @spec env(site(), [term()], [Derivation.fact()]) :: %{atom() => term()}
  def env({head, body, _ptrs}, tuple, used) do
    outputs =
      for({:call, _name, [_at | outs]} <- body, do: outs)
      |> Enum.zip(used)
      |> Enum.flat_map(fn {outs, {_name, consumed}} -> Enum.zip(outs, Enum.drop(consumed, 1)) end)

    Map.merge(
      Map.new(for {{:var, nm}, q} <- Enum.zip(head, tuple), do: {nm, Derivation.free_to_zero(q)}),
      Map.new(outputs, fn {{:var, nm}, q} -> {nm, Derivation.free_to_zero(q)} end)
    )
  end

  # Heads and calls cannot tell apart clauses that differ only in what
  # their bodies equate, so the equations both sides ground decide.
  @spec settled?(site(), [term()], [Derivation.fact()]) :: boolean()
  defp settled?({_head, body, _ptrs} = site, tuple, used) do
    bindings = env(site, tuple, used)

    Enum.all?(for({:eq, l, r} <- body, do: {l, r}), fn {l, r} ->
      case {Lang.value(l, bindings), Lang.value(r, bindings)} do
        {{:ok, a}, {:ok, b}} -> a == b
        _open -> true
      end
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
