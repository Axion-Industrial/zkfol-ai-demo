defmodule Zkfol.Semantics do
  @moduledoc """
  I am the integer semantics of the logic: Figure 3 of the paper, where zero
  is the one true value and predicates never go negative (Lemma 2.17).
  """

  alias Zkfol.Ast
  alias Zkfol.Interpretation

  @doc "I evaluate a term or predicate at column `x` under `itp`; for a predicate 0 is true."
  @spec eval(Ast.term_t() | Ast.pred(), Interpretation.t(), pos_integer()) :: integer() | :error
  def eval(node, itp, x) do
    Ast.postwalk(node, fn
      q when is_integer(q) ->
        q

      :x ->
        x

      :len ->
        Interpretation.len(itp)

      {:cell, _i} = read ->
        at(read, itp, x)

      {:cell, _i, _address} = read ->
        at(read, itp, x)

      {:add, a, b} ->
        defined([a, b], fn -> a + b end)

      {:mul, a, b} ->
        product([a, b])

      {:reify, v} ->
        v

      {:natural, v} ->
        defined([v], fn -> if v >= 0, do: 0, else: 1 end)

      {:permutes, cells, values} ->
        defined(cells, fn -> if Enum.sort(cells) == Enum.sort(values), do: 0, else: 1 end)

      {:eq, a, b} ->
        defined([a, b], fn -> (a - b) * (a - b) end)

      {:conj, vs} ->
        defined(vs, fn -> Enum.sum(vs) end)

      {:disj, vs} ->
        product(vs)
    end)
  end

  @doc "I am the column an address names under `itp` at `x`, or `:error` off the matrix."
  @spec column(Ast.address(), Interpretation.t(), pos_integer()) :: integer() | :error
  def column({:at, base, _mul, _add} = address, itp, x) do
    with b when is_integer(b) <- standing(base, itp, x), do: Ast.column(address, b)
  end

  @spec at(Ast.term_t(), Interpretation.t(), pos_integer()) :: integer() | :error
  defp at(read, itp, x) do
    {i, address} = Ast.read(read)
    fetch(itp, i, column(address, itp, x))
  end

  @spec standing(Ast.address_base(), Interpretation.t(), pos_integer()) :: integer() | :error
  defp standing(:x, _itp, x), do: x
  defp standing({:cell, j}, itp, x), do: fetch(itp, j, x)

  @spec fetch(Interpretation.t(), Ast.row_ref(), integer() | :error) :: integer() | :error
  defp fetch(_itp, _i, :error), do: :error

  defp fetch(itp, i, x) do
    with {:ok, held} <- Interpretation.fetch(itp, i, x), do: held
  end

  @spec defined([integer() | :error], (-> integer())) :: integer() | :error
  defp defined(vs, said), do: if(:error in vs, do: :error, else: said.())

  # A zero factor makes the product zero even beside an undefined cell.
  @spec product([integer() | :error]) :: integer() | :error
  defp product(vs), do: if(0 in vs, do: 0, else: defined(vs, fn -> Enum.product(vs) end))

  @doc "I am the judgement: `itp` satisfies `phi` exactly when `phi` is 0 at every column."
  @spec valid?(Ast.pred(), Interpretation.t()) :: boolean()
  def valid?(phi, itp), do: Enum.all?(1..Interpretation.len(itp), &holds?(phi, itp, &1))

  @doc "I am true when `phi` holds at column `x` under `itp`; an undefined cell holds nothing."
  @spec holds?(Ast.pred(), Interpretation.t(), pos_integer()) :: boolean()
  def holds?(phi, itp, x), do: eval(phi, itp, x) == 0
end
