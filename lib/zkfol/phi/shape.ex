defmodule Zkfol.Phi.Shape do
  @moduledoc """
  I am what is known of a value's structure.

  Knowledge is monotonic. Unknown becomes scalar or list; `{:at_least, n}` becomes an
  extent; nothing else changes.

  ### Public API

  - `meet/2`: what two accounts of one value agree on, or `:contradiction`.
  - `count/1`, `width/1`: a list's element count; a list of scalars' count.
  - `longer/2`, `from/2`: an extent some elements longer, and seen from another column.
  """

  @typedoc """
  How many elements a list has: `m·X + a` along the trace, a count being `{0, n}`; or at
  least `n`, nothing known being `{:at_least, 0}`.
  """
  @type extent :: {integer(), integer()} | {:at_least, non_neg_integer()}

  @type t :: :unknown | :scalar | {:list, extent(), t()}

  @doc "I return what two accounts of one value agree on, or `:contradiction`."
  @spec meet(t(), t()) :: t() | :contradiction
  def meet(:unknown, shape), do: shape
  def meet(shape, :unknown), do: shape
  def meet(:scalar, :scalar), do: :scalar

  def meet({:list, a, of_a}, {:list, b, of_b}) do
    with extent when extent != :contradiction <- extents(a, b),
         element when element != :contradiction <- meet(of_a, of_b),
         do: {:list, extent, element}
  end

  def meet(_, _), do: :contradiction

  # A bound yields to a higher bound or to any extent; two extents must be equal.
  @spec extents(extent(), extent()) :: extent() | :contradiction
  defp extents(extent, extent), do: extent
  defp extents({:at_least, a}, {:at_least, b}), do: {:at_least, max(a, b)}
  defp extents({:at_least, bound}, {0, n}) when n < bound, do: :contradiction
  defp extents({0, n}, {:at_least, bound}) when n < bound, do: :contradiction
  defp extents({:at_least, _}, extent), do: extent
  defp extents(extent, {:at_least, _}), do: extent
  defp extents(_, _), do: :contradiction

  @doc "I return the extent `d` elements longer; a bound cannot fall below zero."
  @spec longer(extent(), integer()) :: extent()
  def longer({:at_least, n}, d), do: {:at_least, max(n + d, 0)}
  def longer({m, a}, d), do: {m, a + d}

  @doc "I return the extent as seen from the column `d` further on: `m·(X + d) + a`."
  @spec from(extent(), integer()) :: extent()
  def from(bound = {:at_least, _}, _d), do: bound
  def from({m, a}, d), do: {m, m * d + a}

  @doc "I return a list's element count when it is known."
  @spec count(t()) :: non_neg_integer() | nil
  def count({:list, {0, n}, _}), do: n
  def count(_), do: nil

  @doc "I return the count of a list of scalars: the rows a record takes, one per field."
  @spec width(t()) :: non_neg_integer() | nil
  def width(:scalar), do: 1
  def width({:list, {0, n}, :scalar}), do: n
  def width(_), do: nil
end
