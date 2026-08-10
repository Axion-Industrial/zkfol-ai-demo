defmodule Zkfol.Al do
  @moduledoc """
  I am the AL backend: a statement becomes clauses and runs as
  written, so the derivation is the witness. The clauses go down as
  plain AL, AL's journal of the committed derivation comes back, and
  the witness is its facts, laid by `Zkfol.Derivation` and judged by
  the oracle. The act has two halves: `derived/3` runs -- prepare,
  ask, extract, journal -- and `relaid/2` links and lays what it
  established, no run of its own. `solved/3` is both in one call.

  My satellites are the distance from the ideal: `Zkfol.Al.Consumption`
  dies when the journal names the fired clause. Two have already closed
  their distance: laying is the allocator's, held by `Zkfol.Derivation`
  under `Zkfol.Alloc`, and the frozen expansion of an equation into its
  directions is one CLP constraint goal.
  """

  import Kernel, except: [apply: 3]

  alias Zkfol.Al.Ask
  alias Zkfol.Derivation
  alias Zkfol.Lang
  alias Zkfol.Lay
  alias Zkfol.Lang.Rel
  alias Zkfol.Alloc
  alias Zkfol.Ast
  alias Zkfol.Refusal
  alias Zkfol.Interpretation
  alias Zkfol.Log
  alias Zkfol.Statement

  @class :zkfol

  @typedoc "An emitted AL program: goal structs ready for AL.eval/3."
  @type program :: [struct()]

  @typep bind :: %{optional(pos_integer()) => integer()}

  # Everything an ask needs, prepared once: see `prepared/4`.
  @typep prep :: %{
           root: Rel.t(),
           name: atom(),
           names: MapSet.t(),
           program: program(),
           bind: bind(),
           len?: boolean(),
           branch: term() | nil,
           basedon: term() | nil,
           heap: pos_integer() | nil
         }

  @doc """
  I emit the question program of a relation: the clauses as plain AL,
  no witness laid out.

      question(Examples.EUser.fib())
  """
  @spec question(Rel.t() | [Rel.t()]) :: {:ok, program()} | {:error, Refusal.t()}
  def question(%Rel{} = root), do: question([root])
  def question([%Rel{} | _rest] = rels), do: question_program(rels)
  def question([]), do: {:error, {:no_relations, %{}}}

  @doc """
  I derive the witness at `arguments`, or refuse with the reason.

      solve(Examples.EUser.fib(), [8])
      solve(kernel_statement, [:_, n - 2])
      solve(Examples.EFacts.factorial(), [6], branch: :head)

  `arguments` address the root relation's rows in order, root first
  then scope. `:_` leaves a row free; `:bind` names a row directly.
  The question runs once, free rows genuinely free, and the witness
  is the journal's facts, one column each. A finite failure refuses
  as no_answer; past a budget, by the budget. `:branch` keeps the
  install, `:heap` bounds the derivation, `:basedon` bases the
  journaled act.
  """
  @spec solve(Statement.t() | Rel.t() | [Rel.t()], [integer() | :_], keyword()) ::
          {:ok, Interpretation.t()} | {:error, Refusal.t()}
  def solve(target, arguments, opts \\ []) do
    with {:ok, solved} <- solved(target, arguments, opts), do: {:ok, solved.witness}
  end

  @doc """
  I am the run half: the derivation `arguments` establish, before any
  allocation places it. `relaid/2` is the other half.
  """
  @spec derived(Statement.t() | Rel.t() | [Rel.t()], [integer() | :_], keyword()) ::
          {:ok, Derivation.t()} | {:error, Refusal.t()}
  def derived(target, arguments, opts \\ [])

  def derived(%Statement{rels: [_ | _] = rels}, args, opts), do: derive_rels(rels, args, opts)
  def derived(%Statement{}, _args, _opts), do: {:error, {:no_relations, %{}}}
  def derived(%Rel{} = root, args, opts), do: derive_rels([root], args, opts)
  def derived([%Rel{} | _rest] = rels, args, opts), do: derive_rels(rels, args, opts)
  def derived([], _args, _opts), do: {:error, {:no_relations, %{}}}

  @doc """
  I am the solving act whole: the `Zkfol.Statement.Solved` stage, its
  linked predicate, witness, derivation, and allocation, `derived/3`
  run and `relaid/2` laid over what it established.
  """
  @spec solved(Statement.t() | Rel.t() | [Rel.t()], [integer() | :_], keyword()) ::
          {:ok, Statement.Solved.t()} | {:error, Refusal.t()}
  def solved(target, arguments, opts \\ []) do
    statement = statement(target)

    with {:ok, derivation} <- derived(statement, arguments, opts),
         {:ok, laid} <- relaid(statement, derivation),
         do: {:ok, laid.stage}
  end

  @doc """
  I am the link half: I lay `derivation` as the statement's witness --
  the shape compiled from its relations, the allocation assigned, the
  predicate linked, the banks laid and judged -- one pure act, no run.
  A subderivation or a candidate layout lays through me.
  """
  @spec relaid(Statement.t(), Derivation.t()) :: {:ok, Statement.t()} | {:error, Refusal.t()}
  def relaid(%Statement{rels: [root | _rest] = rels} = statement, %Derivation{} = derivation) do
    with {:ok, shape} <- Lang.compile(root, rels),
         alloc = Alloc.assign(shape),
         {:ok, linked} <- Alloc.link(shape.pred, alloc),
         members = Enum.filter(rels, &(&1.name in shape.members)),
         lay = Lay.of(derivation, alloc, shape, members),
         {:ok, witness} <- Lay.witness(lay),
         :ok <- judged(linked, witness) do
      {:ok, %{statement | stage: %Statement.Solved{pred: linked, witness: witness, lay: lay}}}
    end
  end

  @doc """
  I derive every answer at `arguments`, naming the ones I report:
  the ask before `solve/3` proves.

      apply(Examples.EUser.fib(), [8, :a])
      apply(EAl.tab(), [:n, :a])

  An integer pins a row as `solve/3` does; an atom names a row in
  every answer; `:_` leaves a row free and unreported. A finite ask
  answers whole; past the budget it refuses by the budget. Pin a row
  to ask for less.
  """
  @spec apply(Statement.t() | Rel.t() | [Rel.t()], [integer() | atom()], keyword()) ::
          {:ok, [%{atom() => integer()}]} | {:error, Refusal.t()}
  def apply(target, arguments, opts \\ [])

  def apply(%Statement{rels: [_ | _] = rels}, args, opts), do: apply_rels(rels, args, opts)
  def apply(%Rel{} = root, args, opts), do: apply_rels([root], args, opts)
  def apply([%Rel{} | _rest] = rels, args, opts), do: apply_rels(rels, args, opts)
  def apply(_target, _args, _opts), do: {:error, {:no_relations, %{}}}

  # --- the flow: prepare, ask, extract, journal ---

  @doc """
  I open a stepping ask at `arguments`: the question of `target` as
  plain AL, installed on a branch of my own, and the goal that runs
  against it. Nothing derives yet.

      {:ok, ask} = open(Examples.EAl.tab(), [:_, :_], [])

  `arguments` address the root relation's head rows in order as
  `solve/3` does, `:_` free. I prepare as `solve/3` prepares: only the
  relations the root's closure reaches install, and a relation whose
  clauses name len wants its count bound. Where `apply/3` collects
  every answer at once, I hand them over one at a time: `step/1` takes
  the next, `close/1` discards the branch. `:branch` says what to fork
  from, `:heap` bounds the install.

  The ask holds AL's search state, so the process that opens it is
  the process that must step it.
  """
  @spec open(Rel.t() | [Rel.t()], [integer() | :_], keyword()) ::
          {:ok, Ask.t()} | {:error, Refusal.t()}
  def open(%Rel{} = root, arguments, opts), do: open([root], arguments, opts)

  def open([%Rel{} | _rest] = rels, arguments, opts) do
    with {:ok, prep} <- prepared(rels, arguments, opts) do
      branch = AL.Branch.fork(:tip, based(landing(prep.branch)))

      case install(prep.program, branch, prep.heap || 256_000_000) do
        :ok ->
          {:ok,
           %Ask{
             name: prep.name,
             rels: rels,
             goal: plain(call(prep, goal(prep.root.arity, prep.bind, arguments))),
             arguments: arguments,
             branch: branch
           }}

        {:error, _reason} = refusal ->
          AL.Branch.discard(branch)
          refusal
      end
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
  # the bindings are read, and they are the answer. A finite no is the
  # end of the search, which is the ask's own policy on a no.
  @spec answered(term(), Ask.t()) :: {Ask.outcome(), Ask.t()}
  defp answered(evaluated, ask) do
    case outcome(evaluated) do
      {:ok, bindings, state} -> {ground(bindings, ask.arguments), %{ask | state: state}}
      {:no, _reason} -> {:exhausted, ask}
      {:error, _reason} = refusal -> {refusal, ask}
    end
  end

  # The answer: a bound argument as it was asked, a free one as the
  # search ground it. An answer is every asked row ground, so a row
  # the search left open under its constraints refuses as residue.
  @spec ground(AL.Var.store(), [integer() | :_]) ::
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

  @spec derive_rels([Rel.t()], [integer() | :_], keyword()) ::
          {:ok, Derivation.t()} | {:error, Refusal.t()}
  defp derive_rels(rels, args, opts) do
    with {:ok, prep} <- prepared(rels, args, opts) do
      on_question(prep, 256_000_000, fn branch, heap ->
        with {:ok, tree} <- derive(prep, branch, heap) do
          derivation = Derivation.of(tree, prep.names, prep.len?)
          count = length(derivation.facts)
          event = {:al_solved, %{name: prep.name, count: count, branch: branch.id}}
          Log.push(event, prep.basedon)

          {:ok, derivation}
        end
      end)
    end
  end

  # A target as the statement it stands for: what the link half lays on.
  @spec statement(Statement.t() | Rel.t() | [Rel.t()]) :: Statement.t()
  defp statement(%Statement{} = statement), do: statement
  defp statement(%Rel{} = root), do: %Statement{rels: [root]}
  defp statement(rels) when is_list(rels), do: %Statement{rels: rels}

  # The oracle on the whole witness: banks stacked, every region in it.
  @spec judged(Ast.pred(), Interpretation.t()) :: :ok | {:error, Refusal.t()}
  defp judged(pred, witness) do
    if Zkfol.Semantics.valid?(pred, witness),
      do: :ok,
      else: {:error, {:witness_invalid, %{}}}
  end

  # Everything both asks share, prepared once. The shape says which
  # relations the root's closure reaches: only those are asked.
  @spec prepared([Rel.t()], [integer() | atom()], keyword()) ::
          {:ok, prep()} | {:error, Refusal.t()}
  defp prepared([root | _rest] = rels, args, opts) do
    with {:ok, order} <- Lang.members(root, rels),
         members = Enum.filter(rels, &(&1.name in order)),
         {:ok, program} <- question_program(members),
         {:ok, bind} <- bind(Enum.to_list(1..root.arity), args, opts),
         len? = Enum.any?(members, &mentions_len?(&1.clauses)),
         :ok <- len_bound(len?, bind) do
      {:ok,
       %{
         root: root,
         name: Keyword.get(opts, :name, root.name),
         names: MapSet.new(members, & &1.name),
         program: program,
         bind: bind,
         len?: len?,
         branch: Keyword.get(opts, :branch),
         basedon: Keyword.get(opts, :basedon),
         heap: Keyword.get(opts, :heap)
       }}
    end
  end

  # The question installed on the landed branch.
  @spec on_question(prep(), pos_integer(), (AL.Branch.t(), pos_integer() -> any())) :: any()
  defp on_question(prep, default_heap, fun) do
    heap = prep.heap || default_heap

    AL.Branch.on(landing(prep.branch), fn branch ->
      with :ok <- install(prep.program, branch, heap), do: fun.(branch, heap)
    end)
  end

  # len names the trace, which only a bound count sizes ahead of time.
  @spec len_bound(boolean(), bind()) :: :ok | {:error, Refusal.t()}
  defp len_bound(false, _bind), do: :ok
  defp len_bound(true, bind) when is_map_key(bind, 1), do: :ok
  defp len_bound(true, _bind), do: {:error, {:len_needs_a_bound_count, %{}}}

  # A free row the answer grounds pins a replay: the search's journal
  # carries redo scars, the ground re-run's is the derivation clean.
  @spec derive(prep(), AL.Branch.t(), pos_integer()) ::
          {:ok, [map()]} | {:error, Refusal.t()}
  defp derive(%{root: root, bind: bind, name: name} = prep, branch, heap) do
    args = goal(root.arity, bind, [])

    tree =
      &(&1.domino.trace
        |> Enum.reverse()
        |> AL.Trace.derivation_tree(&1.active_choicepoint.store))

    with {:ok, bindings, derived} <- ask(plain(call(prep, args)), branch, heap, name, tree) do
      grounded =
        Enum.map(args, fn
          {nm, [], nil} = var ->
            value = bindings |> AL.Var.deref(:"$#{nm}") |> AL.Var.subst(bindings)
            if is_integer(value), do: value, else: var

          ground ->
            ground
        end)

      if grounded == args do
        {:ok, derived}
      else
        with {:ok, _bindings, replayed} <-
               ask(plain(call(prep, grounded)), branch, heap, name, tree),
             do: {:ok, replayed}
      end
    end
  end

  # The root's call at `args`: len rides last where the clauses name
  # it, the bound count that sizes the trace.
  @spec call(prep(), [Macro.t() | integer()]) :: Macro.t()
  defp call(%{root: root, len?: false}, args), do: {root.name, [], [@class | args]}

  defp call(%{root: root, len?: true, bind: bind}, args),
    do: {root.name, [], [@class | args ++ [Map.fetch!(bind, 1)]]}

  @spec plain(Macro.t()) :: [struct()]
  defp plain(goal), do: [AL.ast_to_pattern(goal)]

  # One eval against the installed question, refusals typed. The heap
  # cap is ours, not AL's: its guarded eval sheds the state to nothing,
  # and the derivation is what we came for. `digest` reads the state
  # inside the cap, so only its answer crosses the boundary.
  @spec ask([struct()], AL.Branch.t(), pos_integer(), atom(), (AL.t() -> term())) ::
          {:ok, AL.Var.store(), term()} | {:error, Refusal.t()}
  defp ask(query, branch, heap, name, digest) do
    case outcome(capped_eval(query, branch, heap, digest)) do
      {:ok, bindings, derived} -> {:ok, bindings, derived}
      {:no, _reason} -> {:error, {:no_answer, %{relation: name}}}
      {:error, _reason} = refusal -> refusal
    end
  end

  # AL's eval under our own heap cap. The state stays in the dying
  # process -- an exit reason is copied onto the parent's uncapped heap,
  # so what leaves is what `digest` made of it.
  @spec capped_eval([struct()], AL.Branch.t(), pos_integer(), (AL.t() -> term())) :: term()
  defp capped_eval(query, branch, heap, digest) do
    {pid, ref} =
      spawn_monitor(fn ->
        Process.flag(:max_heap_size, %{size: heap, kill: true, error_logger: false})
        exit({:derived, digested(AL.eval(query, nil, branch, []), digest)})
      end)

    receive do
      {:DOWN, ^ref, :process, ^pid, {:derived, result}} ->
        result

      {:DOWN, ^ref, :process, ^pid, _killed} ->
        {:error, "the derivation exceeded #{heap} heap words"}
    end
  end

  # An answer sheds to its digest; anything else is already small.
  @spec digested(term(), (AL.t() -> term())) :: term()
  defp digested({:atomic, {bindings, state}}, digest), do: {:atomic, {bindings, digest.(state)}}
  defp digested(other, _digest), do: other

  # The call's arguments: a named row rides its name, a bound row its
  # value, anything else a fresh variable.
  @spec goal(pos_integer(), bind(), [integer() | atom()]) :: [Macro.t() | integer()]
  defp goal(arity, bind, args) do
    Enum.zip(1..arity, args ++ Stream.cycle([:_]))
    |> Enum.map(fn
      {_row, a} when is_atom(a) and a != :_ -> v(a)
      {row, _} -> Map.get(bind, row, v(:"qa#{row}"))
    end)
  end

  # AL's outcome, typed; the caller owns the policy on a finite no. A
  # search stopped by the budget is nobody's policy: it never reached
  # a no, so it refuses as itself.
  @spec outcome(term()) ::
          {:ok, AL.Var.store(), term()} | {:no, term()} | {:error, Refusal.t()}
  defp outcome({:atomic, {bindings, state}}), do: {:ok, bindings, state}

  defp outcome({:aborted, %{reason: {:resource_limit_exceeded, n}}}),
    do: {:error, {:unresolved_within_budget, %{reductions: n}}}

  defp outcome({:aborted, reason}), do: {:no, reason}
  defp outcome(exceeded), do: Refusal.from_al(exceeded)

  # Rows `args` left bound, skipping `:_`, under any `opts[:bind]` override.
  # An argument past the last row addresses nothing, and zipping it away
  # would answer a question no one asked.
  @spec bind([pos_integer()], [integer() | atom()], keyword()) ::
          {:ok, bind()} | {:error, Refusal.t()}
  defp bind(rows, args, _opts) when length(args) > length(rows),
    do: {:error, {:arguments_exceed_rows, %{args: length(args), rows: length(rows)}}}

  defp bind(rows, args, opts) do
    override = Keyword.get(opts, :bind, %{})

    case Map.keys(override) -- rows do
      [] ->
        {:ok,
         rows
         |> Enum.zip(args)
         |> Enum.reject(fn {_row, a} -> is_atom(a) end)
         |> Map.new()
         |> Map.merge(override)}

      outside ->
        {:error, {:arguments_exceed_rows, %{bind: outside, rows: length(rows)}}}
    end
  end

  # --- apply: every answer, under findall ---

  # The question under a findall that keeps each answer.
  @spec apply_rels([Rel.t()], [integer() | atom()], keyword()) ::
          {:ok, [%{atom() => integer()}]} | {:error, Refusal.t()}
  defp apply_rels([root | _rest] = rels, args, opts) do
    with {:ok, prep} <- prepared(rels, args, opts) do
      names = for a <- args, is_atom(a) and a != :_, do: a
      site = call(prep, goal(root.arity, prep.bind, args))
      template = Enum.map(names, &v/1)
      query = plain(quote(do: findall(unquote(template), unquote([site]), rs)))

      on_question(prep, 20_000_000, fn branch, heap ->
        with {:ok, bindings, _nothing} <-
               ask(query, branch, heap, root.name, fn _state -> nil end) do
          rows = bindings |> AL.Var.deref(:"$rs") |> AL.Var.subst(bindings)

          {:ok,
           for row <- rows do
             names
             |> Enum.zip(row)
             |> Map.new(fn {key, cell} -> {key, Derivation.free_to_zero(cell)} end)
           end}
        end
      end)
    end
  end

  # --- the question: the clauses as plain AL, no witness laid out ---

  # The clauses as written, every constraint AL can hold open posted at
  # clause entry and the rest of the body in the order written; len rides
  # as one more parameter when mentioned.
  @spec question_program([Rel.t()]) :: {:ok, program()} | {:error, Refusal.t()}
  defp question_program(rels) do
    len? = Enum.any?(rels, &mentions_len?(&1.clauses))

    rels
    |> Enum.flat_map(fn rel -> Enum.map(rel.clauses, &{rel.name, &1}) end)
    |> Enum.with_index()
    |> Refusal.map(fn {{rname, clause}, i} -> question_clause(rname, clause, i, len?) end)
    |> case do
      {:ok, clauses} -> {:ok, installed(Enum.map(rels, & &1.name), clauses)}
      refusal -> refusal
    end
  end

  @spec question_clause(atom(), {[term()], [term()]}, non_neg_integer(), boolean()) ::
          {:ok, Macro.t()} | {:error, Refusal.t()}
  defp question_clause(rname, {head, body}, i, len?) do
    case Enum.find(head, &(not (match?({:var, _}, &1) or is_integer(&1)))) do
      nil ->
        body = surfaced(body, i)
        env = [head | Enum.map(body, &Tuple.to_list/1)] |> qvars() |> Map.new(&{&1, &1})
        lenp = if len?, do: [v(:len)], else: []
        params = Enum.map(head, &qterm/1) ++ lenp

        {entry, written} = Enum.split_with(numbered(body), &postable?/1)

        with {:ok, goals} <- Refusal.flat_map(entry ++ written, &goals(&1, i, env, lenp)) do
          {:ok, defmethod(rname, [v(:self) | params], {:__block__, [], goals})}
        end

      bad ->
        {:error, {:head_not_a_column, %{head: bad}}}
    end
  end

  # A mod site as the goals it means, the quotient a name of ours: the
  # defining equation, the remainder under the modulus, and the two
  # signs the Z-side derivation cannot read off the committed rows the
  # predicate stands on. The equation is linear at a literal modulus,
  # so it posts at clause entry and the fixpoint binds both once the
  # dividend grounds.
  @spec surfaced([term()], non_neg_integer()) :: [term()]
  defp surfaced(body, i) do
    body
    |> Enum.with_index()
    |> Enum.flat_map(fn
      {{:mod, r, e, m}, j} ->
        q = {:var, :"m#{i}q#{j}"}

        [
          {:eq, e, {:add, {:mul, q, m}, r}},
          {:cmp, :<, r, m},
          {:cmp, :>, {:add, r, 1}, 0},
          {:cmp, :>, {:add, q, 1}, 0}
        ]

      {goal, _j} ->
        [goal]
    end)
  end

  # The body's statements, each call carrying its place among the calls:
  # what tells one call's fresh argument names from another's.
  @spec numbered([term()]) :: [{term(), non_neg_integer()}]
  defp numbered(body) do
    body
    |> Enum.map_reduce(0, fn
      {:call, _n, _a} = call, j -> {{call, j}, j + 1}
      other, j -> {{other, j}, j}
    end)
    |> elem(0)
  end

  # What posts at clause entry: a constraint AL's fixpoint carries with
  # every variable of it still open, so where the surface wrote it stops
  # mattering. A product of two unknowns is not one -- AL refuses it where
  # it stands -- so it waits where it was written, as does every call.
  @spec postable?({term(), non_neg_integer()}) :: boolean()
  defp postable?({{:eq, t, u}, _j}), do: linear?(t) and linear?(u)
  defp postable?({{:cmp, _op, t, u}, _j}), do: linear?(t) and linear?(u)
  defp postable?({_statement, _j}), do: false

  @spec linear?(term()) :: boolean()
  defp linear?({:mul, t, u}), do: (is_integer(t) or is_integer(u)) and linear?(t) and linear?(u)
  defp linear?({:add, t, u}), do: linear?(t) and linear?(u)
  defp linear?({:reify, {:eq, t, u}}), do: linear?(Ast.arithmetize(Ast.eq(t, u)))
  defp linear?(_term), do: true

  # A statement of clause `i`'s body: an equation is CLP's `eq`, a guard the
  # comparison itself, each sound with either side still open and each
  # narrowing the rest through AL's fixpoint. A call sends, its computed
  # arguments equated to fresh names first.
  @spec goals({term(), non_neg_integer()}, non_neg_integer(), %{atom() => atom()}, [Macro.t()]) ::
          {:ok, [Macro.t()]} | {:error, Refusal.t()}
  defp goals({{:eq, t, u}, _j}, _i, env, _lenp) do
    with {:ok, goal} <- binary(:eq, t, u, env), do: {:ok, [goal]}
  end

  defp goals({{:cmp, op, t, u}, _j}, _i, env, _lenp) do
    with {:ok, goal} <- binary(op, t, u, env), do: {:ok, [goal]}
  end

  defp goals({{:call, name, args}, j}, i, env, lenp) do
    with {:ok, passed} <- Refusal.map(Enum.with_index(args), &argument(&1, i, j, env)) do
      {defs, args} = Enum.unzip(passed)
      {:ok, Enum.concat(defs) ++ [{name, [], [v(:self) | args] ++ lenp}]}
    end
  end

  # A variable or literal rides as itself; anything computed goes through
  # a fresh name one equation binds it to.
  @spec argument({term(), non_neg_integer()}, non_neg_integer(), non_neg_integer(), %{
          atom() => atom()
        }) :: {:ok, {[Macro.t()], Macro.t()}} | {:error, Refusal.t()}
  defp argument({{:var, nm}, _k}, _i, _j, _env), do: {:ok, {[], v(nm)}}
  defp argument({q, _k}, _i, _j, _env) when is_integer(q), do: {:ok, {[], q}}

  defp argument({expr, k}, i, j, env) do
    fresh = v(:"q#{i}c#{j}a#{k}")

    with {:ok, term} <- arith(expr, env),
         do: {:ok, {[{:eq, [], [fresh, term]}], fresh}}
  end

  # A surface term as AL arithmetic over the clause's variables.
  @spec arith(term(), %{atom() => atom()}) :: {:ok, Macro.t()} | {:error, Refusal.t()}
  defp arith(q, _env) when is_integer(q), do: {:ok, q}
  defp arith(:len, _env), do: {:ok, v(:len)}

  defp arith({:reify, {:eq, t, u}}, env), do: arith(Ast.arithmetize(Ast.eq(t, u)), env)

  defp arith({:add, t, u}, env), do: binary(:+, t, u, env)
  defp arith({:mul, t, u}, env), do: binary(:*, t, u, env)

  defp arith({:var, nm}, env) do
    case env do
      %{^nm => carrier} -> {:ok, v(carrier)}
      _env -> {:error, {:unbound_variable, %{variable: nm}}}
    end
  end

  defp arith(term, _env), do: {:error, {:unliftable_term, %{term: term}}}

  @spec binary(atom(), term(), term(), %{atom() => atom()}) ::
          {:ok, Macro.t()} | {:error, Refusal.t()}
  defp binary(op, t, u, env) do
    with {:ok, a} <- arith(t, env),
         {:ok, b} <- arith(u, env),
         do: {:ok, {op, [], [a, b]}}
  end

  @spec qterm(term()) :: Macro.t()
  defp qterm({:var, nm}), do: v(nm)
  defp qterm(q), do: q

  @spec qvars(term()) :: [atom()]
  defp qvars({:var, nm}), do: [nm]
  defp qvars(t) when is_tuple(t), do: t |> Tuple.to_list() |> qvars()
  defp qvars(t) when is_list(t), do: Enum.uniq(Enum.flat_map(t, &qvars/1))
  defp qvars(_t), do: []

  @spec mentions_len?(term()) :: boolean()
  defp mentions_len?(:len), do: true
  defp mentions_len?(t) when is_tuple(t), do: t |> Tuple.to_list() |> Enum.any?(&mentions_len?/1)
  defp mentions_len?(t) when is_list(t), do: Enum.any?(t, &mentions_len?/1)
  defp mentions_len?(_t), do: false

  @spec defmethod(atom(), [Macro.t()], Macro.t()) :: Macro.t()
  defp defmethod(name, head, body), do: {:defmethod, [], [@class, name, head, [do: body]]}

  # A program: the class, the retraction preamble, then the clauses.
  @spec installed([atom()], [Macro.t()]) :: program()
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

  # An install that cannot land refuses; the caller owns the branch.
  @spec install(program(), AL.Branch.t(), pos_integer()) :: :ok | {:error, Refusal.t()}
  defp install(program, branch, heap) do
    case outcome(AL.eval(program, nil, branch, heap: heap)) do
      {:ok, _bindings, _state} -> :ok
      {:no, reason} -> {:error, {:send_failed, %{reason: reason}}}
      {:error, _reason} = refusal -> refusal
    end
  end

  # :head reads as wherever the session is checked out, for the viewer;
  # nothing named falls to the configured branch, if one is configured
  # -- the test suite lands every solve on one branch this way.
  @spec landing(term() | nil) :: term() | nil
  # What a fresh branch forks from: the session's head unless one is named.
  @spec based(term() | nil) :: AL.Branch.t()
  defp based(nil), do: AL.Branch.head()
  defp based(id), do: %AL.Branch{id: id}

  defp landing(:head), do: AL.Branch.head().id
  defp landing(nil), do: Application.get_env(:zkfol, :branch)
  defp landing(other), do: other

  @spec v(atom()) :: Macro.t()
  defp v(name), do: {name, [], nil}
end
