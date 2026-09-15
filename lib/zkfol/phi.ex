defmodule Zkfol.Phi do
  @moduledoc """
  I lower a statement's relations to a predicate over cells and the allocation those cells
  stand on, and lay the run's derivation on it. Four rules make every equation:

  1. A symbol is a cell: handed one it references it, handed none it allocates a row, a
     repeat equates.
  2. A call is one fact, the callee present at an address; one whose clause the values
     select and whose steps are finite is said in place instead.
  3. Recursion is address arithmetic: a call to a relation being laid continues it.
  4. Data fills cells; sizes, structure and ground literals shape the predicate.

  A member is compiled in three steps: its parameters are declared as accesses or storage
  from what the call handed and what its clauses say, each clause is matched and its goals
  interpreted on that walk, and the scalars the clauses read but nothing bound are given
  cells.

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
  alias Zkfol.Phi.Value
  alias Zkfol.Phi.Expression
  alias Zkfol.Phi.Layout
  alias Zkfol.Phi.Place
  alias Zkfol.Phi.Shape
  alias Zkfol.Phi.Schedule
  alias Zkfol.Phi.Walk
  alias Zkfol.Phi.Walk.Clause
  alias Zkfol.Refusal
  alias Zkfol.Statement

  @typep value :: Value.t()
  @typep frame :: Value.frame()
  @typep placement :: {atom(), [value()], frame(), Walk.t()}

  # `inlining` holds the argument sizes of every call being expanded on this path, so a
  # recursive call can be seen to shrink or not.
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

    with {:ok, pred, alloc, walk} <- lowered(root, rels, args) do
      stage = %Statement.Solved{
        pred: Alloc.link(pred, alloc),
        lay: Lay.of(derivation, alloc),
        lowering: walk
      }

      {:ok, %{statement | stage: stage}}
    end
  end

  @doc "I am the predicate of `root` against `rels`, linked."
  @spec lower(Rel.t(), [Rel.t()]) :: {:ok, Ast.pred()} | {:error, Refusal.t()}
  def lower(root = %Rel{}, rels) do
    case compile(root, rels) do
      {:ok, pred, alloc} -> {:ok, Alloc.link(pred, alloc)}
      x -> x
    end
  end

  @doc "I compile `root` against `rels` to its predicate and allocation; `args` size its banks."
  @spec compile(Rel.t(), [Rel.t()] | nil, [term()]) ::
          {:ok, Ast.pred(), Alloc.t()} | {:error, Refusal.t()}
  def compile(root = %Rel{}, rels \\ nil, args \\ []) do
    with {:ok, pred, alloc, _walk} <- lowered(root, rels, args), do: {:ok, pred, alloc}
  end

  # Each pattern against its value, in order; `:dead` is a clause that cannot match.
  @spec match([term()], [Value.t()], Walk.t()) :: Walk.t() | :dead
  defp match([], [], walk), do: walk

  defp match([pattern | patterns], [value | values], walk) do
    with walk = %Walk{} <- unify(pattern, value, walk), do: match(patterns, values, walk)
  end

  @spec lowered(Rel.t(), [Rel.t()] | nil, [term()]) ::
          {:ok, Ast.pred(), Alloc.t(), Walk.t()} | {:error, Refusal.t()}
  defp lowered(root, rels, args) do
    with {:ok, [root | _rest] = reached} <- Lang.reached(root, rels || [root]) do
      compiled(root, Map.new(reached, &{&1.name, &1}), args)
    end
  end

  @spec compiled(Rel.t(), %{atom() => Rel.t()}, [term()]) ::
          {:ok, Ast.pred(), Alloc.t(), Walk.t()} | {:error, Refusal.t()}
  defp compiled(root = %Rel{}, scope, args) do
    # A handed integer is data (rule 4): its count may place a bank, its value is never
    # written into the predicate.
    handed =
      for k <- 0..(root.arity - 1)//1 do
        case Enum.at(args, k) do
          cells when is_list(cells) -> cells
          q when is_integer(q) -> {:count, q, nil}
          _open -> :fresh
        end
      end

    # A relation that reaches itself is recursive: a call to it is unrolled only while its
    # arguments shrink, and laid as a member otherwise.
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

    {name, _binds, walk} = compile_member(root, handed, %{}, ctx)

    pred =
      Ast.conj(
        walk.predicates ++
          for(bank = %Bank{} <- walk.members, do: runs(bank))
      )

    {pred, members} = Zkfol.Nodes.lower(Value.shaped(pred, walk.shapes), walk.members)
    {:ok, pred, Alloc.numbered(members, name), walk}
  catch
    {:refused, refusal} -> {:error, refusal}
  end

  # A bank's presence is one on a single run starting at column two, so a forger cannot
  # shorten a walk by dropping presence in the middle.
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

  # Local rows are numbered after the parameters', by name, so goal order moves nothing.
  @spec compile_member(Rel.t(), [value()], Place.known(), ctx()) ::
          {atom(), [value()], Walk.t()}
  defp compile_member(%Rel{} = rel, handed, known, ctx) do
    name = minted(rel.name, ctx.taken)
    syms = Layout.params(rel)
    refs = for sym <- syms, do: {name, {:param, sym}}
    {steps, initial} = parameters(rel, handed, known, ctx.scope, refs)
    binds = Enum.map(refs, &Map.get(initial.env, &1, {:fresh, &1}))

    member = %Member{name: name, relation: rel.name, steps: steps, slots: [], sites: %{}}

    ctx = %{
      ctx
      | ancestors: [{member, binds} | ctx.ancestors],
        taken: Enum.into([name | Walk.banks(initial)], ctx.taken),
        member: name
    }

    clauses = compile_clauses(rel, member, binds, initial, ctx)

    live = for %Clause{compiled: walk = %Walk{}} <- clauses, do: walk
    present = Ast.eq({:cell, {:in, name}}, 1)
    branches = for clause <- live, do: Ast.conj([present | Enum.sort_by(clause.eqs, &inspect/1)])
    {binds, slots, banks, shapes} = allocate_parameters(refs, initial, live)

    sites =
      Map.new(Enum.with_index(clauses), fn
        {%Clause{compiled: %Walk{sites: sites}}, k} ->
          {k, for({_i, site} <- Enum.sort(sites), do: site)}

        {%Clause{compiled: :dead}, k} ->
          {k, []}
      end)

    local = live |> Enum.flat_map(& &1.slots) |> Enum.sort_by(&elem(&1.allocation, 1))
    member = %{member | sites: sites, slots: slots ++ local}
    predicate = Ast.disj([Ast.eq({:cell, {:in, name}}, 0) | branches])

    walk = %Walk{
      members: [member | banks] ++ Enum.flat_map(live, & &1.members),
      predicates: [predicate | Enum.flat_map(live, & &1.predicates)],
      clauses: clauses,
      shapes: shapes
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

  # Each parameter is declared as what it stands on, before any clause is matched. The
  # layout decides from the relation's clauses and the handed places; the walk receives
  # the decision as the values it reads today.
  @spec parameters(Rel.t(), [value()], Place.known(), %{atom() => Rel.t()}, [Ast.row_ref()]) ::
          {{non_neg_integer(), integer()} | nil, Walk.t()}
  defp parameters(rel, handed, known, scope, refs) do
    {{step, counter}, shapes} = Layout.shapes(rel, handed, known, scope)
    places = Layout.places(rel, refs, handed, shapes, {step, counter})

    declarations =
      for {{ref, form, place, shape}, k} <-
            Enum.with_index(Enum.zip([refs, handed, places, shapes])) do
        declared(rel, ref, form, place, shape, {step, counter}, k)
      end

    {counter, Enum.reduce(declarations, Walk.refine(%Walk{}, known), &Walk.merge/2)}
  end

  # The layout's decision as a declaration over the value it was made for.
  @spec declared(Rel.t(), Ast.row_ref(), value(), Place.t(), Shape.t(), Layout.steps(), integer()) ::
          Walk.t()
  defp declared(_rel, ref, form, place, shape, {step, counter}, k) do
    {j, o} = counter || {nil, 0}

    case {place, form} do
      {{:node, _id}, _form} ->
        Walk.bind(%Walk{}, ref, {:node, Ast.cell(ref)}, {:node, ref})

      {_column, _form} when k == j and shape == :scalar ->
        Walk.bind(%Walk{}, ref, Ast.add(:x, o))

      {{:along, _, _}, {:along, _, _}} when step != nil and counter != nil ->
        Walk.bind(%Walk{}, ref, Place.stepped(form, shape))

      {{:along, _, _}, {:along, _, _}} ->
        Walk.bind(%Walk{}, ref, form)

      {along = {:along, _, _}, _handed} ->
        Walk.bank(%Walk{}, ref, along, shape)

      {_read_as_it_is, _form} ->
        Walk.bind(%Walk{}, ref, form)
    end
  end

  # A parameter the clauses bound keeps the storage they chose; one they only read gets a
  # cell; one nothing read needs no storage at all.
  @spec allocate_parameters([Ast.row_ref()], Walk.t(), [Walk.t()]) ::
          {[value()], [Slot.t()], [Bank.t()], %{Ast.row_ref() => Shape.t()}}
  defp allocate_parameters(refs, initial, clauses) do
    # The earliest declaration of a parameter wins.
    declared = List.foldr([initial | clauses], %Walk{}, &Walk.merge/2)
    shapes = declared.shapes

    constraints =
      for %Walk{eqs: [_ | _] = eqs} <- clauses, do: Value.shaped(Ast.conj(eqs), shapes)

    read = MapSet.new(Enum.flat_map(constraints, &Zkfol.Nodes.reads(&1, shapes)))

    parameters =
      for ref = {_name, {:param, sym}} <- refs do
        allocation =
          Map.get(declared.parameters, ref, if(ref in read, do: {:cell, ref}, else: :none))

        access = Map.get(declared.env, ref, {:fresh, ref})
        {Value.shaped(access, shapes), %Slot{name: sym, allocation: allocation}}
      end

    banks =
      for {_access, %Slot{allocation: {:bank, bank, _address}}} <- parameters,
          do: %Bank{
            name: bank,
            element: Map.get(shapes, {bank, 1}, :unknown),
            depth:
              case shapes[{bank, 1}] do
                {:list, {:at_least, width}, :scalar} -> max(1, width)
                {:list, {0, width}, :scalar} -> max(1, width)
                _shape -> 1
              end
          }

    {binds, slots} = Enum.unzip(parameters)
    {binds, slots, banks, shapes}
  end

  ############################################################
  #                         Literals                         #
  ############################################################

  # A list of integers is data and takes a bank; a list of cells already stands (rule 1).
  @spec data_list?(value()) :: boolean()
  defp data_list?([]), do: false

  defp data_list?(cells) when is_list(cells),
    do: Enum.all?(cells, &(is_integer(&1) or &1 == [] or data_list?(&1)))

  defp data_list?(_form), do: false

  ############################################################
  #                     Clause Constraints                   #
  ############################################################

  # Every clause is compiled, the impossible ones kept as `:dead`, so the views can show
  # why a clause failed.
  @spec compile_clauses(Rel.t(), Member.t(), [value()], Walk.t(), ctx()) ::
          [Clause.t()]
  defp compile_clauses(%Rel{clauses: clauses}, %Member{name: name}, binds, seeded, ctx) do
    {walks, _taken} =
      Enum.map_reduce(Enum.with_index(clauses), ctx.taken, fn {{head, body}, k}, taken ->
        matched = match(head, binds, seeded)

        {compiled, taken} =
          with walk = %Walk{} <- matched,
               walk = %Walk{} <- compile_goals(body, walk, %{ctx | site: [k], taken: taken}) do
            {walk, Enum.into(Alloc.names(walk.members), taken)}
          else
            :dead -> {:dead, taken}
          end

        {%Clause{
           member: name,
           head: head,
           body: body,
           accesses: binds,
           before: seeded,
           matched: matched,
           compiled: compiled
         }, taken}
      end)

    walks
  end

  # A goal that needs a binding not yet made waits; the schedule retries it when the
  # binding appears.
  @spec compile_goals([term()], Walk.t(), ctx()) :: Walk.t() | :dead
  defp compile_goals(goals, walk, ctx) do
    Schedule.run(Schedule.new(goals), walk, fn goal, k, walk ->
      goal_context = %{
        ctx
        | site: [k | ctx.site],
          taken: Enum.into(Alloc.names(walk.members), ctx.taken)
      }

      compile_goal(goal, walk, goal_context)
    end)
  end

  @spec compile_goal(term(), Walk.t(), ctx()) :: Walk.t() | :dead | Expression.waiting()
  defp compile_goal({:eq, a, b}, walk, _ctx), do: equate(a, b, walk)

  defp compile_goal({:call, q, args}, walk, ctx) do
    {callee, args} =
      case q do
        {:var, _r} ->
          {:rel, p, fixed} = Expression.resolve!(q, walk)
          {ctx.scope[p], fixed ++ args}

        _name ->
          {ctx.scope[q] || throw({:refused, {:relation_not_in_scope, %{relation: q}}}), args}
      end

    cond do
      callee.phi -> phi_goal(callee, args, walk, ctx)
      # A relation of no clauses and no phi steers the derivation only; here it is nothing.
      callee.clauses == [] -> walk
      true -> compile_call(callee, args, walk, ctx)
    end
  end

  # Either side may bind the other; when neither can yet, the names both need are reported.
  @spec equate(term(), term(), Walk.t()) :: Walk.t() | :dead | Expression.waiting()
  defp equate(a, b, walk) do
    with {:waiting, left} <- equation_side(a, b, walk),
         {:waiting, right} <- equation_side(b, a, walk),
         do: {:waiting, Enum.uniq(left ++ right)}
  end

  # A name or a sum can be bound from the other side; a structure is matched value to value.
  defp equation_side(pattern, other, walk) do
    case pattern do
      {:var, _name} ->
        with {:ok, value} <- Expression.resolve(other, walk), do: unify(pattern, value, walk)

      {op, _a, _b} when op in [:add, :mul] ->
        with {:ok, value} <- Expression.resolve(other, walk),
             do: bind_expression(pattern, value, walk)

      _structure ->
        with {:ok, pattern} <- Expression.resolve(pattern, walk),
             {:ok, value} <- Expression.resolve(other, walk),
             do: unify(pattern, value, walk)
    end
  end

  ############################################################
  #                         Calling                          #
  ############################################################

  # A call is said in place when exactly one clause matches and its body compiles without
  # storage; otherwise it is a member, a continuation of one being laid or a new one.
  @spec compile_call(Rel.t(), [term()], Walk.t(), ctx()) :: Walk.t() | :dead
  defp compile_call(callee, args, walk, ctx) do
    # A primitive's clauses read a handed count as the cell it stands in.
    values =
      for arg <- args do
        case Expression.argument(arg, walk) do
          {:count, _q, form} when callee.phi != nil -> form
          value -> value
        end
      end

    {strategy, within} = enter_call(callee, values, walk.shapes, ctx)

    expansions =
      for {{head, body}, k} <- Enum.with_index(callee.clauses),
          inner = %Walk{} <- [match(head, values, %Walk{shapes: walk.shapes})] do
        if strategy == :residual,
          do: :residual,
          else: inline_clause(callee.name, {k, head, body, inner}, args, walk, within)
      end

    case {strategy, Enum.reject(expansions, &(&1 == :dead))} do
      {_strategy, []} ->
        :dead

      # A walk over a counted list is cheaper as a member; expanded only when it cannot be.
      {:prefer_call, [{:constrained, expanded}]} ->
        try do
          called(callee, args, values, walk, ctx)
        catch
          {:refused, {:unliftable_term, _detail}} -> expanded
        end

      {_strategy, [{kind, expanded}]} when kind in [:substitution, :constrained] ->
        expanded

      _residual ->
        called(callee, args, values, walk, ctx)
    end
  end

  # The call as a member: the one being laid when the values continue it, a new one else.
  @spec called(Rel.t(), [term()], [value()], Walk.t(), ctx()) :: Walk.t() | :dead
  defp called(callee, args, values, walk, ctx) do
    member =
      reuse_member(callee, values, ctx) || place_new_member(callee, values, walk.shapes, ctx)

    call_constraints(callee, args, member, walk, ctx)
  end

  # Whether a call may be expanded, and whether it should be: a recursive call expands only
  # while its arguments are finite and shrinking; one walking a counted list prefers a member.
  @spec enter_call(Rel.t(), [value()], Place.known(), ctx()) ::
          {:inline | :prefer_call | :residual, ctx()}
  defp enter_call(%Rel{name: name}, values, known, ctx) do
    key = specialization(name, values)
    sizes = Enum.map(values, &size(&1, known))
    around = Map.get(ctx.inlining, key)
    shrunk = if around, do: Enum.zip(sizes, around)
    constructed = Enum.any?(values, &(is_list(&1) or match?({:pair, _, _}, &1)))
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

        not constructed and Enum.any?(values, &(Place.count(&1) != nil)) ->
          :prefer_call

        true ->
          :inline
      end

    {strategy, %{ctx | inlining: Map.put(ctx.inlining, key, sizes)}}
  end

  # Two calls with different passed relations are different calls for the shrinking check.
  @spec specialization(atom(), [value()]) :: {atom(), [{non_neg_integer(), value()}]}
  defp specialization(name, values),
    do: {name, for({value = {:rel, _, _}, k} <- Enum.with_index(values), do: {k, value})}

  @spec finite?(value()) :: boolean()
  defp finite?({:node, _id}), do: false
  defp finite?({:across, _, _, _}), do: false
  defp finite?(along = {:along, _, _}), do: Place.count(along) != nil
  defp finite?({:pair, h, t}), do: finite?(h) and finite?(t)
  defp finite?([h | t]), do: finite?(h) and finite?(t)
  defp finite?(:x), do: false
  defp finite?({tag, _a, _b}) when tag in [:add, :mul, :count], do: false
  defp finite?(_value), do: true

  # The cells a value holds; a handed integer counts as that many.
  @spec size(value(), Place.known()) :: integer() | nil
  defp size(q, _known) when is_integer(q), do: q
  defp size(along = {:along, _, _}, known), do: Place.size(along, known)
  defp size([], _known), do: 0

  defp size({:pair, h, t}, known),
    do: with(a when a != nil <- size(h, known), b when b != nil <- size(t, known), do: a + b)

  defp size([h | t], known),
    do: with(a when a != nil <- size(h, known), b when b != nil <- size(t, known), do: a + b)

  defp size({:across, _, _, _}, _known), do: nil
  defp size(:fresh, _known), do: nil
  defp size({:fresh, _ref}, _known), do: nil
  defp size({:rel, _p, _f}, _known), do: nil
  defp size(_cell, _known), do: 1

  # The clause body is compiled in a walk of its own; the expansion is a substitution when
  # it made no equations, constrained when it did, and residual when it needed storage.
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

    with walk = %Walk{members: [], slots: [], sites: []} <-
           compile_goals(body, inner, %{ctx | site: [k, name | ctx.site]}),
         [] <- Walk.banks(walk) do
      outputs = for pattern <- head, do: Expression.resolve!(pattern, walk)
      free = walk.eqs == [] and not Enum.any?(outputs, &arithmetic?/1)

      case match(
             args,
             outputs,
             Walk.constrain(Walk.refine(caller, walk.shapes), Enum.reverse(walk.eqs))
           ) do
        walk = %Walk{} -> {if(free, do: :substitution, else: :constrained), walk}
        :dead -> :residual
      end
    else
      :dead -> :dead
      _allocated -> :residual
    end
  catch
    {:refused, {:unroll_budget, _detail} = refusal} -> throw({:refused, refusal})
    {:refused, _detail} -> :residual
  end

  @spec arithmetic?(value()) :: boolean()
  defp arithmetic?({op, _a, _b}) when op in [:add, :mul], do: true
  defp arithmetic?({:pair, h, t}), do: arithmetic?(h) or arithmetic?(t)
  defp arithmetic?([h | t]), do: arithmetic?(h) or arithmetic?(t)
  defp arithmetic?(_value), do: false

  # The caller gains the member's presence, an equation per argument, and the call site.
  @spec call_constraints(Rel.t(), [term()], placement(), Walk.t(), ctx()) ::
          Walk.t() | :dead
  defp call_constraints(callee, args, {name, binds, frame, made}, caller, %{site: [k | _]} = ctx) do
    caller = Walk.refine(caller, made.shapes)
    present = Ast.eq(Value.frame({:cell, {:in, name}}, frame), 1)

    with walk = %Walk{} <-
           match(
             args,
             for(bind <- binds, do: Value.frame(bind, frame)),
             Walk.constrain(caller, [present])
           ) do
      pointers =
        for {:at, {:cell, ref = {_owner, {:own, {sym, _site}}}}, 1, 0} <- [frame],
            do: %Slot{name: sym, allocation: {:cell, ref}}

      site = %Site{
        callee: name,
        address: frame,
        occurrence: occurrence(callee.name, walk, ctx)
      }

      %{
        walk
        | members: walk.members ++ made.members,
          predicates: walk.predicates ++ made.predicates,
          eqs: Enum.reverse(made.eqs, walk.eqs),
          sites: walk.sites ++ [{k, site}],
          slots: walk.slots ++ pointers,
          clauses: walk.clauses ++ made.clauses
      }
    end
  end

  @spec occurrence(atom(), Walk.t(), ctx()) :: non_neg_integer()
  defp occurrence(name, walk, %{site: [k, clause | nesting], ancestors: ancestors, scope: scope}) do
    relation =
      case nesting do
        [relation | _rest] -> relation
        [] -> elem(hd(ancestors), 0).relation
      end

    {_head, body} = Enum.at(scope[relation].clauses, clause)

    Enum.count(Enum.take(body, k), fn
      {:call, {:var, _} = callback, _args} ->
        {:rel, called, _fixed} = Expression.resolve!(callback, walk)
        called == name

      {:call, called, _args} ->
        called == name

      _goal ->
        false
    end)
  end

  # Rule 3. A literal list or a different passed relation cannot continue a member.
  @spec reuse_member(Rel.t(), [value()], ctx()) :: placement() | nil
  defp reuse_member(callee, values, ctx) do
    with {%Member{name: ancestor, steps: steps}, binds} <-
           Enum.find(ctx.ancestors, fn {member, _binds} -> member.relation == callee.name end),
         true <-
           Enum.all?(Enum.zip(values, binds), fn
             {_value, {:node, _id}} -> true
             {cells, _bind} when is_list(cells) -> false
             {{:pair, _, _}, _bind} -> false
             {:fresh, along = {:along, _, _}} -> match?({m, _a} when m != 0, Place.extent(along))
             {{:node, _id}, _bind} -> false
             {{:rel, _p, _fixed} = passed, bind} -> bind == passed
             _form -> true
           end) do
      frame = framed_at(frame_of(values, steps), ancestor, ctx)
      {ancestor, binds, frame, %Walk{}}
    else
      _another -> nil
    end
  end

  # A bank made from a literal holds exactly those cells: its presence is bounded here.
  @spec place_new_member(Rel.t(), [value()], Place.known(), ctx()) :: placement()
  defp place_new_member(callee, values, known, ctx) do
    lifted = for form <- values, do: liftable(form)
    {_step, steps} = Layout.column_counter(callee.clauses, lifted, known)

    frame =
      case frame_of(values, steps) do
        # A callee whose steps count no column stands at the caller's column.
        :ptr when steps == nil -> Ast.address(:x, 1, 0)
        frame -> framed_at(frame, callee.name, ctx)
      end

    {name, binds, walk} =
      compile_member(callee, for(form <- lifted, do: Value.unframe(form, frame)), known, ctx)

    bounded =
      for {cells, bind} <- Enum.zip(lifted, binds),
          data_list?(cells),
          along = {:along, _, _} <- [Value.frame(bind, frame)],
          eq <- Place.bounded(along, length(cells)),
          do: eq

    {name, binds, frame, %{walk | eqs: bounded}}
  end

  # A call with no affine frame reads through a pointer cell owned by the call site.
  @spec framed_at(frame() | :ptr, atom(), ctx()) :: frame()
  defp framed_at(:ptr, target, ctx) do
    Ast.address({:cell, {ctx.member, {:own, {:"which #{target}", ctx.site}}}}, 1, 0)
  end

  defp framed_at(frame, _target, _ctx), do: frame

  # What a callee may take as handed: cells of the caller's column, data, counts. A list
  # or term placed elsewhere becomes a node the callee equates with.
  @spec liftable(value()) :: value()
  defp liftable(node = {:node, _id}), do: node
  defp liftable(along = {:along, _, {:at, base, _, _}}) when base != :x, do: Place.node_of(along)
  defp liftable(element = {:across, _, _, _}), do: element
  defp liftable(along = {:along, _, _}), do: along
  defp liftable(pair = {:pair, _, _}), do: Place.node_of(pair)
  defp liftable(form) when is_list(form) or is_integer(form) or form == :fresh, do: form
  defp liftable({tag, _a, _b} = form) when tag in [:count, :rel], do: form
  defp liftable(form), do: if(Place.affine(form) != nil, do: form, else: :fresh)

  # The caller's column where the callee's count stands; a pointer when no count is known.
  @spec frame_of([value()], tuple() | nil) :: frame() | :ptr
  defp frame_of(_values, nil), do: :ptr

  defp frame_of(values, {j, o}) do
    count =
      case Enum.at(values, j) do
        along = {:along, _, _} -> Place.extent(along)
        cells when is_list(cells) -> if data_list?(cells), do: {0, length(cells)}
        form -> Place.affine(form)
      end

    with {m, a} <- count, do: Ast.address(:x, m, a - o), else: (_open -> :ptr)
  end

  # A primitive with a known index picks the cell; otherwise its meaning is applied to
  # the prepared arguments.
  @spec phi_goal(Rel.t(), [term()], Walk.t(), ctx()) :: Walk.t() | :dead
  defp phi_goal(callee, args, walk, ctx) do
    {module, op} = callee.phi

    case pick(callee.phi, args, walk) do
      {v, selected} ->
        unify(v, selected, walk)

      nil ->
        {resolved, walk} = prepare(args, walk, ctx.member, ctx.site)

        Walk.constrain(walk, Ast.folded(apply(module, op, resolved)))
    end
  catch
    {:refused, {:unliftable_term, %{term: {:node, _id}}}}
    when callee.al == nil and callee.clauses != [] ->
      compile_call(callee, args, walk, ctx)

    {:refused, {reason, detail}} ->
      throw({:refused, {reason, Map.put(detail, :relation, callee.name)}})
  end

  # An unbound output name gets a local cell; everything else is its value.
  @spec prepare([term()], Walk.t(), atom(), [term()]) :: {[Value.t()], Walk.t()}
  defp prepare(args, walk, member, site) do
    Enum.map_reduce(args, walk, fn arg, walk ->
      case {arg, Expression.argument(arg, walk)} do
        {{:var, name}, :fresh} ->
          ref = {member, {:own, {name, site}}}
          cell = Ast.cell(ref)
          slot = %Slot{name: name, allocation: {:cell, ref}}
          {cell, %{walk | env: Map.put(walk.env, name, cell), slots: walk.slots ++ [slot]}}

        _bound ->
          {Value.elements(Expression.resolve!(arg, walk), walk.shapes), walk}
      end
    end)
  end

  @spec pick({module(), atom()}, [term()], Walk.t()) :: {term(), value()} | nil
  defp pick({Ast, :nth}, [i, xs, v], walk) do
    with q when is_integer(q) <- Expression.argument(i, walk),
         cells when is_list(cells) <- Value.elements(Expression.argument(xs, walk), walk.shapes),
         true <- q >= 1 and q <= length(cells),
         do: {v, Enum.at(cells, q - 1)},
         else: (_unpicked -> nil)
  end

  defp pick(_phi, _args, _env), do: nil

  ############################################################
  #                        Unifying                          #
  ############################################################

  @spec unify(term(), value(), Walk.t()) :: Walk.t() | :dead
  defp unify(value, value, walk), do: walk
  defp unify(_pattern, :fresh, walk), do: walk
  defp unify(:fresh, _value, walk), do: walk

  defp unify({:var, v}, value, walk = %Walk{env: env}) do
    case env do
      %{^v => _held} -> unify(Walk.fetch(walk, v), value, walk)
      _fresh -> %{walk | env: Map.put(env, v, value)}
    end
  end

  # Two unresolved parameters become one until a value binds either.
  defp unify(a = {:fresh, ref}, b = {:fresh, other}, walk = %Walk{env: env}) do
    cond do
      is_map_key(env, ref) -> unify(Walk.fetch(walk, ref), b, walk)
      is_map_key(env, other) -> unify(a, Walk.fetch(walk, other), walk)
      true -> %{walk | env: Map.put(env, other, a)}
    end
  end

  # The parameter takes storage for the value, then is matched against it.
  defp unify({:fresh, ref}, value, walk = %Walk{env: env}) do
    case env do
      %{^ref => _bound} ->
        unify(Walk.fetch(walk, ref), value, walk)

      _unbound ->
        value = if value == nil, do: [], else: value
        walk = Walk.allocate(walk, ref, value)
        unify(Walk.fetch(walk, ref), value, walk)
    end
  end

  # A bracket against a parameter nothing placed: the parameter takes a bank of the
  # bracket's length, open past its tail. The layout places what a body binds for the
  # callee's own parameters; a caller's unbound output reaches here.
  defp unify({:cons, _h, _t} = bracket, {:fresh, ref}, walk = %Walk{env: env})
       when not is_map_key(env, ref) do
    extent =
      case Lang.Term.closed(bracket) do
        nil -> {1, 0}
        elements -> {0, length(elements)}
      end

    shape = {:list, extent, :unknown}
    walk = Walk.bank(walk, ref, {:along, {Bank.of(ref), 1}, Place.head(shape)}, shape)
    unify(bracket, walk.env[ref], walk)
  end

  defp unify(pattern, {:fresh, _ref} = fresh, walk), do: unify(fresh, pattern, walk)

  defp unify({:node, a}, {:node, b}, walk), do: Walk.constrain(walk, [Ast.eq(a, b)])
  defp unify(node = {:node, _id}, other, walk), do: unify(other, node, walk)

  defp unify(along = {:along, _, _}, {:node, id}, walk),
    do: Walk.constrain(walk, [Ast.eq(elem(Place.node_of(along), 1), id)])

  defp unify(q, {:node, id}, walk) when is_integer(q),
    do: Walk.constrain(walk, [Ast.eq(Place.read(:value, id), q)])

  defp unify(q, {:count, _held, form}, walk) when is_integer(q),
    do: Walk.constrain(walk, [Ast.eq(form, q)])

  defp unify(q, form, walk)
       when is_integer(q) and (form == :x or elem(form, 0) in [:cell, :add, :mul]),
       do: Walk.constrain(walk, pinned(form, q))

  # An integer against an element: a record has no number, an element still unknown may.
  defp unify(q, element = {:across, row, _address, _skipped}, walk) when is_integer(q) do
    case Map.get(walk.shapes, row) do
      {:list, _extent, _fields} -> :dead
      _scalar_or_unknown -> Walk.constrain(walk, [Ast.eq(element, q)])
    end
  end

  defp unify(q, _value, _walk) when is_integer(q), do: :dead

  defp unify(nil, value, walk), do: unify([], value, walk)

  defp unify([], value, walk), do: Walk.ended(walk, value)

  defp unify({:cons, h, t}, value, walk), do: unify({:pair, h, t}, value, walk)

  defp unify([h | t], value, walk), do: unify({:pair, h, t}, value, walk)

  defp unify({:pair, h, t}, value, walk) do
    with {:ok, vh, vt, walk} <- Walk.peel(walk, value),
         walk = %Walk{} <- unify(h, vh, walk),
         do: unify(t, vt, walk)
  end

  defp unify(pattern = {op, _a, _b}, value, walk) when op in [:add, :mul] do
    case bind_expression(pattern, value, walk) do
      {:waiting, _names} -> throw({:refused, {:unbound_variable, %{equation: pattern}}})
      matched -> matched
    end
  end

  defp unify(pattern = {:papply, _p, _fixed}, value, walk),
    do: unify(Expression.resolve!(pattern, walk), value, walk)

  # Two lists along the trace: the same one, or one counted against the other's elements.
  defp unify(a = {:along, _, _}, b = {:along, _, _}, walk) do
    known = walk.shapes

    cond do
      a == b -> walk
      Place.count(b) -> unify(a, elements(b, known), walk)
      Place.count(a) -> unify(b, elements(a, known), walk)
      true -> throw({:refused, {:unliftable_term, %{term: b}}})
    end
  end

  defp unify(a = {:along, _, _}, value, walk) when is_list(value), do: unify(value, a, walk)
  defp unify(a = {:along, _, _}, value = {:pair, _, _}, walk), do: unify(value, a, walk)
  defp unify({:along, _, _}, _value, _walk), do: :dead
  defp unify({:rel, _p, _f}, _value, _walk), do: :dead

  defp unify(element = {:across, _, _, _}, value, walk)
       when is_list(value) or (is_tuple(value) and elem(value, 0) == :pair),
       do: unify(value, element, walk)

  defp unify(a, b, walk), do: equated(a, b, walk)

  defp bind_expression(pattern, value, walk) do
    case Expression.solve(pattern, walk) do
      {:ok, ^pattern} ->
        equated(pattern, value, walk)

      {:ok, bound} ->
        unify(bound, value, walk)

      {:free, name, rebuild} ->
        %{walk | env: Map.put(walk.env, name, rebuild.(Value.scalar(value)))}

      waiting = {:waiting, _names} ->
        waiting
    end
  end

  @spec equated(value(), value(), Walk.t()) :: Walk.t() | :dead
  defp equated(a, b, walk) do
    cond do
      is_integer(b) ->
        unify(b, a, walk)

      is_list(b) or match?({:pair, _, _}, b) or match?({:along, _, _}, b) or
          match?({:rel, _p, _f}, b) ->
        :dead

      true ->
        Walk.constrain(walk, [Ast.eq(Value.scalar(a), Value.scalar(b))])
    end
  end

  # A counted list along the trace as the list of its elements.
  @spec elements(value(), Place.known()) :: [value()]
  defp elements(along, known),
    do: for(i <- 0..(Place.count(along) - 1)//1, do: Place.slice(along, i, known))

  # An integer against the column pins the column; against anything else, that cell.
  @spec pinned(Ast.term_t(), integer()) :: [Ast.pred()]
  defp pinned(form, q) do
    case Place.affine(form) do
      {1, o} -> [Ast.eq(:x, q - o)]
      _cell -> Ast.folded(Ast.eq(Value.scalar(form), q))
    end
  end
end
