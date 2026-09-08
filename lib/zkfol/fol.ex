defmodule Zkfol.FOL do
  @moduledoc """
  I am the standard relations: the helpers every program leans on,
  resolved by name wherever `use Zkfol.Lang` writes a clause, after the
  program's own and before the prims.

  ### Public API

  - `each/0`: `each(r, xs)`, `r` holding of every cell.
  - `map/0`: `map(r, xs, ys)`, `ys` the image of `xs` under `r`.
  - `length/0`: `length(xs, n)`.
  - `between/0`: `between(lo, hi, x)`.
  - `append/0`: `append(xs, ys, zs)`.
  - `concat/0`: `concat(xss, zs)`, the sequences of `xss` one after another.
  - `chunk/0`: `chunk(n, xs, ys)`, `xs` in runs of `n`.
  - `split/0`: `split(n, xs, ys, zs)`, the first `n` cells of `xs` and the rest.
  - `column/0`: `column(rows, cols)`, `cols` the transpose of `rows`.
  - `heads/0`: `heads(rows, hs, ts)`, one cell off the front of every row.
  """

  use Zkfol.Lang

  defrel each(_r, [])

  defrel each(r, [h | t]) do
    r(h)
    each(r, t)
  end

  defrel map(_r, [], [])

  defrel map(r, [h | t], [g | s]) do
    r(h, g)
    map(r, t, s)
  end

  defrel length([], 0)

  defrel length([_ | t], n) do
    length(t, m)
    n = m + 1
  end

  defrel between(lo, hi, x) do
    x >= lo
    x <= hi
  end

  defrel append([], ys, ys)

  defrel append([h | t], ys, [h | zs]) do
    append(t, ys, zs)
  end

  defrel concat([], [])

  defrel concat([xs | rest], zs) do
    concat(rest, ys)
    append(xs, ys, zs)
  end

  defrel chunk(_n, [], [])

  defrel chunk(n, xs, [c | cs]) do
    split(n, xs, c, rest)
    chunk(n, rest, cs)
  end

  defrel split(0, xs, [], xs)

  defrel split(n, [h | t], [h | p], rest) do
    split(n - 1, t, p, rest)
  end

  defrel heads([], [], [])

  defrel heads([[h | t] | rs], [h | hs], [t | ts]) do
    heads(rs, hs, ts)
  end

  defrel column([[] | _], [])

  defrel column(rows, [c | cs]) do
    heads(rows, c, rest)
    column(rest, cs)
  end
end
