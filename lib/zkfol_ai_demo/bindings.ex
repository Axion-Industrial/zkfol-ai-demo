defmodule ZkfolAiDemo.Bindings do
  @moduledoc """
  I turn the values a proof binds into 32-bit words and back. A hash, a nonce or a list of
  figures becomes a run of words, and the words sit in the public rows of a statement, where
  the proof binds every cell.

  ### Public API

  - `words/1` and `hex/1` convert between a binary and its words.
  - `place/3` lays named values along the public rows, as bindings and claims.
  - `hash/1` hashes a value the way every binding hashes one.
  """

  alias Zkfol.Interpretation
  alias Zkfol.ZincPlus.Binding

  @doc "I am SHA-256 of `value`, the hash every binding of a string uses."
  @spec hash(iodata()) :: binary()
  def hash(value), do: :crypto.hash(:sha256, value)

  @doc "I am `bytes` as big-endian 32-bit words, the last padded with zeros."
  @spec words(binary()) :: [non_neg_integer()]
  def words(bytes) do
    padded = bytes <> :binary.copy(<<0>>, rem(4 - rem(byte_size(bytes), 4), 4))
    for <<word::32 <- padded>>, do: word
  end

  @doc "I am `words` as hex, eight digits a word: how the verifier writes a bound value."
  @spec hex([non_neg_integer()]) :: String.t()
  def hex(words),
    do:
      Enum.map_join(words, &(&1 |> Integer.to_string(16) |> String.pad_leading(8, "0")))
      |> String.downcase()

  @doc """
  I lay `public` along as many rows of `width` cells as it takes, the first of them row
  `first`, and say where each value sits: the rows, the bindings that read the values back, and
  the claims that make their cells public. A word sits where its place in the run falls, so a
  value can cross from one row to the next.
  """
  @spec place([{String.t(), [non_neg_integer()]}], pos_integer(), pos_integer()) ::
          {[[non_neg_integer()]], [Binding.t()], [Interpretation.claim()]}
  def place(public, width, first) do
    {placed, _next} =
      Enum.map_reduce(public, 1, fn {name, words}, x ->
        {{name, Enum.to_list(x..(x + length(words) - 1)//1)}, x + length(words)}
      end)

    rows =
      public |> Enum.flat_map(&elem(&1, 1)) |> Enum.chunk_every(width, width, Stream.cycle([0]))

    bindings =
      for {name, xs} <- placed,
          do: %Binding{name: name, cells: for(x <- xs, do: cell(x, width))}

    claims =
      for {name, xs} <- placed, x <- xs do
        {row, at} = position(x, width)
        {"#{name}.#{x}", first + row, at}
      end

    {rows, bindings, claims}
  end

  # Word `x` of the run (from 1) stands in row `row` (from 0) at place `at` (from 1).
  @spec position(pos_integer(), pos_integer()) :: {non_neg_integer(), pos_integer()}
  defp position(x, width), do: {div(x - 1, width), rem(x - 1, width) + 1}

  # The public cell that holds it, as the prover counts: the row, and the place from the end.
  @spec cell(pos_integer(), pos_integer()) :: {non_neg_integer(), non_neg_integer()}
  defp cell(x, width) do
    {row, at} = position(x, width)
    {row, width - at}
  end
end
