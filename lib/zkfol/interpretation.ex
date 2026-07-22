defmodule Zkfol.Interpretation do
  @moduledoc """
  I am an interpretation of the matrix symbol C: Definition 2.16 of the paper.

  I hold one rectangular matrix of non-negative integers, indexed 1-based as
  `C@i,x` (row `i`, column `x`). The number of rows is the arity; the number
  of columns is len(C).
  """

  use TypedStruct

  @typedoc "A public claim: the named cell (row, column) carries the result."
  @type claim :: {String.t(), pos_integer(), pos_integer()}

  typedstruct enforce: true do
    field(:rows, tuple())
  end

  @doc """
  I build an interpretation from a list of equal-length rows of
  non-negative integers. I raise on anything else.
  """
  @spec new([[non_neg_integer()]]) :: t()
  def new([first | _] = rows) when first != [] do
    widths = rows |> Enum.map(&length/1) |> Enum.uniq()

    unless widths == [length(first)] do
      raise ArgumentError, "rows must have equal length, got #{inspect(widths)}"
    end

    for row <- rows, entry <- row, not is_integer(entry) or entry < 0 do
      raise ArgumentError, "entries must be non-negative integers, got #{inspect(entry)}"
    end

    %__MODULE__{rows: rows |> Enum.map(&List.to_tuple/1) |> List.to_tuple()}
  end

  @doc "I am my rows as lists: the shape `new/1` accepts."
  @spec rows(t()) :: [[non_neg_integer()]]
  def rows(%__MODULE__{rows: rows}),
    do: rows |> Tuple.to_list() |> Enum.map(&Tuple.to_list/1)

  @doc "I return C@i,x."
  @spec at(t(), pos_integer(), pos_integer()) :: non_neg_integer()
  def at(%__MODULE__{rows: rows}, i, x), do: rows |> elem(i - 1) |> elem(x - 1)

  @doc "I return `{:ok, C@i,x}`, or `:error` when the cell lies outside me."
  @spec fetch(t(), pos_integer(), pos_integer()) :: {:ok, non_neg_integer()} | :error
  def fetch(%__MODULE__{rows: rows}, i, x) do
    with true <- i in 1..tuple_size(rows)//1,
         row = elem(rows, i - 1),
         true <- x in 1..tuple_size(row)//1 do
      {:ok, elem(row, x - 1)}
    else
      _outside -> :error
    end
  end

  @doc "I return the number of rows, ar(C)."
  @spec arity(t()) :: pos_integer()
  def arity(%__MODULE__{rows: rows}), do: tuple_size(rows)

  @doc "I return the number of columns, len(C)."
  @spec len(t()) :: pos_integer()
  def len(%__MODULE__{rows: rows}), do: rows |> elem(0) |> tuple_size()
end
