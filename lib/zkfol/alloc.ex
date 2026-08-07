defmodule Zkfol.Alloc do
  @moduledoc """
  I am the linker: one value assigning each matrix symbol a bank of
  rows in the one committed matrix, consulted by predicate resolution
  (`link/3`), witness assembly (`interpret/2`), and claims
  (`claims/2`), so the three can never disagree. Linking a numeric
  predicate is the identity: today's single-symbol statements pass
  through me untouched.

  ### Public API

  - `new/2` — regions in order, publicity by name.
  - `rows/2`, `offset/2` — where a symbol's bank landed.
  - `link/3` — named references to absolute rows, named lens to constants.
  - `interpret/2` — the family stacked into one `Zkfol.Interpretation`.
  - `claims/2` — claims by name to claims by row.
  """

  use TypedStruct

  alias Zkfol.Ast
  alias Zkfol.Interpretation
  alias Zkfol.Refusal

  typedstruct enforce: true do
    field(:regions, [{atom(), pos_integer()}])
    field(:slots, %{atom() => [atom()]}, default: %{})
    field(:public, [atom()], default: [])
  end

  @doc "I am the allocation of `regions` in order, `opts[:public]` naming the open ones."
  @spec new([{atom(), pos_integer()}], keyword()) :: t()
  def new(regions, opts \\ []),
    do: %__MODULE__{regions: regions, public: Keyword.get(opts, :public, [])}

  @doc "I am the rows of `sym`: absolute, 1-based, in region order."
  @spec rows(t(), atom()) :: Range.t()
  def rows(%__MODULE__{} = alloc, sym) do
    offset = offset(alloc, sym)
    (offset + 1)..(offset + width(alloc, sym))//1
  end

  @doc "I am the row offset of `sym`: the rows allocated before its region."
  @spec offset(t(), atom()) :: non_neg_integer()
  def offset(%__MODULE__{regions: regions}, sym) do
    case Enum.split_while(regions, fn {name, _width} -> name != sym end) do
      {_before, []} -> raise ArgumentError, "no region #{sym}"
      {before, _rest} -> before |> Enum.map(&elem(&1, 1)) |> Enum.sum()
    end
  end

  @doc """
  I resolve every named reference to its absolute row and fold named
  lens through `lens`; numeric references pass through, so linking a
  linked predicate is the identity.
  """
  @spec link(Ast.pred(), t(), %{atom() => pos_integer()}) ::
          {:ok, Ast.pred()} | {:error, Refusal.t()}
  def link(pred, %__MODULE__{} = alloc, lens \\ %{}) do
    {:ok, Ast.postwalk(pred, &resolve(&1, alloc, lens))}
  catch
    {:refused, reason} -> {:error, reason}
  end

  @doc """
  I lay the family into the one matrix: each symbol's rows stacked in
  region order, shorter symbols padded to the widest length with
  their own base column, so the linked predicate and the witness
  cannot disagree about where a bank lives.
  """
  @spec interpret(t(), %{atom() => Interpretation.t()}) ::
          {:ok, Interpretation.t()} | {:error, Refusal.t()}
  def interpret(%__MODULE__{regions: regions}, family) do
    with {:ok, banks} <- Refusal.map(regions, &bank(&1, family)) do
      rows = Enum.concat(banks)
      len = rows |> Enum.map(&length/1) |> Enum.max()
      {:ok, rows |> Enum.map(&pad(&1, len)) |> Interpretation.new()}
    end
  end

  @doc "I resolve claim references by name; numeric rows pass through."
  @spec claims(t(), [{String.t(), Ast.row_ref(), pos_integer()}]) ::
          {:ok, [Interpretation.claim()]} | {:error, Refusal.t()}
  def claims(%__MODULE__{} = alloc, named) do
    {:ok, for({name, ref, x} <- named, do: {name, absolute(ref, alloc), x})}
  catch
    {:refused, reason} -> {:error, reason}
  end

  @doc """
  I am the rows a statement stands on: each member's arguments in
  closure order, the tag row behind them, the pointer bank, then the
  objects it declares, publicity read off their layouts.
  `Zkfol.Lang` names the derivation's rows; the numbering is mine,
  and an object's bank is as much mine as a member's.
  """
  @spec assign(Zkfol.Lang.shape(), [Zkfol.Lang.Rel.t()]) :: t()
  def assign(shape, objects \\ []) do
    alloc =
      new(
        for(name <- shape.members, do: {name, shape.arities[name]}) ++
          if(shape.tags == %{}, do: [], else: [{:tag, 1}]) ++
          if(shape.pointers == [], do: [], else: [{:ptr, length(shape.pointers)}]) ++
          for(rel <- objects, do: {rel.name, rel.layout.rows}),
        public: for(rel <- objects, rel.layout.public, do: rel.name)
      )

    %{alloc | slots: Map.get(shape, :slots, %{})}
  end

  @doc "I am how many rows I assign in all."
  @spec width(t()) :: non_neg_integer()
  def width(%__MODULE__{regions: regions}), do: regions |> Enum.map(&elem(&1, 1)) |> Enum.sum()

  @doc """
  I read a symbol's bank back out of a laid witness: `interpret/2`
  then me is the identity on every region that needed no padding.
  """
  @spec region(Interpretation.t(), t(), atom()) :: Interpretation.t()
  def region(%Interpretation{} = witness, %__MODULE__{} = alloc, sym) do
    Interpretation.new(
      for i <- rows(alloc, sym) do
        for x <- 1..Interpretation.len(witness), do: Interpretation.at(witness, i, x)
      end
    )
  end

  @doc """
  I am the banks a statement's objects declare, each read off its own
  facts. An object without facts is an existential nothing filled,
  and refuses.
  """
  @spec declared([Zkfol.Lang.Rel.t()]) ::
          {:ok, %{atom() => Interpretation.t()}} | {:error, Refusal.t()}
  def declared(objects) do
    with {:ok, datas} <- Refusal.map(objects, &object_data/1),
         do: {:ok, Map.new(Enum.zip(Enum.map(objects, & &1.name), datas))}
  end

  ############################################################
  #                   Private Implementation                 #
  ############################################################

  @spec width(t(), atom()) :: pos_integer()
  defp width(%__MODULE__{regions: regions}, sym) do
    {^sym, width} = List.keyfind(regions, sym, 0)
    width
  end

  @spec resolve(term(), t(), %{atom() => pos_integer()}) :: term()
  defp resolve({:cell, ref}, alloc, _lens), do: {:cell, absolute(ref, alloc)}

  defp resolve({:cell, ref, ptr}, alloc, _lens),
    do: {:cell, absolute(ref, alloc), absolute(ptr, alloc)}

  defp resolve({:len, sym}, _alloc, lens),
    do: Map.get(lens, sym) || throw({:refused, {:unknown_length, %{symbol: sym}}})

  defp resolve(node, _alloc, _lens), do: node

  @spec absolute(Ast.row_ref(), t()) :: pos_integer()
  defp absolute(i, _alloc) when is_integer(i), do: i

  defp absolute({sym, i}, alloc) do
    unless List.keymember?(alloc.regions, sym, 0),
      do: throw({:refused, {:symbol_not_allocated, %{symbol: sym}}})

    if i > width(alloc, sym),
      do: throw({:refused, {:row_outside_region, %{symbol: sym, row: i}}})

    offset(alloc, sym) + i
  end

  @spec bank({atom(), pos_integer()}, %{atom() => Interpretation.t()}) ::
          {:ok, [[non_neg_integer()]]} | {:error, Refusal.t()}
  defp bank({sym, width}, family) do
    case family do
      %{^sym => itp} ->
        rows = Interpretation.rows(itp)

        if length(rows) == width,
          do: {:ok, rows},
          else:
            {:error, {:region_shape_mismatch, %{symbol: sym, rows: length(rows), region: width}}}

      _family ->
        {:error, {:region_uninterpreted, %{symbol: sym}}}
    end
  end

  @spec pad([non_neg_integer()], pos_integer()) :: [non_neg_integer()]
  defp pad([base | _rest] = row, len), do: row ++ List.duplicate(base, len - length(row))

  @spec object_data(Zkfol.Lang.Rel.t()) :: {:ok, Interpretation.t()} | {:error, Refusal.t()}
  defp object_data(rel) do
    if Zkfol.Matrix.extensional?(rel),
      do: {:ok, Zkfol.Matrix.data(rel)},
      else: {:error, {:existential_unfilled, %{symbol: rel.name}}}
  end
end
