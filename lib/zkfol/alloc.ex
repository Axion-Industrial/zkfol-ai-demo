defmodule Zkfol.Alloc do
  @moduledoc """
  I am the layout: the members a statement's relations stand on and the bank of rows each
  takes in the one committed matrix.

  ### Public API

  - `new/1`: an allocation of bare banks, one of each width.
  - `numbered/2`: the members a walk made, in rows, the root first.
  - `root/1`, `member/2`, `names/1`: the root, a member by name, my members' names.
  - `presence/2`: the row a member's facts stand on.
  - `regions/1`, `rows/2`, `row/2`, `width/1`: where a symbol's bank landed.
  - `link/2`, `aimed/2`: named references to absolute rows.
  """

  use TypedStruct

  alias Zkfol.Ast

  defmodule Slot do
    @moduledoc """
    I am a binding: whose cells I read, and where under a column I meet them.

        rows: [row],  at: nil          one cell of my own, at my member's standing
        rows: bank's, at: {mul, add}   the bank's cells, `Lay.at/2` reading where each meets
        rows: [],     at: {1, origin}  the column itself, the index it counts standing
        rows: [],     at: nil          nothing of the trace: a relation my site passed

    Rows not my member's are a name handed to it already standing: one cell, two readers.
    """
    use TypedStruct

    typedstruct enforce: true do
      field(:name, atom())
      field(:rows, [Zkfol.Ast.row_ref()], default: [])
      field(:at, {integer(), integer()} | nil, default: nil)
    end

    @doc "I am a parameter on a row of my own, met at my member's own standing."
    @spec own(atom(), [Zkfol.Ast.row_ref()]) :: t()
    def own(name, rows), do: %__MODULE__{name: name, rows: rows}

    @doc "I am a parameter meeting a bank: its cells, my `p`-th at `mul * X + add - p`."
    @spec bank(atom(), [Zkfol.Ast.row_ref()], {integer(), integer()}) :: t()
    def bank(name, rows, at), do: %__MODULE__{name: name, rows: rows, at: at}

    @doc "I am the column itself: the index my member counts, its first standing for `origin`."
    @spec index(atom(), integer()) :: t()
    def index(name, origin), do: %__MODULE__{name: name, at: {1, origin}}

    @doc "I am a relation my site passed, which stands on no row of the trace."
    @spec passed(atom()) :: t()
    def passed(name), do: %__MODULE__{name: name}

    @doc "I am the name each row of mine shows: my own where I spend one, numbered where more."
    @spec names(t()) :: [atom()]
    def names(%__MODULE__{name: name, rows: [_one]}), do: [name]

    def names(%__MODULE__{name: name, rows: rows}),
      do: for(i <- 1..length(rows)//1, do: :"#{name}#{i}")

    @doc "I am the member whose rows I read, none where I read no row."
    @spec owner(t()) :: atom() | nil
    def owner(%__MODULE__{rows: [{name, _i} | _rest]}), do: name
    def owner(%__MODULE__{}), do: nil

    @doc "I say whether I meet a bank: cells of another member, strided under my column."
    @spec bank?(t()) :: boolean()
    def bank?(%__MODULE__{rows: rows, at: at}), do: rows != [] and at != nil

    @doc "I say whether I am the column itself, which spends no row of anyone's."
    @spec index?(t()) :: boolean()
    def index?(%__MODULE__{rows: rows, at: at}), do: rows == [] and at != nil
  end

  defmodule Site do
    @moduledoc """
    I am a source call and where its callee stands. `occurrence` counts preceding
    calls to the same relation in the source clause, including inlined calls.
    The address is affine in the caller's column or reads a pointer cell.
    """
    use TypedStruct

    typedstruct enforce: true do
      field(:callee, atom())
      field(:address, Zkfol.Ast.address())
      field(:occurrence, non_neg_integer())
    end
  end

  defmodule Member do
    @moduledoc """
    I am one relation as a call site reaches it, `relation` its name in the surface: a slot
    per parameter and per existential, the presence row, and the site each call of mine
    reaches. `steps` is the parameter my column counts and the count my first column
    stands for.
    """
    use TypedStruct

    typedstruct enforce: true do
      field(:name, atom())
      field(:relation, atom() | nil, default: nil)
      field(:slots, [Zkfol.Alloc.Slot.t()], default: [])
      field(:steps, {non_neg_integer(), integer()} | nil, default: nil)
      field(:present, Zkfol.Ast.row_ref() | nil, default: nil)
      field(:sites, [[Zkfol.Alloc.Site.t()]], default: [])
    end

    @doc "I am `relation` as one site reaches it, standing on the presence row my name names."
    @spec of(atom(), atom(), {non_neg_integer(), integer()} | nil) :: t()
    def of(name, relation, steps),
      do: %__MODULE__{name: name, relation: relation, steps: steps, present: {:in, name}}

    @doc "I am a bank: `dim` rows a cell and no relation of my own."
    @spec bank(atom(), pos_integer()) :: t()
    def bank(name, dim),
      do: %__MODULE__{
        name: name,
        present: {:in, name},
        slots: [Slot.own(:cells, bank_rows(name, dim))]
      }

    @doc "I am the name of the bank a parameter's cells stand in."
    @spec bank_name(Zkfol.Ast.row_ref()) :: atom()
    def bank_name({name, {:param, sym}}), do: :"#{name} #{sym}"

    @doc "I am the row refs of the bank `name`, `dim` rows deep."
    @spec bank_rows(atom(), pos_integer()) :: [Zkfol.Ast.row_ref()]
    def bank_rows(name, dim), do: for(i <- 1..dim//1, do: {name, i})

    @doc "I say whether I am a bank: a member with no relation of its own to say."
    @spec bank?(t()) :: boolean()
    def bank?(%__MODULE__{relation: relation}), do: relation == nil

    @doc "I am the slot `name` names, or the one standing `place`-th among mine."
    @spec slot(t(), atom() | pos_integer()) :: Slot.t() | nil
    def slot(%__MODULE__{slots: slots}, name) when is_atom(name),
      do: Enum.find(slots, &(&1.name == name))

    def slot(%__MODULE__{slots: slots}, place) when is_integer(place) and place > 0,
      do: Enum.at(slots, place - 1)

    @doc "I am the column a fact counting `count` stands at, none where I count nothing."
    @spec column(t(), integer()) :: integer() | nil
    def column(%__MODULE__{steps: {_j, origin}}, count), do: count - origin
    def column(%__MODULE__{steps: nil}, _count), do: nil

    @doc "I am the rows my slots spend."
    @spec width(t()) :: non_neg_integer()
    def width(%__MODULE__{} = member), do: length(rows(member))

    @doc "I am the name of every row I spend, in order."
    @spec rows(t()) :: [atom()]
    def rows(%__MODULE__{} = member), do: Enum.flat_map(open(member), &Slot.names/1)

    @doc "I am the reference of every row I spend, in order: the walk's name for it."
    @spec refs(t()) :: [Zkfol.Ast.row_ref()]
    def refs(%__MODULE__{} = member), do: Enum.flat_map(open(member), & &1.rows)

    @doc "I am the slots standing on rows of my own: a row names the member spending it."
    @spec open(t()) :: [Slot.t()]
    def open(%__MODULE__{name: name, slots: slots}),
      do: for(slot <- slots, slot.rows == [] or Slot.owner(slot) == name, do: slot)
  end

  typedstruct enforce: true do
    field(:members, [Member.t()], default: [])
  end

  @doc "I am the allocation of a bare bank per name, each of its width."
  @spec new([{atom(), pos_integer()}]) :: t()
  def new(banks),
    do: %__MODULE__{members: for({name, width} <- banks, do: Member.bank(name, width))}

  @doc "I am the root member: the relation the act named, first among my members."
  @spec root(t()) :: Member.t()
  def root(%__MODULE__{members: [root | _rest]}), do: root

  @doc "I am the member named `name`."
  @spec member(t(), atom()) :: Member.t() | nil
  def member(%__MODULE__{members: members}, name), do: Enum.find(members, &(&1.name == name))

  @doc "I am my members' names, in order."
  @spec names(t() | [Member.t()]) :: [atom()]
  def names(%__MODULE__{members: members}), do: names(members)
  def names(members) when is_list(members), do: for(member <- members, do: member.name)

  @doc "I am the bank each member spending rows takes, and the presence bank behind them."
  @spec regions(t()) :: [{atom(), pos_integer()}]
  def regions(%__MODULE__{members: members}) do
    for(member <- members, Member.width(member) > 0, do: {member.name, Member.width(member)}) ++
      [{:in, length(members)}]
  end

  @doc "I am the rows of `sym`: absolute, 1-based, in region order, none where I hold no `sym`."
  @spec rows(t(), atom()) :: Range.t() | nil
  def rows(%__MODULE__{} = alloc, sym) do
    {before, rest} = Enum.split_while(regions(alloc), fn {name, _width} -> name != sym end)
    offset = Enum.sum(for {_name, width} <- before, do: width)

    with [{^sym, span} | _rest] <- rest, do: (offset + 1)..(offset + span)//1, else: ([] -> nil)
  end

  @doc "I am the absolute row a reference names."
  @spec row(t(), Ast.row_ref()) :: pos_integer()
  def row(_alloc, i) when is_integer(i), do: i
  def row(%__MODULE__{} = alloc, {sym, i}) when is_integer(i), do: rows(alloc, sym).first + i - 1

  def row(%__MODULE__{} = alloc, {:in, name}),
    do: rows(alloc, :in).first + Enum.find_index(names(alloc), &(&1 == name))

  def row(%__MODULE__{} = alloc, {sym, _which} = ref),
    do: rows(alloc, sym).first + Enum.find_index(Member.refs(member(alloc, sym)), &(&1 == ref))

  @doc "I am the absolute row a pointer address reads, none where it is affine in the column."
  @spec aimed(t(), Ast.address()) :: pos_integer() | nil
  def aimed(%__MODULE__{} = alloc, {:at, {:cell, ref}, _mul, _add}), do: row(alloc, ref)
  def aimed(%__MODULE__{}, {:at, :x, _mul, _add}), do: nil

  @doc "I am the absolute row the facts of `name` stand on."
  @spec presence(t(), atom()) :: pos_integer()
  def presence(%__MODULE__{} = alloc, name), do: row(alloc, member(alloc, name).present)

  @doc "I am how many rows I assign in all."
  @spec width(t()) :: non_neg_integer()
  def width(%__MODULE__{} = alloc), do: alloc |> regions() |> Enum.map(&elem(&1, 1)) |> Enum.sum()

  @doc "I resolve every named reference to its absolute row; numeric ones pass through."
  @spec link(Ast.pred(), t()) :: Ast.pred()
  def link(pred, %__MODULE__{} = alloc), do: Ast.postwalk(pred, &resolve(&1, alloc))

  @doc "I am the members a walk made, in rows, the root first."
  @spec numbered([Member.t()], atom()) :: t()
  def numbered(made, root), do: %__MODULE__{members: Enum.sort_by(made, &(&1.name != root))}

  ############################################################
  #                   Private Implementation                 #
  ############################################################

  @spec resolve(term(), t()) :: term()
  defp resolve({:cell, _ref} = read, alloc), do: linked(read, alloc)
  defp resolve({:cell, _ref, _address} = read, alloc), do: linked(read, alloc)
  defp resolve(node, _alloc), do: node

  @spec linked(Ast.term_t(), t()) :: Ast.term_t()
  defp linked(read, alloc) do
    {ref, {:at, _base, mul, add} = address} = Ast.read(read)
    ptr = aimed(alloc, address)
    Ast.at(row(alloc, ref), (ptr && {:cell, ptr}) || :x, mul, add)
  end
end
