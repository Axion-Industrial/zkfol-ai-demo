defmodule ZkfolAiDemo.NoDash do
  @moduledoc """
  I am the no-dash policy in zkFOL's relational language: one relation, true of a text
  exactly when no codepoint of it is an em dash.

  A text is its list of codepoints, so the check is `absent/2` over that list. It is the
  whole statement. `ZkfolAiDemo.Canon` is the thorough version, which first normalises the
  ways a dash can be smuggled in (entities, escapes, look-alikes) and then proves this same
  absence over what is left.

  ### Public API

  - `no_dash/1` is the relation; see `Examples.ENoDash` for it proved and refused.
  - `text/1` reads a string as the list of codepoints the relation is stated over.
  """

  use Zkfol.Lang

  # 8212 is U+2014, the em dash. It is written as its codepoint because this project's lint
  # refuses the character itself in any file.
  defrel no_dash(text) do
    absent(8212, text)
  end

  @doc "I read `string` as the list of its codepoints."
  @spec text(String.t()) :: [non_neg_integer()]
  def text(string), do: String.to_charlist(string)
end
