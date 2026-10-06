defmodule Zkfol.Harness.Grounding do
  @moduledoc """
  I am the grounding policy as a statement: every numeric figure in an output also appears in
  a supplied source set. Where the text policy bounds each cell, this one is a membership
  check, so it shows the mechanism is not lexical.

  The sources are a public table, laid in the public row after the other bound values. A
  figure row and a pointer row say, for every figure, which cell of the table it equals; the
  prover supplies the pointer and the circuit reads it. The table is also a witness row tied
  cell for cell to the public one, because the pointer query reads witness rows only, and the
  pointer is held inside the table so it cannot land on another public value. Padding
  figures equal a sentinel that stands first in the table and that no figure can equal.

  Every cell stays under 2^56: the pinned Zinc+ rejects an honest proof of a column holding
  a larger value beside small ones. A figure of at most 15 digits encodes under 2^54, and
  the sentinel is 2^55.

  ### Public API

  - `statement/3` builds the statement for an output, its sources and a context.
  - `policy_hash/0` is the hash of the published policy file.
  - `canonicaliser_hash/0` is the hash of what reads the figures.
  """

  alias Zkfol.Ast
  alias Zkfol.Harness.Bindings
  alias Zkfol.Harness.Canon
  alias Zkfol.Harness.Context
  alias Zkfol.Harness.Figures
  alias Zkfol.Harness.Statement
  alias Zkfol.Refusal

  @policy Path.expand("../../../harness/policy/grounding.json", __DIR__)
  @external_resource @policy
  @policy_bytes File.read!(@policy)
  @width JSON.decode!(@policy_bytes)["columns"]
  @sentinel Integer.pow(2, 55)
  @rows 3

  @doc "I am the hash of the published grounding policy file."
  @spec policy_hash() :: binary()
  def policy_hash, do: Bindings.hash(@policy_bytes)

  @doc "I am the hash of what reads the figures: the canonicaliser and the figure reader."
  @spec canonicaliser_hash() :: binary()
  def canonicaliser_hash, do: Bindings.hash(Canon.source_hash() <> Figures.source_hash())

  @doc "I am the statement that every figure of `output` appears in `sources`."
  @spec statement(String.t(), [String.t()], Context.t()) ::
          {:ok, Statement.t()} | {:error, Refusal.t()}
  def statement(output, sources, %Context{} = context) do
    with {:ok, figures} <- Figures.extract(output),
         {:ok, source_figures} <- Refusal.flat_map(sources, &Figures.extract/1) do
      table = [@sentinel | source_figures |> Enum.uniq() |> Enum.sort()]
      leading = leading(context)
      offset = leading |> Enum.flat_map(&elem(&1, 1)) |> length()
      public = leading ++ [{"sources", table}]
      cells = offset + length(table)

      if length(figures) > @width or cells > @width,
        do:
          {:error,
           {:text_exceeds_capacity, %{cells: max(length(figures), cells), capacity: @width}}},
        else: {:ok, build(output, figures, table, public, offset, context)}
    end
  end

  @spec build(
          String.t(),
          [non_neg_integer()],
          [non_neg_integer()],
          list(),
          non_neg_integer(),
          Context.t()
        ) ::
          Statement.t()
  defp build(output, figures, table, public, offset, context) do
    at = table |> Enum.with_index(offset + 1) |> Map.new()
    padding = List.duplicate(@sentinel, @width - length(figures))
    cells = figures ++ padding
    pointers = for figure <- cells, do: Map.get(at, figure, offset + 1)
    {table_row, _bindings, _claims} = Bindings.place(public, @width, @rows + 1)

    %Statement{
      pred: pred(offset + 1, offset + length(table)),
      rows: [cells, pointers, table_row],
      stand_in: [
        for(figure <- cells, do: if(Map.has_key?(at, figure), do: figure, else: @sentinel)),
        pointers,
        table_row
      ],
      public: public,
      pins: for({name, words} <- public, into: %{}, do: {name, Bindings.hex(words)}),
      output: output,
      manifest: %{
        predicate: "grounding",
        policy_sha256: Base.encode16(policy_hash(), case: :lower),
        canonicaliser_sha256: Base.encode16(canonicaliser_hash(), case: :lower),
        figures: length(figures),
        source_figures: length(table) - 1,
        model: context.model,
        system_prompt: context.system_prompt,
        user_prompt: context.user_prompt,
        nonce: Base.encode16(context.nonce, case: :lower)
      }
    }
  end

  # The values bound before the sources, in the order every statement binds them.
  @spec leading(Context.t()) :: [{String.t(), [non_neg_integer()]}]
  defp leading(context) do
    [
      {"policy", Bindings.words(policy_hash())},
      {"canonicaliser", Bindings.words(canonicaliser_hash())} | Context.public(context)
    ]
  end

  # Row 1 holds the figures, row 2 their pointers, row 3 the table, row 4 the public row.
  @spec pred(pos_integer(), pos_integer()) :: Ast.pred()
  defp pred(first, last) do
    Ast.conj([
      Ast.eq(Ast.cell(1), Ast.cell(3, 2)),
      Ast.eq(Ast.cell(3), Ast.cell(@rows + 1)),
      Ast.natural(Ast.sub(Ast.cell(2), first)),
      Ast.natural(Ast.sub(last, Ast.cell(2)))
    ])
  end
end
