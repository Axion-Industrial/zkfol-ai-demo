defmodule Zkfol.Phi.View do
  @moduledoc """
  I am cells of the trace read in an order: index `(i_1 .. i_k)` names the cell on row
  `r0 + sum(i_j * row_j)` at column `m * base + a + sum(i_j * col_j)`.
  """

  use TypedStruct

  @type extent :: non_neg_integer() | {integer(), integer()} | :open
  @type axis :: %{row: integer(), col: integer(), extent: extent()}
  @type col :: {Zkfol.Ast.address_base(), integer(), integer()} | nil

  typedstruct enforce: true do
    field(:row, Zkfol.Ast.row_ref() | nil)
    field(:col, col())
    field(:axes, [axis()], default: [])
  end

  @doc "I am a bank of `rows` `len` long: cell p at `m * X + a + 1 - p`, cell r on row r."
  @spec bank([Zkfol.Ast.row_ref()], extent()) :: t()
  def bank([row | rest] = rows, len) do
    len = normal(len)
    inner = if rest == [], do: [], else: [%{row: 1, col: 0, extent: length(rows)}]
    %__MODULE__{row: row, col: placed(len), axes: [%{row: 0, col: -1, extent: len} | inner]}
  end

  @spec placed(extent()) :: col()
  defp placed({m, a}), do: {:x, m, a + 1}
  defp placed(n) when is_integer(n), do: placed({0, n})
  defp placed(:open), do: nil

  @spec normal(extent()) :: extent()
  defp normal({0, n}), do: n
  defp normal(extent), do: extent

  @doc "I am my outer extent."
  @spec len(t()) :: extent()
  def len(%__MODULE__{axes: [%{extent: extent} | _rest]}), do: extent

  @doc "I am how many outer cells I hold, where that stands still."
  @spec count(t()) :: non_neg_integer() | nil
  def count(%__MODULE__{} = view), do: if(is_integer(len(view)), do: len(view))

  @doc "I am how many cells I hold in all, where every extent of mine stands still."
  @spec size(t()) :: non_neg_integer() | nil
  def size(%__MODULE__{axes: axes}) do
    if Enum.all?(axes, &is_integer(&1.extent)), do: Enum.product(for(a <- axes, do: a.extent))
  end

  @doc "I say whether my extent stands still: I step rows, or my outer extent is a number."
  @spec finite?(t()) :: boolean()
  def finite?(%__MODULE__{col: nil}), do: false
  def finite?(%__MODULE__{} = view), do: rowed?(view) or is_integer(len(view))

  @doc "I say whether my outer axis steps rows, which only compile time indexes."
  @spec rowed?(t()) :: boolean()
  def rowed?(%__MODULE__{axes: [%{row: dr} | _rest]}), do: dr != 0

  @doc "I am the rows I span: the origin's and every row a row axis reaches."
  @spec rows(t()) :: [Zkfol.Ast.row_ref()]
  def rows(%__MODULE__{row: {bank, r0}, axes: axes}) do
    rowed = for %{row: dr, extent: e} <- axes, dr != 0, do: for(i <- 0..(e - 1)//1, do: i * dr)
    for o <- Enum.sort(Enum.map(product(rowed), &Enum.sum/1)), do: {bank, r0 + o}
  end

  @spec product([[integer()]]) :: [[integer()]]
  defp product([]), do: [[]]
  defp product([choices | rest]), do: for(i <- choices, more <- product(rest), do: [i | more])

  @doc "I am the cell at `indices`, as a term."
  @spec cell(t(), [integer()]) :: Zkfol.Ast.term_t()
  def cell(%__MODULE__{row: {bank, r0}, col: {base, m, a}, axes: axes}, indices) do
    steps = Enum.zip(indices, axes)
    dr = Enum.sum(for {i, axis} <- steps, do: i * axis.row)
    dc = Enum.sum(for {i, axis} <- steps, do: i * axis.col)
    Zkfol.Ast.at({bank, r0 + dr}, base, m, a + dc)
  end

  @doc "I am every cell of mine in index order, where every extent stands still."
  @spec cells(t()) :: [Zkfol.Ast.term_t()]
  def cells(%__MODULE__{axes: axes} = view) do
    unless Enum.all?(axes, &is_integer(&1.extent)),
      do: throw({:refused, {:unliftable_term, %{term: view}}})

    for indices <- product(for(a <- axes, do: Enum.to_list(0..(a.extent - 1)//1))),
        do: cell(view, indices)
  end

  @doc "I am my `i`-th outer cell: a view a rank lower, or the cell itself."
  @spec slice(t(), integer()) :: t() | Zkfol.Ast.term_t()
  def slice(%__MODULE__{axes: [_one]} = view, i), do: cell(view, [i])

  def slice(%__MODULE__{axes: [axis | rest]} = view, i),
    do: %{moved(view, axis, i) | axes: rest}

  @doc "I am myself from my `i`-th outer cell on."
  @spec shifted(t(), integer()) :: t()
  def shifted(%__MODULE__{axes: [axis | rest]} = view, i),
    do: %{moved(view, axis, i) | axes: [%{axis | extent: less(axis.extent, i)} | rest]}

  @spec moved(t(), axis(), integer()) :: t()
  defp moved(%__MODULE__{row: {bank, r0}, col: {base, m, a}} = view, axis, i),
    do: %{view | row: {bank, r0 + i * axis.row}, col: {base, m, a + i * axis.col}}

  @spec less(extent(), integer()) :: extent()
  defp less({m, a}, i), do: normal({m, a - i})
  defp less(n, i) when is_integer(n), do: n - i
  defp less(:open, _i), do: :open

  @doc "I am myself as the caller sees me: my column's base worn in `frame`."
  @spec framed(t(), Zkfol.Phi.Value.frame()) :: t()
  def framed(%__MODULE__{col: {:x, mc, ac}} = view, {m, a}) when is_integer(m) do
    axes = for axis <- view.axes, do: %{axis | extent: scaled(axis.extent, m, a)}
    %{view | col: {:x, mc * m, mc * a + ac}, axes: axes}
  end

  def framed(%__MODULE__{col: {:x, mc, ac}} = view, {:ptr, w}),
    do: %{view | col: {{:cell, w}, mc, ac}}

  def framed(%__MODULE__{col: nil} = view, _frame), do: view

  def framed(%__MODULE__{} = deref, _frame),
    do: throw({:refused, {:unliftable_term, %{term: deref}}})

  @spec scaled(extent(), integer(), integer()) :: extent()
  defp scaled({me, ae}, m, a), do: normal({me * m, me * a + ae})
  defp scaled(extent, _m, _a), do: extent

  @doc "I am myself as the callee sees me, `framed`'s inverse; the unreached lose their column."
  @spec reframed(t(), Zkfol.Phi.Value.frame()) :: t()
  def reframed(%__MODULE__{row: nil, col: {:x, 0, _q}} = literal, _frame), do: literal

  def reframed(%__MODULE__{col: {:x, mc, ac}} = view, {m, a}) when is_integer(m) do
    with {:ok, mc2} <- divided(mc, m),
         {:ok, axes} <- unscaled(view.axes, m, a) do
      %{view | col: {:x, mc2, ac - mc2 * a}, axes: axes}
    else
      :apart -> unplaced(view)
    end
  end

  def reframed(%__MODULE__{} = view, _frame), do: unplaced(view)

  @spec unplaced(t()) :: t()
  defp unplaced(%__MODULE__{} = view) do
    axes =
      for a <- view.axes, do: %{a | extent: if(is_integer(a.extent), do: a.extent, else: :open)}

    %{view | col: nil, axes: axes}
  end

  @spec unscaled([axis()], integer(), integer()) :: {:ok, [axis()]} | :apart
  defp unscaled([], _m, _a), do: {:ok, []}

  defp unscaled([%{extent: {me, ae}} = axis | rest], m, a) do
    with {:ok, me2} <- divided(me, m),
         {:ok, more} <- unscaled(rest, m, a),
         do: {:ok, [%{axis | extent: normal({me2, ae - me2 * a})} | more]}
  end

  defp unscaled([axis | rest], m, a),
    do: with({:ok, more} <- unscaled(rest, m, a), do: {:ok, [axis | more]})

  @spec divided(integer(), integer()) :: {:ok, integer()} | :apart
  defp divided(0, _m), do: {:ok, 0}
  defp divided(_c, 0), do: :apart
  defp divided(c, m), do: if(rem(c, m) == 0, do: {:ok, div(c, m)}, else: :apart)

  @doc """
  I am myself as a member whose column counts me reads me: `k * X + c` outer cells left
  at column X, the head affine in X.
  """
  @spec stepped(t(), extent()) :: t() | nil
  def stepped(%__MODULE__{} = view, n) when is_integer(n), do: stepped(view, {0, n})
  def stepped(%__MODULE__{} = view, :open), do: unplaced(view)

  def stepped(%__MODULE__{col: {:x, mc, ac}, axes: [%{extent: e} = axis | rest]} = view, {k, c})
      when e != :open do
    {me, ae} = if(is_integer(e), do: {0, e}, else: e)
    col = {:x, mc + axis.col * (me - k), ac + axis.col * (ae - c)}
    %{view | col: col, axes: [%{axis | extent: normal({k, c})} | rest]}
  end

  def stepped(%__MODULE__{} = view, form) do
    if view == bank(rows(view), len(view)), do: bank(rows(view), form)
  end

  @doc "I am my presence cell: my bank's presence row, read at my own column."
  @spec presence(t()) :: Zkfol.Ast.term_t()
  def presence(%__MODULE__{row: {bank, _r}, col: {base, m, a}}),
    do: Zkfol.Ast.at({:in, bank}, base, m, a)

  @doc """
  I am what peeling my outer cell costs: a row axis holds one where its
  extent says so, a column axis where my presence says so, a known
  extent deciding outright.
  """
  @spec peeled(t()) :: {:ok, [Zkfol.Ast.pred()]} | :dead
  def peeled(%__MODULE__{axes: [%{extent: e} | _rest]} = view) do
    cond do
      e == 0 -> :dead
      is_integer(e) -> {:ok, []}
      rowed?(view) -> :dead
      true -> {:ok, [Zkfol.Ast.eq(presence(view), 1)]}
    end
  end

  @doc "I am what a closed end past my cells costs: my presence 0 there, or my extent spent."
  @spec ended(t()) :: {:ok, [Zkfol.Ast.pred()]} | :dead
  def ended(%__MODULE__{axes: [%{extent: e} | _rest]} = view) do
    cond do
      e == 0 -> {:ok, []}
      is_integer(e) -> :dead
      rowed?(view) -> :dead
      true -> {:ok, [Zkfol.Ast.eq(presence(view), 0)]}
    end
  end

  @doc "I am the presence equations fencing me to `n` cells."
  @spec bounded(t(), non_neg_integer()) :: [Zkfol.Ast.pred()]
  def bounded(%__MODULE__{} = view, 0), do: [Zkfol.Ast.eq(presence(view), 0)]

  def bounded(%__MODULE__{} = view, n),
    do: [Zkfol.Ast.eq(presence(view), 1), Zkfol.Ast.eq(presence(shifted(view, n)), 0)]

  @doc "I am a term as a view of rank zero: a cell at its address, or a term affine in X."
  @spec of(term()) :: t() | nil
  def of(:x), do: %__MODULE__{row: nil, col: {:x, 1, 0}}
  def of(q) when is_integer(q), do: %__MODULE__{row: nil, col: {:x, 0, q}}
  def of({:count, q, _cell}), do: of(q)

  def of({:add, a, b}) do
    with %__MODULE__{row: nil, col: {:x, m, k}} <- of(a),
         %__MODULE__{row: nil, col: {:x, 0, q}} <- of(b),
         do: %__MODULE__{row: nil, col: {:x, m, k + q}},
         else: (_apart -> nil)
  end

  def of({:mul, a, q}) when is_integer(q) do
    with %__MODULE__{row: nil, col: {:x, m, k}} <- of(a),
         do: %__MODULE__{row: nil, col: {:x, m * q, k * q}},
         else: (_apart -> nil)
  end

  def of(cell) do
    with {ref, {:at, base, m, a}} <- Zkfol.Ast.read(cell),
         do: %__MODULE__{row: ref, col: {base, m, a}}
  end

  @doc "I am a view of rank zero as the term it reads: the cell, or the column's term."
  @spec term(t()) :: Zkfol.Ast.term_t()
  def term(%__MODULE__{row: nil, col: {base, m, a}}),
    do: Zkfol.Ast.add(Zkfol.Ast.mul(base, m), a)

  def term(%__MODULE__{row: ref, col: {base, m, a}, axes: []}),
    do: Zkfol.Ast.at(ref, base, m, a)
end
