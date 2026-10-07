defmodule ZkfolAiDemo.Refusal do
  @moduledoc """
  I am the prose for the refusals the demo adds to zkFOL's own. A refusal is
  `{reason, detail}`; I read the demo's reasons and leave the rest to `Zkfol.Refusal`.

  ### Public API

  - `message/1` reads a refusal out as prose.
  """

  @doc "I read `refusal` out as prose, for a human at the end of the line."
  @spec message(Zkfol.Refusal.t()) :: String.t()
  def message({:allowlist_unsigned, _detail}),
    do: "the allowlist's signature does not verify against the published key"

  def message({:signing_key_exists, %{path: path}}),
    do: "a signing key already exists at #{path}; keep it or remove it first"

  def message({:signing_key_missing, %{path: path}}),
    do: "no signing key at #{path}; make one with bin/harness keygen"

  def message({:figure_exceeds_cell, %{figure: figure}}),
    do: "the figure #{figure} has more than 15 digits and does not fit a cell"

  def message({:text_exceeds_capacity, %{cells: cells, capacity: capacity}}),
    do: "the text needs #{cells} cells and the layout holds #{capacity}"

  def message({:encoding_unbounded, %{depth: depth}}),
    do: "the text is encoded more than #{depth} levels deep, so it cannot be normalised"

  def message({:input_unreadable, %{path: path}}),
    do: "there is no file at #{path}; give the path of a file that exists"

  def message({:dashes_found, %{count: count}}),
    do: "#{count} dash characters in the project; rewrite them without"

  def message({:no_api_key, _detail}), do: "ANTHROPIC_API_KEY is not set in the environment"

  def message({:model_error, %{said: said}}), do: said

  def message(refusal), do: Zkfol.Refusal.message(refusal)
end
