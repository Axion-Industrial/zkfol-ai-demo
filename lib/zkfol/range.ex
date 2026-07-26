defmodule Zkfol.Range do
  @moduledoc """
  I am the range checks R of Figure 1: `t < C_i` and `C_i < t`,
  with `t` any term, checked natively at every column.
  """

  alias Zkfol.Ast
  alias Zkfol.Interpretation
  alias Zkfol.Semantics

  @type check :: {:below, pos_integer(), Ast.term_t()} | {:above, pos_integer(), Ast.term_t()}

  # The check C_i(x) < t for all columns x.
  @spec below(pos_integer(), Ast.term_t()) :: check()
  defp below(i, t), do: {:below, i, t}

  # The check t < C_i(x) for all columns x.
  @spec above(pos_integer(), Ast.term_t()) :: check()
  defp above(i, t), do: {:above, i, t}

  @doc "I am the checks keeping pointer row `i` a valid column index, in 1..len."
  @spec pointer(pos_integer()) :: [check()]
  def pointer(i), do: [above(i, 0), below(i, Ast.add(Ast.len(), 1))]

  @doc "I decide whether a check holds under `itp`."
  @spec holds?(check(), Interpretation.t()) :: boolean()
  def holds?({:below, i, t}, itp) do
    all_columns?(itp, fn x -> Interpretation.at(itp, i, x) < Semantics.eval(t, itp, x) end)
  end

  def holds?({:above, i, t}, itp) do
    all_columns?(itp, fn x -> Semantics.eval(t, itp, x) < Interpretation.at(itp, i, x) end)
  end

  @spec all_columns?(Interpretation.t(), (pos_integer() -> boolean())) :: boolean()
  defp all_columns?(itp, fun), do: Enum.all?(1..Interpretation.len(itp), fun)
end
