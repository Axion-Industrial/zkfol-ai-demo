defmodule Zkfol.Phi.View do
  @moduledoc """
  I describe a sequence's access to existing trace cells.

  A sequence's elements are scalars or fixed-width records. Selecting a record
  returns an ordinary list of cell references: list matching handles its head
  and tail, and no puzzle cells are copied.

  `row` names the first component row; `col = {:at, base, scale, offset}` names the
  head column. Sequences end at column one, so the head address is the remaining
  length plus one. Changing that address determines the length. A record's
  components occupy consecutive rows at the same column.

  ### Public API

  - `bank/2`: a sequence with its records' component rows.
  - `cell/2`, `cells/1`, `slice/2`, `shifted/2`: access and traversal over the same cells.
  - `count/1`, `size/1`, `width/1`, `finite?/1`, `rows/1`: shape and access span.
  - `framed/2`, `reframed/2`, `stepped/2`: express the view at a call's column.
  - `presence/1`, `peeled/1`, `ended/1`, `bounded/2`: equations required by observations.
  """

  use TypedStruct

  alias Zkfol.Alloc.Bank
  alias Zkfol.Ast

  @type extent :: non_neg_integer() | {integer(), integer()} | :open

  defmodule Record do
    @moduledoc "I describe a sequence element with a fixed number of scalar components."
    use TypedStruct

    typedstruct enforce: true do
      field(:width, non_neg_integer())
    end
  end

  typedstruct enforce: true do
    field(:row, Zkfol.Ast.row_ref())
    field(:col, Ast.address() | nil)
    field(:length, extent())
    field(:element, :scalar | Record.t())
  end

  @doc "I access `len` elements in a bank, starting at column `len + 1`."
  @spec bank(Bank.t(), extent()) :: t()
  def bank(%Bank{name: name, depth: width}, len) do
    len = normal(len)
    element = if width == 1, do: :scalar, else: %Record{width: width}
    %__MODULE__{row: {name, 1}, col: placed(len), length: len, element: element}
  end

  @spec placed(extent()) :: Ast.address() | nil
  defp placed({m, a}), do: Ast.address(:x, m, a + 1)
  defp placed(n) when is_integer(n), do: placed({0, n})
  defp placed(:open), do: nil

  @spec normal(extent()) :: extent()
  defp normal({0, n}), do: n
  defp normal(extent), do: extent

  @doc "I return the sequence length when it is known."
  @spec count(t()) :: non_neg_integer() | nil
  def count(%__MODULE__{length: n}), do: if(is_integer(n), do: n)

  @doc "I return the number of scalar cells when the sequence length is known."
  @spec size(t()) :: non_neg_integer() | nil
  def size(view = %__MODULE__{length: n}),
    do: if(is_integer(n), do: n * width(view))

  @doc "I say whether my sequence has a known length and a column address."
  @spec finite?(t()) :: boolean()
  def finite?(%__MODULE__{col: nil}), do: false
  def finite?(%__MODULE__{length: n}), do: is_integer(n)

  @doc "I return the number of component rows used by each element."
  @spec width(t()) :: non_neg_integer()
  def width(%__MODULE__{element: %Record{width: n}}), do: n
  def width(%__MODULE__{}), do: 1

  @doc "I give back rows starting with the given view"
  @spec rows(t()) :: [Zkfol.Ast.row_ref()]
  def rows(view = %__MODULE__{row: {bank, first}}) do
    Enum.map(first..(first + width(view) - 1)//1, &{bank, &1})
  end

  @doc "I map source indices to the existing trace cell they name."
  @spec cell(t(), [integer()]) :: Zkfol.Ast.term_t()
  def cell(view = %__MODULE__{row: {bank, first}, col: {:at, base, m, offset}}, indices) do
    element_index = Enum.at(indices, 0, 0)

    component_index =
      if match?(%Record{}, view.element), do: Enum.at(indices, 1, 0), else: 0

    Zkfol.Ast.at({bank, first + component_index}, base, m, offset - element_index)
  end

  @doc "I return cell references in source order: each element's components, then the next element."
  @spec cells(t()) :: [Zkfol.Ast.term_t()]
  def cells(view = %__MODULE__{}) do
    if size(view) == nil, do: throw({:refused, {:unliftable_term, %{term: view}}})
    for i <- 0..(view.length - 1)//1, j <- 0..(width(view) - 1)//1, do: cell(view, [i, j])
  end

  @doc "I select one scalar or a record of references to existing cells."
  @spec slice(t(), integer()) :: [Zkfol.Ast.term_t()] | Zkfol.Ast.term_t()
  def slice(view = %__MODULE__{element: :scalar}, i), do: cell(view, [i])

  def slice(view = %__MODULE__{}, i),
    do: for(j <- 0..(width(view) - 1)//1, do: cell(view, [i, j]))

  @doc "I skip `i` elements, moving the head and reducing the remaining length."
  @spec shifted(t(), integer()) :: t()
  def shifted(view = %__MODULE__{col: {:at, base, scale, offset}}, i),
    do: located(view, Ast.address(base, scale, offset - i))

  @doc "I express my head address in the caller's coordinates."
  @spec framed(t(), Zkfol.Phi.Value.frame()) :: t()
  def framed(view = %__MODULE__{col: nil}, _frame), do: view

  def framed(view = %__MODULE__{}, frame) do
    with col = {:at, _, _, _} <- Ast.reframe(view.col, frame),
         do: located(view, col),
         else: (_unreached -> throw({:refused, {:unliftable_term, %{term: view}}}))
  end

  @doc "I express my head address in the callee's coordinates, or leave it unplaced."
  @spec reframed(t(), Zkfol.Phi.Value.frame()) :: t()
  def reframed(view = %__MODULE__{}, frame), do: located(view, Ast.unframe(view.col, frame))

  # A sequence's empty suffix is at column one.
  @spec located(t(), Ast.address() | nil) :: t()
  defp located(view, col = {:at, _base, m, a}),
    do: %{view | col: col, length: normal({m, a - 1})}

  defp located(view = %__MODULE__{length: n}, nil),
    do: %{view | col: nil, length: if(is_integer(n), do: n, else: :open)}

  @doc "I place a sequence counted by the member's column at its inferred length."
  @spec stepped(t(), extent()) :: t() | nil
  def stepped(view = %__MODULE__{}, n) when is_integer(n), do: stepped(view, {0, n})
  def stepped(view = %__MODULE__{}, :open), do: located(view, nil)

  def stepped(view = %__MODULE__{col: {:at, :x, _, _}}, form),
    do: located(view, placed(form))

  def stepped(view = %__MODULE__{col: nil, length: :open}, form),
    do: located(view, placed(form))

  def stepped(_view, _form), do: nil

  @doc "I am my presence cell: my bank's presence row, read at my own column."
  @spec presence(t()) :: Zkfol.Ast.term_t()
  def presence(%__MODULE__{row: {bank, _r}, col: {:at, base, m, a}}),
    do: Zkfol.Ast.at({:in, bank}, base, m, a)

  @doc """
  I require an element: a known length decides directly; an unknown sequence
  length requires presence at its head.
  """
  @spec peeled(t()) :: {:ok, [Zkfol.Ast.pred()]} | :dead
  def peeled(view = %__MODULE__{}) do
    e = view.length

    cond do
      e == 0 -> :dead
      is_integer(e) -> {:ok, []}
      true -> {:ok, [Zkfol.Ast.eq(presence(view), 1)]}
    end
  end

  @doc "I require an empty sequence: a known length decides directly; otherwise its head must be absent."
  @spec ended(t()) :: {:ok, [Zkfol.Ast.pred()]} | :dead
  def ended(view = %__MODULE__{}) do
    e = view.length

    cond do
      e == 0 -> {:ok, []}
      is_integer(e) -> :dead
      true -> {:ok, [Zkfol.Ast.eq(presence(view), 0)]}
    end
  end

  @doc "I require presence for exactly `n` elements."
  @spec bounded(t(), non_neg_integer()) :: [Zkfol.Ast.pred()]
  def bounded(view = %__MODULE__{}, 0), do: [Zkfol.Ast.eq(presence(view), 0)]

  def bounded(view = %__MODULE__{}, n),
    do: [Zkfol.Ast.eq(presence(view), 1), Zkfol.Ast.eq(presence(shifted(view, n)), 0)]
end
