defmodule ZkfolAiDemo.Text do
  @moduledoc """
  I am the text policy as a statement: a raw output is canonicalised, and the statement is
  that `ZkfolAiDemo.NoDash.no_dash/1` holds of its codepoints. zkFOL derives the witness and
  the predicate from the relation, so the policy is the relation and nothing more.

  The compiler unrolls the rule three times for every codepoint and stops at 3,000, so a text
  of more than `capacity/0` codepoints is refused before anything is proved. A shorter text is
  padded with NUL cells, which a canonical text never holds, so that the values a proof binds
  fit in the one public row.

  A text that breaks the rule has no derivation. It still reaches the real prover, as
  `ZkfolAiDemo.Statement` explains: I derive the nearest text that complies and put the real
  codepoints in its place.

  ### Public API

  - `statement/2` builds the statement for a raw output under a context.
  - `capacity/0` is the longest canonical text, in codepoints, the compiler derives.
  """

  alias Zkfol.Refusal
  alias ZkfolAiDemo.Bindings
  alias ZkfolAiDemo.Canon
  alias ZkfolAiDemo.Context
  alias ZkfolAiDemo.Derivation
  alias ZkfolAiDemo.NoDash
  alias ZkfolAiDemo.Statement

  @capacity 999

  # The public row holds 44 words (five hashes of eight and a nonce of four), one to a column,
  # and a derived witness has a column more than the text has cells.
  @min_cells 64

  # Where the derivation keeps the text: the bank of `no_dash`'s parameter.
  @bank :"no_dash text"

  @doc "I am the longest canonical text, in codepoints, that the compiler derives."
  @spec capacity() :: pos_integer()
  def capacity, do: @capacity

  @doc "I am the statement for `raw` under `context`."
  @spec statement(String.t(), Context.t()) :: {:ok, Statement.t()} | {:error, Refusal.t()}
  def statement(raw, %Context{} = context) do
    with {:ok, canonical} <- Canon.text(raw),
         {:ok, cells} <- cells(canonical),
         {:ok, derivation, rows} <- witnessed(cells) do
      {:ok,
       %Statement{
         derivation: derivation,
         rows: rows,
         public: [
           {"policy", Bindings.words(NoDash.source_hash())},
           {"canonicaliser", Bindings.words(Canon.source_hash())} | Context.public(context)
         ],
         output: raw,
         manifest: manifest(canonical, cells, context)
       }}
    end
  end

  @spec cells(String.t()) :: {:ok, [non_neg_integer()]} | {:error, Refusal.t()}
  defp cells(canonical) do
    codepoints = NoDash.text(canonical)

    if length(codepoints) > @capacity,
      do: {:error, {:text_exceeds_capacity, %{cells: length(codepoints), capacity: @capacity}}},
      else: {:ok, codepoints ++ List.duplicate(0, max(@min_cells - length(codepoints), 0))}
  end

  # The witness: derived from the text when the rule holds of it, and otherwise from the
  # nearest text it does hold of, with the real cells put in the text's row.
  @spec witnessed([non_neg_integer()]) ::
          {:ok, Derivation.t(), [[integer()]]} | {:error, Refusal.t()}
  defp witnessed(cells), do: witnessed(cells, Derivation.run(NoDash.no_dash(), [cells]))

  defp witnessed(_cells, {:ok, derivation}), do: {:ok, derivation, derivation.rows}

  defp witnessed(cells, :no_answer) do
    with {:ok, derivation} <- Derivation.run(NoDash.no_dash(), [NoDash.repaired(cells)]),
         do: {:ok, derivation, Derivation.forged(derivation, @bank, cells)}
  end

  defp witnessed(_cells, {:error, _refusal} = error), do: error

  # The record of a run for whoever audits it. None of it is proved: the proof binds the
  # hashes, and this is what they were hashes of, so anyone can recompute them.
  @spec manifest(String.t(), [non_neg_integer()], Context.t()) :: map()
  defp manifest(canonical, cells, %Context{} = context) do
    %{
      predicate: "text",
      policy: "no_dash",
      policy_sha256: hex(NoDash.source_hash()),
      canonicaliser_sha256: hex(Canon.source_hash()),
      canonical_sha256: hex(Bindings.hash(canonical)),
      cells: length(cells),
      unicode_version: String.Unicode.version() |> Tuple.to_list() |> Enum.join("."),
      model: context.model,
      system_prompt: context.system_prompt,
      user_prompt: context.user_prompt,
      nonce: hex(context.nonce)
    }
  end

  @spec hex(binary()) :: String.t()
  defp hex(bytes), do: Base.encode16(bytes, case: :lower)
end
