defmodule Zkfol.Phi.Walk do
  @moduledoc """
  I retain the bindings, equations and allocation decisions made while compiling a clause.

  `env` binds source variables and parameter references to symbolic values.
  `parameters` records each parameter's allocation; `:none` means it shares an
  existing access. `banks` records owned bank depths, and `slots` holds local storage.
  An impossible walk is `:dead`.
  A member retains its clauses; each clause's body retains the clauses of members it calls.

  ### Public API

  - `merge/2`: combine parameter declarations.
  - `constrain/2`: retain the equations required by an observation.
  - `bind/3`, `bind/4`: bind a parameter and record its allocation.
  - `bank/3`, `bank/4`: give an unresolved parameter its own sequence storage.
  - `peel/2`, `ended/2`: observe a source bracket, recording its storage requirements.
  """

  use TypedStruct

  alias Zkfol.Alloc.Bank
  alias Zkfol.Alloc.Member
  alias Zkfol.Alloc.Site
  alias Zkfol.Alloc.Slot
  alias Zkfol.Ast
  alias Zkfol.Phi.{Cons, Value, View}

  defmodule Clause do
    @moduledoc "I retain one compiled clause's inputs and the walks before and after its rules."
    use TypedStruct

    typedstruct enforce: true do
      field(:member, atom())
      field(:head, [term()])
      field(:body, [term()])
      field(:accesses, [Zkfol.Phi.Value.t()])
      field(:before, Zkfol.Phi.Walk.t())
      field(:matched, Zkfol.Phi.Walk.t() | :dead)
      field(:compiled, Zkfol.Phi.Walk.t() | :dead)
    end
  end

  typedstruct do
    field(:env, map(), default: %{})
    field(:parameters, %{Ast.row_ref() => Zkfol.Alloc.allocation()}, default: %{})
    field(:banks, %{atom() => pos_integer()}, default: %{})
    field(:members, [Member.t() | Bank.t()], default: [])
    field(:predicates, [Ast.pred()], default: [])
    field(:eqs, [Ast.pred()], default: [])
    field(:sites, [{non_neg_integer(), Site.t()}], default: [])
    field(:slots, [Slot.t()], default: [])
    field(:clauses, [Clause.t()], default: [])
  end

  @doc "I merge a parameter declaration into a walk; the declaration's entries take precedence."
  @spec merge(t(), t()) :: t()
  def merge(declaration = %__MODULE__{}, walk = %__MODULE__{}) do
    %{
      walk
      | env: Map.merge(walk.env, declaration.env),
        parameters: Map.merge(walk.parameters, declaration.parameters),
        banks: Map.merge(walk.banks, declaration.banks)
    }
  end

  @doc "I collect conjuncts in reverse order without copying the clause accumulated so far."
  @spec constrain(t(), [Ast.pred()]) :: t()
  def constrain(walk = %__MODULE__{}, eqs), do: %{walk | eqs: Enum.reverse(eqs, walk.eqs)}

  @doc """
  I bind a parameter to an access. A handed count gets a cell, the column uses no row,
  and other accesses are shared. A fresh parameter waits for matching to resolve it.
  """
  @spec bind(t(), Ast.row_ref(), Value.t()) :: t()
  def bind(walk, _ref, :fresh), do: walk

  def bind(walk, ref, {:count, q, _cell}),
    do: bind(walk, ref, {:count, q, Ast.cell(ref)}, {:cell, ref})

  def bind(walk, ref, :x), do: bind(walk, ref, :x, {:column, 0})
  def bind(walk, ref, access = {:add, :x, o}), do: bind(walk, ref, access, {:column, o})
  def bind(walk, ref, access), do: bind(walk, ref, access, :none)

  @doc "I bind a parameter and record the allocation required by that binding."
  @spec bind(t(), Ast.row_ref(), Value.t(), Zkfol.Alloc.allocation()) :: t()
  def bind(walk, ref, value, allocation),
    do: %{
      walk
      | env: Map.put(walk.env, ref, value),
        parameters: Map.put(walk.parameters, ref, allocation)
    }

  @doc "I give a parameter its own sequence bank; matching its records can require more rows."
  @spec bank(t(), Ast.row_ref(), View.extent(), pos_integer()) :: t()
  def bank(walk = %__MODULE__{}, ref, extent, depth \\ 1) do
    bank = Bank.of(ref)
    view = View.bank(%Bank{name: bank, depth: depth}, extent)
    walk = bind(walk, ref, view, {:bank, bank, view.col || Ast.address(:x, 0, 0)})
    %{walk | banks: Map.put_new(walk.banks, bank, depth)}
  end

  @doc """
  I expose a source bracket's head and tail, retaining the equations and storage it needs.
  A cell in a bank I own can introduce a record: its head occupies that component row,
  and its tail starts at the next. Existing values use their own pair representation.
  """
  @spec peel(t(), Value.t()) :: {:ok, Value.t(), Value.t(), t()} | :dead
  def peel(walk = %__MODULE__{banks: banks}, value) do
    case Ast.read(value) do
      {{bank, row}, {:at, base, scale, offset}} when is_map_key(banks, bank) ->
        tail = Ast.at({bank, row + 1}, base, scale, offset)
        {:ok, value, tail, require_rows(walk, bank, row)}

      _existing ->
        with {:ok, head, tail, equations} <- Cons.peel(value),
             do: {:ok, head, tail, constrain(walk, equations)}
    end
  end

  @doc "I close a source bracket, retaining its end equations or its owned record's width."
  @spec ended(t(), Value.t()) :: t() | :dead
  def ended(walk = %__MODULE__{banks: banks}, value) do
    case Ast.read(value) do
      {{bank, row}, _address} when is_map_key(banks, bank) ->
        require_rows(walk, bank, row - 1)

      _existing ->
        with {:ok, equations} <- Cons.ended(value), do: constrain(walk, equations)
    end
  end

  @spec require_rows(t(), atom(), integer()) :: t()
  defp require_rows(walk, bank, rows),
    do: %{walk | banks: Map.update!(walk.banks, bank, &max(&1, rows))}
end
