defmodule ZkfolAiDemo.Figures do
  @moduledoc """
  I read the numeric figures out of a text, as integers a statement can compare.

  A figure is a run of ASCII digits with optional thousands commas and an optional decimal
  fraction. Commas are dropped, trailing zeros of the fraction are dropped, and the figure
  is encoded as its digits (leading zeros dropped) times 16, plus the length of its fraction,
  so `3.5` and `35` are different figures and `3.50` is `3.5`. A figure of more than 15
  digits is refused, since it would not fit a cell.

  The text is canonicalised first, so a figure written as an entity or an escape is read.
  Digits in other scripts are not figures. A dash or slash inside a date splits it into
  separate figures.

  ### Public API

  - `extract/1` is the figures of a text, in order, with repeats.
  - `source_hash/0` is the hash of this file as compiled.
  """

  alias ZkfolAiDemo.Canon
  alias Zkfol.Refusal

  @external_resource __ENV__.file
  @source_hash :crypto.hash(:sha256, File.read!(__ENV__.file))
  @max_digits 15

  @doc "I am the figures of `text`, encoded, in order of appearance."
  @spec extract(String.t()) :: {:ok, [non_neg_integer()]} | {:error, Refusal.t()}
  def extract(text) do
    with {:ok, canonical} <- Canon.text(text) do
      ~r/\d+(?:,\d{3})*(?:\.\d+)?/
      |> Regex.scan(canonical)
      |> Enum.map(fn [figure] -> encode(figure) end)
      |> Refusal.map(& &1)
    end
  end

  @doc "I am the hash of this file as compiled, which the canonicaliser hash includes."
  @spec source_hash() :: binary()
  def source_hash, do: @source_hash

  @spec encode(String.t()) :: {:ok, non_neg_integer()} | {:error, Refusal.t()}
  defp encode(figure) do
    [whole | fraction] = figure |> String.replace(",", "") |> String.split(".")
    fraction = fraction |> Enum.join() |> String.trim_trailing("0")
    digits = String.trim_leading(whole <> fraction, "0")

    if String.length(digits) > @max_digits,
      do: {:error, {:figure_exceeds_cell, %{figure: figure}}},
      else: {:ok, String.to_integer("0" <> digits) * 16 + String.length(fraction)}
  end
end
