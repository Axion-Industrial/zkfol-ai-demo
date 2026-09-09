defmodule Zkfol.Phi.Walk do
  @moduledoc """
  I retain the bindings, equations and allocation decisions made while compiling a clause.

  `env` binds source variables and parameter references to symbolic values.
  `parameters` records each parameter's allocation; `:none` means it shares an
  existing access. `shapes` records observations of owned or borrowed elements.
  `slots` holds local storage.
  An impossible walk is `:dead`.
  A member retains its clauses; each clause's body retains the clauses of members it calls.

  ### Public API

  - `fetch/2`, `follow/2`: follow aliases and read values with their resolved element shapes.
  - `refine/2`: retain element shape requirements.
  - `merge/2`: combine parameter declarations.
  - `constrain/2`: retain the equations required by an observation.
  - `bind/3`, `bind/4`: bind a parameter and record its allocation.
  - `allocate/3`: choose storage for a newly resolved parameter.
  - `banks/1`: the banks owned by parameter allocations.
  - `bank/3`, `bank/4`: give an unresolved parameter its own sequence storage.
  - `peel/2`, `ended/2`: observe a source bracket, recording its storage requirements.
  """

  use TypedStruct

  alias Zkfol.Alloc.Bank
  alias Zkfol.Alloc.Member
  alias Zkfol.Alloc.Site
  alias Zkfol.Alloc.Slot
  alias Zkfol.Ast
  alias Zkfol.Phi.{Cons, Ref, Value, View}
  alias Zkfol.Phi.View.{Element, Fields, Record}

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
    field(:shapes, %{Ast.row_ref() => View.element()}, default: %{})
    field(:parameters, %{Ast.row_ref() => Zkfol.Alloc.allocation()}, default: %{})
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
        shapes: merge_shapes(walk.shapes, declaration.shapes)
    }
  end

  @doc "I collect conjuncts in reverse order without copying the clause accumulated so far."
  @spec constrain(t(), [Ast.pred(Value.scalar())]) :: t()
  def constrain(walk = %__MODULE__{}, eqs) do
    required =
      eqs
      |> Enum.flat_map(
        &Ast.reduce(&1, [], fn
          %Element{row: row}, rows -> [row | rows]
          _term, rows -> rows
        end)
      )
      |> Map.new(&{&1, :scalar})

    walk = refine(walk, required)
    eqs = Enum.map(eqs, &Value.shaped(&1, walk.shapes))
    %{walk | eqs: Enum.reverse(eqs, walk.eqs)}
  end

  @doc "I resolve the element shapes of a bound value before handing it to another walk."
  @spec fetch(t(), term()) :: Value.t()
  def fetch(walk, name), do: follow(walk, Map.fetch!(walk.env, name))

  @doc "I follow parameter aliases, retaining an unresolved reference's identity."
  @spec follow(t(), Value.t()) :: Value.t()
  def follow(walk, fresh = {:fresh, ref}) do
    case Map.fetch(walk.env, ref) do
      {:ok, value} -> follow(walk, value)
      :error -> fresh
    end
  end

  def follow(walk, value), do: Value.shaped(value, walk.shapes)

  @doc "I retain compatible shape requirements, independently of storage ownership."
  @spec refine(t(), %{Ast.row_ref() => View.element()}) :: t()
  def refine(walk, shapes), do: %{walk | shapes: merge_shapes(walk.shapes, shapes)}

  defp merge_shapes(a, b) do
    Map.merge(a, b, fn
      _row, shape, shape ->
        shape

      _row, %Record{width: {:at_least, a}}, %Record{width: {:at_least, b}} ->
        %Record{width: {:at_least, max(a, b)}}

      _row, %Record{width: {:at_least, min}}, shape = %Record{width: width}
      when is_integer(width) and width >= min ->
        shape

      _row, shape = %Record{width: width}, %Record{width: {:at_least, min}}
      when is_integer(width) and width >= min ->
        shape

      row, a, b ->
        throw({:refused, {:unliftable_term, %{term: {row, a, b}}}})
    end)
  end

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

  @doc """
  I choose storage for a newly resolved parameter. Structure shares its existing access;
  scalars and node references get parameter cells. Matching must constrain the chosen access
  to equal the value: this operation records storage without adding equations.
  """
  @spec allocate(t(), Ast.row_ref(), Value.t()) :: t()
  def allocate(walk, ref, value) do
    cell = Ast.cell(ref)

    cond do
      is_integer(value) ->
        bind(walk, ref, {:count, value, cell}, {:cell, ref})

      is_struct(value, Ref) ->
        bind(walk, ref, %Ref{id: cell}, {:node, ref})

      is_list(value) or is_struct(value, View) or is_struct(value, Cons) or
        is_struct(value, Element) or is_struct(value, Fields) or match?({:rel, _, _}, value) ->
        bind(walk, ref, value, :none)

      true ->
        bind(walk, ref, cell, {:cell, ref})
    end
  end

  @doc "I return the banks owned by parameter allocations."
  @spec banks(t()) :: [atom()]
  def banks(%__MODULE__{parameters: parameters}) do
    for {_ref, {:bank, name, _address}} <- parameters, do: name
  end

  @doc "I give a parameter its own sequence bank; matching its records can require more rows."
  @spec bank(t(), Ast.row_ref(), View.extent(), View.element()) :: t()
  def bank(walk = %__MODULE__{}, ref, extent, element \\ :unknown) do
    bank = Bank.of(ref)
    view = View.bank(bank, element, extent)
    walk = bind(walk, ref, view, {:bank, bank, view.col || Ast.address(:x, 0, 0)})
    if element == :unknown, do: walk, else: refine(walk, %{view.row => element})
  end

  @doc "I peel an unresolved record or an existing pair; ownership does not change its meaning."
  @spec peel(t(), Value.t()) :: {:ok, Value.t(), Value.t(), t()} | :dead
  def peel(walk, element = %Element{}), do: peel(walk, %Fields{element: element})

  def peel(
        walk,
        fields = %Fields{
          element: %Element{row: row = {bank, first}, col: {:at, base, m, a}},
          offset: n
        }
      ) do
    walk = refine(walk, %{row => %Record{width: {:at_least, n + 1}}})
    {:ok, Ast.at({bank, first + n}, base, m, a), %{fields | offset: n + 1}, walk}
  end

  def peel(walk, value) do
    value = Value.shaped(value, walk.shapes)

    with {:ok, head, tail, equations} <- Cons.peel(value),
         do: {:ok, head, tail, constrain(walk, equations)}
  end

  @doc "I close a record's shape or require an existing sequence to end."
  @spec ended(t(), Value.t()) :: t() | :dead
  def ended(walk, %Element{row: row}), do: refine(walk, %{row => %Record{width: 0}})

  def ended(walk, %Fields{element: %Element{row: row}, offset: width}),
    do: refine(walk, %{row => %Record{width: width}})

  def ended(walk, value) do
    with {:ok, equations} <- Cons.ended(Value.shaped(value, walk.shapes)),
         do: constrain(walk, equations)
  end
end
