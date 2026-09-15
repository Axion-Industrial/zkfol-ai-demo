defmodule Zkfol.Unrolling do
  @moduledoc """
  I decide where each list stands so that the predicate reads it without a pointer.

  Zinc+ charges for pointer reads. A list laid along the trace, one element per column
  with its head at a column affine in X, is read by plain shifts instead. I choose that
  layout wherever the relation's clauses allow it: a cons becomes cells one column apart,
  a recursive call becomes the same member one column back, and a call over a source
  literal is replaced by its clauses. This is an optimization. With `unrolling: false` on
  the `Zkfol.Phi` pass, Phi does not call me: every list is a node in the heap, every
  constant a count in its cell, every call a member at a pointer, and every program
  still compiles and proves at a higher cost. If pricing moves to egglog, or a backend
  makes pointer reads cheap, this module is what changes.

  Per member, before any clause is matched, I compute the stepping call, which is the
  first recursive call that moves a parameter; the column counter, which is the parameter
  that call moves or else the first list, whose count is read from the column; the extent
  of every other list relative to that counter; and a place for each parameter, by the
  table in `place/6`.

  Per call, I decide whether it is unrolled into its clauses or compiled as a member
  (`strategy/4`), and the column a continued or a new member stands at (`frame/2`,
  `new_frame/4`).

  ### Public API

  - `parameters/5`: the column counter, and a shape and a place per parameter.
  - `strategy/4`: unroll a call, prefer a member, or require one.
  - `frame/2`, `new_frame/4`: the column a continued member and a new member stand at.
  """

  alias Zkfol.Alloc.Bank
  alias Zkfol.Ast
  alias Zkfol.Lang
  alias Zkfol.Lang.Rel
  alias Zkfol.Phi.{Layout, Place, Shape, Value}

  require Place

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

  @doc "I return the column counter, and a shape and a place per parameter."
  @spec parameters(
          Rel.t(),
          [Ast.row_ref()],
          [Place.t()],
          Place.known(),
          %{atom() => Rel.t()}
        ) :: {counter() | nil, [Shape.t()], [Place.t()]}
  def parameters(rel = %Rel{clauses: clauses, arity: arity}, refs, handed, known, scope) do
    {step, counter} = column_counter(clauses, handed, known)
    solve = %{step: step, counter: counter, handed: handed, known: known, scope: scope, seen: []}

    shapes =
      for k <- 0..(arity - 1)//1 do
        case extent(rel, k, solve) do
          nil -> :scalar
          extent -> {:list, extent, Layout.element(Enum.at(handed, k), known)}
        end
      end

    places =
      for {{ref, form, shape}, k} <- Enum.with_index(Enum.zip([refs, handed, shapes])) do
        place(clauses, k, ref, form, shape, {step, counter})
      end

    {counter, shapes, places}
  end

  # A term, a list in a member that counts no column, and an unbounded list nothing was
  # handed for are nodes; no bank can hold them. A scalar is a cell, except the column
  # counter, which reads the column itself, and a handed constant, which is inlined. A
  # passed relation's fixed arguments take the member's own cells. A list that already
  # stands somewhere is read where it is, re-headed at the member's extent when the member
  # steps. Every other list takes a bank along the trace.
  @spec place(clauses(), integer(), Ast.row_ref(), Place.t(), Shape.t(), steps()) :: Place.t()
  defp place(clauses, k, ref, form, shape, {step, counter}) do
    {j, o} = counter || {nil, 0}

    cond do
      Enum.any?([
        term?(clauses, k),
        match?({:node, _}, form),
        not Layout.matrix?(form),
        step != nil and counter == nil and shape != :scalar,
        open?(shape) and Place.fresh?(form)
      ]) ->
        {:node, Ast.cell(ref)}

      shape == :scalar and k == j ->
        Ast.add(:x, o)

      match?({:rel, _, _}, form) ->
        Place.owned(form, ref)

      shape == :scalar ->
        scalar_place(form, ref)

      Place.is_laid(form) and step != nil and counter != nil ->
        Place.stepped(form, shape)

      match?({:across, _, _, _}, form) or Place.is_laid(form) or match?({:pair, _, _}, form) ->
        form

      true ->
        {:along, {Bank.of(ref), 1}, Place.head(shape)}
    end
  end

  @spec open?(Shape.t()) :: boolean()
  defp open?({:list, {:at_least, _}, _}), do: true
  defp open?(_shape), do: false

  @spec scalar_place(Place.t(), Ast.row_ref()) :: Place.t()
  defp scalar_place(q, _ref) when is_integer(q), do: q
  defp scalar_place({:count, q, _cell}, ref), do: {:count, q, Ast.cell(ref)}
  defp scalar_place(:fresh, ref), do: {:fresh, ref}
  defp scalar_place(form, _ref), do: form

  ############################################################
  #                       The counter                        #
  ############################################################

  # The stepping call and the column counter: the parameter the stepping call displaces,
  # or else the first list, unless the clauses make it a term or it cannot be walked.
  @spec column_counter(clauses(), [Place.t()], Place.known()) :: steps()
  defp column_counter(clauses, handed, known) do
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
  defp walkable?({:held, _, _, _}), do: false
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

  # The origin is the smallest count a base clause fixes, minus one, so that count maps to
  # column one. A handed list shorter than every base clause sets the origin from its own
  # length; this depends on the handed data.
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

    list? = match?({:list, _, _}, Place.shape(form, solve.known)) or Layout.list?(clauses, k)

    cond do
      not list? -> nil
      solve.step == nil or solve.counter == nil -> handed_extent(form, solve.known)
      k == j -> {1, o}
      true -> recurrence_extent(rel, k, solve)
    end
  end

  # A list already standing somewhere keeps its extent; one nothing was handed for is
  # open. A handed literal keeps its count, which depends on the handed data, because a
  # member that does not step cannot walk an open list yet.
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

  # The extent of the callee's parameter `p` and the origin of its counter. nil when the
  # callee counts no column or is already being solved.
  @spec callee_extent(Rel.t(), non_neg_integer(), solve()) :: {Shape.extent(), integer()} | nil
  defp callee_extent(callee = %Rel{name: q, arity: arity}, p, solve) do
    fresh = List.duplicate(:fresh, arity)

    with false <- q in solve.seen,
         {step, counter = {_jc, oc}} <-
           column_counter(callee.clauses, fresh, solve.known),
         false <- term?(callee.clauses, p),
         inner = %{solve | step: step, counter: counter, handed: fresh, seen: [q | solve.seen]},
         extent = {_m, _a} <- extent(callee, p, inner) do
      {extent, oc}
    else
      _unstepped -> nil
    end
  end

  # The count the base clause gives a parameter, or gives a name sharing its pattern. A
  # name the recursion passes through unchanged takes the count it was handed, which
  # depends on the handed data.
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

  ############################################################
  #                         The calls                        #
  ############################################################

  @typedoc """
  The argument sizes of every call being unrolled on the path, by call, so a recursive
  call can be seen to shrink or not.
  """
  @type inlining :: %{{atom(), [{non_neg_integer(), Value.t()}]} => [integer() | nil]}

  @doc """
  I decide whether a recursive call is unrolled into its clauses, prefers a member, or
  must be a member. It is unrolled only while no known argument size grows or appears and
  one shrinks, which bounds the unrolling. A call over a counted list prefers a member. I
  also return the updated sizes for the path.
  """
  @spec strategy(Rel.t(), [Value.t()], Place.known(), inlining()) ::
          {:inline | :prefer_call | :residual, inlining()}
  def strategy(%Rel{name: name}, values, known, inlining) do
    key = specialization(name, values)
    sizes = Enum.map(values, &size(&1, known))
    around = Map.get(inlining, key)
    shrunk = if around, do: Enum.zip(sizes, around)
    constructed = Enum.any?(values, &(is_list(&1) or match?({:pair, _, _}, &1)))

    decreases =
      shrunk == nil or
        (Enum.all?(shrunk, fn {a, b} -> a == nil or (b != nil and a <= b) end) and
           Enum.any?(shrunk, fn {a, b} -> a != nil and b != nil and a < b end))

    strategy =
      cond do
        not decreases ->
          :residual

        not constructed and Enum.any?(values, &(Place.count(&1) != nil)) ->
          :prefer_call

        true ->
          :inline
      end

    {strategy, Map.put(inlining, key, sizes)}
  end

  # Two calls with different passed relations are different calls for the shrinking check.
  @spec specialization(atom(), [Value.t()]) :: {atom(), [{non_neg_integer(), Value.t()}]}
  defp specialization(name, values),
    do: {name, for({value = {:rel, _, _}, k} <- Enum.with_index(values), do: {k, value})}

  # How many cells a value holds, a natural standing for that many and an unresolved
  # scalar for one; a negative or an element of unknown shape counts nothing.
  @spec size(Value.t(), Place.known()) :: non_neg_integer() | nil
  defp size(q, _known) when is_integer(q), do: if(q >= 0, do: q)
  defp size(laid, known) when Place.is_laid(laid), do: Place.size(laid, known)
  defp size([], _known), do: 0

  defp size({:pair, h, t}, known),
    do: with(a when a != nil <- size(h, known), b when b != nil <- size(t, known), do: a + b)

  defp size([h | t], known),
    do: with(a when a != nil <- size(h, known), b when b != nil <- size(t, known), do: a + b)

  defp size({:across, _, _, _}, _known), do: nil
  defp size({:rel, _p, _f}, _known), do: nil
  defp size(_cell, _known), do: 1

  @doc """
  I return where a new member stands: the caller's column where the callee's count
  stands, or the caller's own column when the callee counts none, since unrolling gives
  each call its own column.
  """
  @spec new_frame(Rel.t(), [Value.t()], [Value.t()], Place.known()) :: Ast.address() | :ptr
  def new_frame(%Rel{clauses: clauses}, values, lifted, known) do
    case column_counter(clauses, lifted, known) do
      {_step, nil} -> Ast.address(:x, 1, 0)
      {_step, counter} -> frame(values, counter)
    end
  end

  @doc "I return the caller's column where a continued member's count stands, or `:ptr` when the count is open."
  @spec frame([Value.t()], counter()) :: Ast.address() | :ptr
  def frame(values, {j, o}) do
    count =
      case Enum.at(values, j) do
        laid when Place.is_laid(laid) -> Place.extent(laid)
        cells when is_list(cells) -> if Layout.data?(cells), do: {0, length(cells)}
        form -> Place.affine(form)
      end

    with {m, a} <- count, do: Ast.address(:x, m, a - o), else: (_open -> :ptr)
  end
end
