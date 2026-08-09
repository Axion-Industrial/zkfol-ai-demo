defmodule Zkfol.Al do
  @moduledoc """
  I am the AL backend: a statement becomes clauses and runs, so the
  witness is the derivation's own trace, judged by the oracle. The
  quantifier over columns is the recursion, the disjuncts are the
  clauses, the claims are the query, and every equation is emitted in
  each direction it can run, frozen on its inputs: the runtime
  schedules, whichever side arrives drives, and the rest wake as
  checks. A read row nothing determines is refused as the prover's
  knowledge.
  """

  import Kernel, except: [apply: 3]

  alias Zkfol.Al.Ask
  alias Zkfol.Lang
  alias Zkfol.Lang.Rel
  alias Zkfol.Ast
  alias Zkfol.Refusal
  alias Zkfol.Interpretation
  alias Zkfol.Log
  alias Zkfol.Semantics
  alias Zkfol.Statement

  @class :zkfol

  @typedoc "An emitted AL program: goal structs ready for AL.eval/3."
  @type program :: [struct()]

  @typep plan :: %{
           rows: [pos_integer()],
           schedules: %{pos_integer() => pos_integer()},
           window: non_neg_integer(),
           dynamic: [pos_integer()],
           len?: boolean(),
           arity: pos_integer(),
           asked: [pos_integer()],
           counter: :row | :argument
         }

  @typep bind :: %{optional(pos_integer()) => integer()}

  @doc """
  I emit the AL program of a relation under its own name, or refuse
  with the reason.

      translate(Examples.EUser.regs())
  """
  @spec translate(Rel.t() | [Rel.t()], atom() | nil) :: {:ok, program()} | {:error, Refusal.t()}
  def translate(target, name \\ nil)

  def translate(%Rel{} = root, name), do: translate([root], name)

  def translate([%Rel{} | _rest] = rels, name) do
    with {:ok, program, _plan} <- clauses_program(rels, name || hd(rels).name),
         do: {:ok, program}
  end

  @doc """
  I emit the question program of a relation: the clauses as plain AL,
  no witness laid out.

      question(Examples.EUser.fib())
  """
  @spec question(Rel.t() | [Rel.t()]) :: {:ok, program()} | {:error, Refusal.t()}
  def question(%Rel{} = root), do: question([root])
  def question([%Rel{} | _rest] = rels), do: question_program(rels)

  @doc """
  I derive every answer at `arguments`, naming the ones I report.

      apply(Examples.EUser.fib(), [5, :a])
      apply(Examples.EUser.fib(), [:n, :a], upto: 6)

  An integer pins a row as `solve/3` does. An atom names a row and comes
  back under that name in every answer; `:_` leaves a row free and
  unreported. Where `solve/3` stops at the first derivation, I report
  every one over the indices asked for: a free index has no last answer,
  so `:upto` says how far to look and is required when index one is not
  pinned. Each count runs as its own eval, renewing the reduction
  budget as solve's deepening does.
  """
  @spec apply(Statement.t() | Rel.t() | [Rel.t()], [integer() | atom()], keyword()) ::
          {:ok, [%{atom() => integer()}]} | {:error, Refusal.t()}
  def apply(target, arguments, opts \\ [])

  def apply(%Statement{rels: [_ | _] = rels}, args, opts), do: apply_rels(rels, args, opts)
  def apply(%Rel{} = root, args, opts), do: apply_rels([root], args, opts)
  def apply([%Rel{} | _rest] = rels, args, opts), do: apply_rels(rels, args, opts)
  def apply(_target, _args, _opts), do: {:error, {:no_relations, %{}}}

  @doc """
  I open a stepping ask at `arguments`: the question of `target` as
  plain AL, installed on a branch of my own, and the goal that runs
  against it. Nothing derives yet.

      {:ok, ask} = open(Examples.EAl.tab(), [:_, :_], [])

  `arguments` address the root relation's head rows in order as
  `solve/3` does, `:_` free. Where `apply/3` collects every answer at
  once, I hand them over one at a time: `step/1` takes the next,
  `close/1` discards the branch. `:branch` says what to fork from,
  `:heap` bounds the install.

  The ask holds AL's search state, so the process that opens it is
  the process that must step it.
  """
  @spec open(Rel.t() | [Rel.t()], [integer() | :_], keyword()) ::
          {:ok, Ask.t()} | {:error, Refusal.t()}
  def open(%Rel{} = root, arguments, opts), do: open([root], arguments, opts)

  def open([%Rel{} = root | _rest] = rels, arguments, opts) do
    branch = AL.Branch.fork(:tip, based(landing(Keyword.get(opts, :branch))))
    bind = for {a, row} <- Enum.with_index(arguments, 1), a != :_, into: %{}, do: {row, a}
    args = Enum.map(1..root.arity, &Map.get(bind, &1, v(:"qa#{&1}")))

    with {:ok, program} <- question_program(rels),
         :ok <- install(program, branch, Keyword.get(opts, :heap, 256_000_000)) do
      {:ok,
       %Ask{
         name: root.name,
         rels: rels,
         goal: [AL.ast_to_pattern({root.name, [], [@class | args]})],
         arguments: arguments,
         branch: branch
       }}
    else
      {:error, _reason} = refusal ->
        AL.Branch.discard(branch)
        refusal
    end
  end

  def open([], _arguments, _opts), do: {:error, {:no_relations, %{}}}

  @doc """
  I take the ask's next answer, and the ask to step again: the
  argument list with every free row ground. The search runs out as
  `:exhausted`; a row it leaves open is residue, not an answer. The
  ask advances whenever AL did, so a refused step is stepped past
  rather than asked again.
  """
  @spec step(Ask.t()) :: {Ask.outcome(), Ask.t()}
  def step(%Ask{state: nil} = ask), do: answered(AL.eval(ask.goal, nil, ask.branch, []), ask)
  def step(%Ask{state: state} = ask), do: answered(AL.next_solution(state), ask)

  @doc "I discard the ask's branch: the install and its journal go with it."
  @spec close(Ask.t()) :: :ok
  def close(%Ask{branch: branch}), do: AL.Branch.discard(branch)

  # AL's outcome for one step. The state stays in this process; only
  # the bindings are read, and they are the answer.
  @spec answered(term(), Ask.t()) :: {Ask.outcome(), Ask.t()}
  defp answered({:atomic, {bindings, state}}, ask),
    do: {ground(bindings, ask.arguments), %{ask | state: state}}

  defp answered({:aborted, %{reason: {:resource_limit_exceeded, n}}}, ask),
    do: {{:error, {:unresolved_within_budget, %{reductions: n}}}, ask}

  defp answered({:aborted, _reason}, ask), do: {:exhausted, ask}
  defp answered(exceeded, ask), do: {Refusal.from_al(exceeded), ask}

  # The answer: a bound argument as it was asked, a free one as the
  # search ground it. An answer is every asked row ground, so a row
  # the search left open under its constraints refuses as residue.
  @spec ground(AL.Var.bindings(), [integer() | :_]) ::
          {:ok, [integer()]} | {:error, Refusal.t()}
  defp ground(bindings, arguments) do
    answer =
      for {argument, row} <- Enum.with_index(arguments, 1) do
        if argument == :_,
          do: bindings |> AL.Var.deref(:"$qa#{row}") |> AL.Var.subst(bindings),
          else: argument
      end

    if Enum.all?(answer, &is_integer/1),
      do: {:ok, answer},
      else: {:error, {:residue, %{answer: answer}}}
  end

  # What a fresh branch forks from: the session's head unless one is named.
  @spec based(term() | nil) :: AL.Branch.t()
  defp based(nil), do: AL.Branch.head()
  defp based(id), do: %AL.Branch{id: id}

  @spec apply_rels([Rel.t()], [integer() | atom()], keyword()) ::
          {:ok, [%{atom() => integer()}]} | {:error, Refusal.t()}
  defp apply_rels([_, _ | _] = _rels, _args, _opts),
    do: {:error, {:calls_between_relations, %{}}}

  defp apply_rels(rels, args, opts) do
    name = Keyword.get(opts, :name, hd(rels).name)

    with {:ok, program, plan} <- clauses_program(rels, name),
         {:ok, bind} <- bind(plan.rows, args, opts),
         {:ok, counts} <- span(hd(args), opts) do
      names = for a <- args, is_atom(a) and a != :_, do: a
      answers(program, &every(name, &1, bind, names, plan, args), counts, names, opts)
    end
  end

  # A free index has no last answer, so the caller says how far to look.
  # Without one this walks deeper derivations until the heap stops it.
  @spec span(integer() | atom(), keyword()) :: {:ok, Enumerable.t()} | {:error, Refusal.t()}
  defp span(index, _opts) when is_integer(index), do: {:ok, [index]}

  defp span(_index, opts) do
    case Keyword.fetch(opts, :upto) do
      {:ok, upto} -> {:ok, 1..upto}
      :error -> {:error, {:free_index_needs_a_bound, %{}}}
    end
  end

  # The query solve/3 would make at one count, under a findall that
  # keeps each answer; a named or free index pins to the count by
  # unification, an integer one arrived bound through bind/3.
  @spec every(atom(), pos_integer(), bind(), [atom()], plan(), [integer() | atom()]) ::
          [struct()]
  defp every(name, count, bind, names, plan, args) do
    slots = Enum.zip(plan.rows, args ++ Stream.cycle([:_]))

    goal =
      Enum.map(slots, fn
        {_row, a} when is_atom(a) and a != :_ -> v(a)
        {row, _} -> Map.get(bind, row, v(row(row, "c")))
      end)

    [index | _rest] = goal
    pin = if is_integer(index), do: [], else: [quote(do: unify(unquote(index), unquote(count)))]

    call = {name, [], [@class | goal ++ if(plan.len?, do: [index], else: []) ++ [v(:t)]]}
    template = Enum.map(names, &v/1)

    [AL.ast_to_pattern(quote(do: findall(unquote(template), unquote(pin ++ [call]), rs)))]
  end

  # One eval per count, as solve deepens: each candidate renews the
  # reduction budget one `between` over the range would exhaust.
  @spec answers([struct()], (pos_integer() -> [struct()]), Enumerable.t(), [atom()], keyword()) ::
          {:ok, [%{atom() => integer()}]} | {:error, Refusal.t()}
  defp answers(program, query_at, counts, names, opts) do
    heap = Keyword.get(opts, :heap, 256_000_000)

    AL.Branch.on(landing(Keyword.get(opts, :branch)), fn branch ->
      with :ok <- install(program, branch, heap) do
        Enum.reduce_while(counts, {:ok, []}, fn count, {:ok, acc} ->
          case AL.eval(query_at.(count), nil, branch, heap: heap) do
            {:atomic, {bindings, _}} ->
              rows = bindings |> AL.Var.deref(:"$rs") |> AL.Var.subst(bindings)
              {:cont, {:ok, acc ++ for(row <- rows, do: names |> Enum.zip(row) |> Map.new())}}

            {:aborted, _reason} ->
              {:cont, {:ok, acc}}

            exceeded ->
              {:halt, Refusal.from_al(exceeded)}
          end
        end)
      end
    end)
  end

  # An install that cannot land refuses; the caller owns the branch.
  @spec install(program(), AL.Branch.t(), pos_integer()) :: :ok | {:error, Refusal.t()}
  defp install(program, branch, heap) do
    case AL.eval(program, nil, branch, heap: heap) do
      {:atomic, _} -> :ok
      {:aborted, reason} -> {:error, {:send_failed, %{reason: reason}}}
      exceeded -> Refusal.from_al(exceeded)
    end
  end

  @doc """
  I derive the witness at `arguments`, or refuse with the reason.

      solve(Examples.EUser.fib(), [8])
      solve(kernel_statement, [:_, n - 2])
      solve(Examples.EFacts.factorial(), [6], branch: :head)

  `arguments` address the relation's own rows in order -- for a closure
  the root's, the list reading root-first-then-scope as a statement's
  rels do -- whatever claims a pass may have hung on the statement; `:_`
  leaves a row free, and `:bind` names a row directly when counting to
  it is unpleasant. The recursion count is always row one: bound, it
  runs once at that count. Free, the clauses are asked plainly first
  -- no trace, no size -- and the answer's ground values pin the
  derivation; what the question cannot ground, the structural ask
  resolves. A question that fails finitely refuses as no_answer; one
  that outruns its budgets refuses by the budget; nothing searches by
  witness size. `:bind` fixes rows directly, merged over whatever
  `arguments` bound. `:branch` keeps the install, `:heap` bounds the
  derivation, `:basedon` bases the journaled derivation, landing it
  on that act's trail.
  """
  @spec solve(Ast.pred() | Statement.t() | Rel.t() | [Rel.t()], [integer() | :_], keyword()) ::
          {:ok, Interpretation.t()} | {:error, Refusal.t()}
  def solve(target, arguments, opts \\ [])

  def solve(%Statement{rels: [_ | _] = rels} = statement, args, opts),
    do: solve_rels(rels, statement, args, opts)

  def solve(%Statement{}, _args, _opts), do: {:error, {:no_relations, %{}}}

  def solve(%Rel{} = root, args, opts), do: solve_rels([root], [root], args, opts)
  def solve([%Rel{} | _rest] = rels, args, opts), do: solve_rels(rels, rels, args, opts)
  def solve([], _args, _opts), do: {:error, {:no_relations, %{}}}

  def solve({tag, _parts}, _arguments, _opts) when tag in [:conj, :disj],
    do: {:error, {:raw_predicate_has_no_clauses, %{}}}

  def solve({:eq, _t, _u}, _arguments, _opts),
    do: {:error, {:raw_predicate_has_no_clauses, %{}}}

  # Row 1 is always the recursion driver (rel_plan/1 puts it first, and
  # every clause head reads it as the count), so a bound row 1 is a
  # bound trace length; anything else has to deepen for it.
  @spec solve_rels([Rel.t()], Statement.t() | [Rel.t()], [integer() | :_], keyword()) ::
          {:ok, Interpretation.t()} | {:error, Refusal.t()}
  defp solve_rels(rels, target, args, opts) do
    opts = Keyword.put_new(opts, :name, hd(rels).name)

    with {:ok, program, plan} <- clauses_program(rels, Keyword.fetch!(opts, :name)),
         {:ok, pred} <- target_pred(target),
         {:ok, bind} <- bind(plan.asked, args, opts) do
      AL.Branch.on(landing(Keyword.get(opts, :branch)), fn branch ->
        with {:ok, bind, counts} <- question(rels, plan, bind, opts, branch) do
          run_installed(program, pred, plan, counts, bind, opts, branch)
        end
      end)
    end
  end

  # With the count bound the trace machinery knows what to do; len is
  # the trace length, which only a bound count names. Anything else
  # asks the question first: what it grounds is bound, a lone answer's
  # index is the count, and past the question only the structural ask
  # remains -- nothing searches by witness size.
  @spec question([Rel.t()], plan(), bind(), keyword(), AL.Branch.t()) ::
          {:ok, bind(), [pos_integer()]} | {:error, Refusal.t()}
  defp question(rels, plan, bind, opts, branch) do
    cond do
      is_map_key(bind, 1) ->
        {:ok, bind, [Map.fetch!(bind, 1)]}

      Enum.any?(rels, &mentions_len?(&1.clauses)) ->
        {:error, {:len_needs_a_bound_count, %{}}}

      true ->
        case asked(rels, plan, bind, opts, branch) do
          {:ok, bind} ->
            counts =
              if plan.counter == :row and is_map_key(bind, 1),
                do: [Map.fetch!(bind, 1)],
                else: []

            {:ok, bind, counts}

          :unresolved ->
            {:ok, bind, []}

          {:error, _reason} = refusal ->
            refusal
        end
    end
  end

  # The predicate rides the stage once a statement is lowered, so a
  # closure walk here would be the second of two. Only a raw target
  # still has to compile.
  @spec target_pred(Statement.t() | [Rel.t()]) :: {:ok, Ast.pred()} | {:error, Refusal.t()}
  defp target_pred(%Statement{stage: :raw, rels: [root | _rest] = rels}),
    do: with({:ok, %{pred: pred}} <- Lang.compile(root, rels), do: {:ok, pred})

  defp target_pred(%Statement{} = statement), do: {:ok, Statement.pred(statement)}

  defp target_pred([root | _rest] = rels),
    do: with({:ok, %{pred: pred}} <- Lang.compile(root, rels), do: {:ok, pred})

  # Rows `args` left bound, skipping `:_`, under any `opts[:bind]` override.
  # An argument past the last row addresses nothing, and zipping it away
  # would answer a question no one asked.
  @spec bind([pos_integer()], [integer() | atom()], keyword()) ::
          {:ok, bind()} | {:error, Refusal.t()}
  defp bind(rows, args, _opts) when length(args) > length(rows),
    do: {:error, {:arguments_exceed_rows, %{args: length(args), rows: length(rows)}}}

  defp bind(rows, args, opts) do
    {:ok,
     rows
     |> Enum.zip(args)
     |> Enum.reject(fn {_row, a} -> is_atom(a) end)
     |> Map.new()
     |> Map.merge(Keyword.get(opts, :bind, %{}))}
  end

  # The pred the stage already carries; compiled only when none does.
  # A free pointer left unbound by everything else enumerates the
  # columns below.
  @spec enumerations(plan()) :: [Macro.t()]
  defp enumerations(plan) do
    for j <- plan.dynamic do
      c = v(row(j, "c"))
      quote(do: alternative([vm_ground(unquote(c))], [between(self, 1, x1, unquote(c))]))
    end
  end

  # A step descends and recurses; the relation's own guard is what stops
  # it past the base, its descent and equations wait frozen for whichever
  # side arrives, derefs wait on the trace, and a free pointer enumerates.
  @spec step(atom(), [Macro.t()], [Macro.t()], [Macro.t()], plan()) :: Macro.t()
  defp step(name, head, current, defining, plan) do
    body =
      quote do
        unquote_splicing(AL.Equations.equation(:x1, [:add, :x, -1], "ix"))
        unquote_splicing(defining)
        unquote(recurse(name, plan))
        unquote_splicing(unpack(plan) ++ enumerations(plan))
      end

    defmethod(name, head ++ [[{:|, [], [current, v(:t)]}]], body)
  end

  # A base pinned at column one is the trace's terminal; pinned any
  # higher it constrains its column and keeps descending.
  @spec pinned(atom(), [Macro.t()], [Macro.t()], [Macro.t()], integer(), plan()) :: Macro.t()
  defp pinned(name, head, current, defining, 1, _plan),
    do: defmethod(name, head ++ [[current]], {:__block__, [], defining})

  defp pinned(name, head, current, defining, pin, plan) do
    body =
      quote do
        unify(x1, unquote(pin - 1))
        unquote_splicing(defining)
        unquote(recurse(name, plan))
      end

    defmethod(name, head ++ [[{:|, [], [current, v(:t)]}]], body)
  end

  @spec defmethod(atom(), [Macro.t()], Macro.t()) :: Macro.t()
  defp defmethod(name, head, body), do: {:defmethod, [], [@class, name, head, [do: body]]}

  # Row one carries the descent: the next level's index is this one's
  # x1, which is what makes the step descend at all. Window rows above
  # one come off the previous slot.
  @spec recurse(atom(), plan()) :: Macro.t()
  defp recurse(name, plan) do
    args =
      Enum.map(plan.rows, fn
        1 -> v(:x1)
        r -> v(row(r, "p1"))
      end) ++ if(plan.len?, do: [v(:len)], else: [])

    {name, [], [v(:self) | args] ++ [v(:t)]}
  end

  # Columns beyond the first live in the trace; one unification reads them all.
  @spec unpack(plan()) :: [Macro.t()]
  defp unpack(%{window: w}) when w < 2, do: []

  defp unpack(plan) do
    rows = Enum.map(1..plan.window, fn k -> Enum.map(plan.rows, &v(row(&1, "p#{k}"))) end)
    {init, [last]} = Enum.split(rows, plan.window - 1)
    pattern = init ++ [{:|, [], [last, v(:deeper)]}]
    [quote(do: unify(unquote(pattern), t))]
  end

  # A program: the class, the retraction preamble, then the clauses.
  @spec installed(atom() | [atom()], [Macro.t()]) :: program()
  defp installed(name, clauses) when is_atom(name), do: installed([name], clauses)

  defp installed(names, clauses) do
    retractions =
      for name <- names do
        quote do
          forall([vm_method(unquote(@class), unquote(name), impl), vm_clause(impl, h, _b)]) do
            vm_retract_oapply(impl, h)
          end
        end
      end

    program =
      quote do
        vm_set_class(unquote(@class), :object)
        unquote_splicing(retractions ++ clauses)
      end

    AL.ast_to_pattern(program)
  end

  # --- the question: the clauses as plain AL, no witness laid out ---

  # A question asks what is derivable without laying anything out: the
  # clauses go down as written, calls in body order, equations and
  # guards frozen in both directions. len names the trace, which a
  # question does not have, so len keeps the traced path.
  @spec question_program([Rel.t()]) :: {:ok, program()} | {:error, Refusal.t()}
  defp question_program(rels) do
    if Enum.any?(rels, &mentions_len?(&1.clauses)) do
      {:error, {:len_needs_a_bound_count, %{}}}
    else
      question_clauses(rels)
    end
  end

  @spec question_clauses([Rel.t()]) :: {:ok, program()} | {:error, Refusal.t()}
  defp question_clauses(rels) do
    rels
    |> Enum.flat_map(fn rel -> Enum.map(rel.clauses, &{rel.name, &1}) end)
    |> Enum.with_index()
    |> Refusal.map(fn {{rname, clause}, i} -> question_clause(rname, clause, i) end)
    |> case do
      {:ok, clauses} -> {:ok, installed(Enum.map(rels, & &1.name), clauses)}
      refusal -> refusal
    end
  end

  @spec question_clause(atom(), {[term()], [term()]}, non_neg_integer()) ::
          {:ok, Macro.t()} | {:error, Refusal.t()}
  defp question_clause(rname, {head, body}, i) do
    env = [head | Enum.map(body, &Tuple.to_list/1)] |> qvars() |> Map.new(&{&1, &1})
    params = Enum.map(head, &qterm/1)

    {calls, defs} =
      body
      |> Enum.filter(&match?({:call, _n, _a}, &1))
      |> Enum.with_index()
      |> Enum.map_reduce([], fn {{:call, n, args}, j}, defs ->
        {args, defs} = qargs(args, i, j, env, defs)
        {{n, [], [v(:self) | args]}, defs}
      end)

    with {:ok, guards} <- rel_guards(body, env),
         {:ok, equations} <- rel_equations(body, i, env) do
      goals = {:__block__, [], defs ++ guards ++ equations ++ calls}
      {:ok, defmethod(rname, [v(:self) | params], goals)}
    end
  end

  # A call argument beyond a variable or literal computes through a
  # fresh name, its equation frozen in both directions.
  @spec qargs([term()], non_neg_integer(), non_neg_integer(), map(), [Macro.t()]) ::
          {[Macro.t()], [Macro.t()]}
  defp qargs(args, i, j, env, defs) do
    args
    |> Enum.with_index()
    |> Enum.map_reduce(defs, fn
      {{:var, nm}, _k}, defs ->
        {v(nm), defs}

      {q, _k}, defs when is_integer(q) ->
        {q, defs}

      {expr, k}, defs ->
        fresh = :"q#{i}c#{j}a#{k}"
        {:ok, prefix} = rel_prefix(expr, env)
        {v(fresh), defs ++ AL.Equations.equation(fresh, prefix, "qq#{i}#{j}#{k}")}
    end)
  end

  @spec qterm(term()) :: Macro.t()
  defp qterm({:var, nm}), do: v(nm)
  defp qterm(q), do: q

  @spec qvars(term()) :: [atom()]
  defp qvars({:var, nm}), do: [nm]
  defp qvars(t) when is_tuple(t), do: t |> Tuple.to_list() |> qvars()
  defp qvars(t) when is_list(t), do: Enum.uniq(Enum.flat_map(t, &qvars/1))
  defp qvars(_t), do: []

  # Ask the question at the root, free rows genuinely free; every
  # integer the answer grounds binds its row for the trace to come.
  @spec asked([Rel.t()], plan(), bind(), keyword(), AL.Branch.t()) ::
          {:ok, bind()} | :unresolved | {:error, Refusal.t()}
  defp asked(rels, plan, bind, opts, branch) do
    with {:ok, program} <- question_program(rels) do
      name = hd(rels).name
      args = Enum.map(plan.asked, fn r -> Map.get(bind, r, v(:"qa#{r}")) end)
      query = [AL.ast_to_pattern({name, [], [@class | args]})]
      heap = Keyword.get(opts, :heap, 256_000_000)

      with :ok <- install(program, branch, heap) do
        case AL.eval(query, nil, branch, heap: heap) do
          {:atomic, {bindings, _state}} ->
            ground =
              for r <- plan.asked,
                  not is_map_key(bind, r),
                  value = bindings |> AL.Var.deref(:"$qa#{r}") |> AL.Var.subst(bindings),
                  is_integer(value),
                  do: {r, value}

            {:ok, Map.merge(bind, Map.new(ground))}

          {:aborted, %{reason: {:resource_limit_exceeded, _n}}} ->
            :unresolved

          {:aborted, _reason} ->
            {:error, {:no_answer, %{relation: name}}}

          _exceeded ->
            :unresolved
        end
      end
    end
  end

  # --- clauses, directly: a relation is nearly the program ---

  # One self-recursive relation as before; a closure takes its own path.
  @spec clauses_program([Rel.t()], atom()) ::
          {:ok, program(), plan()} | {:error, Refusal.t()}
  defp clauses_program([%Rel{} = rel], name) do
    with :ok <- lone([], rel),
         {:ok, plan, computed} <- rel_plan(rel),
         {:ok, clauses} <- rel_clauses(rel, name, plan, computed),
         do: {:ok, installed(name, clauses), plan}
  end

  defp clauses_program([%Rel{} | _rest] = rels, name), do: closure_program(rels, name)

  @spec lone([Rel.t()], Rel.t()) :: :ok | {:error, Refusal.t()}
  defp lone([], %Rel{name: name, clauses: clauses}) do
    called = for {_head, body} <- clauses, {:call, n, _args} <- body, uniq: true, do: n

    case called do
      [^name] -> :ok
      [] -> :ok
      _other -> {:error, {:calls_between_relations, %{}}}
    end
  end

  defp lone(_rest, _rel),
    do: {:error, {:calls_between_relations, %{}}}

  # A closure runs as one chain over one trace, every element the
  # closure's full width, each column filled by whichever member's
  # clause fires: a fact grounds its own slice and pads the rest, the
  # root's rule reads its callees through Lang's pointer rows -- at
  # targets the head determines or an earlier call's output binds.
  # A member calling itself still awaits by name.
  @spec closure_program([Rel.t()], atom()) ::
          {:ok, program(), plan()} | {:error, Refusal.t()}
  defp closure_program([root | _rest] = rels, name) do
    with {:ok, table} <- Lang.compile(root, rels) do
      case Enum.filter(rels, &is_map_key(table.rows, &1.name)) do
        [lone] ->
          clauses_program([lone], name)

        members ->
          with :ok <- closed(members),
               {:ok, clauses} <-
                 closure_clauses(members, name, closure_plan(members, table), table),
               do: {:ok, installed(name, clauses), closure_plan(members, table)}
      end
    end
  end

  @spec closed([Rel.t()]) :: :ok | {:error, Refusal.t()}
  defp closed(rels) do
    names = MapSet.new(rels, & &1.name)

    ok? =
      Enum.all?(rels, fn rel ->
        Enum.all?(rel.clauses, fn
          {head, []} ->
            Enum.all?(head, &is_integer/1)

          {head, body} ->
            Enum.all?(head, &match?({:var, _}, &1)) and
              Enum.all?(body, fn
                {:call, n, [_at | outs]} ->
                  n != rel.name and n in names and
                    Enum.all?(outs, &match?({:var, _}, &1))

                _goal ->
                  true
              end)
        end)
      end)

    if ok?, do: :ok, else: {:error, {:calls_between_relations, %{}}}
  end

  # Lang's allocation, taken whole: the trace is the closure's width,
  # the pointer rows ride in it, and no row is the count.
  @spec closure_plan([Rel.t()], map()) :: plan()
  defp closure_plan(rels, table) do
    %{
      rows: Enum.to_list(1..table.width),
      schedules: %{},
      window: 0,
      dynamic: table.pointers |> Map.values() |> Enum.sort(),
      len?: Enum.any?(rels, &mentions_len?(&1.clauses)),
      arity: table.width,
      asked: Map.fetch!(table.rows, hd(rels).name),
      counter: :argument
    }
  end

  @spec closure_clauses([Rel.t()], atom(), plan(), map()) ::
          {:ok, [Macro.t()]} | {:error, Refusal.t()}
  defp closure_clauses([root | _rest] = rels, name, plan, table) do
    {terminals, mids} =
      Enum.unzip(
        for rel <- rels, {head, []} <- rel.clauses do
          fact_clauses(name, rel.name, head, plan, table)
        end
      )

    rules =
      for rel <- rels,
          {{_head, [_ | _]} = clause, ptrs} <-
            Enum.zip(rel.clauses, Map.fetch!(table.calls, rel.name)),
          do: {rel.name, clause, ptrs}

    rules
    |> Enum.with_index()
    |> Refusal.map(fn {{rname, clause, ptrs}, i} ->
      member_rule(clause, ptrs, i, name, plan, table, rname, rname == root.name)
    end)
    |> case do
      # Every terminal before any mid: a free counter descends
      # depth-first, and each level must see every bottom before it
      # deepens, or the first mid-chain swallows the search whole.
      {:ok, rules} -> {:ok, terminals ++ mids ++ rules}
      refusal -> refusal
    end
  end

  # A fact holds at any column: terminal at one, mid-chain above it.
  # Its own slice is the fact, other slices pad zero, and a pointer
  # cell pads one to stay a column.
  @spec fact_clauses(atom(), atom(), [term()], plan(), map()) :: {Macro.t(), Macro.t()}
  defp fact_clauses(name, rel_name, head, plan, table) do
    filled = table.rows |> Map.fetch!(rel_name) |> Enum.zip(head) |> Map.new()

    cells =
      Enum.map(plan.rows, fn r ->
        cond do
          is_map_key(filled, r) -> Map.fetch!(filled, r)
          r == table.tag -> Map.fetch!(table.tags, rel_name)
          r in plan.dynamic -> 1
          true -> 0
        end
      end)

    len = if plan.len?, do: [v(:len)], else: []

    mid =
      quote do
        freeze(x, [x > 1])
        unquote_splicing(AL.Equations.equation(:x1, [:add, :x, -1], "ix"))
        unquote({name, [], [v(:self), v(:x1)] ++ len ++ [v(:t)]})
      end

    {defmethod(name, [v(:self), 1 | len] ++ [[cells]], {:__block__, [], []}),
     defmethod(name, [v(:self), v(:x) | len] ++ [[{:|, [], [cells, v(:t)]}]], mid)}
  end

  # A member's rule: its own rows as cells, its calls as frozen reads
  # through the pointer rows, its equations and guards as everywhere.
  # The root's index chains to the column; any other member's floats,
  # bound top-down by whoever reads it.
  @spec member_rule(
          {[term()], [term()]},
          [pos_integer()],
          non_neg_integer(),
          atom(),
          plan(),
          map(),
          atom(),
          boolean()
        ) ::
          {:ok, Macro.t()} | {:error, Refusal.t()}
  defp member_rule({head, body}, ptrs, i, name, plan, table, rname, root?) do
    block = Map.fetch!(table.rows, rname)
    [{:var, index} | outs_h] = head
    carrier = if root?, do: :x, else: row(hd(block), "c")

    env =
      [
        {index, carrier}
        | for({{:var, nm}, r} <- Enum.zip(outs_h, tl(block)), do: {nm, row(r, "c")})
      ]
      |> Map.new()

    calls = for {:call, n, [at | outs]} <- body, do: {n, at, outs}
    {env, derefs, used} = closure_derefs(calls, ptrs, env, plan, table)

    cells =
      Enum.map(plan.rows, fn r ->
        cond do
          r == hd(block) and root? -> v(:x)
          r in block or r in used -> v(row(r, "c"))
          r == table.tag -> Map.fetch!(table.tags, rname)
          r in plan.dynamic -> 1
          true -> 0
        end
      end)

    len = if plan.len?, do: [v(:len)], else: []
    enums = for ptr <- used, do: quote(do: between(self, 1, x1, unquote(v(row(ptr, "c")))))

    with {:ok, guards} <- rel_guards(body, env),
         {:ok, equations} <- rel_equations(body, i, env) do
      goals =
        quote do
          freeze(x, [x > 1])
          unquote_splicing(AL.Equations.equation(:x1, [:add, :x, -1], "ix"))
          unquote_splicing(guards ++ equations)
          unquote({name, [], [v(:self), v(:x1)] ++ len ++ [v(:t)]})
          unquote_splicing(enums ++ derefs)
        end

      {:ok, defmethod(name, [v(:self), v(:x) | len] ++ [[{:|, [], [cells, v(:t)]}]], goals)}
    end
  end

  # A call reads the pointed column off the trace: the pointed column
  # must wear the callee's tag, its index cell must be the target --
  # an equation, so a bound cell can also name the target -- and each
  # output is the callee's row there. Pointer rows arrive from Lang's
  # table in body order; the env binds each call's outputs, so a later
  # target may be a value an earlier call read.
  @spec closure_derefs(list(), [pos_integer()], map(), plan(), map()) ::
          {map(), [Macro.t()], [pos_integer()]}
  defp closure_derefs(calls, ptrs, env, plan, table) do
    calls
    |> Enum.zip(ptrs)
    |> Enum.with_index()
    |> Enum.reduce({env, [], []}, fn {{{callee, at, outs}, ptr}, j}, {env, derefs, used} ->
      cblock = Map.fetch!(table.rows, callee)
      ipos = Enum.find_index(plan.rows, &(&1 == hd(cblock)))
      {ix, rw, dt} = {v(:"ix#{j}"), v(:"rw#{j}"), v(:"dt#{j}")}

      tpos = Enum.find_index(plan.rows, &(&1 == table.tag))
      tg = v(:"tg#{j}")

      pin = [
        quote(do: vm_is(unquote(ix), x1 - unquote(v(row(ptr, "c"))))),
        quote(do: at(t, unquote(ix), unquote(rw))),
        quote(do: at(unquote(rw), unquote(tpos), unquote(tg))),
        quote(do: unify(unquote(tg), unquote(Map.fetch!(table.tags, callee)))),
        quote(do: at(unquote(rw), unquote(ipos), unquote(dt)))
      ]

      {:ok, pexpr} = rel_prefix(at, env)
      pin = pin ++ AL.Equations.equation(:"dt#{j}", pexpr, "pt#{j}", free: [:x, :len])

      {env, reads} =
        outs
        |> Enum.with_index(2)
        |> Enum.reduce({env, []}, fn {{:var, nm}, k}, {env, reads} ->
          r = Enum.at(cblock, k - 1)
          pos = Enum.find_index(plan.rows, &(&1 == r))
          d = :"d#{ptr}v#{r}"

          {Map.put(env, nm, d),
           reads ++ [quote(do: at(unquote(rw), unquote(pos), unquote(v(d))))]}
        end)

      {env, derefs ++ AL.Equations.frozen([:t, row(ptr, "c")], pin ++ reads), used ++ [ptr]}
    end)
  end

  # Rows are the head; affine offsets schedule their pointers, computed
  # targets carry theirs on the trace and enumerate when nothing binds.
  @spec rel_plan(Rel.t()) :: {:ok, plan(), map()}
  defp rel_plan(%Rel{arity: a, clauses: clauses}) do
    targets =
      for {[{:var, ix} | _outs], body} <- clauses,
          {:call, _n, [at | _couts]} <- body,
          do: {ix, at}

    ks = for {ix, at} <- targets, k = offset(at, ix), do: k
    offsets = ks |> Enum.uniq() |> Enum.with_index(a + 1) |> Map.new()

    computed =
      targets
      |> Enum.reject(fn {ix, at} -> offset(at, ix) end)
      |> Enum.map(&elem(&1, 1))
      |> Enum.uniq()
      |> Enum.with_index(a + map_size(offsets) + 1)
      |> Map.new()

    plan = %{
      rows: Enum.to_list(1..a) ++ Map.values(computed),
      schedules: Map.new(offsets, fn {k, row} -> {row, -k} end),
      window: ks |> Enum.map(&(-&1)) |> Enum.max(fn -> 0 end),
      dynamic: computed |> Map.values() |> Enum.sort(),
      len?: mentions_len?(clauses),
      arity: a + map_size(offsets) + map_size(computed),
      asked: Enum.to_list(1..a) ++ Map.values(computed),
      counter: :row
    }

    {:ok, plan, computed}
  end

  # The recurrence offset itself: a call whose target reads the clause's
  # own index k back, k negative. Anything else is a computed target.
  @spec offset(term(), atom()) :: neg_integer() | nil
  defp offset({:add, {:var, ix}, k}, ix) when is_integer(k) and k < 0, do: k
  defp offset(_at, _ix), do: nil

  @spec mentions_len?(term()) :: boolean()
  defp mentions_len?(:len), do: true
  defp mentions_len?(t) when is_tuple(t), do: t |> Tuple.to_list() |> Enum.any?(&mentions_len?/1)
  defp mentions_len?(t) when is_list(t), do: Enum.any?(t, &mentions_len?/1)
  defp mentions_len?(_t), do: false

  @spec rel_clauses(Rel.t(), atom(), plan(), map()) ::
          {:ok, [Macro.t()]} | {:error, Refusal.t()}
  defp rel_clauses(%Rel{clauses: clauses}, name, plan, computed) do
    clauses
    |> Enum.with_index()
    |> Refusal.map(fn {clause, i} -> rel_clause(clause, i, name, plan, computed) end)
  end

  # A fact pins its column; a rule's calls read the window and its
  # equations run in every direction they can, frozen on their inputs.
  @spec rel_clause({[term()], [term()]}, non_neg_integer(), atom(), plan(), map()) ::
          {:ok, Macro.t()} | {:error, Refusal.t()}
  defp rel_clause({[k | outs], body}, i, name, plan, _computed) when is_integer(k) do
    current = [
      k
      | Enum.with_index(outs, 2)
        |> Enum.map(fn
          {{:var, _nm}, at} -> v(row(at, "c"))
          {literal, _at} -> literal
        end)
    ]

    env =
      for {{:var, nm}, at} <- Enum.with_index(outs, 2), into: %{}, do: {nm, row(at, "c")}

    current = current ++ List.duplicate(1, length(plan.rows) - length(current))
    head = [v(:self) | current] ++ if(plan.len?, do: [v(:len)], else: [])

    with {:ok, defining} <- rel_equations(body, i, Map.put(env, :__index__, k)),
         do: {:ok, pinned(name, head, current, defining, k, plan)}
  end

  defp rel_clause({[{:var, index} | outs], body}, i, name, plan, computed),
    do: rel_step(index, outs, body, i, name, plan, computed)

  defp rel_clause({[head | _outs], _body}, _i, _name, _plan, _computed),
    do: {:error, {:head_not_a_column, %{head: head}}}

  @spec rel_step(atom(), [term()], [term()], non_neg_integer(), atom(), plan(), map()) ::
          {:ok, Macro.t()} | {:error, Refusal.t()}
  defp rel_step(index, outs, body, i, name, plan, computed) do
    len = if plan.len?, do: [v(:len)], else: []

    {windowed, pointed} =
      body
      |> Enum.filter(&match?({:call, _n, _args}, &1))
      |> Enum.split_with(fn {:call, _n, [at | _couts]} -> offset(at, index) end)

    env =
      [{index, :x} | Enum.with_index(outs, 2)]
      |> Enum.map(fn
        {{:var, nm}, row} -> {nm, row(row, "c")}
        {nm, :x} -> {nm, :x}
      end)
      |> Map.new()

    env =
      for {:call, _n, [{:add, _ix, k} | couts]} <- windowed,
          {{:var, nm}, at} <- Enum.with_index(couts, 2),
          into: env,
          do: {nm, row(at, "p#{-k}")}

    env =
      for {:call, _n, [at | couts]} <- pointed,
          {{:var, nm}, val} <- Enum.with_index(couts, 2),
          into: env,
          do: {nm, :"d#{computed[at]}v#{val}"}

    # By row, not by count: an offset row takes a number without taking a
    # slot, so the two only agree when the relation has offsets or computed
    # targets but not both.
    current =
      Enum.map(plan.rows, fn
        1 -> v(:x)
        r -> v(row(r, "c"))
      end)

    with {:ok, reads} <- rel_derefs(pointed, computed, env, plan),
         {:ok, guards} <- rel_guards(body, env),
         {:ok, equations} <- rel_equations(body, i, env) do
      defining = guards ++ reads ++ equations
      {:ok, step(name, [v(:self) | current] ++ len, current, defining, plan)}
    end
  end

  # A computed call pins its pointer to the target, frozen either way,
  # and each output reads the pointed column off the trace.
  @spec rel_derefs([term()], map(), map(), plan()) :: {:ok, [Macro.t()]} | {:error, Refusal.t()}
  defp rel_derefs(pointed, computed, env, plan) do
    pointed
    |> Enum.with_index()
    |> Refusal.flat_map(fn {{:call, _n, [at | couts]}, j} ->
      ptr = computed[at]

      with {:ok, target} <- rel_prefix(at, env) do
        pin = AL.Equations.equation(target, row(ptr, "c"), "p#{j}", free: [:x, :len])

        reads =
          for {{:var, _nm}, val} <- Enum.with_index(couts, 2) do
            pos = Enum.find_index(plan.rows, &(&1 == val))
            {d, ix, rw} = {v(:"d#{ptr}v#{val}"), v(:"ix#{ptr}v#{val}"), v(:"rw#{ptr}v#{val}")}

            goals = [
              quote(do: vm_is(unquote(ix), x1 - unquote(v(row(ptr, "c"))))),
              quote(do: at(t, unquote(ix), unquote(rw))),
              quote(do: at(unquote(rw), unquote(pos), unquote(d)))
            ]

            AL.Equations.frozen([:t, row(ptr, "c")], goals)
          end

        {:ok, pin ++ List.flatten(reads)}
      end
    end)
  end

  @spec rel_equations([term()], non_neg_integer(), map()) ::
          {:ok, [Macro.t()]} | {:error, Refusal.t()}
  defp rel_equations(body, i, env) do
    body
    |> Enum.filter(&match?({:eq, _t, _u}, &1))
    |> Enum.with_index()
    |> Refusal.flat_map(fn {{:eq, t, u}, j} ->
      with {:ok, pt} <- rel_prefix(t, env),
           {:ok, pu} <- rel_prefix(u, env),
           do: {:ok, AL.Equations.equation(pt, pu, "q#{i}e#{j}", free: [:x, :len])}
    end)
  end

  # A guard only tests, so it freezes on its names and checks when they arrive.
  @spec rel_guards([term()], map()) :: {:ok, [Macro.t()]} | {:error, Refusal.t()}
  defp rel_guards(body, env) do
    body
    |> Enum.filter(&match?({:cmp, _op, _t, _u}, &1))
    |> Refusal.map(fn {:cmp, op, t, u} ->
      with {:ok, pt} <- rel_prefix(t, env),
           {:ok, pu} <- rel_prefix(u, env) do
        test = {op, [], [pure(pt), pure(pu)]}
        {:ok, AL.Equations.frozen(leaves(pt) ++ leaves(pu), [test])}
      end
    end)
    |> case do
      {:ok, guards} -> {:ok, Enum.concat(guards)}
      refusal -> refusal
    end
  end

  # A prefix term as the DSL writes it, and the names it waits on.
  @spec pure(term()) :: Macro.t()
  defp pure(q) when is_integer(q), do: q
  defp pure(a) when is_atom(a), do: v(a)
  defp pure([op, t, u]), do: {arith(op), [], [pure(t), pure(u)]}

  @spec arith(atom()) :: atom()
  defp arith(:add), do: :+
  defp arith(:mul), do: :*

  @spec leaves(term()) :: [atom()]
  defp leaves(q) when is_integer(q), do: []
  defp leaves(a) when is_atom(a), do: [a]
  defp leaves([_op, t, u]), do: leaves(t) ++ leaves(u)

  # Terms over the clause's variables, as the equation compiler reads them.
  @spec rel_prefix(term(), %{atom() => atom()}) :: {:ok, term()} | {:error, Refusal.t()}
  defp rel_prefix(q, _env) when is_integer(q), do: {:ok, q}
  defp rel_prefix(:len, _env), do: {:ok, :len}

  defp rel_prefix({:reify, {:eq, t, u}}, env),
    do: rel_prefix(Ast.arithmetize(Ast.eq(t, u)), env)

  defp rel_prefix({:var, nm}, env) do
    case env do
      %{^nm => carrier} -> {:ok, carrier}
      _env -> {:error, {:unbound_variable, %{variable: nm}}}
    end
  end

  defp rel_prefix({op, t, u}, env) when op in [:add, :mul] do
    with {:ok, pt} <- rel_prefix(t, env),
         {:ok, pu} <- rel_prefix(u, env),
         do: {:ok, [op, pt, pu]}
  end

  defp rel_prefix(term, _env), do: {:error, {:unliftable_term, %{term: term}}}

  # --- the run: install, deepen, judge ---

  @spec run_installed(
          program(),
          Ast.pred(),
          plan(),
          [pos_integer()],
          bind(),
          keyword(),
          AL.Branch.t()
        ) ::
          {:ok, Interpretation.t()} | {:error, Refusal.t()}
  defp run_installed(program, pred, plan, counts, bind, opts, branch) do
    name = Keyword.get(opts, :name, :col)
    basedon = Keyword.get(opts, :basedon)
    heap = Keyword.get(opts, :heap, 256_000_000)

    with :ok <- install(program, branch, heap) do
      # Chain equations always invert -- a count is only ever descended
      # by one -- so a free count resolves structurally, closure or
      # lone: the terminal names the bottom and the descent names every
      # level above it. This ask is the only search a free count gets;
      # what it cannot reach refuses by name.
      resolved =
        if counts == [] do
          case AL.eval(query(name, v(:zkc), bind, plan), nil, branch, heap: min(heap, 20_000_000)) do
            {:atomic, _} = derived ->
              deliver(derived, pred, :derive, plan)

            {:aborted, %{reason: {:resource_limit_exceeded, n}}} ->
              {:error, {:unresolved_within_budget, %{reductions: n}}}

            {:aborted, _reason} ->
              nil

            exceeded ->
              Refusal.from_al(exceeded)
          end
        end

      derived =
        resolved ||
          case counts do
            [] ->
              {:error, {:no_derivation, %{}}}

            [count] ->
              case AL.eval(query(name, count, bind, plan), nil, branch, heap: heap) do
                {:atomic, _} = answer ->
                  deliver(answer, pred, count, plan)

                {:aborted, _reason} ->
                  {:error, {:no_derivation_at_count, %{count: count, relation: name}}}

                exceeded ->
                  Refusal.from_al(exceeded)
              end
          end

      with {:ok, witness} <- derived do
        count = Interpretation.len(witness)
        Log.push({:al_solved, %{name: name, count: count, branch: branch.id}}, basedon)
        {:ok, witness}
      end
    end
  end

  # :head reads as wherever the session is checked out, for the viewer;
  # nothing named falls to the configured branch, if one is configured
  # -- the test suite lands every solve on one branch this way.
  @spec landing(term() | nil) :: term() | nil
  defp landing(:head), do: AL.Branch.head().id
  defp landing(nil), do: Application.get_env(:zkfol, :branch)
  defp landing(other), do: other

  # For a lone relation row one is the count, so the goal carries the
  # candidate there. A closure's rows are nobody's count, so the counter
  # rides as its own argument, and the goal pins the trace's head while
  # `t` stays whole for deliver to read.
  @spec query(atom(), integer() | Macro.t(), bind(), plan()) :: [struct()]
  defp query(name, count, bind, %{counter: :row} = plan) do
    goal =
      Enum.map(plan.rows, fn
        1 -> count
        r -> Map.get(bind, r, v(row(r, "c")))
      end)

    args = goal ++ if(plan.len?, do: [count], else: []) ++ [v(:t)]
    [AL.ast_to_pattern({name, [], [@class | args]})]
  end

  defp query(name, count, bind, plan) do
    goal =
      Enum.map(plan.rows, fn
        1 -> count
        r -> Map.get(bind, r, v(row(r, "c")))
      end)

    len = if plan.len?, do: [count], else: []
    pin = quote(do: unify(unquote([{:|, [], [goal, v(:rest)]}]), t))
    Enum.map([pin, {name, [], [@class, count | len] ++ [v(:t)]}], &AL.ast_to_pattern/1)
  end

  # Semantic rows come off the trace, pointer rows off their schedule,
  # unread rows are padding, and the oracle judges every column.
  @spec deliver(
          {:atomic, {AL.Var.bindings(), AL.t()}},
          Ast.pred(),
          pos_integer() | :derive,
          plan()
        ) ::
          {:ok, Interpretation.t()} | {:error, Refusal.t()}
  defp deliver({:atomic, {bindings, _state}}, pred, asked, plan) do
    trace = bindings |> AL.Var.deref(:"$t") |> AL.Var.subst(bindings) |> Enum.reverse()
    count = if is_integer(asked), do: asked, else: length(trace)

    columns =
      plan.rows
      |> Enum.with_index()
      |> Map.new(fn {i, at} -> {i, Enum.map(trace, &Enum.at(&1, at))} end)

    matrix =
      for i <- 1..plan.arity do
        case {columns[i], plan.schedules[i]} do
          {nil, nil} -> List.duplicate(0, count)
          {nil, offset} -> Enum.map(1..count, &max(&1 - offset, 1))
          {cells, _offset} -> cells
        end
      end

    values = List.flatten(matrix)

    # A cell the derivation never bound is still an AL variable: the
    # relation determines no value for that row, which is a different
    # complaint from a value that came out negative.
    with :ok <-
           Refusal.refute(values, &(not is_integer(&1)), &{:row_undetermined, %{cell: &1}}),
         :ok <-
           Refusal.refute(values, &(&1 < 0), &{:witness_value_negative, %{value: &1}}) do
      witness = Interpretation.new(matrix)

      if Semantics.valid?(pred, witness),
        do: {:ok, witness},
        else: {:error, {:witness_invalid, %{}}}
    end
  end

  # --- names ---

  @spec row(pos_integer(), String.t()) :: atom()
  defp row(i, prefix), do: :"#{prefix}#{i}"

  @spec v(atom()) :: Macro.t()
  defp v(name), do: {name, [], nil}
end
