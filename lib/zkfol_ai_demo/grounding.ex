defmodule ZkfolAiDemo.Grounding do
  @moduledoc """
  I am the grounding policy as a statement: every numeric figure in an output also appears in
  a supplied source set. The statement is that `ZkfolAiDemo.Grounded.grounded/2` holds of the
  output's figures and the sources, and zkFOL derives the witness and the predicate from the
  relation.

  The sources are opened as public, so a verifier sees exactly what the figures were checked
  against and pins it. The figures stay private. A sentinel stands first among the sources and
  pads the figures to a minimum length, so that the values a proof binds fit in the one public
  row. No figure can equal it: a figure is under 2^54, and the sentinel is 2^55, because the
  pinned Zinc+ rejects an honest proof of a column holding a larger value beside small ones.

  An output with a figure the sources lack has no derivation. It still reaches the real prover,
  as `ZkfolAiDemo.Statement` explains: every figure the sources lack is replaced by the sentinel
  to make the nearest output that is grounded, and the real figures are put in its place.

  ### Public API

  - `statement/3` builds the statement for an output, its sources and a context.
  - `canonicaliser_hash/0` is the hash of what reads the figures.
  """

  alias Zkfol.Refusal
  alias ZkfolAiDemo.Bindings
  alias ZkfolAiDemo.Canon
  alias ZkfolAiDemo.Context
  alias ZkfolAiDemo.Derivation
  alias ZkfolAiDemo.Figures
  alias ZkfolAiDemo.Grounded
  alias ZkfolAiDemo.Statement

  @sentinel Integer.pow(2, 55)

  # The public row holds 44 words, one to a column, and a derived witness has a column more
  # than the figures.
  @min_figures 48

  # Where the derivation keeps the figures: the bank of `grounded`'s first argument.
  @bank :"grounded a1"

  @doc "I am the hash of what reads the figures: the canonicaliser and the figure reader."
  @spec canonicaliser_hash() :: binary()
  def canonicaliser_hash, do: Bindings.hash(Canon.source_hash() <> Figures.source_hash())

  @doc "I am the statement that every figure of `output` appears in `sources`."
  @spec statement(String.t(), [String.t()], Context.t()) ::
          {:ok, Statement.t()} | {:error, Refusal.t()}
  def statement(output, sources, %Context{} = context) do
    with {:ok, figures} <- Figures.extract(output),
         {:ok, source_figures} <- Refusal.flat_map(sources, &Figures.extract/1),
         table = [@sentinel | source_figures |> Enum.uniq() |> Enum.sort()],
         padded = figures ++ List.duplicate(@sentinel, max(@min_figures - length(figures), 0)),
         {:ok, derivation, rows} <- witnessed(padded, table) do
      {:ok,
       %Statement{
         derivation: derivation,
         rows: rows,
         public: [
           {"policy", Bindings.words(Grounded.source_hash())},
           {"canonicaliser", Bindings.words(canonicaliser_hash())} | Context.public(context)
         ],
         output: output,
         manifest: manifest(figures, table, context)
       }}
    end
  end

  # The witness: derived from the figures when they are grounded, and otherwise from the
  # nearest figures that are, with the real figures put in the figures' row.
  @spec witnessed([non_neg_integer()], [non_neg_integer()]) ::
          {:ok, Derivation.t(), [[integer()]]} | {:error, Refusal.t()}
  defp witnessed(figures, table) do
    case Derivation.run(Grounded.grounded(), [figures, table], :sources) do
      {:ok, derivation} ->
        {:ok, derivation, derivation.rows}

      :no_answer ->
        with {:ok, derivation} <-
               Derivation.run(Grounded.grounded(), [repaired(figures, table), table], :sources),
             do: {:ok, derivation, Derivation.forged(derivation, @bank, figures)}

      {:error, _refusal} = error ->
        error
    end
  end

  # The nearest figures that are grounded: each the sources lack becomes the sentinel. The
  # relation is asked; no rule is repeated here.
  @spec repaired([non_neg_integer()], [non_neg_integer()]) :: [non_neg_integer()]
  defp repaired(figures, table) do
    for figure <- figures,
        do: if(Derivation.holds?(Grounded.member(), [figure, table]), do: figure, else: @sentinel)
  end

  @spec manifest([non_neg_integer()], [non_neg_integer()], Context.t()) :: map()
  defp manifest(figures, table, context) do
    %{
      predicate: "grounding",
      policy: "grounded",
      policy_sha256: Base.encode16(Grounded.source_hash(), case: :lower),
      canonicaliser_sha256: Base.encode16(canonicaliser_hash(), case: :lower),
      figures: length(figures),
      source_figures: length(table) - 1,
      model: context.model,
      system_prompt: context.system_prompt,
      user_prompt: context.user_prompt,
      nonce: Base.encode16(context.nonce, case: :lower)
    }
  end
end
