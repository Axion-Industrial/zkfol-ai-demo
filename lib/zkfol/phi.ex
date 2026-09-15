defmodule Zkfol.Phi do
  @moduledoc """
  I am the lowering pass: a statement's relations become cells and equalities, and the
  run's derivation is laid on the allocation born of them. Four rules make every equation:

  1. A symbol is a cell: handed one it references it, handed none it allocates a row, a
     repeat equates.
  2. A call is one fact, the callee present at an address; one whose clause the values
     select and whose steps are finite is said in place instead.
  3. Recursion is address arithmetic: a call to a relation being laid continues it.
  4. Data fills cells; sizes, structure and ground literals shape the predicate.

  For each member, `bind_parameters` chooses symbolic accesses using the column and
  sequence extents. `compile_clauses` produces constraints and resolves unknown bindings.
  `allocate_parameters` completes the slots and bank depths for Lay. Extent inference
  reads source recurrences without constructing allocations.

  ### Public API

  - `run/2`, `verb/0`: the pass.
  - `relaid/2`: the derivation laid as the statement's witness.
  - `compile/3`: the predicate and the allocation it stands on.
  - `lower/2`: that predicate, linked.
  """

  @behaviour Zkfol.Pipeline

  alias Zkfol.Alloc
  alias Zkfol.Alloc.Bank
  alias Zkfol.Alloc.Member
  alias Zkfol.Alloc.Site
  alias Zkfol.Alloc.Slot
  alias Zkfol.Ast
  alias Zkfol.Derivation
  alias Zkfol.Lay
  alias Zkfol.Lang
  alias Zkfol.Lang.Rel
  alias Zkfol.Phi.Ref
  alias Zkfol.Phi.Cons
  alias Zkfol.Phi.View
  alias Zkfol.Phi.Value
  alias Zkfol.Phi.Walk
  alias Zkfol.Refusal
  alias Zkfol.Statement

  @typep value :: Value.t()
  @typep frame :: Value.frame()
  @typep placement :: {atom(), [value()], frame(), Walk.t()}

  # `inlining`: sizes of the calls being expanded on this path.
  @typep ctx :: %{
           scope: %{atom() => Rel.t()},
           recursive: MapSet.t(),
           ancestors: [{Member.t(), [value()]}],
           taken: MapSet.t(),
           member: atom(),
           site: [non_neg_integer() | atom()],
           inlining: %{{atom(), [{non_neg_integer(), value()}]} => [integer() | nil]}
         }

  @doc "I lay a derived statement; one that has not run passes through."
  @impl Zkfol.Pipeline
  @spec run(Statement.t(), keyword()) :: {:ok, Statement.t()} | {:error, Refusal.t()}
  def run(statement = %Statement{stage: %Derivation{} = derivation}, _opts),
    do: relaid(statement, derivation)

  def run(statement = %Statement{}, _opts), do: {:ok, statement}

  @impl Zkfol.Pipeline
  @spec verb() :: Zkfol.Pipeline.verdict()
  def verb, do: :lowers

  @doc "I lay the derivation for the statement."
  @spec relaid(Statement.t(), Derivation.t()) :: {:ok, Statement.t()} | {:error, Refusal.t()}
  def relaid(statement = %Statement{rels: [root | _rest] = rels}, derivation = %Derivation{}) do
    # What the run established of the root itself: the arguments, every hole filled.
    {_name, args} = Derivation.root(derivation, root.name) || {root.name, []}

    with {:ok, pred, alloc} <- compile(root, rels, args) do
      stage = %Statement.Solved{pred: Alloc.link(pred, alloc), lay: Lay.of(derivation, alloc)}
      {:ok, %{statement | stage: stage}}
    end
  end

  @doc "I am the predicate of `root` against `rels`, linked."
  @spec lower(Rel.t(), [Rel.t()]) :: {:ok, Ast.pred()} | {:error, Refusal.t()}
  def lower(root = %Rel{}, rels) do
    with {:ok, pred, alloc} <- compile(root, rels), do: {:ok, Alloc.link(pred, alloc)}
  end

  @doc "I compile `root` against `rels` to its predicate and allocation; `args` size its banks."
  @spec compile(Rel.t(), [Rel.t()] | nil, [term()]) ::
          {:ok, Ast.pred(), Alloc.t()} | {:error, Refusal.t()}
  def compile(root = %Rel{}, rels \\ nil, args \\ []) do
    with {:ok, [root | _rest] = reached} <- Lang.reached(root, rels || [root]) do
      compiled(root, Map.new(reached, &{&1.name, &1}), args)
    end
  end

  @spec compiled(Rel.t(), %{atom() => Rel.t()}, [term()]) ::
          {:ok, Ast.pred(), Alloc.t()} | {:error, Refusal.t()}
  defp compiled(root = %Rel{}, scope, args) do
    # A handed scalar is data: its count may place (rule 4), its value never substitutes.
    handed =
      for k <- 0..(root.arity - 1)//1 do
        case Enum.at(args, k) do
          cells when is_list(cells) -> cells
          q when is_integer(q) -> {:count, q, nil}
          _open -> :fresh
        end
      end

    # A relation reaching itself by name is what a call may only unroll finitely or lay.
    recursive =
      for rel = %Rel{name: name} <- Map.values(scope),
          q <- Rel.calls(rel) ++ Rel.passes(rel),
          callee = %Rel{} <- [scope[q]],
          {:ok, reached} <- [Lang.reached(callee, Map.values(scope))],
          name in for(r <- reached, do: r.name),
          into: MapSet.new(),
          do: name

    ctx = %{
      scope: scope,
      recursive: recursive,
      ancestors: [],
      taken: MapSet.new(),
      member: nil,
      site: [],
      inlining: %{}
    }

    {name, _binds, walk} = compile_member(root, handed, ctx)

    pred =
      Ast.conj(
        walk.predicates ++
          for(bank = %Bank{} <- walk.members, do: runs(bank))
      )

    {pred, members} = Zkfol.Nodes.lower(pred, walk.members)
    {:ok, pred, Alloc.numbered(members, name)}
  catch
    {:refused, refusal} -> {:error, refusal}
  end

  # A bank fills one run from column two, so no forger shortens a walk by cutting its presence.
  @spec runs(Bank.t()) :: Ast.pred()
  defp runs(%Bank{name: name}) do
    Ast.disj([
      Ast.eq({:cell, {:in, name}}, 0),
      Ast.eq(Ast.at({:in, name}, :x, 1, -1), 1),
      Ast.eq(:x, 2)
    ])
  end

  ############################################################
  #                     Member Compilation                   #
  ############################################################

  # Spent rows number after the parameters' own, by tag, so goal order moves nothing.
  @spec compile_member(Rel.t(), [value()], ctx()) :: {atom(), [value()], Walk.t()}
  defp compile_member(%Rel{} = rel, handed, ctx) do
    name = minted(rel.name, ctx.taken)
    syms = params(rel)
    refs = for sym <- syms, do: {name, {:param, sym}}
    {steps, binds} = bind_parameters(rel, handed, refs, ctx.scope)

    seeded =
      for {bind, ref} <- Enum.zip(binds, refs),
          %View{row: {bank, _r}} <- [bind],
          bank == Bank.of(ref),
          into: %{},
          do: {bank, length(View.rows(bind))}

    member = %Member{name: name, relation: rel.name, steps: steps, slots: [], sites: %{}}

    ctx = %{
      ctx
      | ancestors: [{member, binds} | ctx.ancestors],
        taken: Enum.into([name | Map.keys(seeded)], ctx.taken),
        member: name
    }

    clauses = compile_clauses(rel, member, binds, %Walk{banks: seeded}, ctx)
    live = for clause = %Walk{} <- clauses, do: clause
    branches = for clause <- live, do: Ast.conj(clause.eqs)
    {binds, slots, banks} = allocate_parameters(binds, refs, seeded, live)

    sites =
      Map.new(Enum.with_index(clauses), fn
        {%Walk{sites: sites}, k} -> {k, for({_i, site} <- Enum.sort(sites), do: site)}
        {:dead, k} -> {k, []}
      end)

    local = live |> Enum.flat_map(& &1.slots) |> Enum.sort_by(&elem(&1.allocation, 1))
    member = %{member | sites: sites, slots: slots ++ local}

    branches =
      for {:conj, [present | eqs]} <- branches,
          do: Ast.conj([present | Enum.sort_by(eqs, &inspect/1)])

    said = Ast.disj([Ast.eq({:cell, {:in, name}}, 0) | branches])

    walk = %Walk{
      members: [member | banks] ++ Enum.flat_map(live, & &1.members),
      predicates: [said | Enum.flat_map(live, & &1.predicates)]
    }

    {name, binds, walk}
  end

  @spec minted(atom(), MapSet.t()) :: atom()
  defp minted(q, taken),
    do:
      Enum.find(
        [q | for(i <- 2..(MapSet.size(taken) + 2)//1, do: :"#{q}#{i}")],
        &(&1 not in taken)
      )

  ############################################################
  #                   Parameter Allocation                   #
  ############################################################

  # Choose how clauses access each parameter. Unbound values are completed after the clauses.
  @spec bind_parameters(Rel.t(), [value()], [Ast.row_ref()], %{atom() => Rel.t()}) ::
          {{non_neg_integer(), integer()} | nil, [value()]}
  defp bind_parameters(rel = %Rel{clauses: clauses}, handed, refs, scope) do
    {step, counter} = column_counter(clauses, handed)
    {j, o} = counter || {nil, 0}
    solve = %{step: step, counter: counter, handed: handed, scope: scope, seen: []}

    binds =
      for {{form, ref}, k} <- Enum.with_index(Enum.zip(handed, refs)) do
        extent = extent(rel, k, solve)

        cond do
          tagged?(clauses, k) or is_struct(form, Ref) or
            (step != nil and counter == nil and extent != nil) or
            (is_list(form) and not bankable?(form)) or
              (extent == :open and (form == :fresh or match?({:fresh, _}, form))) ->
            %Ref{id: Ast.cell(ref)}

          k == j and extent == nil ->
            Ast.add(:x, o)

          extent == nil or
              (match?(%View{}, form) and (step == nil or counter == nil)) ->
            case form do
              :fresh -> {:fresh, ref}
              {:count, q, _cell} -> {:count, q, Ast.cell(ref)}
              _reference -> form
            end

          match?(%View{}, form) ->
            View.stepped(form, extent) ||
              throw({:refused, {:unliftable_term, %{term: form, relation: rel.name}}})

          true ->
            depth = Enum.max([1 | for(c <- List.wrap(form), is_list(c), do: length(c))])
            View.bank(Bank.rows(Bank.of(ref), depth), extent)
        end
      end

    {counter, binds}
  end

  # Clauses resolve unknown bindings; surviving reads demand storage for unresolved scalars.
  # A completed binding owns storage only when it names this parameter's cells.
  @spec allocate_parameters([value()], [Ast.row_ref()], map(), [Walk.t()]) ::
          {[value()], [Slot.t()], [Bank.t()]}
  defp allocate_parameters(binds, refs, seeded, clauses) do
    envs = for clause <- clauses, do: clause.env
    read = MapSet.new(Enum.flat_map(clauses, &Zkfol.Nodes.reads(Ast.conj(&1.eqs))))

    parameters =
      for {bind, {_name, {:param, sym}} = ref} <- Enum.zip(binds, refs) do
        bank = Bank.of(ref)

        bind =
          case bind do
            {:fresh, ^ref} -> Enum.find_value(envs, &Map.get(&1, ref)) || bind
            _resolved -> bind
          end

        allocation =
          case bind do
            {:fresh, ^ref} -> if(ref in read, do: {:cell, ref}, else: :none)
            %Ref{id: {:cell, ^ref}} -> {:node, ref}
            :x -> {:column, 0}
            {:add, :x, o} -> {:column, o}
            {:cell, ^ref} -> {:cell, ref}
            {:count, _q, {:cell, ^ref}} -> {:cell, ref}
            %View{row: {^bank, _r}, col: {_b, m, a}} -> {:bank, bank, {:at, :x, m, a}}
            %View{row: {^bank, _r}, col: nil} -> {:bank, bank, {:at, :x, 0, 0}}
            _reference -> :none
          end

        {bind, %Slot{name: sym, allocation: allocation}}
      end

    banks =
      for ref <- refs,
          bank = Bank.of(ref),
          depths =
            for(banks <- [seeded | Enum.map(clauses, & &1.banks)], depth = banks[bank], do: depth),
          depths != [],
          do: %Bank{name: bank, depth: Enum.max(depths)}

    {binds, slots} = Enum.unzip(parameters)
    {binds, slots, banks}
  end

  ############################################################
  #                 Column and Sequence Extents              #
  ############################################################

  # Choose the column counter before constructing any parameter representation.
  @spec column_counter([{[term()], [term()]}], [value()]) ::
          {step() | nil, {non_neg_integer(), integer()} | nil}
  defp column_counter(clauses, handed) do
    step = displaced_call(clauses)
    j = (step && elem(step, 0)) || Enum.find_index(handed, &counted?/1)

    counter =
      if j && not tagged?(clauses, j) && walkable?(Enum.at(handed, j)),
        do: {j, origin(clauses, j)}

    {step, counter}
  end

  defp tagged?(clauses, k) do
    heads = for {head, _body} <- clauses, do: Enum.at(head, k)
    Enum.any?(heads, &is_integer/1) and Enum.any?(heads, &Lang.Term.sequence?/1)
  end

  # A bank stores a scalar row or equal-width scalar rows; other terms need nodes.
  defp bankable?(cells) do
    scalar_row?(cells) or
      (Enum.all?(cells, &scalar_row?/1) and length(Enum.uniq_by(cells, &length/1)) == 1)
  end

  defp scalar_row?(cells) when is_list(cells), do: Enum.all?(cells, &is_integer/1)
  defp scalar_row?(_value), do: false

  @spec counted?(value()) :: boolean()
  defp counted?(%View{axes: [%{row: 0, extent: e} | _rest]}), do: e != :open
  defp counted?(form) when is_list(form), do: data_list?(form)
  defp counted?(form), do: match?(%View{row: nil, col: {:x, m, _a}} when m != 0, View.of(form))

  @spec walkable?(value()) :: boolean()
  defp walkable?(%View{col: col} = view), do: col != nil and not View.rowed?(view)
  defp walkable?(%Ref{}), do: false
  defp walkable?(%Cons{}), do: false
  defp walkable?(cells) when is_list(cells), do: data_list?(cells)
  defp walkable?(_value), do: true

  # The stepping call: the parameter, its displacement, the callee, how far each argument hands.
  @typep step :: {non_neg_integer(), integer(), atom(), [[integer() | nil]]}

  @spec displaced_call([{[term()], [term()]}]) :: step() | nil
  defp displaced_call(clauses) do
    Enum.find_value(clauses, fn {head, body} ->
      Enum.find_value(body, fn
        {:call, q, args} when is_atom(q) ->
          hands = for pattern <- head, do: for(arg <- args, do: displaced(arg, pattern))

          Enum.find_value(Enum.with_index(hands), fn {ds, k} ->
            with c when c not in [nil, 0] <- Enum.find(ds, &(&1 not in [nil, 0])),
                 do: {k, c, q, hands}
          end)

        _goal ->
          nil
      end)
    end)
  end

  @spec displaced(term(), term()) :: integer() | nil
  defp displaced({:var, _v} = name, name), do: 0

  defp displaced({:add, a, q}, pattern) when is_integer(q),
    do: with(c when is_integer(c) <- displaced(a, pattern), do: c + q)

  defp displaced({:add, q, a}, pattern) when is_integer(q), do: displaced({:add, a, q}, pattern)
  defp displaced({:cons, h, rest}, {:cons, h, t}), do: displaced(rest, t)

  defp displaced(arg, {:cons, _h, t}),
    do: with(c when is_integer(c) <- displaced(arg, t), do: c - 1)

  defp displaced(_arg, _pattern), do: nil

  # The count the smallest base clause stands at, a column from one.
  @spec origin([{[term()], [term()]}], non_neg_integer()) :: integer()
  defp origin(clauses, j),
    do: Enum.min([1 | for({head, _body} <- clauses, n = count_in(head, j), do: n)]) - 1

  # The count a parameter stands at in a clause head: a pin, a closed spine, none for a name.
  @spec count_in([term()], non_neg_integer()) :: non_neg_integer() | nil
  defp count_in(head, k) do
    case Enum.at(head, k) do
      q when is_integer(q) -> q
      {:var, _v} -> nil
      bracket -> if(tail_of(bracket) == nil, do: length(spine(bracket)))
    end
  end

  # Extents depend on the source recurrence and argument shapes, not on allocated rows.
  @spec extent(Rel.t(), non_neg_integer(), map()) :: View.extent() | nil
  defp extent(rel = %Rel{clauses: clauses}, k, solve) do
    form = Enum.at(solve.handed, k)
    {j, o} = solve.counter || {nil, 0}

    sequence =
      data_list?(form) or match?(%View{}, form) or
        Enum.any?(clauses, fn {head, _body} -> Lang.Term.sequence?(Enum.at(head, k)) end)

    cond do
      not sequence -> nil
      solve.step == nil or solve.counter == nil -> Value.count(form) || :open
      k == j -> {1, o}
      true -> recurrence_extent(rel, k, solve)
    end
  end

  @spec recurrence_extent(Rel.t(), non_neg_integer(), map()) :: View.extent()
  defp recurrence_extent(rel = %Rel{name: self}, k, solve = %{step: {j, cj, q, hands}}) do
    handed = Enum.at(solve.handed, k)

    case Enum.find(Enum.with_index(Enum.at(hands, k)), fn {c, _p} -> c != nil end) do
      {c, _p} when q == self ->
        m = div(c, cj)
        {m, intercept(rel.clauses, solve, j, k) - m}

      {c, p} when q != self ->
        callee = solve.scope[q]
        fresh = List.duplicate(:fresh, callee.arity)

        with false <- q in solve.seen,
             {step, {_jc, oc} = counter} <- column_counter(callee.clauses, fresh),
             false <- tagged?(callee.clauses, p),
             inner = %{
               solve
               | step: step,
                 counter: counter,
                 handed: fresh,
                 seen: [self | solve.seen]
             },
             length when length not in [nil, :open] <- extent(callee, p, inner) do
          {_j, o} = solve.counter

          case length do
            {0, a} -> a - c
            {m, a} -> {m, m * (cj + o - oc) + a - c}
            n -> n - c
          end
        else
          _unstepped -> Value.count(handed) || :open
        end

      _apart ->
        Value.count(handed) || :open
    end
  end

  # The base clause's count for a parameter, or what a name one with it there was handed.
  @spec intercept([{[term()], [term()]}], map(), non_neg_integer(), non_neg_integer()) ::
          integer()
  defp intercept(clauses, %{handed: handed, step: {_j, _cj, _q, hands}}, j, k) do
    {base, _body} = Enum.min_by(clauses, fn {head, _body} -> count_in(head, j) || 1 end)

    mates =
      for {pattern, i} <- Enum.with_index(base),
          i == k or (match?({:var, _v}, pattern) and pattern == Enum.at(base, k)),
          do: i

    Enum.find_value(mates, 0, fn i ->
      case count_in(base, i) do
        nil -> if(0 in Enum.at(hands, i), do: Value.count(Enum.at(handed, i)))
        said -> said
      end
    end)
  end

  # Values are data and stand in a bank; forms are cells that already stand (rule 1).
  @spec data_list?(value()) :: boolean()
  defp data_list?([]), do: false

  defp data_list?(cells) when is_list(cells),
    do: Enum.all?(cells, &(is_integer(&1) or &1 == [] or data_list?(&1)))

  defp data_list?(_form), do: false

  @spec params(Rel.t()) :: [atom()]
  defp params(%Rel{clauses: clauses}) do
    {head, _body} = Enum.max_by(clauses, fn {_h, b} -> length(b) end)

    for {pattern, k} <- Enum.with_index(head) do
      with {:var, v} <- pattern, do: v, else: (_other -> :"a#{k + 1}")
    end
  end

  ############################################################
  #                     Clause Constraints                   #
  ############################################################

  # A clause retains its equations, bindings and sites together; impossible clauses stay dead.
  @spec compile_clauses(Rel.t(), Member.t(), [value()], Walk.t(), ctx()) ::
          [Walk.t() | :dead]
  defp compile_clauses(%Rel{clauses: clauses}, %Member{name: name}, binds, seeded, ctx) do
    {walks, _taken} =
      Enum.map_reduce(Enum.with_index(clauses), ctx.taken, fn {{head, body}, k}, taken ->
        with walk = %Walk{} <- unify_all(head, binds, seeded),
             walk = %Walk{} <- compile_goals(body, walk, %{ctx | site: [k], taken: taken}) do
          eqs = [Ast.eq({:cell, {:in, name}}, 1) | Enum.reverse(walk.eqs)]
          {%{walk | eqs: eqs}, Enum.into(Alloc.names(walk.members), taken)}
        else
          :dead -> {:dead, taken}
        end
      end)

    walks
  end

  # A goal naming a value nothing said yet waits for another pass; a dead conjunct ends the walk.
  @spec compile_goals([term()], Walk.t(), ctx()) :: Walk.t() | :dead
  defp compile_goals(goals, walk, ctx),
    do: walk_goals(Enum.with_index(goals), ctx, walk)

  defp walk_goals(goals, ctx, walk) do
    {walk, stalled} =
      Enum.reduce_while(goals, {walk, []}, fn {goal, k}, {walk, stalled} ->
        ctx = %{
          ctx
          | site: [k | ctx.site],
            taken: Enum.into(Alloc.names(walk.members), ctx.taken)
        }

        case compile_goal(goal, walk, ctx) do
          # A dead conjunct is the whole clause: it says only falsity.
          :dead ->
            {:halt, {:dead, []}}

          more = %Walk{} ->
            {:cont, {more, stalled}}

          :stalled ->
            {:cont, {walk, stalled ++ [{goal, k}]}}
        end
      end)

    cond do
      stalled == [] -> walk
      length(stalled) < length(goals) -> walk_goals(stalled, ctx, walk)
      true -> throw({:refused, {:unbound_variable, %{goals: for({g, _k} <- stalled, do: g)}}})
    end
  end

  @spec compile_goal(term(), Walk.t(), ctx()) :: Walk.t() | :dead | :stalled
  defp compile_goal({:eq, a, b}, walk, _ctx),
    do: sided(a, b, walk) || sided(b, a, walk) || :stalled

  defp compile_goal({:call, q, args}, walk = %Walk{env: env}, ctx) do
    {callee, args} =
      case q do
        {:var, _r} ->
          {:rel, p, fixed} = resolve(q, env)
          {ctx.scope[p], fixed ++ args}

        _name ->
          {ctx.scope[q] || throw({:refused, {:relation_not_in_scope, %{relation: q}}}), args}
      end

    cond do
      callee.phi -> phi_goal(callee, args, walk, ctx)
      # A relation of no clauses and no phi drives the derivation only; it says nothing here.
      callee.clauses == [] -> walk
      true -> compile_call(callee, args, walk, ctx)
    end
  end

  # A name or a sum takes the other side's value; a structure must be said itself.
  @spec sided(term(), term(), Walk.t()) :: Walk.t() | :dead | nil
  defp sided(pattern, other, walk = %Walk{env: env}) do
    case pattern do
      {:var, _v} -> unify(pattern, resolve(other, env), walk)
      {op, _a, _b} when op in [:add, :mul] -> unify(pattern, resolve(other, env), walk)
      _structure -> unify(resolve(pattern, env), resolve(other, env), walk)
    end
  catch
    {:refused, {:unbound_variable, _detail}} -> nil
  end

  ############################################################
  #                         Calling                          #
  ############################################################

  # Said in place where the values select a clause and the steps are finite, continued where
  # it names a relation being laid, laid as a member otherwise.
  @spec compile_call(Rel.t(), [term()], Walk.t(), ctx()) :: Walk.t() | :dead
  defp compile_call(callee, args, walk = %Walk{env: env}, ctx) do
    # A primitive's clauses consume scalar values, just as its specialized lowering does.
    values =
      for arg <- args do
        case handed(arg, env) do
          {:count, _q, form} when callee.phi != nil -> form
          value -> value
        end
      end

    {strategy, within} = enter_call(callee, values, ctx)

    candidates =
      for {{head, body}, k} <- Enum.with_index(callee.clauses),
          inner = %Walk{} <- [unify_all(head, values, %Walk{})] do
        if strategy == :residual,
          do: :residual,
          else: inline_clause(callee.name, {k, head, body, inner}, args, walk, within)
      end

    # Placement is demanded only after considering the completed expansions.
    place = fn ->
      member = reuse_member(callee, values, ctx) || place_new_member(callee, values, ctx)
      call_constraints(callee, args, member, walk, ctx)
    end

    case {strategy, Enum.reject(candidates, &(&1 == :dead))} do
      {_strategy, []} ->
        :dead

      {:prefer_call, [{:constrained, expanded}]} ->
        try do
          place.()
        catch
          {:refused, {:unliftable_term, _detail}} -> expanded
        end

      {_strategy, [{kind, expanded}]} when kind in [:substitution, :constrained] ->
        expanded

      _residual ->
        place.()
    end
  end

  # Keep the cost preference separate from whether recursion can be expanded at all.
  @spec enter_call(Rel.t(), [value()], ctx()) :: {:inline | :prefer_call | :residual, ctx()}
  defp enter_call(%Rel{name: name}, values, ctx) do
    key = specialization(name, values)
    sizes = Enum.map(values, &size/1)
    around = Map.get(ctx.inlining, key)
    shrunk = if around, do: Enum.zip(sizes, around)
    constructed = Enum.any?(values, &(is_list(&1) or is_struct(&1, Cons)))
    finite = constructed or Enum.all?(values, &finite?/1)

    decreases =
      shrunk == nil or
        (Enum.any?(shrunk, fn {a, b} -> a && b && a < b end) and
           not Enum.any?(shrunk, fn {a, b} -> a && b && a > b end))

    strategy =
      cond do
        name not in ctx.recursive ->
          :inline

        not finite or not decreases ->
          :residual

        not constructed and
            Enum.any?(
              values,
              &match?(
                %View{col: {_, _, _}, axes: [%{row: 0, extent: e} | _]}
                when is_integer(e),
                &1
              )
            ) ->
          :prefer_call

        true ->
          :inline
      end

    {strategy, %{ctx | inlining: Map.put(ctx.inlining, key, sizes)}}
  end

  # A higher-order call recurs on its specialization, not on an unrelated callback's walk.
  @spec specialization(atom(), [value()]) :: {atom(), [{non_neg_integer(), value()}]}
  defp specialization(name, values),
    do: {name, for({value = {:rel, _, _}, k} <- Enum.with_index(values), do: {k, value})}

  @spec finite?(value()) :: boolean()
  defp finite?(%Ref{}), do: false
  defp finite?(%View{} = view), do: View.finite?(view)
  defp finite?(%Cons{head: h, tail: t}), do: finite?(h) and finite?(t)
  defp finite?([h | t]), do: finite?(h) and finite?(t)
  defp finite?(:x), do: false
  defp finite?({tag, _a, _b}) when tag in [:add, :mul, :count], do: false
  defp finite?(_value), do: true

  # How many cells a value holds, an integer standing for that many.
  @spec size(value()) :: integer() | nil
  defp size(q) when is_integer(q), do: q
  defp size(view = %View{}), do: View.size(view)
  defp size([]), do: 0

  defp size(%Cons{head: h, tail: t}),
    do: with(a when a != nil <- size(h), b when b != nil <- size(t), do: a + b)

  defp size([h | t]), do: with(a when a != nil <- size(h), b when b != nil <- size(t), do: a + b)
  defp size(:fresh), do: nil
  defp size({:fresh, _ref}), do: nil
  defp size({:rel, _p, _f}), do: nil
  defp size(_cell), do: 1

  # Expansion is decided after the body, once impossible clauses and storage are known.
  @spec inline_clause(
          atom(),
          {non_neg_integer(), [term()], [term()], Walk.t()},
          [term()],
          Walk.t(),
          ctx()
        ) ::
          {:substitution | :constrained, Walk.t()} | :dead | :residual
  defp inline_clause(name, {k, head, body, inner}, args, caller, ctx) do
    if length(ctx.site) > 3000, do: throw({:refused, {:unroll_budget, %{relation: name}}})

    with walk = %Walk{members: [], slots: [], sites: [], banks: banks} when map_size(banks) == 0 <-
           compile_goals(body, inner, %{ctx | site: [k, name | ctx.site]}) do
      outputs = for pattern <- head, do: resolve(pattern, walk.env)
      free = walk.eqs == [] and not Enum.any?(outputs, &arithmetic?/1)

      case unify_all(args, outputs, Walk.constrain(caller, Enum.reverse(walk.eqs))) do
        walk = %Walk{} -> {if(free, do: :substitution, else: :constrained), walk}
        :dead -> :residual
      end
    else
      :dead -> :dead
      %Walk{} -> :residual
    end
  catch
    {:refused, {:unroll_budget, _detail} = refusal} -> throw({:refused, refusal})
    {:refused, _detail} -> :residual
  end

  @spec arithmetic?(value()) :: boolean()
  defp arithmetic?({op, _a, _b}) when op in [:add, :mul], do: true
  defp arithmetic?(%Cons{head: h, tail: t}), do: arithmetic?(h) or arithmetic?(t)
  defp arithmetic?([h | t]), do: arithmetic?(h) or arithmetic?(t)
  defp arithmetic?(_value), do: false

  # The chosen member's presence, argument equalities and source site belong to the caller.
  @spec call_constraints(Rel.t(), [term()], placement(), Walk.t(), ctx()) ::
          Walk.t() | :dead
  defp call_constraints(callee, args, {name, binds, frame, made}, caller, %{site: [k | _]} = ctx) do
    present = Ast.eq(Value.frame({:cell, {:in, name}}, frame), 1)

    with walk = %Walk{} <-
           unify_all(
             args,
             for(bind <- binds, do: Value.frame(bind, frame)),
             Walk.constrain(caller, [present])
           ) do
      pointers =
        for {:ptr, {_owner, {:own, {sym, _site}}} = ref} <- [frame],
            do: %Slot{name: sym, allocation: {:cell, ref}}

      site = %Site{
        callee: name,
        address: address(frame),
        occurrence: occurrence(callee.name, walk.env, ctx)
      }

      %{
        walk
        | members: walk.members ++ made.members,
          predicates: walk.predicates ++ made.predicates,
          eqs: Enum.reverse(made.eqs, walk.eqs),
          sites: walk.sites ++ [{k, site}],
          slots: walk.slots ++ pointers
      }
    end
  end

  @spec occurrence(atom(), map(), ctx()) :: non_neg_integer()
  defp occurrence(name, env, %{site: [k, clause | nesting], ancestors: ancestors, scope: scope}) do
    relation =
      case nesting do
        [relation | _rest] -> relation
        [] -> elem(hd(ancestors), 0).relation
      end

    {_head, body} = Enum.at(scope[relation].clauses, clause)

    Enum.count(Enum.take(body, k), fn
      {:call, {:var, _} = callback, _args} ->
        {:rel, called, _fixed} = resolve(callback, env)
        called == name

      {:call, called, _args} ->
        called == name

      _goal ->
        false
    end)
  end

  # Rule 3; a standing list or a call passing another relation is another walk.
  @spec reuse_member(Rel.t(), [value()], ctx()) :: placement() | nil
  defp reuse_member(callee, values, ctx) do
    with {%Member{name: ancestor, steps: steps}, binds} <-
           Enum.find(ctx.ancestors, fn {member, _binds} -> member.relation == callee.name end),
         true <-
           Enum.all?(Enum.zip(values, binds), fn
             {_value, %Ref{}} -> true
             {cells, _bind} when is_list(cells) -> false
             {%Cons{}, _bind} -> false
             {:fresh, %View{} = view} -> is_tuple(View.len(view))
             {%Ref{}, _bind} -> false
             {{:rel, _p, _fixed} = passed, bind} -> bind == passed
             _form -> true
           end) do
      frame = framed_at(frame_of(values, steps), ancestor, ctx)
      {ancestor, binds, frame, %Walk{}}
    else
      _another -> nil
    end
  end

  # A bank minted from a literal holds exactly its cells: presence bounded at the call.
  @spec place_new_member(Rel.t(), [value()], ctx()) :: placement()
  defp place_new_member(callee, values, ctx) do
    lifted = for form <- values, do: liftable(form)
    {_step, steps} = column_counter(callee.clauses, lifted)

    frame =
      case frame_of(values, steps) do
        # A callee no column counts stands where its caller stands.
        :ptr when steps == nil -> {1, 0}
        frame -> framed_at(frame, callee.name, ctx)
      end

    {name, binds, walk} =
      compile_member(callee, for(form <- lifted, do: Value.unframe(form, frame)), ctx)

    bounded =
      for {cells, bind} <- Enum.zip(lifted, binds),
          data_list?(cells),
          view = %View{} <- [Value.frame(bind, frame)],
          eq <- View.bounded(view, length(cells)),
          do: eq

    {name, binds, frame, %{walk | eqs: bounded}}
  end

  # A pointer frame names its row; the completed call site owns its allocation.
  @spec framed_at(frame() | :ptr, atom(), ctx()) :: frame()
  defp framed_at(:ptr, target, ctx) do
    {:ptr, {ctx.member, {:own, {:"which #{target}", ctx.site}}}}
  end

  defp framed_at(frame, _target, _ctx), do: frame

  @spec address(frame()) :: Ast.address()
  defp address({m, a}) when is_integer(m), do: Ast.address(:x, m, a)
  defp address({:ptr, ref}), do: Ast.address({:cell, ref}, 1, 0)

  # A cell of the caller's cannot stand a callee's rows: the callee holds its own and equates.
  @spec liftable(value()) :: value()
  defp liftable(%Ref{} = ref), do: ref
  defp liftable(%View{col: {base, _m, _a}} = view) when base != :x, do: Ref.of(view)
  defp liftable(%View{} = view), do: view
  defp liftable(%Cons{} = cons), do: Ref.of(cons)
  defp liftable(form) when is_list(form) or is_integer(form) or form == :fresh, do: form
  defp liftable({tag, _a, _b} = form) when tag in [:count, :rel], do: form
  defp liftable(form), do: if(match?(%View{row: nil}, View.of(form)), do: form, else: :fresh)

  # Where the callee's count stands in the caller's column, or a pointer where it cannot say.
  @spec frame_of([value()], tuple() | nil) :: frame() | :ptr
  defp frame_of(_values, nil), do: :ptr

  defp frame_of(values, {j, o}) do
    count =
      case Enum.at(values, j) do
        view = %View{} -> with(n when is_integer(n) <- View.len(view), do: {0, n})
        cells when is_list(cells) -> if data_list?(cells), do: {0, length(cells)}
        form -> with(%View{row: nil, col: {:x, m, a}} <- View.of(form), do: {m, a})
      end

    with {m, a} <- count, do: {m, a - o}, else: (_open -> :ptr)
  end

  # An indexed read whose index stands picks its cell outright (rule 1).
  @spec phi_goal(Rel.t(), [term()], Walk.t(), ctx()) :: Walk.t() | :dead
  defp phi_goal(callee, args, walk, ctx) do
    {module, op} = callee.phi

    case pick(callee.phi, args, walk.env) do
      {v, selected} ->
        unify(v, selected, walk)

      nil ->
        {resolved, walk} =
          Enum.map_reduce(args, walk, fn arg, walk ->
            case {arg, handed(arg, walk.env)} do
              {{:var, v}, :fresh} ->
                ref = {ctx.member, {:own, {v, ctx.site}}}
                slot = %Slot{name: v, allocation: {:cell, ref}}

                {Ast.cell(ref),
                 %{walk | env: Map.put(walk.env, v, Ast.cell(ref)), slots: walk.slots ++ [slot]}}

              _held ->
                {Value.elements(resolve(arg, walk.env)), walk}
            end
          end)

        Walk.constrain(walk, Ast.folded(apply(module, op, resolved)))
    end
  catch
    {:refused, {:unliftable_term, %{term: %Ref{}}}}
    when callee.al == nil and callee.clauses != [] ->
      compile_call(callee, args, walk, ctx)

    {:refused, {reason, detail}} ->
      throw({:refused, {reason, Map.put(detail, :relation, callee.name)}})
  end

  @spec pick({module(), atom()}, [term()], map()) :: {term(), value()} | nil
  defp pick({Ast, :nth}, [i, xs, v], env) do
    with q when is_integer(q) <- handed(i, env),
         cells when is_list(cells) <- Value.elements(handed(xs, env)),
         true <- q >= 1 and q <= length(cells),
         do: {v, Enum.at(cells, q - 1)},
         else: (_unpicked -> nil)
  end

  defp pick(_phi, _args, _env), do: nil

  ############################################################
  #                        Unifying                          #
  ############################################################

  @spec unify_all([term()], [value()], Walk.t()) :: Walk.t() | :dead
  defp unify_all([], [], walk), do: walk

  defp unify_all([pattern | patterns], [value | values], walk) do
    with walk = %Walk{} <- unify(pattern, value, walk), do: unify_all(patterns, values, walk)
  end

  @spec unify(term(), value(), Walk.t()) :: Walk.t() | :dead
  defp unify(value, value, walk), do: walk
  defp unify(_pattern, :fresh, walk), do: walk
  defp unify(:fresh, _value, walk), do: walk

  defp unify({:var, v}, value, walk = %Walk{env: env}) do
    case env do
      %{^v => held} -> unify(held, value, walk)
      _fresh -> %{walk | env: Map.put(env, v, value)}
    end
  end

  # A fresh name takes its standing from what meets it (rule 1).
  defp unify({:fresh, ref} = fresh, value, walk = %Walk{env: env}) do
    case Map.get(env, ref) do
      nil -> met(fresh, value, walk)
      held -> unify(held, value, walk)
    end
  end

  defp unify({:cons, _h, _t} = bracket, {:fresh, ref}, walk = %Walk{env: env})
       when not is_map_key(env, ref) do
    bank = Bank.of(ref)
    len = if tail_of(bracket) == nil, do: length(spine(bracket)), else: {1, 0}
    view = View.bank([{bank, 1}], len)
    walk = %{walk | env: Map.put(env, ref, view), banks: Map.put_new(walk.banks, bank, 1)}
    unify(bracket, view, walk)
  end

  defp unify(pattern, {:fresh, _ref} = fresh, walk), do: unify(fresh, pattern, walk)

  defp unify(%Ref{id: a}, %Ref{id: b}, walk), do: Walk.constrain(walk, [Ast.eq(a, b)])
  defp unify(%Ref{} = ref, other, walk), do: unify(other, ref, walk)
  defp unify([], %Ref{id: id}, walk), do: Walk.constrain(walk, [Ast.eq(id, 1)])

  defp unify(%View{} = view, %Ref{id: id}, walk),
    do: Walk.constrain(walk, [Ast.eq(Ref.of(view).id, id)])

  defp unify(q, %Ref{} = ref, walk) when is_integer(q),
    do: Walk.constrain(walk, [Ast.eq(Ref.read(:value, ref), q)])

  defp unify(q, {:count, _held, form}, walk) when is_integer(q),
    do: Walk.constrain(walk, [Ast.eq(form, q)])

  defp unify(q, form, walk)
       when is_integer(q) and (form == :x or elem(form, 0) in [:cell, :add, :mul]),
       do: Walk.constrain(walk, pinned(form, q))

  defp unify(q, _value, _walk) when is_integer(q), do: :dead

  defp unify(nil, value, walk), do: unify([], value, walk)

  defp unify([], %View{col: {_b, _m, _a}} = view, walk),
    do: with({:ok, eqs} <- View.ended(view), do: Walk.constrain(walk, eqs))

  defp unify([], value, walk = %Walk{banks: banks}) do
    case Ast.read(value) do
      {{bank, r}, _at} when is_map_key(banks, bank) -> deepened(walk, bank, r - 1)
      _other -> :dead
    end
  end

  # A bracket meeting a cell of a bank being minted reads it as a column: the rows grow under it.
  defp unify({:cons, h, t}, value, walk = %Walk{banks: banks}) do
    case Ast.read(value) do
      {{bank, r}, {:at, base, m, a}} when is_map_key(banks, bank) ->
        with walk = %Walk{} <- unify(h, value, deepened(walk, bank, r)),
             do: unify(t, Ast.at({bank, r + 1}, base, m, a), walk)

      _cells ->
        unify(%Cons{head: h, tail: t}, value, walk)
    end
  end

  defp unify([h | t], value, walk), do: unify(%Cons{head: h, tail: t}, value, walk)

  defp unify(%Cons{head: h, tail: t}, value, walk) do
    with {:ok, vh, vt, pins} <- Cons.peel(value),
         walk = %Walk{} <- unify(h, vh, Walk.constrain(walk, pins)),
         do: unify(t, vt, walk)
  end

  defp unify({op, _a, _b} = pattern, value, walk = %Walk{env: env}) when op in [:add, :mul] do
    case solvable(pattern, env) do
      {:ok, ^pattern} -> equated(pattern, value, walk)
      {:ok, held} -> unify(held, value, walk)
      {:free, v, rebuilt} -> %{walk | env: Map.put(env, v, rebuilt.(Value.scalar(value)))}
      :stuck -> throw({:refused, {:unbound_variable, %{equation: pattern}}})
    end
  end

  defp unify({:papply, p, fixed}, value, walk),
    do: unify({:rel, p, for(f <- fixed, do: resolve(f, walk.env))}, value, walk)

  defp unify(a = %View{}, b = %View{}, walk) do
    cond do
      a.col == nil or b.col == nil -> throw({:refused, {:unliftable_term, %{term: b}}})
      View.count(b) -> unify(a, for(i <- 0..(View.count(b) - 1)//1, do: View.slice(b, i)), walk)
      View.count(a) -> unify(b, for(i <- 0..(View.count(a) - 1)//1, do: View.slice(a, i)), walk)
      true -> throw({:refused, {:unliftable_term, %{term: b}}})
    end
  end

  defp unify(%View{} = a, value, walk) when is_list(value), do: unify(value, a, walk)
  defp unify(%View{} = a, value = %Cons{}, walk), do: unify(value, a, walk)
  defp unify(%View{}, _value, _walk), do: :dead
  defp unify({:rel, _p, _f}, _value, _walk), do: :dead
  defp unify(a, b, walk), do: equated(a, b, walk)

  @spec deepened(Walk.t(), atom(), integer()) :: Walk.t()
  defp deepened(walk, bank, rows),
    do: %{walk | banks: Map.update!(walk.banks, bank, &max(&1, rows))}

  @spec equated(value(), value(), Walk.t()) :: Walk.t() | :dead
  defp equated(a, b, walk) do
    cond do
      is_integer(b) -> unify(b, a, walk)
      is_list(b) or is_struct(b, Cons) or is_struct(b, View) or match?({:rel, _p, _f}, b) -> :dead
      true -> Walk.constrain(walk, [Ast.eq(Value.scalar(a), Value.scalar(b))])
    end
  end

  @spec met(value(), value(), Walk.t()) :: Walk.t() | :dead
  defp met({:fresh, ref}, nil, walk), do: %{walk | env: Map.put(walk.env, ref, [])}

  defp met(fresh, {:fresh, other}, walk = %Walk{env: env}) when is_map_key(env, other),
    do: unify(fresh, env[other], walk)

  defp met(fresh, {:fresh, other}, walk), do: %{walk | env: Map.put(walk.env, other, fresh)}

  defp met({:fresh, ref}, q, walk) when is_integer(q),
    do:
      Walk.constrain(
        %{walk | env: Map.put(walk.env, ref, {:count, q, Ast.cell(ref)})},
        pinned(Ast.cell(ref), q)
      )

  defp met({:fresh, ref}, %Ref{} = value, walk) do
    node = %Ref{id: Ast.cell(ref)}
    unify(node, value, %{walk | env: Map.put(walk.env, ref, node)})
  end

  defp met({:fresh, ref}, value, walk)
       when is_list(value) or is_struct(value, View) or is_struct(value, Cons) or
              elem(value, 0) == :rel,
       do: %{walk | env: Map.put(walk.env, ref, value)}

  defp met({:fresh, ref}, value, walk) do
    cell = Ast.cell(ref)
    unify(cell, value, %{walk | env: Map.put(walk.env, ref, cell)})
  end

  # An integer against the column pins the column; against a cell, the cell.
  @spec pinned(Ast.term_t(), integer()) :: [Ast.pred()]
  defp pinned(form, q) do
    case View.of(form) do
      %View{row: nil, col: {:x, 1, o}} -> [Ast.eq(:x, q - o)]
      _cell -> Ast.folded(Ast.eq(Value.scalar(form), q))
    end
  end

  ############################################################
  #                        Resolving                         #
  ############################################################

  # What a call hands over: the value a term stands for, a name no goal
  # has bound yet yielding `:fresh`, since a later goal resolves it.
  @spec handed(term(), map()) :: value()
  defp handed({:var, v}, env), do: deref(Map.get(env, v, :fresh), env)

  defp handed(arg, env) do
    resolve(arg, env)
  catch
    {:refused, {:unbound_variable, _detail}} -> :fresh
  end

  @spec deref(value(), map()) :: value()
  defp deref({:fresh, ref} = fresh, env),
    do:
      with(held when held != nil <- Map.get(env, ref), do: deref(held, env), else: (nil -> fresh))

  defp deref(value, _env), do: value

  @spec resolve(term(), map()) :: value()
  defp resolve(q, _env) when is_integer(q), do: q
  defp resolve(nil, _env), do: []

  defp resolve({:var, v}, env) do
    case Map.get(env, v, :fresh) do
      :fresh -> throw({:refused, {:unbound_variable, %{variable: v}}})
      {:fresh, _ref} = fresh -> resolve(fresh, env)
      form -> form
    end
  end

  defp resolve({:fresh, _ref} = fresh, env) do
    case deref(fresh, env) do
      {:fresh, unread} -> {:cell, unread}
      held -> held
    end
  end

  defp resolve({:papply, p, fixed}, env), do: {:rel, p, for(f <- fixed, do: resolve(f, env))}

  defp resolve({:add, a, b}, env),
    do: Ast.add(Value.scalar(resolve(a, env)), Value.scalar(resolve(b, env)))

  defp resolve({:mul, a, b}, env),
    do: Ast.mul(Value.scalar(resolve(a, env)), Value.scalar(resolve(b, env)))

  defp resolve({:cons, h, t}, env) do
    Cons.new(resolve(h, env), resolve(t, env))
  end

  defp resolve(value, _env), do: value

  # A side as it resolves, or the one free name it is linear in.
  @spec solvable(term(), map()) :: {:ok, value()} | {:free, atom(), (term() -> term())} | :stuck
  defp solvable({:var, v}, env) when not is_map_key(env, v), do: {:free, v, & &1}

  defp solvable({:add, a, b}, env) do
    left = with {:ok, value} <- solvable(a, env), do: {:ok, Value.scalar(value)}

    case {left, solvable(b, env)} do
      {{:ok, ra}, {:ok, rb}} ->
        {:ok, Ast.add(ra, Value.scalar(rb))}

      {{:ok, ra}, {:free, v, rebuilt}} ->
        {:free, v, fn r -> rebuilt.(Ast.add(r, Ast.mul(ra, -1))) end}

      {{:free, v, rebuilt}, {:ok, rb}} ->
        {:free, v, fn r -> rebuilt.(Ast.add(r, Ast.mul(Value.scalar(rb), -1))) end}

      _stuck ->
        :stuck
    end
  end

  defp solvable(term, env) do
    {:ok, resolve(term, env)}
  catch
    {:refused, {:unbound_variable, _detail}} -> :stuck
  end

  ############################################################
  #                        Brackets                          #
  ############################################################

  @spec spine(term()) :: [term()]
  defp spine({:cons, h, t}), do: [h | spine(t)]
  defp spine(_end), do: []

  @spec tail_of(term()) :: term() | nil
  defp tail_of({:cons, _h, t}), do: tail_of(t)
  defp tail_of({:var, _v} = tail), do: tail
  defp tail_of(_closed), do: nil
end
