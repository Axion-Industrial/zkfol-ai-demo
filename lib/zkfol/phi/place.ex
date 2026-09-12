defmodule Zkfol.Phi.Place do
  @moduledoc """
  I represent the value's location in the trace. A shape is a fact about a bank, held by the walk,
  so a place says only which cells.

  - a term: a scalar's place is the cell, or the expression in cells, that holds it.
  - `along`: a list unrolled along the trace. `row` is the bank's first row and the head
    is the column, affine in X, of the head element. Element k is at the head column minus
    k; an element's scalars are on consecutive rows. Only `Zkfol.Unrolling` makes one.
  - `held`: a list in a bank held behind a pointer: the cell `ref` names a column `c`, and
    the head element stands at `m·c + a`. Elements follow as in `along`.
  - `across`: a list laid across rows at one column, with `skipped` fields already read.
    An element of a list in a bank is read this way when it is itself a list.
  - `node`: a term in the heap, by its id.
  - a literal: an integer, or a list of places; the call it is handed to places it.
  - `pair`: a list built from a head and a tail, placed nowhere itself.
  - `rel`: a relation passed by name, with its fixed arguments.
  - `count`: a handed count, standing in the cell that holds it.
  - `fresh`: a parameter nothing has bound, by its row; `:fresh` when it has none yet.

  ### Public API

  - `shape/2`: the shape of a place, given the banks' shapes.
  - `peel/2`, `ended/2`: a list as head and tail, or as empty, and what that taught.
  - `is_laid/1`: the guard for a list in a bank, `along` or `held`.
  - `slice/3`, `shifted/2`: one element of a list in a bank, and the list past `i`.
  - `extent/1`, `count/1`, `width/2`, `cells/2`, `size/2`: what a list in a bank holds.
  - `stepped/2`, `presence/1`, `bounded/2`: a list re-headed along the trace, and its presence.
  - `address/1`: the column form of a list's head, as the allocation and the backend read it.
  - `fresh?/1`: whether nothing has bound the place.
  - `affine/1`: the coefficients of a scalar place that is `m * X + a`.
  - `framed/2`, `unframed/2`: an addressed place from a call's column, and back.
  - `head/1`: the head of a list of a shape unrolled along the trace, which ends at column one.
  - `node_of/1`, `read/2`: the node realizing a place, and a field read through a node.
  """

  alias Zkfol.Ast
  alias Zkfol.Phi.Shape

  @typedoc "How a cell is named through a node: its tag, value, head or tail."
  @type field :: :tag | :value | :head | :tail

  @typedoc "The column an unrolled list's head stands at: affine in X."
  @type head :: {:at, :x, integer(), integer()}

  @type t ::
          Ast.term_t()
          # Used for unrolling lists.
          | {:along, Ast.row_ref(), head()}
          | {:held, Ast.row_ref(), Ast.row_ref(), {integer(), integer()}}
          | {:across, Ast.row_ref(), Ast.address(), non_neg_integer()}
          | {:node, Ast.term_t()}
          | [t()]
          | {:pair, t(), t()}
          | {:rel, atom(), [t()]}
          | {:count, integer(), Ast.term_t()}
          | {:fresh, Ast.row_ref()}
          | :fresh

  @typedoc "What is known of each bank: the shape of every element on its rows."
  @type known :: %{Ast.row_ref() => Shape.t()}

  @typedoc "What an observation learned: a bank's shape, or nothing."
  @type learned :: known()

  @doc "I match a list in a bank: `along` or `held`."
  defguard is_laid(place) when is_tuple(place) and elem(place, 0) in [:along, :held]

  @doc "I return the shape of a place"
  @spec shape(t(), known()) :: Shape.t()
  def shape(place, known) do
    case place do
      {:node, _id} -> :unknown
      :fresh -> :unknown
      {:fresh, _ref} -> :unknown
      {:pair, head, tail} -> after_one(shape(tail, known), shape(head, known))
      {:along, row, _head} -> {:list, extent(place), Map.get(known, row, :unknown)}
      {:held, row, _ref, _head} -> {:list, extent(place), Map.get(known, row, :unknown)}
      {:rel, _name, _fixed} -> :unknown
      cells when is_list(cells) -> {:list, {0, length(cells)}, data_shape(cells, known)}
      {:across, row, _address, skipped} -> rest(Map.get(known, row, :unknown), skipped)
      _term -> :scalar
    end
  end

  @doc "I return the head column of a list of this shape laid along the trace. A list of extent n heads at column n + 1. An open list heads at X."
  @spec head(Shape.t()) :: head()
  def head({:list, extent, _element}) do
    case Shape.longer(extent, 1) do
      {:at_least, _} -> Ast.address(:x, 1, 0)
      {m, a} -> Ast.address(:x, m, a)
    end
  end

  @doc "I return the column form of a list's head, as the allocation and the backend read it."
  @spec address(t()) :: Ast.address()
  def address({:along, _row, head}), do: head
  def address({:held, _row, ref, {m, a}}), do: Ast.address({:cell, ref}, m, a)

  @doc "I return a list's extent. A list along the trace ends at column one, so its extent is its head column minus one. A held list is open."
  @spec extent(t()) :: Shape.extent()
  def extent({:along, _row, {:at, :x, m, a}}), do: {m, a - 1}
  def extent({:held, _row, _ref, _head}), do: {:at_least, 0}

  # A record read past its first `skipped` fields is the list of those remaining.
  @spec rest(Shape.t(), non_neg_integer()) :: Shape.t()
  defp rest(shape, 0), do: shape

  defp rest(shape, skipped) do
    case shape do
      {:list, {0, n}, :scalar} ->
        {:list, {0, max(n - skipped, 0)}, :scalar}

      {:list, {:at_least, n}, :scalar} ->
        {:list, {:at_least, max(n - skipped, 0)}, :scalar}

      _ ->
        :unknown
    end
  end

  # Every element of a literal is a literal; the list's element shape is what they agree on.
  @spec data_shape([term()], known()) :: Shape.t()
  defp data_shape([], _known), do: :unknown

  defp data_shape(cells, known) do
    cells
    |> Enum.map(&shape(&1, known))
    |> Enum.reduce(&agreed/2)
  end

  # A pair is a list one longer than its tail, of what head and tail's elements agree on.
  @spec after_one(Shape.t(), Shape.t()) :: Shape.t()
  defp after_one({:list, {:at_least, n}, element}, head) do
    {:list, {:at_least, n + 1}, agreed(element, head)}
  end

  defp after_one({:list, {m, a}, element}, head) do
    {:list, {m, a + 1}, agreed(element, head)}
  end

  defp after_one(_scalar_or_unknown, head) do
    {:list, {:at_least, 1}, head}
  end

  @spec agreed(Shape.t(), Shape.t()) :: Shape.t()
  defp agreed(a, b) do
    case Shape.meet(a, b) do
      :contradiction -> :unknown
      shape -> shape
    end
  end

  @doc """
  I return a list's first element and the rest. The element of an `along` list is a cell
  when the bank holds scalars, and an `across` record otherwise. Peeling a record says the
  bank's elements have one more field than was known; I return that too.
  """
  @spec peel(t(), known()) :: {:ok, t(), t(), learned()} | :dead
  def peel(place, known) do
    case place do
      {:pair, head, tail} ->
        {:ok, head, tail, %{}}

      [head | tail] ->
        {:ok, head, tail, %{}}

      {:node, id} ->
        {:ok, {:node, read(:head, id)}, {:node, read(:tail, id)}, %{}}

      laid when is_laid(laid) ->
        {:ok, slice(laid, 0, known), shifted(laid, 1), %{}}

      {:across, row = {bank, first}, address, skipped} ->
        opened = {:list, {:at_least, skipped + 1}, :scalar}

        case Shape.meet(Map.get(known, row, :unknown), opened) do
          :contradiction ->
            :dead

          shape ->
            field = at({bank, first + skipped}, address)
            {:ok, field, {:across, row, address, skipped + 1}, %{row => shape}}
        end

      _ ->
        :dead
    end
  end

  @doc "I return what a list being empty says of its bank, or `:dead` when it cannot be empty."
  @spec ended(t(), known()) :: {:ok, learned()} | :dead
  def ended(place, known) do
    case place do
      [] ->
        {:ok, %{}}

      {:node, _id} ->
        {:ok, %{}}

      laid when is_laid(laid) ->
        {:ok, %{}}

      {:across, row, _address, skipped} ->
        case Shape.meet(Map.get(known, row, :unknown), {:list, {0, skipped}, :scalar}) do
          :contradiction -> :dead
          shape -> {:ok, %{row => shape}}
        end

      _scalar_or_nothing ->
        :dead
    end
  end

  @doc "I return element `i` of a list in a bank: a cell, a record's cells, or an element not yet known."
  @spec slice(t(), integer(), known()) :: t()
  def slice(laid, i, known) when is_laid(laid) do
    row = {bank, first} = elem(laid, 1)
    column = shifted_by(address(laid), i)

    case Map.get(known, row, :unknown) do
      :scalar -> at(row, column)
      {:list, {0, width}, :scalar} -> Enum.map(0..(width - 1)//1, &at({bank, first + &1}, column))
      _list_or_unknown -> {:across, row, column, 0}
    end
  end

  @doc "I return a list's element count when it is known."
  @spec count(t()) :: non_neg_integer() | nil
  def count(laid) when is_laid(laid), do: Shape.count({:list, extent(laid), :unknown})
  def count(_place), do: nil

  @doc "I return the rows each element of a list in a bank takes, when its bank's shape says."
  @spec width(t(), known()) :: pos_integer() | nil
  def width(laid, known) when is_laid(laid),
    do: Shape.width(Map.get(known, elem(laid, 1), :unknown))

  @doc "I return every cell of a list in a bank in source order, or refuse a list I cannot count."
  @spec cells(t(), known()) :: [Ast.term_t()]
  def cells(laid, known) when is_laid(laid) do
    {bank, first} = elem(laid, 1)

    case size(laid, known) do
      nil ->
        throw({:refused, {:unliftable_term, %{term: laid}}})

      _counted ->
        for i <- 0..(count(laid) - 1)//1, j <- 0..(width(laid, known) - 1)//1 do
          at({bank, first + j}, shifted_by(address(laid), i))
        end
    end
  end

  @doc "I return the number of cells a list in a bank holds, when known; an empty list holds none."
  @spec size(t(), known()) :: non_neg_integer() | nil
  def size(laid, known) when is_laid(laid) do
    case {count(laid), width(laid, known)} do
      {nil, _width} -> nil
      {0, _width} -> 0
      {_n, nil} -> nil
      {n, width} -> n * width
    end
  end

  @doc "I return a list in a bank re-headed along the trace at a shape's extent."
  @spec stepped(t(), Shape.t()) :: t()
  def stepped(laid, shape) when is_laid(laid), do: {:along, elem(laid, 1), head(shape)}

  @doc "I return a list's presence cell: its bank's presence row at its head column."
  @spec presence(t()) :: Ast.term_t()
  def presence(laid) when is_laid(laid) do
    {bank, _first} = elem(laid, 1)
    at({:in, bank}, address(laid))
  end

  @doc "I return the equations holding a list in a bank to exactly `n` elements."
  @spec bounded(t(), non_neg_integer()) :: [Ast.pred()]
  def bounded(laid, 0), do: [Ast.eq(presence(laid), 0)]

  def bounded(laid, n),
    do: [Ast.eq(presence(laid), 1), Ast.eq(presence(shifted(laid, n)), 0)]

  @doc "I return a list in a bank past its first `i` elements."
  @spec shifted(t(), integer()) :: t()
  def shifted({:along, row, head}, i), do: {:along, row, shifted_by(head, i)}
  def shifted({:held, row, ref, {m, a}}, i), do: {:held, row, ref, {m, a - i}}

  @doc "I say whether nothing has bound the place."
  @spec fresh?(t()) :: boolean()
  def fresh?(:fresh), do: true
  def fresh?({:fresh, _ref}), do: true
  def fresh?(_place), do: false

  @doc "I give back {m, a} for a scalar place m * X + a; other places have no affine form."
  @spec affine(t()) :: {integer(), integer()} | nil
  def affine(:x), do: {1, 0}
  def affine(q) when is_integer(q), do: {0, q}
  def affine({:count, _q, cell}), do: affine(cell)

  def affine({:add, a, b}) do
    case {affine(a), affine(b)} do
      {{m, k}, {0, q}} -> {m, k + q}
      _apart -> nil
    end
  end

  def affine({:mul, a, q}) when is_integer(q) do
    case affine(a) do
      {m, k} -> {m * q, k * q}
      nil -> nil
    end
  end

  def affine(_place), do: nil

  @doc "I return an addressed place as seen from a call's column. A held list has no column address, so it is unreached."
  @spec framed(t(), Ast.address()) :: t() | :unreached
  def framed(place, {:at, :x, 1, 0}), do: place
  def framed({:along, row, head}, frame), do: placed({:along, row, Ast.reframe(head, frame)})
  def framed({:held, _row, _ref, _head}, _frame), do: :unreached

  def framed({:across, row, address, n}, frame),
    do: placed({:across, row, Ast.reframe(address, frame), n})

  @doc "I return an addressed place as seen inside the call, or `:unreached` when the frame cannot express it."
  @spec unframed(t(), Ast.address()) :: t() | :unreached
  def unframed(place, {:at, :x, 1, 0}), do: place
  def unframed({:along, row, head}, frame), do: placed({:along, row, Ast.unframe(head, frame)})
  def unframed({:held, _row, _ref, _head}, _frame), do: :unreached

  def unframed({:across, row, address, n}, frame),
    do: placed({:across, row, Ast.unframe(address, frame), n})

  # A head the frame cannot express is unreached. A head reframed onto a pointer cell
  # becomes a held list.
  @spec placed(tuple()) :: t() | :unreached
  defp placed({:along, _row, nil}), do: :unreached
  defp placed({:along, row, {:at, {:cell, ref}, m, a}}), do: {:held, row, ref, {m, a}}
  defp placed({:across, _row, nil, _skipped}), do: :unreached
  defp placed(place), do: place

  @doc "I return the node realizing a place: itself when it is one, the empty list's, or a row named by it."
  @spec node_of(t() | term()) :: {:node, Ast.term_t()}
  def node_of(node = {:node, _id}), do: node
  def node_of([]), do: {:node, 1}
  def node_of(place), do: {:node, Ast.cell({Zkfol.Nodes, {:node, place}})}

  @doc "I read one field of a node: its tag, value, head or tail, through the staging row when its id is no row."
  @spec read(field(), Ast.term_t()) :: Ast.term_t()
  def read(field, {:cell, row}), do: Ast.cell({Zkfol.Nodes, field}, row)
  def read(field, id), do: Ast.cell({Zkfol.Nodes, field}, {Zkfol.Nodes, {:read, id}})

  @spec at(Ast.row_ref(), Ast.address()) :: Ast.term_t()
  defp at(row, {:at, base, m, a}), do: Ast.at(row, base, m, a)

  @spec shifted_by(Ast.address(), integer()) :: Ast.address()
  defp shifted_by({:at, base, m, a}, i), do: Ast.address(base, m, a - i)
end
