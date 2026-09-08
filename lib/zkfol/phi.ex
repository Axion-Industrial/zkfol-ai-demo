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

  ### Public API

  - `run/2`, `verb/0`: the pass.
  - `relaid/2`: the derivation laid as the statement's witness.
  - `compile/3`: the predicate and the allocation it stands on.
  - `lower/2`: that predicate, linked.
  """

  @behaviour Zkfol.Pipeline

  alias Zkfol.Alloc
  alias Zkfol.Alloc.Member
  alias Zkfol.Alloc.Site
  alias Zkfol.Alloc.Slot
  alias Zkfol.Ast
  alias Zkfol.Derivation
  alias Zkfol.Lay
  alias Zkfol.Lang
  alias Zkfol.Lang.Rel
  alias Zkfol.Phi.View
  alias Zkfol.Phi.Walk
  alias Zkfol.Refusal
  alias Zkfol.Statement

  @typedoc """
  What a name holds: a literal, a term, a view, a known sequence, a passed relation, a
  handed count, a cell nothing read yet, or nothing yet.
  """
  @type value ::
          integer()
          | Ast.term_t()
          | View.t()
          | [value()]
          | {:rel, atom(), [value()]}
          | {:count, integer(), Ast.term_t()}
          | {:fresh, Ast.row_ref()}
          | :fresh

  @typedoc "Where a call reaches: an affine frame of the column, or a pointer cell."
  @type frame :: {integer(), integer()} | {:ptr, Ast.row_ref()}

  # `inlining`: sizes of the calls being said in place; `self`: the call names its own relation.
  @typep ctx :: %{
           scope: %{atom() => Rel.t()},
           recursive: MapSet.t(),
           path: [{atom(), atom()}],
           ancestors: %{atom() => {Member.t(), [value()]}},
           taken: MapSet.t(),
           member: atom(),
           site: [non_neg_integer()],
           inlining: %{atom() => [integer() | nil]},
           self: boolean()
         }

  @doc "I lay a derived statement; one that has not run passes through."
  @impl Zkfol.Pipeline
  @spec run(Statement.t(), keyword()) :: {:ok, Statement.t()} | {:error, Refusal.t()}
  def run(%Statement{stage: %Derivation{} = derivation} = statement, _opts),
    do: relaid(statement, derivation)

  def run(%Statement{} = statement, _opts), do: {:ok, statement}

  @impl Zkfol.Pipeline
  @spec verb() :: Zkfol.Pipeline.verdict()
  def verb, do: :lowers

  @doc "I lay the derivation for the statement."
  @spec relaid(Statement.t(), Derivation.t()) :: {:ok, Statement.t()} | {:error, Refusal.t()}
  def relaid(%Statement{rels: [root | _rest] = rels} = statement, %Derivation{} = derivation) do
    # What the run established of the root itself: the arguments, every hole filled.
    {_name, args} = Derivation.root(derivation, root.name) || {root.name, []}

    with {:ok, pred, alloc} <- compile(root, rels, args) do
      stage = %Statement.Solved{pred: Alloc.link(pred, alloc), lay: Lay.of(derivation, alloc)}
      {:ok, %{statement | stage: stage}}
    end
  end

  @doc "I am the predicate of `root` against `rels`, linked."
  @spec lower(Rel.t(), [Rel.t()]) :: {:ok, Ast.pred()} | {:error, Refusal.t()}
  def lower(%Rel{} = root, rels) do
    with {:ok, pred, alloc} <- compile(root, rels), do: {:ok, Alloc.link(pred, alloc)}
  end

  @doc "I compile `root` against `rels` to its predicate and allocation; `args` size its banks."
  @spec compile(Rel.t(), [Rel.t()] | nil, [term()]) ::
          {:ok, Ast.pred(), Alloc.t()} | {:error, Refusal.t()}
  def compile(%Rel{} = root, rels \\ nil, args \\ []) do
    with {:ok, [root | _rest] = reached} <- Lang.reached(root, rels || [root]) do
      compiled(root, Map.new(reached, &{&1.name, &1}), args)
    end
  end

  @spec compiled(Rel.t(), %{atom() => Rel.t()}, [term()]) ::
          {:ok, Ast.pred(), Alloc.t()} | {:error, Refusal.t()}
  defp compiled(%Rel{} = root, scope, args) do
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
      for %Rel{name: name} = rel <- Map.values(scope),
          q <- Rel.calls(rel) ++ Rel.passes(rel),
          %Rel{} = callee <- [scope[q]],
          {:ok, reached} <- [Lang.reached(callee, Map.values(scope))],
          name in for(r <- reached, do: r.name),
          into: MapSet.new(),
          do: name

    ctx = %{
      scope: scope,
      recursive: recursive,
      path: [],
      ancestors: %{},
      taken: MapSet.new(),
      member: nil,
      site: [],
      inlining: %{},
      self: false
    }

    {name, _binds, walk} = laid(root, handed, ctx)
    said = Map.new(walk.saids)

    pred =
      Ast.conj(
        for(m <- walk.members, not Member.bank?(m), do: said[m.name]) ++
          for(m <- walk.members, Member.bank?(m), do: runs(m))
      )

    {:ok, pred, Alloc.numbered(walk.members, name)}
  catch
    {:refused, refusal} -> {:error, refusal}
  end

  # A bank fills one run from column two, so no forger shortens a walk by cutting its presence.
  @spec runs(Member.t()) :: Ast.pred()
  defp runs(%Member{present: present}) do
    Ast.disj([
      Ast.eq({:cell, present}, 0),
      Ast.eq(Ast.at(present, :x, 1, -1), 1),
      Ast.eq(:x, 2)
    ])
  end

  ############################################################
  #                         Laying                           #
  ############################################################

  # Spent rows number after the parameters' own, by tag, so goal order moves nothing.
  @spec laid(Rel.t(), [value()], ctx()) :: {atom(), [value()], Walk.t()}
  defp laid(%Rel{} = rel, handed, ctx) do
    name = minted(rel.name, ctx.taken)
    syms = params(rel)
    refs = for sym <- syms, do: {name, {:param, sym}}
    handed = for {form, ref} <- Enum.zip(handed, refs), do: owned(form, ref)
    {steps, binds, dims} = footing(rel, handed, refs, ctx.scope, [])
    member = Member.of(name, rel.name, steps)

    ctx = %{
      ctx
      | path: [{rel.name, name} | ctx.path],
        ancestors: Map.put(ctx.ancestors, name, {member, binds}),
        taken: Enum.into([name | Map.keys(dims)], ctx.taken),
        member: name
    }

    {clauses, envs, walk} = said(rel, member, binds, dims, ctx)
    branches = for {branch, _sites} <- clauses, branch, do: branch
    read = MapSet.new(Enum.flat_map(branches, &Ast.reads/1))
    dims = grown(envs, dims)
    binds = for {bind, ref} <- Enum.zip(binds, refs), do: settled(bind, ref, envs, read)

    member = %{
      member
      | sites: for({_branch, sites} <- clauses, do: sites),
        slots: slots(binds, syms, name, dims) ++ Enum.sort_by(walk.spent, &hd(&1.rows))
    }

    banks =
      for ref <- refs,
          dim = dims[Member.bank_name(ref)],
          do: Member.bank(Member.bank_name(ref), dim)

    branches =
      for {:conj, [present | eqs]} <- branches,
          do: Ast.conj([present | Enum.sort_by(eqs, &inspect/1)])

    said = Ast.disj([Ast.eq({:cell, member.present}, 0) | branches])

    walk = %{
      walk
      | members: [member | banks] ++ walk.members,
        saids: [{name, said} | walk.saids],
        spent: []
    }

    {name, binds, walk}
  end

  # A scalar the act or a caller handed is data in a cell of the member's own (rule 4).
  @spec owned(value(), Ast.row_ref()) :: value()
  defp owned(:fresh, ref), do: {:fresh, ref}
  defp owned({:count, q, _cell}, ref), do: {:count, q, {:cell, ref}}
  defp owned(form, _ref), do: form

  @spec settled(value(), Ast.row_ref(), [map()], MapSet.t()) :: value()
  defp settled(bind, ref, envs, read) do
    case Enum.find_value(envs, &Map.get(&1, ref)) do
      nil -> if(ref in read, do: {:cell, ref}, else: bind)
      held -> held
    end
  end

  @spec minted(atom(), MapSet.t()) :: atom()
  defp minted(q, taken),
    do:
      Enum.find(
        [q | for(i <- 2..(MapSet.size(taken) + 2)//1, do: :"#{q}#{i}")],
        &(&1 not in taken)
      )

  @spec grown([map()], %{atom() => pos_integer()}) :: %{atom() => pos_integer()}
  defp grown(envs, dims) do
    for env <- envs, {{:bank, bank}, dim} <- env, reduce: dims do
      acc -> Map.update(acc, bank, dim, &max(&1, dim))
    end
  end

  # A parameter handed on displaced along the column steps; the base clause's count is the origin.
  @spec footing(Rel.t(), [value()], [Ast.row_ref()], %{atom() => Rel.t()}, [atom()]) ::
          {{non_neg_integer(), integer()} | nil, [value()], %{atom() => pos_integer()}}
  defp footing(%Rel{clauses: clauses} = rel, handed, refs, scope, seen) do
    step = stepping(clauses)
    j = (step && elem(step, 0)) || Enum.find_index(handed, &counted?/1)
    o = if(j, do: origin(clauses, j), else: 0)
    steps = if j && walkable?(Enum.at(handed, j)), do: {j, o}
    solve = %{step: step, o: o, clauses: clauses, handed: handed, scope: scope, seen: seen}

    data =
      for {form, ref} <- Enum.zip(handed, refs), is_list(form), into: %{} do
        {Member.bank_name(ref), Enum.max([1 | for(c <- form, is_list(c), do: length(c))])}
      end

    dims =
      for {ref, k} <- Enum.with_index(refs), into: %{} do
        {Member.bank_name(ref), max(shape(clauses, k), data[Member.bank_name(ref)] || 1)}
      end

    binds =
      for {{form, ref}, k} <- Enum.with_index(Enum.zip(handed, refs)) do
        sequence =
          data_list?(form) or match?(%View{}, form) or
            Enum.any?(clauses, fn {head, _body} -> Lang.Term.sequence?(Enum.at(head, k)) end)

        extent =
          cond do
            not sequence -> nil
            step == nil or steps == nil -> count_of(form) || :open
            k == j -> {1, o}
            true -> extent(rel, k, solve)
          end

        cond do
          k == j and not sequence ->
            View.term(%View{row: nil, col: {:x, 1, o}})

          extent == nil or (match?(%View{}, form) and (step == nil or steps == nil)) ->
            form

          match?(%View{}, form) ->
            View.stepped(form, extent) ||
              throw({:refused, {:unliftable_term, %{term: form, relation: rel.name}}})

          true ->
            View.bank(
              Member.bank_rows(Member.bank_name(ref), dims[Member.bank_name(ref)]),
              extent
            )
        end
      end

    dims =
      for {bind, ref} <- Enum.zip(binds, refs),
          %View{row: {bank, _r}} <- [bind],
          bank == Member.bank_name(ref),
          into: %{},
          do: {bank, dims[bank]}

    {steps, binds, dims}
  end

  @spec counted?(value()) :: boolean()
  defp counted?(%View{axes: [%{row: 0, extent: e} | _rest]}), do: e != :open
  defp counted?(form) when is_list(form), do: data_list?(form)
  defp counted?(form), do: match?(%View{row: nil, col: {:x, m, _a}} when m != 0, View.of(form))

  @spec walkable?(value()) :: boolean()
  defp walkable?(%View{col: col} = view), do: col != nil and not View.rowed?(view)
  defp walkable?(cells) when is_list(cells), do: data_list?(cells)
  defp walkable?(_value), do: true

  # The stepping call: the parameter, its displacement, the callee, how far each argument hands.
  @typep step :: {non_neg_integer(), integer(), atom(), [[integer() | nil]]}

  @spec stepping([{[term()], [term()]}]) :: step() | nil
  defp stepping(clauses) do
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

  # The rows a parameter's bank needs: its longest closed inner bracket, one otherwise.
  @spec shape([{[term()], [term()]}], non_neg_integer()) :: pos_integer()
  defp shape(clauses, k) do
    inners =
      for {head, _body} <- clauses,
          {:cons, _h, _t} = bracket <- [Enum.at(head, k)],
          {:cons, _h, _t} = inner <- spine(bracket),
          tail_of(inner) == nil,
          do: length(spine(inner))

    Enum.max([1 | inners])
  end

  # On itself, the fixpoint: `c` cells a step from the base clause's count.
  @spec extent(Rel.t(), non_neg_integer(), map()) :: View.extent()
  defp extent(%Rel{name: self}, k, %{step: {j, cj, q, hands}} = solve) do
    handed = Enum.at(solve.handed, k)

    case Enum.find(Enum.with_index(Enum.at(hands, k)), fn {c, _p} -> c != nil end) do
      {c, _p} when q == self ->
        m = div(c, cj)
        {m, intercept(solve, j, k) - m}

      {c, p} when q != self ->
        crefs = for sym <- params(solve.scope[q]), do: {q, {:param, sym}}
        fresh = for r <- crefs, do: {:fresh, r}

        with false <- q in solve.seen,
             {{_jc, oc}, cbinds, _dims} <-
               footing(solve.scope[q], fresh, crefs, solve.scope, [self | solve.seen]),
             %View{} = view <- Enum.at(cbinds, p) do
          [{:_, 1}]
          |> View.bank(View.len(view))
          |> View.framed({1, cj + solve.o - oc})
          |> View.shifted(c)
          |> View.len()
        else
          _unstepped -> count_of(handed) || :open
        end

      _apart ->
        count_of(handed) || :open
    end
  end

  # The base clause's count for a parameter, or what a name one with it there was handed.
  @spec intercept(map(), non_neg_integer(), non_neg_integer()) :: integer()
  defp intercept(%{clauses: clauses, handed: handed, step: {_j, _cj, _q, hands}}, j, k) do
    {base, _body} = Enum.min_by(clauses, fn {head, _body} -> count_in(head, j) || 1 end)

    mates =
      for {pattern, i} <- Enum.with_index(base),
          i == k or (match?({:var, _v}, pattern) and pattern == Enum.at(base, k)),
          do: i

    Enum.find_value(mates, 0, fn i ->
      case count_in(base, i) do
        nil -> if(0 in Enum.at(hands, i), do: count_of(Enum.at(handed, i)))
        said -> said
      end
    end)
  end

  @spec count_of(value() | nil) :: non_neg_integer() | nil
  defp count_of({:count, q, _form}), do: q
  defp count_of(q) when is_integer(q), do: q
  defp count_of([]), do: 0
  defp count_of([_h | t]), do: with(n when n != nil <- count_of(t), do: n + 1)
  defp count_of(%View{} = view), do: View.count(view)
  defp count_of(_value), do: nil

  # Values are data and stand in a bank; forms are cells that already stand (rule 1).
  @spec data_list?(value()) :: boolean()
  defp data_list?([]), do: false

  defp data_list?(cells) when is_list(cells),
    do: Enum.all?(cells, &(is_integer(&1) or &1 == [] or data_list?(&1)))

  defp data_list?(_form), do: false

  # A view of another member's cells is a rearrangement, laid by nothing.
  @spec slots([value()], [atom()], atom(), %{atom() => pos_integer()}) :: [Slot.t()]
  defp slots(binds, syms, name, dims) do
    for {bind, sym} <- Enum.zip(binds, syms) do
      ref = {name, {:param, sym}}
      bank = Member.bank_name(ref)

      case bind do
        :x ->
          Slot.index(sym, 0)

        {:add, :x, o} ->
          Slot.index(sym, o)

        {:cell, ^ref} ->
          Slot.own(sym, [ref])

        {:count, _q, {:cell, ^ref}} ->
          Slot.own(sym, [ref])

        %View{row: {^bank, _r}, col: {_b, m, a}} ->
          Slot.bank(sym, Member.bank_rows(bank, dims[bank]), {m, a})

        %View{row: {^bank, _r}, col: nil} ->
          Slot.bank(sym, Member.bank_rows(bank, dims[bank]), {0, 0})

        _reference ->
          Slot.passed(sym)
      end
    end
  end

  @spec params(Rel.t()) :: [atom()]
  defp params(%Rel{clauses: clauses}) do
    {head, _body} = Enum.max_by(clauses, fn {_h, b} -> length(b) end)

    for {pattern, k} <- Enum.with_index(head) do
      with {:var, v} <- pattern, do: v, else: (_other -> :"a#{k + 1}")
    end
  end

  ############################################################
  #                         Saying                           #
  ############################################################

  # A clause the values kill says nothing and lays nothing.
  @spec said(Rel.t(), Member.t(), [value()], %{atom() => pos_integer()}, ctx()) ::
          {[{Ast.pred() | nil, [Site.t()]}], [map()], Walk.t()}
  defp said(%Rel{clauses: clauses}, %Member{} = member, binds, dims, ctx) do
    seeded = Map.new(dims, fn {bank, dim} -> {{:bank, bank}, dim} end)

    {results, walk} =
      Enum.map_reduce(Enum.with_index(clauses), %Walk{}, fn {{head, body}, k}, acc ->
        ctx = %{ctx | site: [k], taken: Enum.into(Alloc.names(acc.members), ctx.taken)}

        case unify_all(head, binds, seeded) do
          :dead ->
            {{nil, [], nil}, acc}

          {:ok, env, pins} ->
            walk = walked(body, env, ctx)
            eqs = [Ast.eq({:cell, member.present}, 1) | pins ++ walk.eqs]
            sites = for {_k, site} <- Enum.sort_by(walk.sites, &elem(&1, 0)), site, do: site
            {{Ast.conj(eqs), sites, walk.env}, Walk.join(acc, %{walk | eqs: [], sites: []})}
        end
      end)

    {for({b, s, _env} <- results, do: {b, s}), for({_b, _s, env} <- results, env, do: env), walk}
  end

  # A goal naming a value nothing said yet waits for another pass; a dead conjunct ends the walk.
  @spec walked([term()], map(), ctx()) :: Walk.t()
  defp walked(goals, env, ctx), do: walked(Enum.with_index(goals), env, ctx, %Walk{})

  defp walked(goals, env, ctx, walk) do
    {walk, stalled} =
      Enum.reduce_while(goals, {%{walk | env: env}, []}, fn {goal, k}, {walk, stalled} ->
        ctx = %{
          ctx
          | site: [k | ctx.site],
            taken: Enum.into(Alloc.names(walk.members), ctx.taken)
        }

        case goaled(goal, walk.env, ctx) do
          # A dead conjunct is the whole clause: it says only falsity.
          %Walk{dead?: true} = dead ->
            {:halt, {%{walk | env: dead.env, eqs: [Ast.eq(0, 1)], dead?: true}, []}}

          %Walk{} = more ->
            {:cont,
             {Walk.join(walk, %{more | sites: for({_g, s} <- more.sites, do: {k, s})}), stalled}}

          :stalled ->
            {:cont, {walk, stalled ++ [{goal, k}]}}
        end
      end)

    cond do
      stalled == [] -> walk
      length(stalled) < length(goals) -> walked(stalled, walk.env, ctx, walk)
      true -> throw({:refused, {:unbound_variable, %{goals: for({g, _k} <- stalled, do: g)}}})
    end
  end

  @spec goaled(term(), map(), ctx()) :: Walk.t() | :stalled
  defp goaled({:eq, a, b}, env, _ctx) do
    case sided(a, b, env) || sided(b, a, env) do
      {:ok, env, eqs} -> %Walk{env: env, eqs: eqs}
      :dead -> Walk.dead(env)
      nil -> :stalled
    end
  end

  defp goaled({:call, q, args}, env, ctx) do
    {callee, args} =
      case q do
        {:var, _r} ->
          {:rel, p, fixed} = resolve(q, env)
          {ctx.scope[p], fixed ++ args}

        _name ->
          {ctx.scope[q] || throw({:refused, {:relation_not_in_scope, %{relation: q}}}), args}
      end

    cond do
      callee.phi -> phi_goal(callee, args, env, ctx)
      # A relation of no clauses and no phi drives the derivation only; it says nothing here.
      callee.clauses == [] -> %Walk{env: env}
      true -> resolved(callee, args, env, %{ctx | self: q == callee.name})
    end
  end

  # A name or a sum takes the other side's value; a structure must be said itself.
  @spec sided(term(), term(), map()) :: {:ok, map(), [Ast.pred()]} | :dead | nil
  defp sided(pattern, other, env) do
    case pattern do
      {:var, _v} -> unify(pattern, resolve(other, env), env)
      {op, _a, _b} when op in [:add, :mul] -> unify(pattern, resolve(other, env), env)
      _structure -> unify(resolve(pattern, env), resolve(other, env), env)
    end
  catch
    {:refused, {:unbound_variable, _detail}} -> nil
  end

  ############################################################
  #                         Calling                          #
  ############################################################

  # Said in place where the values select a clause and the steps are finite, continued where
  # it names a relation being laid, laid as a member otherwise.
  @spec resolved(Rel.t(), [term()], map(), ctx()) :: Walk.t()
  defp resolved(callee, args, env, ctx) do
    values = for arg <- args, do: handed(arg, env)
    finite = finite?(callee, values, ctx)

    said =
      for {{head, body}, k} <- Enum.with_index(callee.clauses),
          {:ok, inner, pins} <- [unify_all(head, values, %{})],
          result <- [finite && inlined(callee, {k, body, inner, pins}, args, values, env, ctx)],
          result != :dead,
          do: result

    case said do
      [] -> Walk.dead(env)
      [{:ok, walk}] -> walk
      [{:standing, walk}] -> sited(callee, args, values, env, ctx, walk)
      _laid -> sited(callee, args, values, env, ctx, nil)
    end
  end

  # Recursion is said in place only over finite values, or over a list shrinking by its own name.
  @spec finite?(Rel.t(), [value()], ctx()) :: boolean()
  defp finite?(%Rel{name: name}, values, ctx) do
    around = if ctx.self, do: Map.get(ctx.inlining, name)
    shrunk = if around, do: Enum.zip(for(v <- values, do: size(v)), around)

    name not in ctx.recursive or
      ((Enum.any?(values, &is_list/1) or Enum.all?(values, &finite?/1)) and
         (shrunk == nil or
            (Enum.any?(shrunk, fn {a, b} -> a && b && a < b end) and
               not Enum.any?(shrunk, fn {a, b} -> a && b && a > b end))))
  end

  @spec finite?(value()) :: boolean()
  defp finite?(%View{} = view), do: View.finite?(view)
  defp finite?([h | t]), do: finite?(h) and finite?(t)
  defp finite?(:x), do: false
  defp finite?({tag, _a, _b}) when tag in [:add, :mul, :count], do: false
  defp finite?(_value), do: true

  # How many cells a value holds, an integer standing for that many.
  @spec size(value()) :: integer() | nil
  defp size(q) when is_integer(q), do: q
  defp size(%View{} = view), do: View.size(view)
  defp size([]), do: 0
  defp size([h | t]), do: with(a when a != nil <- size(h), b when b != nil <- size(t), do: a + b)
  defp size(:fresh), do: nil
  defp size({:fresh, _ref}), do: nil
  defp size({:rel, _p, _f}), do: nil
  defp size(_cell), do: 1

  # A saying holds only where it laid nothing; over a standing extent only where it is free.
  @spec inlined(
          Rel.t(),
          {non_neg_integer(), [term()], map(), [Ast.pred()]},
          [term()],
          [value()],
          map(),
          ctx()
        ) ::
          {:ok | :standing, Walk.t()} | :dead | :laid
  defp inlined(callee, {k, body, inner, pins}, args, values, env, ctx) do
    if length(ctx.site) > 3000, do: throw({:refused, {:unroll_budget, %{relation: callee.name}}})

    within = %{
      ctx
      | site: [k, callee.name | ctx.site],
        inlining: Map.put(ctx.inlining, callee.name, for(v <- values, do: size(v)))
    }

    walk = walked(body, inner, within)

    if walk.dead?, do: throw(:dead)

    {head, _body} = Enum.at(callee.clauses, k)
    outputs = for pattern <- head, do: resolve(pattern, walk.env)

    standing =
      not Enum.any?(values, &is_list/1) and callee.name in ctx.recursive and
        Enum.any?(
          values,
          &match?(
            %View{col: {_b, _m, _a}, axes: [%{row: 0, extent: e} | _]} when is_integer(e),
            &1
          )
        )

    free = pins == [] and walk.eqs == [] and not Enum.any?(outputs, &arithmetic?/1)

    with true <-
           not Enum.any?(walk.env, fn {key, _value} -> match?({:bank, _}, key) end) and
             walk.members == [] and walk.spent == [] and
             Enum.all?(walk.sites, &(elem(&1, 1) == nil)),
         {:ok, env, eqs} <- unify_all(args, outputs, env) do
      {if(free or not standing, do: :ok, else: :standing),
       %{walk | env: env, eqs: pins ++ walk.eqs ++ eqs, sites: [{0, nil}]}}
    else
      _held -> :laid
    end
  catch
    :dead -> :dead
    {:refused, {:unroll_budget, _detail} = refusal} -> throw({:refused, refusal})
    {:refused, _detail} -> :laid
  end

  @spec arithmetic?(value()) :: boolean()
  defp arithmetic?({op, _a, _b}) when op in [:add, :mul], do: true
  defp arithmetic?([h | t]), do: arithmetic?(h) or arithmetic?(t)
  defp arithmetic?(_value), do: false

  # A walk over a standing extent no frame can lay takes the unrolled saying.
  @spec sited(Rel.t(), [term()], [value()], map(), ctx(), Walk.t() | nil) :: Walk.t()
  defp sited(callee, args, values, env, ctx, unrolled) do
    {name, binds, frame, walk} = continued(callee, values, ctx) || laid_at(callee, values, ctx)

    {env, eqs, dead?} =
      Enum.reduce(Enum.zip(args, binds), {env, [], false}, fn {arg, bind}, {env, eqs, dead?} ->
        case unify(arg, framed(bind, frame), env) do
          {:ok, env, more} -> {env, eqs ++ more, dead?}
          :dead -> {env, eqs, true}
        end
      end)

    present = Ast.eq(framed({:cell, {:in, name}}, frame), 1)

    %{
      walk
      | env: env,
        dead?: dead?,
        eqs: [present | eqs ++ walk.eqs],
        sites: [
          {0,
           %Site{
             callee: name,
             address: address(frame),
             occurrence: occurrence(callee.name, env, ctx)
           }}
        ]
    }
  catch
    {:refused, {:unliftable_term, _detail}} when unrolled != nil -> unrolled
  end

  @spec occurrence(atom(), map(), ctx()) :: non_neg_integer()
  defp occurrence(name, env, %{site: [k, clause | nesting], path: path, scope: scope}) do
    relation =
      case nesting do
        [relation | _rest] -> relation
        [] -> elem(hd(path), 0)
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
  @spec continued(Rel.t(), [value()], ctx()) :: {atom(), [value()], frame(), Walk.t()} | nil
  defp continued(callee, values, ctx) do
    with {_rel, ancestor} <- List.keyfind(ctx.path, callee.name, 0),
         {%Member{steps: steps}, binds} = ctx.ancestors[ancestor],
         true <-
           Enum.all?(Enum.zip(values, binds), fn
             {cells, _bind} when is_list(cells) -> false
             {{:rel, _p, _fixed} = passed, bind} -> bind == passed
             _form -> true
           end) do
      {frame, spent} = framed_at(frame_of(values, steps), ancestor, ctx)
      {ancestor, binds, frame, %Walk{spent: spent}}
    else
      _another -> nil
    end
  end

  # A bank minted from a literal holds exactly its cells: presence bounded at the call.
  @spec laid_at(Rel.t(), [value()], ctx()) :: {atom(), [value()], frame(), Walk.t()}
  defp laid_at(callee, values, ctx) do
    lifted = for form <- values, do: liftable(form)
    refs = for sym <- params(callee), do: {callee.name, {:param, sym}}
    owned = for {form, ref} <- Enum.zip(lifted, refs), do: owned(form, ref)
    {steps, _binds, _dims} = footing(callee, owned, refs, ctx.scope, [])

    {frame, spent} =
      case frame_of(values, steps) do
        # A callee no column counts stands where its caller stands.
        :ptr when steps == nil -> {{1, 0}, []}
        :ptr -> framed_at(:ptr, callee.name, ctx)
        frame -> {frame, []}
      end

    {name, binds, walk} = laid(callee, for(form <- lifted, do: reframed(form, frame)), ctx)

    bounded =
      for {cells, bind} <- Enum.zip(lifted, binds),
          data_list?(cells),
          %View{} = view <- [framed(bind, frame)],
          eq <- View.bounded(view, length(cells)),
          do: eq

    {name, binds, frame, %{walk | eqs: bounded, spent: walk.spent ++ spent}}
  end

  # A pointer frame spends a which row of the caller's, aimed at `target`.
  @spec framed_at(frame() | :ptr, atom(), ctx()) :: {frame(), [Slot.t()]}
  defp framed_at(:ptr, target, ctx) do
    ref = {ctx.member, {:own, {:"which #{target}", ctx.site}}}
    {{:ptr, ref}, [Slot.own(:"which #{target}", [ref])]}
  end

  defp framed_at(frame, _target, _ctx), do: {frame, []}

  @spec address(frame()) :: Ast.address()
  defp address({m, a}) when is_integer(m), do: Ast.address(:x, m, a)
  defp address({:ptr, ref}), do: Ast.address({:cell, ref}, 1, 0)

  # A cell of the caller's cannot stand a callee's rows: the callee holds its own and equates.
  @spec liftable(value()) :: value()
  defp liftable(%View{} = view), do: view
  defp liftable(form) when is_list(form) or is_integer(form) or form == :fresh, do: form
  defp liftable({tag, _a, _b} = form) when tag in [:count, :rel], do: form
  defp liftable(form), do: if(match?(%View{row: nil}, View.of(form)), do: form, else: :fresh)

  # Where the callee's count stands in the caller's column, or a pointer where it cannot say.
  @spec frame_of([value()], tuple() | nil) :: frame() | :ptr
  defp frame_of(_values, nil), do: :ptr

  defp frame_of(values, {j, o}) do
    count =
      case Enum.at(values, j) do
        %View{} = view -> with(n when is_integer(n) <- View.len(view), do: {0, n})
        cells when is_list(cells) -> if data_list?(cells), do: {0, length(cells)}
        form -> with(%View{row: nil, col: {:x, m, a}} <- View.of(form), do: {m, a})
      end

    with {m, a} <- count, do: {m, a - o}, else: (_open -> :ptr)
  end

  # An indexed read whose index stands picks its cell outright (rule 1).
  @spec phi_goal(Rel.t(), [term()], map(), ctx()) :: Walk.t()
  defp phi_goal(callee, args, env, ctx) do
    {module, op} = callee.phi

    case pick(callee.phi, args, env) do
      {v, selected} ->
        {:ok, env, eqs} = unify(v, selected, env)
        %Walk{env: env, eqs: eqs}

      nil ->
        {resolved, {env, spent}} =
          Enum.map_reduce(args, {env, []}, fn arg, {env, spent} ->
            case {arg, handed(arg, env)} do
              {{:var, v}, :fresh} ->
                ref = {ctx.member, {:own, {v, ctx.site}}}
                {{:cell, ref}, {Map.put(env, v, {:cell, ref}), spent ++ [Slot.own(v, [ref])]}}

              _held ->
                {spelt(resolve(arg, env)), {env, spent}}
            end
          end)

        %Walk{env: env, eqs: Ast.folded(apply(module, op, resolved)), spent: spent}
    end
  catch
    {:refused, {reason, detail}} ->
      throw({:refused, {reason, Map.put(detail, :relation, callee.name)}})
  end

  @spec pick({module(), atom()}, [term()], map()) :: {term(), value()} | nil
  defp pick({Ast, :nth}, [i, xs, v], env) do
    with q when is_integer(q) <- handed(i, env),
         cells when is_list(cells) <- spelt(handed(xs, env)),
         true <- q >= 1 and q <= length(cells),
         do: {v, Enum.at(cells, q - 1)},
         else: (_unpicked -> nil)
  end

  defp pick(_phi, _args, _env), do: nil

  @spec spelt(value()) :: value()
  defp spelt(%View{} = view), do: View.cells(view)
  defp spelt([h | t]), do: [spelt(h) | spelt(t)]
  defp spelt({:count, _q, form}), do: form
  defp spelt(form), do: form

  ############################################################
  #                        Unifying                          #
  ############################################################

  @spec unify_all([term()], [value()], map()) :: {:ok, map(), [Ast.pred()]} | :dead
  defp unify_all(patterns, values, env) do
    Enum.zip(patterns, values)
    |> Enum.reduce_while({:ok, env, []}, fn {pattern, value}, {:ok, env, eqs} ->
      case unify(pattern, value, env) do
        {:ok, env, more} -> {:cont, {:ok, env, eqs ++ more}}
        :dead -> {:halt, :dead}
      end
    end)
  end

  @spec unify(term(), value(), map()) :: {:ok, map(), [Ast.pred()]} | :dead
  defp unify(_pattern, :fresh, env), do: {:ok, env, []}
  defp unify(:fresh, _value, env), do: {:ok, env, []}

  defp unify({:var, v}, value, env) do
    case env do
      %{^v => held} -> unify(held, value, env)
      _fresh -> {:ok, Map.put(env, v, value), []}
    end
  end

  # A fresh name takes its standing from what meets it (rule 1).
  defp unify({:fresh, ref} = fresh, value, env) do
    case Map.get(env, ref) do
      nil -> met(fresh, value, env)
      held -> unify(held, value, env)
    end
  end

  defp unify({:cons, _h, _t} = bracket, {:fresh, ref}, env) when not is_map_key(env, ref) do
    bank = Member.bank_name(ref)
    len = if tail_of(bracket) == nil, do: length(spine(bracket)), else: {1, 0}
    view = View.bank([{bank, 1}], len)
    unify(bracket, view, env |> Map.put(ref, view) |> Map.put_new({:bank, bank}, 1))
  end

  defp unify(pattern, {:fresh, _ref} = fresh, env), do: unify(fresh, pattern, env)

  defp unify(q, value, env) when is_integer(q) do
    case value do
      ^q ->
        {:ok, env, []}

      r when is_integer(r) ->
        :dead

      {:count, _held, form} ->
        {:ok, env, [Ast.eq(form, q)]}

      form when is_tuple(form) and elem(form, 0) in [:cell, :add, :mul] ->
        {:ok, env, pinned(form, q)}

      :x ->
        {:ok, env, pinned(:x, q)}

      _structure ->
        :dead
    end
  end

  defp unify(nil, value, env), do: unify([], value, env)

  defp unify([], [], env), do: {:ok, env, []}

  defp unify([], %View{col: {_b, _m, _a}} = view, env),
    do: with({:ok, eqs} <- View.ended(view), do: {:ok, env, eqs})

  defp unify([], value, env) do
    case Ast.read(value) do
      {{bank, r}, _at} when is_map_key(env, {:bank, bank}) ->
        {:ok, deepened(env, bank, r - 1), []}

      _other ->
        :dead
    end
  end

  # A bracket meeting a cell of a bank being minted reads it as a column: the rows grow under it.
  defp unify({:cons, h, t}, value, env) do
    case Ast.read(value) do
      {{bank, r}, {:at, base, m, a}} when is_map_key(env, {:bank, bank}) ->
        with {:ok, env, eqs} <- unify(h, value, deepened(env, bank, r)),
             {:ok, env, more} <- unify(t, Ast.at({bank, r + 1}, base, m, a), env),
             do: {:ok, env, eqs ++ more}

      _cells ->
        unify([h | t], value, env)
    end
  end

  defp unify([h | t], value, env) do
    case value do
      [vh | vt] ->
        with {:ok, env, eqs} <- unify(h, vh, env),
             {:ok, env, more} <- unify(t, vt, env),
             do: {:ok, env, eqs ++ more}

      %View{col: {_b, _m, _a}} = view ->
        with {:ok, pins} <- View.peeled(view),
             {:ok, env, eqs} <- unify(h, View.slice(view, 0), env),
             {:ok, env, more} <- unify(t, View.shifted(view, 1), env),
             do: {:ok, env, pins ++ eqs ++ more}

      _other ->
        :dead
    end
  end

  defp unify({op, _a, _b} = pattern, value, env) when op in [:add, :mul] do
    case solvable(pattern, env) do
      {:ok, ^pattern} -> equated(pattern, value, env)
      {:ok, held} -> unify(held, value, env)
      {:free, v, rebuilt} -> {:ok, Map.put(env, v, rebuilt.(term(value))), []}
      :stuck -> throw({:refused, {:unbound_variable, %{equation: pattern}}})
    end
  end

  defp unify({:papply, p, fixed}, value, env),
    do: unify({:rel, p, for(f <- fixed, do: resolve(f, env))}, value, env)

  defp unify(%View{} = a, %View{} = b, env) do
    cond do
      a == b -> {:ok, env, []}
      a.col == nil or b.col == nil -> throw({:refused, {:unliftable_term, %{term: b}}})
      View.count(b) -> unify(a, for(i <- 0..(View.count(b) - 1)//1, do: View.slice(b, i)), env)
      View.count(a) -> unify(b, for(i <- 0..(View.count(a) - 1)//1, do: View.slice(a, i)), env)
      true -> throw({:refused, {:unliftable_term, %{term: b}}})
    end
  end

  defp unify(%View{} = a, value, env) when is_list(value), do: unify(value, a, env)
  defp unify(%View{}, _value, _env), do: :dead
  defp unify({:rel, _p, _f} = a, value, env), do: if(a == value, do: {:ok, env, []}, else: :dead)
  defp unify(a, b, env), do: equated(a, b, env)

  @spec deepened(map(), atom(), integer()) :: map()
  defp deepened(env, bank, rows), do: Map.update!(env, {:bank, bank}, &max(&1, rows))

  @spec equated(value(), value(), map()) :: {:ok, map(), [Ast.pred()]} | :dead
  defp equated(a, b, env) do
    cond do
      a == b -> {:ok, env, []}
      is_integer(b) -> unify(b, a, env)
      is_list(b) or match?(%View{}, b) or match?({:rel, _p, _f}, b) -> :dead
      true -> {:ok, env, [Ast.eq(term(a), term(b))]}
    end
  end

  @spec met(value(), value(), map()) :: {:ok, map(), [Ast.pred()]} | :dead
  defp met({:fresh, ref} = fresh, value, env) do
    cell = {:cell, ref}

    case value do
      nil ->
        {:ok, Map.put(env, ref, []), []}

      :fresh ->
        {:ok, env, []}

      {:fresh, other} when is_map_key(env, other) ->
        unify(fresh, env[other], env)

      {:fresh, other} ->
        {:ok, Map.put(env, other, fresh), []}

      q when is_integer(q) ->
        {:ok, Map.put(env, ref, {:count, q, cell}), pinned(cell, q)}

      taken when is_list(taken) or is_struct(taken, View) ->
        {:ok, Map.put(env, ref, taken), []}

      {:rel, _p, _f} ->
        {:ok, Map.put(env, ref, value), []}

      term ->
        with({:ok, env, eqs} <- unify(cell, term, env), do: {:ok, Map.put(env, ref, cell), eqs})
    end
  end

  # An integer against the column pins the column; against a cell, the cell.
  @spec pinned(Ast.term_t(), integer()) :: [Ast.pred()]
  defp pinned(form, q) do
    case View.of(form) do
      %View{row: nil, col: {:x, 1, o}} -> [Ast.eq(:x, q - o)]
      _cell -> Ast.folded(Ast.eq(term(form), q))
    end
  end

  ############################################################
  #                         Framing                          #
  ############################################################

  # A callee's binding worn in the caller's frame.
  @spec framed(value(), frame()) :: value()
  defp framed({:fresh, ref}, frame), do: framed({:cell, ref}, frame)
  defp framed(form, {1, 0}), do: form
  defp framed([h | t], frame), do: [framed(h, frame) | framed(t, frame)]
  defp framed({:count, _q, form}, frame), do: framed(form, frame)
  defp framed(%View{} = view, frame), do: View.framed(view, frame)
  defp framed({:rel, _p, _f} = passed, _frame), do: passed
  defp framed(form, _frame) when is_integer(form) or form in [:fresh, []], do: form

  defp framed(form, frame) do
    Ast.postwalk(form, fn
      leaf when leaf == :x or (is_tuple(leaf) and elem(leaf, 0) == :cell) ->
        View.term(View.framed(View.of(leaf), frame))

      {:add, a, b} ->
        Ast.add(a, b)

      node ->
        node
    end)
  end

  # `framed`'s inverse: only the column and literals cross into a callee.
  @spec reframed(value(), frame()) :: value()
  defp reframed(form, {1, 0}), do: form
  defp reframed(%View{} = view, frame), do: View.reframed(view, frame)
  defp reframed({:count, _q, _cell} = count, _frame), do: count

  defp reframed(form, _frame) when is_list(form) or form == :fresh or elem(form, 0) == :rel,
    do: form

  defp reframed(form, frame) do
    with %View{row: nil} = leaf <- View.of(form),
         %View{col: {_b, _m, _a}} = worn <- View.reframed(leaf, frame) do
      View.term(worn)
    else
      _unreached -> :fresh
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
  defp resolve({:add, a, b}, env), do: Ast.add(term(resolve(a, env)), term(resolve(b, env)))
  defp resolve({:mul, a, b}, env), do: Ast.mul(term(resolve(a, env)), term(resolve(b, env)))

  defp resolve({:cons, h, t}, env) do
    case resolve(t, env) do
      tail when is_list(tail) ->
        [resolve(h, env) | tail]

      %View{} = view ->
        View.consed(view, resolve(h, env))

      _other ->
        throw({:refused, {:unliftable_term, %{term: {:cons, h, t}}}})
    end
  end

  defp resolve(value, _env), do: value

  # A side as it resolves, or the one free name it is linear in.
  @spec solvable(term(), map()) :: {:ok, value()} | {:free, atom(), (term() -> term())} | :stuck
  defp solvable(term, env) do
    {:ok, resolve(term, env)}
  catch
    {:refused, {:unbound_variable, _detail}} -> freed(term, env)
  end

  @spec freed(term(), map()) :: {:free, atom(), (term() -> term())} | :stuck
  defp freed({:var, v}, env), do: if(is_map_key(env, v), do: :stuck, else: {:free, v, & &1})

  defp freed({:add, a, b}, env) do
    case {solvable(a, env), solvable(b, env)} do
      {{:ok, ra}, {:free, v, rebuilt}} ->
        {:free, v, fn r -> rebuilt.(Ast.add(r, Ast.mul(term(ra), -1))) end}

      {{:free, v, rebuilt}, {:ok, rb}} ->
        {:free, v, fn r -> rebuilt.(Ast.add(r, Ast.mul(term(rb), -1))) end}

      _stuck ->
        :stuck
    end
  end

  defp freed(_term, _env), do: :stuck

  @spec term(value()) :: Ast.term_t()
  defp term({:count, _q, form}), do: form
  defp term({:fresh, ref}), do: {:cell, ref}

  defp term(form)
       when is_list(form) or is_struct(form, View) or (is_tuple(form) and elem(form, 0) == :rel),
       do: throw({:refused, {:unliftable_term, %{term: form}}})

  defp term(form), do: form

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
