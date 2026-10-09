defmodule ZkfolAiDemo.NoDash do
  @moduledoc """
  I am the no-dash policy in zkFOL's relational language: one relation, true of a text
  exactly when no codepoint of it is an em dash.

  A text is its list of codepoints, so the check is `absent/2` over that list. It is the
  whole policy. `ZkfolAiDemo.Canon` first folds every dash look-alike to the em dash and
  decodes the encodings a dash can hide in, so this one codepoint is the only one left to
  forbid. `ZkfolAiDemo.Text` proves this relation of the canonical text.

  This file is the published policy: `source_hash/0` is SHA-256 of it as compiled, so
  `sha256sum lib/zkfol_ai_demo/no_dash.ex` reproduces it, and every proof binds it.

  ### Public API

  - `no_dash/1` is the relation; see `Examples.ENoDash` for it proved and refused.
  - `text/1` reads a string as the list of codepoints the relation is stated over.
  - `repaired/1` is a text with every em dash replaced by a space.
  - `source_hash/0` is the hash of this file.
  """

  use Zkfol.Lang

  @external_resource __ENV__.file
  @source_hash :crypto.hash(:sha256, File.read!(__ENV__.file))

  # 8212 is U+2014, the em dash. It is written as its codepoint because this project's lint
  # refuses the character itself in any file.
  @dash 8212

  defrel no_dash(text) do
    absent(8212, text)
  end

  @doc "I read `string` as the list of its codepoints."
  @spec text(String.t()) :: [non_neg_integer()]
  def text(string), do: String.to_charlist(string)

  @doc "I am `codepoints` with every em dash replaced by a space: the nearest text the rule holds of."
  @spec repaired([non_neg_integer()]) :: [non_neg_integer()]
  def repaired(codepoints), do: Enum.map(codepoints, &if(&1 == @dash, do: ?\s, else: &1))

  @doc "I am the SHA-256 of this file as it was compiled."
  @spec source_hash() :: binary()
  def source_hash, do: @source_hash
end
