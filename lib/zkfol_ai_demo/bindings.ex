defmodule ZkfolAiDemo.Bindings do
  @moduledoc """
  I turn the values a proof binds into 32-bit words and back. A hash, a nonce or a list of
  figures becomes a run of words, and the words sit in the one public row of a statement,
  where the proof binds every cell.

  ### Public API

  - `words/1` and `hex/1` convert between a binary and its words.
  - `place/1` lays named values along the public row, as bindings and claims.
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
  I lay `public` along a row of `width` cells and say where each value sits: the row, the
  bindings that read it back, and the claims that make its cells public.
  """
  @spec place([{String.t(), [non_neg_integer()]}], pos_integer(), pos_integer()) ::
          {[non_neg_integer()], [Binding.t()], [Interpretation.claim()]}
  def place(public, width, row) do
    values = Enum.flat_map(public, &elem(&1, 1))
    true = length(values) <= width

    {placed, _next} =
      Enum.map_reduce(public, 1, fn {name, words}, x ->
        {{name, Enum.to_list(x..(x + length(words) - 1)//1)}, x + length(words)}
      end)

    bindings =
      for {name, xs} <- placed,
          do: %Binding{name: name, cells: for(x <- xs, do: {0, width - x})}

    claims = for {name, xs} <- placed, x <- xs, do: {"#{name}.#{x}", row, x}
    {values ++ List.duplicate(0, width - length(values)), bindings, claims}
  end
end
