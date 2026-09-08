defmodule Zkfol.Lay do
  @moduledoc """
  I am the lay as a value: how one allocation placed one derivation.

  ### Public API

  - `of/2`: the placement computed once.
  - `witness/1`: my matrix as the laid interpretation.
  - `claims/2`: the cells the parameters an act opens hold, by row.
  - `arrows/1`: one arrow per consumption between laid columns.
  - `addresses/1`: each address row beside the member holding it.
  - `regions/1`: the alloc's banks by name and absolute rows.
  - `at/2`, `head/1`: where a slot's cell stands, and where a run of cells starts.
  """

  use TypedStruct

  alias Zkfol.Alloc
  alias Zkfol.Alloc.Member
  alias Zkfol.Alloc.Site
  alias Zkfol.Alloc.Slot
  alias Zkfol.Ast
  alias Zkfol.Derivation
  alias Zkfol.Interpretation
  alias Zkfol.Refusal

  @typedoc "One fact standing on one member: where it stands and what its calls consumed."
  @type stand :: %{
          fact: Derivation.fact(),
          member: atom(),
          column: pos_integer(),
          uses: [use()]
        }

  @typedoc "One consumption: the site that made it, and the fact it took."
  @type use :: {Site.t(), Derivation.fact()}

  @typedoc "Where a reading puts what it consumed: the column it names, or a column of its own."
  @type aim :: pos_integer() | {:free, pos_integer()}

  @typedoc "Which parameter an act opens: the head variable, or its 1-based position."
  @type parameter :: atom() | pos_integer()

  @typedoc "What an act opens: a parameter of the root or a member, or one cell of it by index."
  @type opening :: parameter() | {atom(), parameter()} | {atom(), parameter(), integer()}

  typedstruct enforce: true do
    field(:alloc, Alloc.t())
    field(:derivation, Derivation.t())
    field(:stands, [stand()])
  end

  @doc "I take the join of the derivation and alloc to form information for laying."
  @spec of(Derivation.t(), Alloc.t()) :: t()
  def of(%Derivation{} = derivation, %Alloc{members: [root | _rest]} = alloc) do
    lay = %__MODULE__{alloc: alloc, derivation: derivation, stands: []}

    case Derivation.root(derivation, root.relation) do
      nil -> lay
      fact -> descend([{fact, root.name, {:free, 1}}], lay)
    end
  end

  @doc "I am my matrix; an unread cell pads zero, or one on an address row."
  @spec witness(t()) :: Interpretation.t()
  def witness(%__MODULE__{alloc: alloc, stands: stands} = lay) do
    cells = Map.new(Enum.flat_map(stands, &laid(&1, lay)))

    len = Enum.max([1 | for({{_row, x}, _value} <- cells, do: x)])
    aimed = MapSet.new(addresses(lay), & &1.ptr)

    Interpretation.new(
      for row <- 1..Alloc.width(alloc) do
        for x <- 1..len,
            do:
              cells
              |> Map.get({row, x}, if(row in aimed, do: 1, else: 0))
              |> Derivation.free_to_zero()
      end
    )
  end

  @doc """
  I am the cells the parameters `public` opens hold, the member's presence beside each: a
  bare parameter the root's, `{relation, parameter}` a member's, with `index` one cell.
  """
  @spec claims(t(), [opening()]) :: {:ok, [Interpretation.claim()]} | {:error, Refusal.t()}
  def claims(_lay, []), do: {:ok, []}

  def claims(%__MODULE__{alloc: alloc} = lay, public) do
    with {:ok, named} <- Refusal.flat_map(public, &opened(&1, lay)) do
      {:ok,
       Enum.uniq(
         for {name, ref, x} <- named,
             {label, at} <- [{name, ref} | presence(ref, alloc)] do
           {label, Alloc.row(alloc, at), x}
         end
       )}
    end
  end

  @doc "I am one arrow per consumption between laid columns, named by the address row if any."
  @spec arrows(t()) :: [
          %{
            ptr: pos_integer() | nil,
            from_row: pos_integer(),
            from: pos_integer(),
            to: pos_integer(),
            to_row: pos_integer()
          }
        ]
  def arrows(%__MODULE__{alloc: alloc} = lay) do
    for stand <- lay.stands,
        {%Site{callee: callee, address: address}, _fact} = use <- stand.uses do
      %{
        ptr: Alloc.aimed(alloc, address),
        from_row: Alloc.presence(alloc, stand.member),
        from: stand.column,
        to: standing(lay, stand, use),
        to_row: Alloc.presence(alloc, callee)
      }
    end
  end

  @doc "I am each address row beside the member holding it."
  @spec addresses(t()) :: [%{ptr: pos_integer(), member: atom()}]
  def addresses(%__MODULE__{alloc: alloc}) do
    for member <- alloc.members,
        calls <- member.sites,
        %Site{address: address} <- calls,
        ptr = Alloc.aimed(alloc, address),
        uniq: true,
        do: %{ptr: ptr, member: member.name}
  end

  @doc "I am the alloc's banks by name and absolute rows."
  @spec regions(t() | Alloc.t()) :: [
          %{name: atom(), first: pos_integer(), last: pos_integer()}
        ]
  def regions(%__MODULE__{alloc: alloc}), do: regions(alloc)

  def regions(%Alloc{} = alloc) do
    for {name, _width} <- Alloc.regions(alloc) do
      rows = Alloc.rows(alloc, name)
      %{name: name, first: rows.first, last: rows.last}
    end
  end

  @doc """
  I am where the `index`-th cell of `slot`'s run stands: an address in the column
  its member stands at, which `Ast.column/2` reads as a number.
  """
  @spec at(Slot.t(), non_neg_integer()) :: Ast.address()
  def at(%Slot{at: {mul, add}}, index), do: Ast.address(:x, mul, add - index)

  @doc """
  I am where a run of `extent` cells has its head: the column one past its end,
  its cells running leftward from there. A run of no fixed extent has no head.
  """
  @spec head({integer(), integer()} | non_neg_integer() | :open) :: Ast.address() | nil
  def head({mul, add}), do: Ast.address(:x, mul, add + 1)
  def head(count) when is_integer(count), do: head({0, count})
  def head(:open), do: nil

  ############################################################
  #                   Private Implementation                 #
  ############################################################

  @spec opened(opening(), t()) ::
          {:ok, [{String.t(), Ast.row_ref(), pos_integer()}]} | {:error, Refusal.t()}
  defp opened({relation, parameter, index}, lay), do: spent(relation, parameter, index, lay)

  defp opened({relation, parameter}, lay), do: spent(relation, parameter, nil, lay)

  defp opened(parameter, %__MODULE__{alloc: alloc} = lay),
    do: spent(Alloc.root(alloc).name, parameter, nil, lay)

  @spec spent(atom(), parameter(), integer() | nil, t()) ::
          {:ok, [{String.t(), Ast.row_ref(), pos_integer()}]} | {:error, Refusal.t()}
  defp spent(relation, parameter, index, %__MODULE__{alloc: alloc} = lay) do
    with {:ok, member} <-
           held(Alloc.member(alloc, relation), {:relation_not_in_scope, %{relation: relation}}),
         {:ok, slot} <-
           held(Member.slot(member, parameter), {:unbound_variable, %{variable: parameter}}),
         {:ok, columns} <- columns(slot, member, index, lay) do
      {:ok,
       for(x <- columns, ref <- spends(slot, member), do: {"#{member.name}.#{slot.name}", ref, x})}
    end
  end

  # An index spends no row; opening it opens the presence at the column.
  @spec spends(Slot.t(), Member.t()) :: [Ast.row_ref()]
  defp spends(%Slot{rows: []}, %Member{present: present}), do: [present]
  defp spends(%Slot{rows: rows}, _member), do: rows

  @spec presence(Ast.row_ref(), Alloc.t()) :: [{String.t(), Ast.row_ref()}]
  defp presence({sym, _i}, alloc) do
    case Alloc.member(alloc, sym) do
      %Member{present: present} -> [{"in", present}]
      nil -> []
    end
  end

  defp presence(_ref, _alloc), do: []

  @spec held(term(), Refusal.t()) :: {:ok, term()} | {:error, Refusal.t()}
  defp held(nil, refusal), do: {:error, refusal}
  defp held(found, _refusal), do: {:ok, found}

  @spec columns(Slot.t(), Member.t(), integer() | nil, t()) ::
          {:ok, [pos_integer()]} | {:error, Refusal.t()}
  defp columns(%Slot{rows: [_ | _]} = slot, _member, index, _lay)
       when is_integer(index) and slot.at != nil,
       do: {:ok, [Ast.column(head(index), 0)]}

  defp columns(_slot, %Member{name: name} = member, index, _lay) when is_integer(index) do
    with {:ok, x} <- held(Member.column(member, index), {:beyond_the_rows, %{relation: name}}),
         do: {:ok, [x]}
  end

  defp columns(%Slot{rows: [_ | _]} = slot, member, _index, lay) when slot.at != nil do
    with {:ok, {cells, x}} <-
           held(spelt(slot, member, lay), {:beyond_the_rows, %{sequence: Slot.owner(slot)}}),
         do: {:ok, for(p <- (length(cells) - 1)..0//-1, do: Ast.column(at(slot, p), x))}
  end

  defp columns(_slot, %Member{name: name}, _index, %__MODULE__{stands: stands}) do
    with {:ok, %{fact: fact}} <-
           held(Enum.find(stands, &(&1.member == name)), {:beyond_the_rows, %{relation: name}}),
         do:
           {:ok, for(stand <- stands, stand.member == name, stand.fact == fact, do: stand.column)}
  end

  @spec spelt(Slot.t(), Member.t(), t()) :: {[term()], pos_integer()} | nil
  defp spelt(slot, %Member{name: name, slots: slots}, %__MODULE__{} = lay) do
    with %{fact: {_relation, tuple}, column: x} <- Enum.find(lay.stands, &(&1.member == name)),
         cells when is_list(cells) <- Enum.at(tuple, Enum.find_index(slots, &(&1 == slot))),
         do: {cells, x},
         else: (_unheld -> nil)
  end

  @spec descend([{Derivation.fact(), atom(), aim()}], t()) :: t()
  defp descend([], %__MODULE__{stands: stands} = lay), do: %{lay | stands: Enum.reverse(stands)}

  defp descend([{{_relation, tuple} = fact, name, aim} | rest], %__MODULE__{} = lay) do
    %__MODULE__{alloc: alloc, derivation: derivation, stands: stands} = lay
    member = Alloc.member(alloc, name)
    taken = MapSet.new(for stand <- stands, stand.member == name, do: stand.column)
    column = placed(aim, member, tuple, taken)

    if Enum.any?(stands, &(&1.fact == fact and &1.member == name and &1.column == column)) do
      descend(rest, lay)
    else
      sites = Enum.at(member.sites, Derivation.clause(derivation, fact) || length(member.sites))
      uses = consumed(sites || [], Derivation.consumed(derivation, fact), alloc)
      stand = %{fact: fact, member: name, column: column, uses: uses}

      reached =
        for {%Site{callee: callee, address: address}, took} <- uses,
            do: {took, callee, aimed(address, column)}

      descend(rest ++ reached, %{lay | stands: [stand | stands]})
    end
  end

  # Inlining erases sites, not source calls: join by the occurrence in the original clause.
  @spec consumed([Site.t()], [Derivation.fact()], Alloc.t()) :: [use()]
  defp consumed(sites, facts, alloc = %Alloc{}) do
    by_relation = Enum.group_by(facts, &elem(&1, 0))

    for site = %Site{callee: callee, occurrence: occurrence} <- sites,
        %Member{relation: relation} = Alloc.member(alloc, callee),
        fact <- Enum.slice(Map.get(by_relation, relation, []), occurrence, 1),
        do: {site, fact}
  end

  @spec aimed(Ast.address(), pos_integer()) :: aim()
  defp aimed({:at, :x, _mul, _add} = address, column), do: Ast.column(address, column)
  defp aimed({:at, {:cell, _ptr}, _mul, _add}, column), do: {:free, column}

  # A fact two sites consumed stands under each, at the column each names.
  @spec standing(t(), stand(), use()) :: pos_integer()
  defp standing(
         %__MODULE__{stands: stands},
         stand,
         {%Site{callee: callee, address: address}, fact}
       ) do
    with {:free, _near} <- aimed(address, stand.column),
         do: Enum.find_value(stands, 1, &(&1.fact == fact and &1.member == callee and &1.column))
  end

  # A fact no site addressed stands where its steps put its count, else at a vacant column.
  @spec placed(aim(), Member.t(), [term()], MapSet.t()) :: pos_integer()
  defp placed(column, _member, _tuple, _taken) when is_integer(column), do: column

  defp placed({:free, near}, %Member{steps: steps} = member, tuple, taken) do
    with {j, _origin} <- steps,
         count when is_integer(count) <- count_of(Enum.at(tuple, j)),
         do: Member.column(member, count),
         else: (_uncounted -> vacant(near, taken))
  end

  @spec count_of(term()) :: integer() | nil
  defp count_of(q) when is_integer(q), do: q
  defp count_of(cells) when is_list(cells), do: length(cells)
  defp count_of(_open), do: nil

  @spec vacant(pos_integer(), MapSet.t()) :: pos_integer()
  defp vacant(column, used),
    do: if(MapSet.member?(used, column), do: vacant(column + 1, used), else: column)

  @spec laid(stand(), t()) :: [{{pos_integer(), pos_integer()}, term()}]
  defp laid(%{member: name, column: x} = stand, %__MODULE__{alloc: alloc} = lay) do
    member = Alloc.member(alloc, name)
    {_relation, tuple} = stand.fact

    chosen =
      for {%Site{address: address}, _fact} = use <- stand.uses,
          row = Alloc.aimed(alloc, address),
          do: {{row, x}, standing(lay, stand, use)}

    [{{Alloc.presence(alloc, name), x}, 1}] ++
      Enum.flat_map(Enum.zip(tuple, member.slots), &spread(&1, x, alloc)) ++ chosen
  end

  # A slot of a member's own stands at its column; every cell of a sequence on its bank's axis.
  @spec spread({term(), Slot.t()}, pos_integer(), Alloc.t()) ::
          [{{pos_integer(), pos_integer()}, term()}]
  defp spread({value, %Slot{rows: [_ | _], at: nil} = slot}, x, alloc),
    do: onto(value, slot, x, alloc)

  defp spread({value, %Slot{at: {_mul, _add}} = slot}, x, alloc) when is_list(value) do
    Enum.flat_map(Enum.with_index(value), fn {cell, p} ->
      column = Ast.column(at(slot, p), x)
      [{{Alloc.presence(alloc, Slot.owner(slot)), column}, 1} | onto(cell, slot, column, alloc)]
    end)
  end

  defp spread({_value, _slot}, _x, _alloc), do: []

  @spec onto(term(), Slot.t(), pos_integer(), Alloc.t()) ::
          [{{pos_integer(), pos_integer()}, term()}]
  defp onto(value, %Slot{rows: rows}, column, alloc),
    do:
      for(
        {cell, row} <- Enum.zip(spent(value, length(rows)), rows),
        do: {{Alloc.row(alloc, row), column}, cell}
      )

  # An inner bracket is an earlier dimension, so its cells run onto rows first.
  @spec spent(term(), non_neg_integer()) :: [term()]
  defp spent(_cells, 0), do: []
  defp spent([], k), do: List.duplicate(0, k)
  defp spent([cell | tail], k) when is_list(cell), do: spent(cell ++ tail, k)
  defp spent([head | tail], k), do: [head | spent(tail, k - 1)]
  defp spent(cell, 1), do: [cell]
  defp spent(_ended, k), do: List.duplicate(0, k)
end

defimpl Inspect, for: Zkfol.Lay do
  import Inspect.Algebra

  def inspect(%Zkfol.Lay{} = lay, _opts) do
    regions =
      Enum.map_join(Zkfol.Lay.regions(lay), " ", fn %{name: name, first: first, last: last} ->
        "#{name}:#{first}-#{last}"
      end)

    concat([
      "#Zkfol.Lay<",
      "#{Enum.max([1 | for(stand <- lay.stands, do: stand.column)])} columns · #{regions}",
      ">"
    ])
  end
end
