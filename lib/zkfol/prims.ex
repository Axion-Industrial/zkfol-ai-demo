defmodule Zkfol.Prims do
  @moduledoc """
  I am the library the surface's comparisons, reductions and reads call:
  each is a relation whose body is its meaning, written once.
  """

  use Zkfol.Lang

  @phi {Zkfol.Ast, :natural}
  @al quote(do: x >= 0)
  defrel natural(x)

  @al quote(do: a > b)
  defrel gt(a, b, s) do
    a = b + 1 + s
    natural(s)
  end

  @al quote(do: a >= b)
  defrel gte(a, b, s) do
    a = b + s
    natural(s)
  end

  @al quote(do: a < b)
  defrel lt(a, b, s) do
    b = a + 1 + s
    natural(s)
  end

  @al quote(do: a <= b)
  defrel lte(a, b, s) do
    b = a + s
    natural(s)
  end

  @phi {Zkfol.Ast, :nth}
  defrel nth(1, [v | _], v)

  defrel nth(n, [_ | t], v) do
    nth(n - 1, t, v)
  end

  # One branch stands above, the other below: apart either way.
  defrel neq(a, b, s) do
    a = b + 1 + s
    natural(s)
  end

  defrel neq(a, b, s) do
    b = a + 1 + s
    natural(s)
  end

  # AL narrows a free grid by `all_dif`; pairwise slack has no bound and exhausts the heap.
  @phi {Zkfol.Ast, :distinct}
  @al quote(do: all_dif(cells))
  defrel all_distinct(cells)

  # The values are the circuit's own: one prescribed lookup, no copy.
  @phi {Zkfol.Ast, :permutation}
  defrel permutation(n, cells) do
    length(cells, n)
    each(cells, between(1, n))
    all_distinct(cells)
  end

  # Evaluation only: a free cell takes each value of its domain in turn.
  @al quote(do: label(x))
  defrel label(x)

  defrel mod(e, m, r, q) do
    e = m * q + r
    r < m
    natural(r)
    natural(q)
  end
end
