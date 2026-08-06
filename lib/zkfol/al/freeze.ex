defmodule Zkfol.Al.Freeze do
  @moduledoc """
  I am the frozen-equation emission: every surface equation expanded
  into each direction it can run, wrapped to wake when its inputs
  arrive, and every guard frozen on its names. I exist because AL's
  arithmetic runs one way at a time; when CLPFD lands, one constraint
  goal per equation replaces everything I emit, and I am deleted
  whole.
  """

  alias Zkfol.Ast
  alias Zkfol.Refusal

  @doc "I emit clause `i`'s equations, each in every direction it can run."
  @spec equations([term()], non_neg_integer(), map()) ::
          {:ok, [Macro.t()]} | {:error, Refusal.t()}
  def equations(body, i, env) do
    body
    |> Enum.filter(&match?({:eq, _t, _u}, &1))
    |> Enum.with_index()
    |> Refusal.flat_map(fn {{:eq, t, u}, j} ->
      with {:ok, pt} <- prefix(t, env),
           {:ok, pu} <- prefix(u, env),
           do: {:ok, AL.Equations.equation(pt, pu, "q#{i}e#{j}", free: [:x, :len])}
    end)
  end

  @doc "I emit the guards, frozen on their names, checking when they arrive."
  @spec guards([term()], map()) :: {:ok, [Macro.t()]} | {:error, Refusal.t()}
  def guards(body, env) do
    body
    |> Enum.filter(&match?({:cmp, _op, _t, _u}, &1))
    |> Refusal.flat_map(fn {:cmp, op, t, u} ->
      with {:ok, pt} <- prefix(t, env),
           {:ok, pu} <- prefix(u, env) do
        test = {op, [], [pure(pt), pure(pu)]}
        {:ok, AL.Equations.frozen(leaves(pt) ++ leaves(pu), [test])}
      end
    end)
  end

  @doc """
  I emit clause `i`'s call `j`'s arguments: a variable or literal
  rides as itself, anything computed goes through a fresh name with
  its equation frozen in both directions.
  """
  @spec args([term()], non_neg_integer(), non_neg_integer(), map(), [Macro.t()]) ::
          {[Macro.t()], [Macro.t()]}
  def args(args, i, j, env, defs) do
    args
    |> Enum.with_index()
    |> Enum.map_reduce(defs, fn
      {{:var, nm}, _k}, defs ->
        {v(nm), defs}

      {q, _k}, defs when is_integer(q) ->
        {q, defs}

      {expr, k}, defs ->
        fresh = :"q#{i}c#{j}a#{k}"
        {:ok, prefix} = prefix(expr, env)
        {v(fresh), defs ++ AL.Equations.equation(fresh, prefix, "qq#{i}#{j}#{k}")}
    end)
  end

  # Terms over the clause's variables, as the equation compiler reads them.
  @spec prefix(term(), %{atom() => atom()}) :: {:ok, term()} | {:error, Refusal.t()}
  defp prefix(q, _env) when is_integer(q), do: {:ok, q}
  defp prefix(:len, _env), do: {:ok, :len}

  defp prefix({:reify, {:eq, t, u}}, env),
    do: prefix(Ast.arithmetize(Ast.eq(t, u)), env)

  defp prefix({:var, nm}, env) do
    case env do
      %{^nm => carrier} -> {:ok, carrier}
      _env -> {:error, {:unbound_variable, %{variable: nm}}}
    end
  end

  defp prefix({op, t, u}, env) when op in [:add, :mul] do
    with {:ok, pt} <- prefix(t, env),
         {:ok, pu} <- prefix(u, env),
         do: {:ok, [op, pt, pu]}
  end

  defp prefix(term, _env), do: {:error, {:unliftable_term, %{term: term}}}

  # A prefix term as the DSL writes it, and the names it waits on.
  @spec pure(term()) :: Macro.t()
  defp pure(q) when is_integer(q), do: q
  defp pure(a) when is_atom(a), do: v(a)
  defp pure([op, t, u]), do: {arith(op), [], [pure(t), pure(u)]}

  @spec arith(atom()) :: atom()
  defp arith(:add), do: :+
  defp arith(:mul), do: :*

  @spec leaves(term()) :: [atom()]
  defp leaves(q) when is_integer(q), do: []
  defp leaves(a) when is_atom(a), do: [a]
  defp leaves([_op, t, u]), do: leaves(t) ++ leaves(u)

  @spec v(atom()) :: Macro.t()
  defp v(name), do: {name, [], nil}
end
