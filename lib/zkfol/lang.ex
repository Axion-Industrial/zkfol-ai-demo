defmodule Zkfol.Lang do
  @moduledoc """
  I am the relational surface: Prolog-shaped clauses over one index,
  compiled to the core language by one rule. A relation owns an index
  row and a value row per output; every call names a pointer row,
  declared through the callee's index row, and reads the value rows
  through it as composed cells. I name those rows and never number
  them: the numbering is `Zkfol.Alloc`'s, so `compile/2` answers what
  a root stands on and `lower/2` answers the predicate once the rows
  are handed out.

      defrel fib(1, 1)
      defrel fib(2, 1)

      defrel fib(x, v) do
        fib(x - 1, v1)
        fib(x - 2, v2)
        v = v1 + v2
      end

      Lang.compile(fib())

  A body statement may also reduce: `r = mod(e, m)` at a literal `m`
  is `exists q in N. e = m*q + r and r < m`, and I own the quotient.
  """

  @behaviour Zkfol.Pipeline

  alias Zkfol.Ast
  alias Zkfol.Refusal
  alias Zkfol.Statement

  @typep env :: %{atom() => Ast.term_t()}
  @typep pointers :: {%{{atom(), Ast.term_t()} => Ast.row_ref()}, pos_integer()}
  @typep tags :: %{atom() => pos_integer()} | nil

  @typedoc """
  What a compiled root stands on, all of it symbolic: the predicate
  over named rows, the members in closure order beside their widths,
  each clause's call sites by pointer name, what each pointer aims
  at in naming order, each member's tag value (empty when a lone
  relation needs no tag), and how many slack and quotient cells a
  column holds.
  """
  @type shape :: %{
          pred: Ast.pred(),
          members: [atom()],
          arities: %{atom() => pos_integer()},
          slots: %{atom() => [atom()]},
          calls: %{atom() => [[Ast.row_ref()]]},
          pointers: [{atom(), Ast.term_t()}],
          tags: %{atom() => pos_integer()},
          slack: non_neg_integer(),
          quot: non_neg_integer()
        }

  defmodule Rel do
    @moduledoc "I am a named relation: clauses of one head shape."
    use TypedStruct

    typedstruct enforce: true do
      field(:name, atom())
      field(:arity, pos_integer())
      field(:clauses, [{[term()], [term()]}])
      field(:layout, Zkfol.Matrix.t() | nil, default: nil, enforce: false)
      field(:home, module() | nil, default: nil, enforce: false)
    end
  end

  defmacro __using__(_opts) do
    quote do
      import Zkfol.Lang, only: [defrel: 1, defrel: 2, rel: 2]
      Module.register_attribute(__MODULE__, :lang_clauses, accumulate: true)
      @before_compile Zkfol.Lang
    end
  end

  @doc "I am one clause: a bare head is a fact, a block body conjoins goals."
  defmacro defrel(head), do: store(head, [])
  defmacro defrel(head, do: block), do: store(head, lines(block))

  @doc """
  I build a relation where a function runs: clauses as defrel writes
  them, `^` splicing the surrounding scope's values in.

      Lang.rel :scaled do
        scaled(1, ^k)

        scaled(x, v) do
          scaled(x - 1, prev)
          v = ^k * prev
        end
      end
  """
  defmacro rel(name, do: block) do
    clauses = for form <- lines(block), do: rel_clause(name, form)
    arity = clauses |> hd() |> elem(0) |> length()

    quote do
      %Zkfol.Lang.Rel{
        name: unquote(name),
        arity: unquote(arity),
        clauses: unquote(Macro.escape(clauses, unquote: true)),
        home: __MODULE__
      }
    end
  end

  @spec rel_clause(atom(), Macro.t()) :: {[term()], [term()]}
  defp rel_clause(name, {name, _meta, args}) do
    args = anonymous(args)

    case List.last(args) do
      [do: block] ->
        {args |> Enum.drop(-1) |> Enum.map(&term/1), block |> lines() |> Enum.map(&goal/1)}

      _bare ->
        {Enum.map(args, &term/1), []}
    end
  end

  defp rel_clause(name, {other, _meta, _args}),
    do: raise(ArgumentError, "the clause #{other} does not belong to the relation #{name}")

  # `_` is an I-don't-care: each occurrence its own fresh name.
  @spec anonymous(Macro.t()) :: Macro.t()
  defp anonymous(ast) do
    {renamed, _n} =
      Macro.prewalk(ast, 0, fn
        {:_, meta, ctx}, n when is_atom(ctx) -> {{:"_gensym#{n}", meta, ctx}, n + 1}
        other, n -> {other, n}
      end)

    renamed
  end

  @spec store(Macro.t(), [Macro.t()]) :: Macro.t()
  defp store(head, body) do
    {name, _meta, args} = head
    {args, body} = anonymous({args, body})
    clause = {Enum.map(args, &term/1), Enum.map(body, &goal/1)}

    quote do
      @lang_clauses {unquote(name), unquote(length(args)), unquote(Macro.escape(clause))}
    end
  end

  defmacro __before_compile__(env) do
    grouped =
      env.module
      |> Module.get_attribute(:lang_clauses)
      |> Enum.reverse()
      |> Enum.group_by(fn {name, arity, _clause} -> {name, arity} end)

    rels =
      Enum.map(grouped, fn {{name, arity}, entries} ->
        clauses = for {_name, _arity, clause} <- entries, do: clause

        quote do
          def unquote(name)() do
            %Zkfol.Lang.Rel{
              name: unquote(name),
              arity: unquote(arity),
              clauses: unquote(Macro.escape(clauses)),
              home: __MODULE__
            }
          end
        end
      end)

    names = grouped |> Map.keys() |> Enum.map(&elem(&1, 0)) |> Enum.uniq()

    program =
      quote do
        @doc "I am the module as a program: `root` first, every other defrel behind it."
        @spec program(atom()) :: [Zkfol.Lang.Rel.t()]
        def program(root) do
          all = for name <- unquote(names), do: apply(__MODULE__, name, [])

          case Enum.split_with(all, &(&1.name == root)) do
            {[rooted], rest} -> [rooted | rest]
            {[], _rest} -> raise ArgumentError, "no defrel #{root} in #{inspect(__MODULE__)}"
          end
        end
      end

    rels ++ [program]
  end

  @spec lines(Macro.t()) :: [Macro.t()]
  defp lines({:__block__, _meta, goals}), do: goals
  defp lines(goal), do: [goal]

  # Surface terms: integers, variables, arithmetic, pinned values,
  # the trace length, and reified equalities.
  @spec term(Macro.t()) :: term()
  defp term({:^, _meta, [expr]}), do: {:unquote, [], [expr]}
  defp term({:len, _meta, ctx}) when is_atom(ctx), do: :len
  defp term({:reify, _meta, [inner]}), do: {:reify, goal(inner)}
  defp term(q) when is_integer(q), do: q
  defp term({name, _meta, ctx}) when is_atom(name) and is_atom(ctx), do: {:var, name}
  defp term({:+, _meta, [a, b]}), do: {:add, term(a), term(b)}
  defp term({:*, _meta, [a, b]}), do: {:mul, term(a), term(b)}
  defp term({:-, _meta, [q]}) when is_integer(q), do: -q
  defp term({:-, _meta, [a]}), do: {:mul, term(a), -1}
  defp term({:-, _meta, [a, b]}) when is_integer(b), do: {:add, term(a), -b}
  defp term({:-, _meta, [a, b]}), do: {:add, term(a), {:mul, term(b), -1}}

  # Surface goals: equations, reductions, guards, and calls.
  @spec goal(Macro.t()) :: term()
  defp goal({:=, _meta, [r, {:mod, _site, [e, m]}]}), do: {:mod, term(r), term(e), term(m)}
  defp goal({:=, _meta, [a, b]}), do: {:eq, term(a), term(b)}

  defp goal({op, _meta, [a, b]}) when op in [:<, :>, :<=, :>=],
    do: {:cmp, op, term(a), term(b)}

  defp goal({name, _meta, args}) when is_atom(name) and is_list(args),
    do: {:call, name, Enum.map(args, &term/1)}

  defp goal(form),
    do: raise(ArgumentError, "a goal is an equation or a call, not #{Macro.to_string(form)}")

  @doc "As a pass I lower a statement's relations to its shape; the first is the root."
  @impl Zkfol.Pipeline
  @spec run(Statement.t(), keyword()) :: {:ok, Statement.t()} | {:error, Refusal.t()}
  def run(%Statement{rels: []} = statement, _opts), do: {:ok, statement}

  def run(%Statement{rels: [root | _rest] = rels} = statement, _opts) do
    with {:ok, shape} <- compile(root, rels),
         do: {:ok, Statement.lowered(statement, shape)}
  end

  @impl Zkfol.Pipeline
  @spec verb() :: Zkfol.Pipeline.verdict()
  def verb, do: :lowers

  @doc """
  I am the predicate of `root` against `rels`, standing on rows: what
  `compile/2` names, `Zkfol.Alloc` numbers. Ask me when the rows are
  all you want; ask `compile/2` when you mean to allocate yourself.

      Lang.lower(fib(), [fib()])
  """
  @spec lower(Rel.t(), [Rel.t()]) :: {:ok, Ast.pred()} | {:error, Refusal.t()}
  def lower(%Rel{} = root, rels) do
    with {:ok, shape} <- compile(root, rels),
         do: Zkfol.Alloc.link(shape.pred, Zkfol.Alloc.assign(shape))
  end

  @doc """
  I compile a root relation against the relations in scope, walking
  its call closure and naming what it stands on: a relation's rows by
  its own name, the tag row, one pointer row per distinct call target.
  Which row each name lands on is `Zkfol.Alloc`'s to say, and it says
  it once the derivation is in hand; I only name.

      Lang.compile(fib())
  """
  @spec compile(Rel.t(), [Rel.t()] | nil) :: {:ok, shape()} | {:error, Refusal.t()}
  def compile(%Rel{} = root, rels \\ nil) do
    scope = Map.new(gathered(rels || [root]), &{&1.name, &1})

    with {:ok, order} <- closure([root.name], scope, MapSet.new(), []),
         tags = tags(order),
         {:ok, branches, calls, {targets, _next}} <- branches(order, scope, tags, {%{}, 1}) do
      {:ok,
       %{
         pred: Ast.disj(branches),
         members: order,
         arities: Map.new(order, &{&1, scope[&1].arity}),
         slots: Map.new(order, &{&1, slots(scope[&1])}),
         calls: calls,
         pointers: aimed(targets),
         tags: tags || %{},
         slack: widest(order, scope, &slacks/1),
         quot: widest(order, scope, &mods/1)
       }}
    end
  end

  @doc """
  I am `rels` with every relation their clauses reach: a callee the
  list misses pulls by name from the home module its defrel compiled
  in, transitively. A name no home answers stays missing, for
  `members/2` to refuse.
  """
  @spec gathered([Rel.t()]) :: [Rel.t()]
  def gathered(rels), do: gather(rels, MapSet.new(rels, & &1.name))

  defp gather(rels, seen) do
    pulled =
      for %Rel{home: home} = rel <- rels,
          home != nil,
          {_head, body} <- rel.clauses,
          {:call, name, _args} <- body,
          not MapSet.member?(seen, name),
          function_exported?(home, name, 0),
          %Rel{} = callee <- [apply(home, name, [])],
          uniq: true,
          do: callee

    case pulled do
      [] -> rels
      new -> gather(rels ++ new, MapSet.union(seen, MapSet.new(new, & &1.name)))
    end
  end

  @doc """
  I am the relations `root` reaches in `rels`, in call order: what a
  question asks, before anyone asks whether it lowers. A call to a
  relation outside `rels` refuses.
  """
  @spec members(Rel.t(), [Rel.t()]) :: {:ok, [atom()]} | {:error, Refusal.t()}
  def members(%Rel{} = root, rels),
    do: closure([root.name], Map.new(gathered(rels), &{&1.name, &1}), MapSet.new(), [])

  @doc """
  I am a clause body's slack sites in order: a guard as it stands, a
  mod site as the bound its remainder is under. The k-th takes the
  k-th slack cell, whoever reads it -- the predicate, or the lay
  that fills it.
  """
  @spec slacks([term()]) :: [{atom(), term(), term()}]
  def slacks(body), do: Enum.flat_map(body, &slacked/1)

  @doc """
  I am a clause body's mod sites in order: each remainder, dividend,
  and modulus. The k-th quotient takes the k-th quotient cell.
  """
  @spec mods([term()]) :: [{term(), term(), term()}]
  def mods(body), do: for({:mod, r, e, m} <- body, do: {r, e, m})

  @doc """
  I am a surface term's value under an environment binding its
  variables, and `:error` when the term is open: a name the
  environment does not carry, or a form that is not arithmetic. A
  reader that must tell ground from open reads me; one that knows its
  site is ground asserts on the `:ok`.
  """
  @spec value(term(), %{atom() => term()}) :: {:ok, integer()} | :error
  def value(q, _env) when is_integer(q), do: {:ok, q}
  def value({:add, t, u}, env), do: combined(&+/2, t, u, env)
  def value({:mul, t, u}, env), do: combined(&*/2, t, u, env)

  def value({:var, nm}, env) do
    case env do
      %{^nm => q} when is_integer(q) -> {:ok, q}
      _open -> :error
    end
  end

  def value(_open, _env), do: :error

  @spec combined((integer(), integer() -> integer()), term(), term(), %{atom() => term()}) ::
          {:ok, integer()} | :error
  defp combined(op, t, u, env) do
    with {:ok, a} <- value(t, env), {:ok, b} <- value(u, env), do: {:ok, op.(a, b)}
  end

  @spec slacked(term()) :: [{atom(), term(), term()}]
  defp slacked({:cmp, op, t, u}), do: [{op, t, u}]
  defp slacked({:mod, r, _e, m}), do: [{:<, r, m}]
  defp slacked(_goal), do: []

  # How many cells of a kind a column holds: the sites of one clause
  # bind together and each takes its own, while clauses share them,
  # since at most one clause binds a column.
  @spec widest([atom()], %{atom() => Rel.t()}, ([term()] -> list())) :: non_neg_integer()
  defp widest(order, scope, sites) do
    counts = for name <- order, {_head, body} <- scope[name].clauses, do: length(sites.(body))
    Enum.max(counts, fn -> 0 end)
  end

  # A member's slots by name: its head variables where a clause binds
  # them all, positional names otherwise. Freshened locals join here
  # when a clause's existential earns a row.
  @spec slots(Rel.t()) :: [atom()]
  defp slots(%Rel{arity: arity, clauses: clauses}) do
    named =
      Enum.find_value(clauses, fn {head, _body} ->
        if Enum.all?(head, &match?({:var, _}, &1)), do: for({:var, nm} <- head, do: nm)
      end)

    named || Enum.map(1..arity, &:"a#{&1}")
  end

  # The pointers in naming order, each saying its callee and address.
  @spec aimed(%{{atom(), Ast.term_t()} => Ast.row_ref()}) :: [{atom(), Ast.term_t()}]
  defp aimed(targets),
    do: targets |> Enum.sort_by(fn {_aim, {:ptr, i}} -> i end) |> Enum.map(&elem(&1, 0))

  # A lone relation is anchored by its own descent; a closure's columns
  # wear their relation, so a read can insist on whose column it reads.
  @spec tags([atom()]) :: %{atom() => pos_integer()} | nil
  defp tags([_lone]), do: nil
  defp tags(order), do: order |> Enum.with_index(1) |> Map.new()

  # The call graph, each relation once, unknown names refused.
  @spec closure([atom()], %{atom() => Rel.t()}, MapSet.t(), [atom()]) ::
          {:ok, [atom()]} | {:error, Refusal.t()}
  defp closure([], _scope, _seen, acc), do: {:ok, Enum.reverse(acc)}

  defp closure([name | rest], scope, seen, acc) do
    cond do
      MapSet.member?(seen, name) ->
        closure(rest, scope, seen, acc)

      rel = scope[name] ->
        called = for {_h, body} <- rel.clauses, {:call, n, _a} <- body, do: n
        closure(called ++ rest, scope, MapSet.put(seen, name), [name | acc])

      true ->
        {:error, {:relation_not_in_scope, %{relation: name}}}
    end
  end

  @spec branches([atom()], %{atom() => Rel.t()}, tags(), pointers()) ::
          {:ok, [Ast.pred()], %{atom() => [[Ast.row_ref()]]}, pointers()}
          | {:error, Refusal.t()}
  defp branches(order, scope, tags, pointers) do
    with {:ok, compiled, pointers} <-
           Refusal.map_reduce(order, pointers, &rel_branches(scope[&1], scope, tags, &2)),
         {branches, calls} = Enum.unzip(compiled),
         do: {:ok, Enum.concat(branches), Map.new(Enum.zip(order, calls)), pointers}
  end

  @spec rel_branches(Rel.t(), %{atom() => Rel.t()}, tags(), pointers()) ::
          {:ok, {[Ast.pred()], [[Ast.row_ref()]]}, pointers()} | {:error, Refusal.t()}
  defp rel_branches(%Rel{name: name, clauses: clauses} = rel, scope, tags, pointers) do
    with {:ok, compiled, pointers} <-
           Refusal.map_reduce(clauses, pointers, &branch(&1, cells(rel), scope, tags, &2)),
         {branches, calls} = Enum.unzip(compiled),
         do: {:ok, {Enum.map(branches, &claim(&1, name, tags)), calls}, pointers}
  end

  # A relation's rows are its own name, one per argument: the index
  # first, its values behind.
  @spec cells(Rel.t()) :: [Ast.row_ref()]
  defp cells(%Rel{name: name, arity: arity}), do: for(i <- 1..arity, do: {name, i})

  # Every branch of a tagged closure claims its column; drop the claim
  # and a column may wear one relation's tag while satisfying another's
  # branch, which is the forgery the tag exists to refuse.
  @spec claim(Ast.pred(), atom(), tags()) :: Ast.pred()
  defp claim(branch, _name, nil), do: branch

  defp claim({:conj, goals}, name, tags),
    do: Ast.conj(goals ++ [Ast.eq(Ast.cell({:tag, 1}), Map.fetch!(tags, name))])

  # One clause: the head binds the index and value rows, each call
  # binds a pointer row and its outputs, then the equations close over
  # the environment.
  @spec branch({[term()], [term()]}, [Ast.row_ref()], %{atom() => Rel.t()}, tags(), pointers()) ::
          {:ok, {Ast.pred(), [Ast.row_ref()]}, pointers()} | {:error, Refusal.t()}
  defp branch({params, body}, rows, scope, tags, pointers) do
    with :ok <- columns(params), do: branch_goals({params, body}, rows, scope, tags, pointers)
  end

  # A head names columns: variables and pinned integers, nothing computed.
  @spec columns([term()]) :: :ok | {:error, Refusal.t()}
  defp columns(params) do
    case Enum.find(params, &(not (match?({:var, _}, &1) or is_integer(&1)))) do
      nil -> :ok
      bad -> {:error, {:head_not_a_column, %{head: bad}}}
    end
  end

  @spec branch_goals(
          {[term()], [term()]},
          [Ast.row_ref()],
          %{atom() => Rel.t()},
          tags(),
          pointers()
        ) :: {:ok, {Ast.pred(), [Ast.row_ref()]}, pointers()} | {:error, Refusal.t()}
  defp branch_goals({params, body}, rows, scope, tags, pointers) do
    bound = Enum.zip(params, Enum.map(rows, &Ast.cell/1))

    env =
      bound
      |> Enum.flat_map(fn
        {{:var, name}, cell} -> [{name, cell}]
        {_literal, _cell} -> []
      end)
      |> Map.new()

    heads =
      bound
      |> Enum.flat_map(fn
        {{:var, _name}, _cell} -> []
        {literal, cell} -> [Ast.eq(cell, literal)]
      end)

    with {:ok, goals, ptrs, env, pointers} <- calls(body, scope, tags, env, pointers),
         {:ok, equations} <- equations(body, env),
         {:ok, guards} <- guards(body, env),
         {:ok, quotients} <- quotients(body, env),
         do: {:ok, {Ast.conj(heads ++ goals ++ equations ++ guards ++ quotients), ptrs}, pointers}
  end

  # Calls resolving to one target share their pointer row: a pointer
  # is a position, whoever reads through it. I also say which row each
  # call site got, in body order, so a backend reads them positionally.
  @spec calls([term()], %{atom() => Rel.t()}, tags(), env(), pointers()) ::
          {:ok, [Ast.pred()], [Ast.row_ref()], env(), pointers()} | {:error, Refusal.t()}
  defp calls(body, scope, tags, env, pointers) do
    body
    |> Enum.filter(&match?({:call, _n, _a}, &1))
    |> Refusal.map_reduce({env, pointers}, fn {:call, name, [at | outs]}, {env, pointers} ->
      [index | value_rows] = cells(scope[name])

      with {:ok, target} <- resolve(at, env),
           {row, pointers} = point(pointers, name, target),
           {:ok, identities, env} <- outputs(outs, value_rows, row, env),
           goals = [schedule(index, row, target) | check(tags, name, row)],
           do: {:ok, {goals ++ identities, row}, {env, pointers}}
    end)
    |> case do
      {:ok, compiled, {env, pointers}} ->
        {goals, ptrs} = Enum.unzip(compiled)
        {:ok, Enum.concat(goals), ptrs, env, pointers}

      refusal ->
        refusal
    end
  end

  # A tagged read insists the pointed column is the callee's.
  @spec check(tags(), atom(), Ast.row_ref()) :: [Ast.pred()]
  defp check(nil, _name, _pointer), do: []

  defp check(tags, name, pointer),
    do: [Ast.eq(Ast.cell({:tag, 1}, pointer), Map.fetch!(tags, name))]

  # Calls resolving to one target share their pointer: a pointer is a
  # position in one callee's extension, so its identity is the callee
  # beside the address -- two callees at one address are two pointers.
  @spec point(pointers(), atom(), Ast.term_t()) :: {Ast.row_ref(), pointers()}
  defp point({named, next} = pointers, callee, target) do
    case named do
      %{{^callee, ^target} => name} -> {name, pointers}
      _named -> {{:ptr, next}, {Map.put(named, {callee, target}, {:ptr, next}), next + 1}}
    end
  end

  # An affine self-call reads as the paper writes it: the index here is
  # the index there plus the offset. Anything else pins the pointed
  # index to the target directly.
  @spec schedule(Ast.row_ref(), Ast.row_ref(), term()) :: Ast.pred()
  defp schedule(index, pointer, {:add, {:cell, index}, q}) when is_integer(q),
    do: Ast.eq(Ast.cell(index), Ast.add(Ast.cell(index, pointer), -q))

  defp schedule(index, pointer, target), do: Ast.eq(Ast.cell(index, pointer), target)

  # A call's outputs are the callee's value rows read through the
  # pointer; a non-fresh output is identified with its cell by equation.
  @spec outputs([term()], [Ast.row_ref()], Ast.row_ref(), env()) ::
          {:ok, [Ast.pred()], env()} | {:error, Refusal.t()}
  defp outputs(outs, value_rows, pointer, env) do
    outs
    |> Enum.zip(value_rows)
    |> Refusal.map_reduce(env, fn {out, row}, env -> output(out, Ast.cell(row, pointer), env) end)
    |> case do
      {:ok, identities, env} -> {:ok, Enum.concat(identities), env}
      refusal -> refusal
    end
  end

  @spec output(term(), Ast.term_t(), env()) ::
          {:ok, [Ast.pred()], env()} | {:error, Refusal.t()}
  defp output({:var, name}, cell, env) when not is_map_key(env, name),
    do: {:ok, [], Map.put(env, name, cell)}

  defp output(out, cell, env) do
    with {:ok, term} <- resolve(out, env), do: {:ok, [Ast.eq(term, cell)], env}
  end

  @spec equations([term()], env()) :: {:ok, [Ast.pred()]} | {:error, Refusal.t()}
  defp equations(body, env) do
    body
    |> Enum.filter(&match?({:eq, _t, _u}, &1))
    |> Refusal.map(fn {:eq, t, u} ->
      with {:ok, t} <- resolve(t, env),
           {:ok, u} <- resolve(u, env),
           do: {:ok, Ast.eq(t, u)}
    end)
  end

  # An inequality is an equation with room in it: `a > b` says that some
  # natural s has a = b + s + 1, and the k-th slack site of a clause
  # takes the k-th slack cell to be that s. The cell is committed, so
  # its bit decomposition is the obligation that s is a natural, and
  # the site needs nothing else.
  @spec guards([term()], env()) :: {:ok, [Ast.pred()]} | {:error, Refusal.t()}
  defp guards(body, env) do
    body
    |> slacks()
    |> Enum.with_index(1)
    |> Refusal.map(fn {{op, t, u}, k} ->
      with {:ok, t} <- resolve(t, env),
           {:ok, u} <- resolve(u, env),
           do: {:ok, slack(op, t, u, Ast.cell({:slack, k}))}
    end)
  end

  @spec slack(atom(), Ast.term_t(), Ast.term_t(), Ast.term_t()) :: Ast.pred()
  defp slack(:>, a, b, s), do: Ast.eq(a, Ast.add(Ast.add(b, 1), s))
  defp slack(:>=, a, b, s), do: Ast.eq(a, Ast.add(b, s))
  defp slack(:<, a, b, s), do: slack(:>, b, a, s)
  defp slack(:<=, a, b, s), do: slack(:>=, b, a, s)

  # `r = mod(e, m)` is the division it means: the k-th quotient cell is
  # the q of e = m*q + r, committed, so its bits are the q in N, while
  # `r < m` rides the slack every site takes. A modulus that is not a
  # literal makes m*q a product of two unknowns, which nothing here
  # can suspend.
  @spec quotients([term()], env()) :: {:ok, [Ast.pred()]} | {:error, Refusal.t()}
  defp quotients(body, env) do
    body
    |> mods()
    |> Enum.with_index(1)
    |> Refusal.map(fn {{r, e, m}, k} ->
      with :ok <- literal(m),
           {:ok, r} <- resolve(r, env),
           {:ok, e} <- resolve(e, env),
           do: {:ok, Ast.eq(e, Ast.add(Ast.mul(Ast.cell({:quot, k}), m), r))}
    end)
  end

  @spec literal(term()) :: :ok | {:error, Refusal.t()}
  defp literal(m) when is_integer(m), do: :ok
  defp literal(m), do: {:error, {:modulus_not_literal, %{modulus: m}}}

  @spec resolve(term(), env()) :: {:ok, Ast.term_t()} | {:error, Refusal.t()}
  defp resolve(q, _env) when is_integer(q), do: {:ok, q}
  defp resolve(:len, _env), do: {:ok, :len}

  defp resolve({:reify, {:eq, t, u}}, env) do
    with {:ok, rt} <- resolve(t, env),
         {:ok, ru} <- resolve(u, env),
         do: {:ok, Ast.arithmetize(Ast.eq(rt, ru))}
  end

  defp resolve({:var, name}, env) do
    case env do
      %{^name => bound} -> {:ok, bound}
      _env -> {:error, {:unbound_variable, %{variable: name}}}
    end
  end

  defp resolve({:add, a, b}, env) do
    with {:ok, a} <- resolve(a, env),
         {:ok, b} <- resolve(b, env),
         do: {:ok, Ast.add(a, b)}
  end

  defp resolve({:mul, a, b}, env) do
    with {:ok, a} <- resolve(a, env),
         {:ok, b} <- resolve(b, env),
         do: {:ok, Ast.mul(a, b)}
  end

  # reify takes an equation; the surface admits reify of a call, which
  # would need a derivation to stand where a term does.
  defp resolve(term, _env), do: {:error, {:unliftable_term, %{term: term}}}
end
