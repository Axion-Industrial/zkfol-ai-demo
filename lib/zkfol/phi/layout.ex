defmodule Zkfol.Phi.Layout do
  @moduledoc """
  I decide what a member's parameters stand on before any clause is matched.

  The predicate never depends on the length of a list it was handed: a list's extent comes
  from the relation's own clauses, or it is open and presence ends it. Shapes first. The
  stepping call is the first recursive call that moves a parameter; the parameter it moves,
  or else the first list, is the column counter, and every other list's extent is expressed
  against that counter. Places second, by the table in `place/6`. A parameter nothing was
  handed takes what the clause body binds it to, by `bound/4`.

  ### Public API

  - `bound/4`: the handed places, a fresh one replaced by what the body binds it to.
  - `shapes/4`: the stepping call, the column counter, and a shape per parameter.
  - `places/5`: a place per parameter.
  """

  alias Zkfol.Alloc.Bank
  alias Zkfol.Ast
  alias Zkfol.Lang
  alias Zkfol.Lang.Rel
  alias Zkfol.Phi.{Place, Shape}

  @typedoc "The column counter: which parameter, and the count its base clause starts at."
  @type counter :: {non_neg_integer(), integer()}

  @typedoc """
  The stepping call: which parameter it moves, by how much, which relation it calls, and
  how far each argument is displaced from each head pattern.
  """
  @type step :: {non_neg_integer(), integer(), atom(), [[integer() | nil]]}

  @typedoc "The stepping call and the column counter, each when there is one."
  @type steps :: {step() | nil, counter() | nil}

  @typep clauses :: [{[term()], [term()]}]

  @typep solve :: %{
           step: step() | nil,
           counter: counter() | nil,
           handed: [Place.t()],
           known: Place.known(),
           scope: %{atom() => Rel.t()},
           seen: [atom()]
         }

  @doc """
  I return the handed places with each fresh one replaced by what the body binds it to.
  The body's calls are read in order, a callee's own body first, so what a callee binds
  its outputs to is what it hands back.
  """
  @spec bound(Rel.t(), [Place.t()], Place.known(), %{atom() => Rel.t()}) :: [Place.t()]
  def bound(rel, handed, known, scope), do: bound(rel, handed, known, scope, [])

  @doc "I return the stepping call, the column counter, and a shape per parameter."
  @spec shapes(Rel.t(), [Place.t()], Place.known(), %{atom() => Rel.t()}) ::
          {steps(), [Shape.t()]}
  def shapes(rel = %Rel{clauses: clauses, arity: arity}, handed, known, scope) do
    {step, counter} = column_counter(clauses, handed, known)
    solve = %{step: step, counter: counter, handed: handed, known: known, scope: scope, seen: []}

    shapes =
      for k <- 0..(arity - 1)//1 do
        case extent(rel, k, solve) do
          nil -> :scalar
          extent -> {:list, extent, element(clauses, k, Enum.at(handed, k), known)}
        end
      end

    {{step, counter}, shapes}
  end

  @doc "I return a place per parameter."
  @spec places(Rel.t(), [Ast.row_ref()], [Place.t()], [Shape.t()], steps()) :: [Place.t()]
  def places(%Rel{clauses: clauses}, refs, handed, shapes, steps) do
    for {{ref, form, shape}, k} <- Enum.with_index(Enum.zip([refs, handed, shapes])) do
      place(clauses, k, ref, form, shape, steps)
    end
  end

  # A node holds what no bank can: a term, a list in a member whose steps count no column,
  # or an unbounded list nothing was handed for. A cell holds a scalar, the column counter
  # reading the column itself. A list already standing somewhere is read as it is. Any
  # other list takes a bank.
  @spec place(clauses(), integer(), Ast.row_ref(), Place.t(), Shape.t(), steps()) :: Place.t()
  defp place(clauses, k, ref, form, shape, {step, counter}) do
    {j, o} = counter || {nil, 0}

    cond do
      Enum.any?([
        term?(clauses, k),
        match?({:node, _}, form),
        not matrix?(form),
        step != nil and counter == nil and shape != :scalar,
        open?(shape) and Place.fresh?(form)
      ]) ->
        {:node, Ast.cell(ref)}

      shape == :scalar and k == j ->
        Ast.add(:x, o)

      shape == :scalar ->
        scalar_place(form, ref)

      match?({:across, _, _, _}, form) or
        match?({:along, _, _}, form) or
          match?({:pair, _, _}, form) ->
        form

      true ->
        {:along, {Bank.of(ref), 1}, Place.head(shape)}
    end
  end

  @spec open?(Shape.t()) :: boolean()
  defp open?({:list, {:at_least, _}, _}), do: true
  defp open?(_shape), do: false

  @spec scalar_place(Place.t(), Ast.row_ref()) :: Place.t()
  defp scalar_place(q, ref) when is_integer(q), do: Ast.cell(ref)
  defp scalar_place({:count, _q, _cell}, ref), do: Ast.cell(ref)
  defp scalar_place(:fresh, ref), do: {:fresh, ref}
  defp scalar_place(form, _ref), do: form

  # What a list's elements are: a closed bracket in a head pattern is a record of that
  # width; failing that, the nesting of a handed literal says it; else it is not yet known.
  @spec element(clauses(), non_neg_integer(), Place.t(), Place.known()) :: Shape.t()
  defp element(clauses, k, form, known) do
    from_patterns =
      Enum.find_value(clauses, fn {head, _body} ->
        case Enum.at(head, k) do
          {:cons, bracket = {:cons, _, _}, _tail} ->
            case Lang.Term.closed(bracket) do
              nil -> nil
              fields -> {:list, {0, length(fields)}, :scalar}
            end

          _other ->
            nil
        end
      end)

    case {from_patterns, Place.shape(form, known)} do
      {nil, {:list, _extent, element}} -> element
      {nil, _scalar_or_unknown} -> :unknown
      {record, _handed} -> record
    end
  end

  # A literal of integers, or of rows of integers all one width, fits a bank; a ragged or
  # deeper literal is a term.
  @spec matrix?(Place.t()) :: boolean()
  defp matrix?(cells) when is_list(cells) do
    rows = Enum.all?(cells, &(is_list(&1) and Enum.all?(&1, fn q -> is_integer(q) end)))
    Enum.all?(cells, &is_integer/1) or (rows and length(Enum.uniq_by(cells, &length/1)) == 1)
  end

  defp matrix?(_place), do: true

  ############################################################
  #                     What a body binds                    #
  ############################################################

  @spec bound(Rel.t(), [Place.t()], Place.known(), %{atom() => Rel.t()}, [atom()]) ::
          [Place.t()]
  defp bound(rel = %Rel{name: name, clauses: clauses}, handed, known, scope, seen) do
    {head, body} = Enum.max_by(clauses, fn {_head, body} -> length(body) end)
    names = Enum.zip(params(rel), handed)
    env = for {name, form} <- names, not Place.fresh?(form), into: %{}, do: {name, form}
    {_step, counter} = column_counter(clauses, handed, known)
    caller = %{known: known, scope: scope, seen: [name | seen], counted: counter != nil}
    env = Enum.reduce(body, env, &binding(&1, &2, caller))

    for {{pattern, name}, form} <- Enum.zip(Enum.zip(head, params(rel)), handed) do
      case {pattern, Map.fetch(env, name)} do
        {{:var, _}, {:ok, place}} -> place
        _handed_or_unbound -> form
      end
    end
  end

  @typep caller :: %{
           known: Place.known(),
           scope: %{atom() => Rel.t()},
           seen: [atom()],
           counted: boolean()
         }

  # A call binds each fresh argument to the callee's place for that parameter; a relation
  # already being read is not read again.
  @spec binding(term(), %{atom() => Place.t()}, caller()) :: %{atom() => Place.t()}
  defp binding({:call, {_mod, q}, args}, env, caller) when is_atom(q),
    do: binding({:call, q, args}, env, caller)

  defp binding({:call, q, args}, env, caller = %{scope: scope, seen: seen})
       when is_atom(q) and is_map_key(scope, q) do
    callee = scope[q]
    handed = Enum.map(args, &argument(&1, env))

    handed_back =
      if q in seen,
        do: handed,
        else: bound(callee, handed, caller.known, scope, seen)

    {{step, _counter}, shapes} = shapes(callee, handed_back, caller.known, scope)

    for {{arg, form, back}, p} <- Enum.with_index(Enum.zip([args, handed, handed_back])),
        {:var, name} <- [arg],
        form == :fresh,
        reduce: env do
      env ->
        place =
          if Place.fresh?(back),
            do: output(callee, p, Enum.at(shapes, p), handed, step, caller.counted),
            else: back

        Map.put(env, name, place)
    end
  end

  defp binding({:eq, {:var, name}, _expression}, env, _caller),
    do: Map.put_new(env, name, Ast.cell(name))

  defp binding(_goal, env, _caller), do: env

  @spec argument(term(), %{atom() => Place.t()}) :: Place.t()
  defp argument({:var, name}, env), do: Map.get(env, name, :fresh)
  defp argument(q, _env) when is_integer(q), do: q
  defp argument(_term, _env), do: :x

  # Where a callee's output parameter stands. A call walking a node stays in the heap; a
  # scalar is a cell; a list takes a bank, behind a pointer when the caller counts no
  # column.
  @spec output(Rel.t(), non_neg_integer(), Shape.t(), [Place.t()], step() | nil, boolean()) ::
          Place.t()
  defp output(callee = %Rel{name: q}, p, shape, handed, step, counted) do
    ref = {q, {:param, Enum.at(params(callee), p)}}
    walked = step && Enum.at(handed, elem(step, 0))

    cond do
      match?({:node, _}, walked) -> {:node, Ast.cell(ref)}
      shape == :scalar -> Ast.cell(ref)
      counted -> {:along, {Bank.of(ref), 1}, Place.head(shape)}
      true -> {:along, {Bank.of(ref), 1}, Ast.address({:cell, ref}, 1, 0)}
    end
  end

  @doc "I name a relation's parameters: the longest clause's variables, `a<k>` for a pattern."
  @spec params(Rel.t()) :: [atom()]
  def params(%Rel{clauses: clauses}) do
    {head, _body} = Enum.max_by(clauses, fn {_head, body} -> length(body) end)

    for {pattern, k} <- Enum.with_index(head) do
      case pattern do
        {:var, name} -> name
        _other -> :"a#{k + 1}"
      end
    end
  end

  ############################################################
  #                       The counter                        #
  ############################################################

  @doc """
  I return the stepping call and the column counter: the parameter the stepping call
  displaces, or else the first list, unless the clauses make it a term or it cannot be walked.
  """
  @spec column_counter(clauses(), [Place.t()], Place.known()) :: steps()
  def column_counter(clauses, handed, known) do
    step = displaced_call(clauses)
    j = (step && elem(step, 0)) || Enum.find_index(handed, &counted?(&1, known))

    counter =
      if j && not term?(clauses, j) && walkable?(Enum.at(handed, j)),
        do: {j, origin(clauses, j, handed, known)}

    {step, counter}
  end

  # A position that is an integer in one head and a bracket in another: a term of two
  # constructors, which only the heap holds.
  @spec term?(clauses(), non_neg_integer()) :: boolean()
  defp term?(clauses, k) do
    heads = for {head, _body} <- clauses, do: Enum.at(head, k)
    Enum.any?(heads, &is_integer/1) and Enum.any?(heads, &Lang.Term.sequence?/1)
  end

  # A list, or a scalar that moves with the column.
  @spec counted?(Place.t(), Place.known()) :: boolean()
  defp counted?(place, known) do
    case {place, Place.shape(place, known)} do
      {_place, {:list, _extent, _element}} -> true
      {term, :scalar} -> match?({m, _a} when m != 0, Place.affine(term))
      _other -> false
    end
  end

  # A node is read through the heap and a list behind a pointer through the pointer.
  @spec walkable?(Place.t()) :: boolean()
  defp walkable?({:node, _}), do: false
  defp walkable?({:pair, _, _}), do: false
  defp walkable?({:along, _, {:at, {:cell, _}, _, _}}), do: false
  defp walkable?(_place), do: true

  # The first recursive call that moves a parameter.
  @spec displaced_call(clauses()) :: step() | nil
  defp displaced_call(clauses) do
    Enum.find_value(clauses, fn {head, body} ->
      Enum.find_value(body, fn
        {:call, q, args} when is_atom(q) ->
          hands = Enum.map(head, fn pattern -> Enum.map(args, &displaced(&1, pattern)) end)

          Enum.find_value(Enum.with_index(hands), fn {ds, k} ->
            with c when c not in [nil, 0] <- Enum.find(ds, &(&1 not in [nil, 0])),
                 do: {k, c, q, hands}
          end)

        _goal ->
          nil
      end)
    end)
  end

  # How far an argument is displaced from a head pattern: `x - 1` from `x` is -1, the
  # tail from `[h | t]` is -1, the pattern itself is 0.
  @spec displaced(term(), term()) :: integer() | nil
  defp displaced(name = {:var, _}, name) do
    0
  end

  defp displaced({:add, a, q}, pattern) when is_integer(q) do
    with c when is_integer(c) <- displaced(a, pattern), do: c + q
  end

  defp displaced({:cons, h, rest}, {:cons, h, t}) do
    displaced(rest, t)
  end

  defp displaced(arg, {:cons, _, t}) do
    with c when is_integer(c) <- displaced(arg, t), do: c - 1
  end

  defp displaced(_arg, _pattern) do
    nil
  end

  # The count the lowest base clause starts at, less one, so counts become columns from one.
  # A handed list shorter than every base clause counts from its own length: the third
  # dependence on data left here.
  @spec origin(clauses(), non_neg_integer(), [Place.t()], Place.known()) :: integer()
  defp origin(clauses, j, handed, known) do
    counts = for {head, _body} <- clauses, n = count_in(head, j), do: n
    Enum.min([1 | counts ++ List.wrap(count(Enum.at(handed, j), known))]) - 1
  end

  # The count a head pattern fixes for a parameter: the integer, the length of a closed
  # bracket, nothing for a name or an open bracket.
  @spec count_in([term()], non_neg_integer()) :: non_neg_integer() | nil
  defp count_in(head, k) do
    case Enum.at(head, k) do
      q when is_integer(q) ->
        q

      {:var, _} ->
        nil

      bracket ->
        with elements when elements != nil <- Lang.Term.closed(bracket), do: length(elements)
    end
  end

  ############################################################
  #                        The extents                       #
  ############################################################

  # A list parameter's extent, from the recurrence alone; nil for a parameter that is no
  # list. Without a counter a list keeps the extent it came with, or is open.
  @spec extent(Rel.t(), non_neg_integer(), solve()) :: Shape.extent() | nil
  defp extent(rel = %Rel{clauses: clauses}, k, solve) do
    form = Enum.at(solve.handed, k)
    {j, o} = solve.counter || {nil, 0}

    list? =
      match?({:list, _, _}, Place.shape(form, solve.known)) or
        Enum.any?(clauses, fn {head, _body} -> Lang.Term.sequence?(Enum.at(head, k)) end)

    cond do
      not list? -> nil
      solve.step == nil or solve.counter == nil -> handed_extent(form, solve.known)
      k == j -> {1, o}
      true -> recurrence_extent(rel, k, solve)
    end
  end

  # A list already standing somewhere keeps its extent; one nothing was handed for is
  # open. A handed literal keeps its count until the unifier can walk an open list in a
  # member that does not step: that count is the one dependence on data left here.
  @spec handed_extent(Place.t(), Place.known()) :: Shape.extent()
  defp handed_extent(form, known) do
    case Place.shape(form, known) do
      {:list, extent, _element} -> extent
      _scalar_or_unknown -> {:at_least, 0}
    end
  end

  # The stepping call hands parameter `k` on displaced by `c`. To this relation itself:
  # the list grows `c / cj` per column and has the base clause's count at column one.
  # To another relation: that relation's extent for it, seen from this member's column
  # and shortened by the displacement. Otherwise what was handed is all that is known.
  @spec recurrence_extent(Rel.t(), non_neg_integer(), solve()) :: Shape.extent()
  defp recurrence_extent(rel = %Rel{name: self}, k, solve = %{step: {j, cj, q, hands}}) do
    handed = Enum.at(solve.handed, k)

    case Enum.find(Enum.with_index(Enum.at(hands, k)), fn {c, _p} -> c != nil end) do
      {c, _p} when q == self ->
        rate = div(c, cj)
        Shape.from({rate, intercept(rel.clauses, solve, j, k)}, -1)

      {c, p} when q != self ->
        {_j, o} = solve.counter

        case callee_extent(solve.scope[q], p, solve) do
          {extent, oc} -> extent |> Shape.from(cj + o - oc) |> Shape.longer(-c)
          nil -> handed_extent(handed, solve.known)
        end

      _apart ->
        handed_extent(handed, solve.known)
    end
  end

  # A callee's extent for its parameter `p`, with its counter's origin; nil when the
  # callee counts no column or is already being asked.
  @spec callee_extent(Rel.t(), non_neg_integer(), solve()) :: {Shape.extent(), integer()} | nil
  defp callee_extent(callee = %Rel{name: q, arity: arity}, p, solve) do
    fresh = List.duplicate(:fresh, arity)

    with false <- q in solve.seen,
         {step, counter = {_jc, oc}} <- column_counter(callee.clauses, fresh, solve.known),
         false <- term?(callee.clauses, p),
         inner = %{solve | step: step, counter: counter, handed: fresh, seen: [q | solve.seen]},
         extent = {_m, _a} <- extent(callee, p, inner) do
      {extent, oc}
    else
      _unstepped -> nil
    end
  end

  # The count the base clause gives a parameter, or gives a name sharing its pattern. A
  # name the recursion passes through unchanged takes the count it was handed: the second
  # dependence on data left here, until an output can share its input's cells.
  @spec intercept(clauses(), solve(), non_neg_integer(), non_neg_integer()) :: integer()
  defp intercept(clauses, %{handed: handed, known: known, step: {_j, _cj, _q, hands}}, j, k) do
    {base, _body} = Enum.min_by(clauses, fn {head, _body} -> count_in(head, j) || 1 end)

    mates =
      for {pattern, i} <- Enum.with_index(base),
          i == k or (match?({:var, _}, pattern) and pattern == Enum.at(base, k)),
          do: i

    Enum.find_value(mates, 0, fn i ->
      case count_in(base, i) do
        nil -> if 0 in Enum.at(hands, i), do: count(Enum.at(handed, i), known)
        said -> said
      end
    end)
  end

  @spec count(Place.t(), Place.known()) :: integer() | nil
  defp count(q, _known) when is_integer(q), do: q
  defp count({:count, q, _cell}, _known), do: q
  defp count(place, known), do: Shape.count(Place.shape(place, known))
end
