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
  use GtBridge.View

  alias GtBridge.Phlow.ColumnedList
  alias Zkfol.Alloc.Bank
  alias Zkfol.Alloc.Member
  alias Zkfol.Alloc.Site
  alias Zkfol.Alloc.Slot
  alias Zkfol.Ast
  alias Zkfol.Phi.{Place, Shape, Value}

  defmodule Clause do
    @moduledoc "I retain one compiled clause's inputs and the walks before and after its rules."
    use TypedStruct
    use GtBridge.View
    alias GtBridge.Phlow.ColumnedList

    typedstruct enforce: true do
      field(:member, atom())
      field(:head, [term()])
      field(:body, [term()])
      field(:accesses, [Zkfol.Phi.Value.t()])
      field(:before, Zkfol.Phi.Walk.t())
      field(:matched, Zkfol.Phi.Walk.t() | :dead)
      field(:compiled, Zkfol.Phi.Walk.t() | :dead)
    end

    defview inputs_view(%Zkfol.Phi.Walk.Clause{head: head, accesses: accesses}, builder) do
      builder.columned_list()
      |> ColumnedList.title("Inputs")
      |> ColumnedList.priority(1)
      |> ColumnedList.items(Enum.zip(head, accesses))
      |> ColumnedList.column("Pattern", fn {pattern, _access} ->
        Zkfol.Face.surface_text(pattern)
      end)
      |> ColumnedList.column("Access", fn {_pattern, access} -> Zkfol.Face.inspected(access) end)
      |> ColumnedList.send(fn {_pattern, access} -> access end)
    end

    defview steps_view(clause = %Zkfol.Phi.Walk.Clause{}, builder) do
      builder.columned_list()
      |> ColumnedList.title("Steps")
      |> ColumnedList.priority(2)
      |> ColumnedList.items([
        {"Before head", clause.before},
        {"After head", clause.matched},
        {"After body", clause.compiled}
      ])
      |> ColumnedList.column("Step", fn {name, _state} -> name end)
      |> ColumnedList.send(fn {_name, state} -> state end)
    end
  end

  typedstruct do
    field(:env, map(), default: %{})
    field(:shapes, %{Ast.row_ref() => Shape.t()}, default: %{})
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
          {:across, row, _address, 0}, rows -> [row | rows]
          _term, rows -> rows
        end)
      )
      |> Enum.reject(&match?({:list, _, _}, Map.get(walk.shapes, &1)))
      |> Map.new(&{&1, :scalar})

    walk = refine(walk, required)
    eqs = Enum.map(eqs, &Value.shaped(&1, walk.shapes))

    # A record read as a number has no number: its fields came back as a list.
    for eq <- eqs, Ast.reduce(eq, false, &(&2 or (is_list(&1) and &1 != []))) do
      throw({:refused, {:unliftable_term, %{term: eq}}})
    end

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
  @spec refine(t(), %{Ast.row_ref() => Shape.t()}) :: t()
  def refine(walk, shapes), do: %{walk | shapes: merge_shapes(walk.shapes, shapes)}

  defp merge_shapes(a, b) do
    Map.merge(a, b, fn row, x, y ->
      case Shape.meet(x, y) do
        :contradiction -> throw({:refused, {:unliftable_term, %{term: {row, x, y}}}})
        shape -> shape
      end
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

      match?({:node, _id}, value) ->
        bind(walk, ref, {:node, cell}, {:node, ref})

      is_list(value) or match?({:along, _, _}, value) or match?({:pair, _, _}, value) or
        match?({:across, _, _, _}, value) or match?({:rel, _, _}, value) ->
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

  @doc "I give a parameter the bank it is laid along, knowing of its rows what the shape says."
  @spec bank(t(), Ast.row_ref(), Place.t(), Shape.t()) :: t()
  def bank(walk = %__MODULE__{}, ref, along = {:along, row = {bank, 1}, address}, shape) do
    {:list, _extent, element} = shape
    walk = bind(walk, ref, along, {:bank, bank, address})
    if element == :unknown, do: walk, else: refine(walk, %{row => element})
  end

  @doc "I peel an unresolved record or an existing pair; ownership does not change its meaning."
  @spec peel(t(), Value.t()) :: {:ok, Value.t(), Value.t(), t()} | :dead
  def peel(walk, {:across, row = {bank, first}, col = {:at, base, m, a}, n}) do
    walk = refine(walk, %{row => {:list, {:at_least, n + 1}, :scalar}})
    {:ok, Ast.at({bank, first + n}, base, m, a), {:across, row, col, n + 1}, walk}
  end

  def peel(walk, value) do
    case Value.shaped(value, walk.shapes) do
      {:pair, head, tail} ->
        {:ok, head, tail, walk}

      [head | tail] ->
        {:ok, head, tail, walk}

      along = {:along, _row, _address} ->
        with walk = %__MODULE__{} <- presence(walk, along, 1),
             do: {:ok, Place.slice(along, 0, walk.shapes), Place.shifted(along, 1), walk}

      {:node, id} ->
        {:ok, {:node, Place.read(:head, id)}, {:node, Place.read(:tail, id)},
         constrain(walk, [Ast.eq(Place.read(:tag, id), 2)])}

      _other ->
        :dead
    end
  end

  @doc "I close a record's shape or require an existing sequence to end."
  @spec ended(t(), Value.t()) :: t() | :dead
  def ended(walk, {:across, row, _address, width}),
    do: refine(walk, %{row => {:list, {0, width}, :scalar}})

  def ended(walk, value) do
    case Value.shaped(value, walk.shapes) do
      [] -> walk
      along = {:along, _row, _address} -> presence(walk, along, 0)
      {:node, id} -> constrain(walk, [Ast.eq(id, 1)])
      _other -> :dead
    end
  end

  # A known length decides presence; otherwise the bank's presence cell must say it.
  defp presence(walk, along, required) do
    case Place.count(along) do
      nil -> constrain(walk, [Ast.eq(Place.presence(along), required)])
      0 when required == 0 -> walk
      n when n > 0 and required == 1 -> walk
      _other -> :dead
    end
  end

  ############################################################
  #                            Views                         #
  ############################################################

  defview predicates_view(%Zkfol.Phi.Walk{predicates: predicates}, builder) do
    builder.columned_list()
    |> ColumnedList.title("Predicates")
    |> ColumnedList.priority(5)
    |> ColumnedList.items(predicates)
    |> ColumnedList.column("Predicate", &Zkfol.Face.phi_text/1)
  end

  defview bindings_view(walk = %Zkfol.Phi.Walk{env: env}, builder) do
    builder.columned_list()
    |> ColumnedList.title("Bindings")
    |> ColumnedList.priority(2)
    |> ColumnedList.items(
      for {name, _access} <- Enum.sort(env), do: {name, Zkfol.Phi.Walk.fetch(walk, name)}
    )
    |> ColumnedList.column("Name", fn {name, _access} -> inspect(name) end)
    |> ColumnedList.column("Access", fn {_name, access} -> Zkfol.Face.inspected(access) end)
    |> ColumnedList.send(fn {_name, access} -> access end)
  end

  defview equations_view(%Zkfol.Phi.Walk{eqs: eqs}, builder) do
    builder.columned_list()
    |> ColumnedList.title("Equations")
    |> ColumnedList.priority(3)
    |> ColumnedList.items(Enum.reverse(eqs))
    |> ColumnedList.column("Equation", &Zkfol.Face.phi_text/1)
  end

  defview storage_view(walk = %Zkfol.Phi.Walk{}, builder) do
    builder.columned_list()
    |> ColumnedList.title("Storage")
    |> ColumnedList.priority(4)
    |> ColumnedList.items([
      {"Owned banks", Zkfol.Phi.Walk.banks(walk)},
      {"Element shapes", walk.shapes},
      {"Parameters", walk.parameters},
      {"Slots", walk.slots},
      {"Members", walk.members}
    ])
    |> ColumnedList.column("What", fn {name, _value} -> name end)
    |> ColumnedList.column("Value", fn {_name, value} -> Zkfol.Face.inspected(value) end)
    |> ColumnedList.send(fn {_name, value} -> value end)
  end
end
