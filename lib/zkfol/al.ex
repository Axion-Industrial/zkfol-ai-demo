defmodule Zkfol.Al do
  @moduledoc """
  I am the AL backend: a statement becomes clauses and runs as
  written, so the derivation is the witness. The clauses go down as
  plain AL, AL's journal of the committed derivation comes back, and
  the witness is its facts, laid by `Zkfol.Derivation` and judged by
  the oracle. The flow: prepare, ask, extract, lay, judge, journal.

  My satellites are the distance from the ideal: `Zkfol.Al.Freeze`
  dies when CLPFD lands, `Zkfol.Al.Consumption` dies when the journal
  names the fired clause. Laying has already left me: it is the
  allocator's, and `Zkfol.Derivation` holds it under `Zkfol.Alloc`.
  """

  import Kernel, except: [apply: 3]

  alias Zkfol.Al.Freeze
  alias Zkfol.Derivation
  alias Zkfol.Lang
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
  @typep fact :: {atom(), [term()]}

  # Everything an ask needs, prepared once: see `prepared/3`.
  @typep prep :: %{
           root: Rel.t(),
           name: atom(),
           shape: Lang.shape(),
           alloc: Alloc.t(),
           linked: Ast.pred(),
           members: [Rel.t()],
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
  def solve(target, arguments, opts \\ [])

  def solve(%Statement{rels: [_ | _] = rels} = statement, args, opts),
    do: solve_rels(rels, statement, args, opts)

  def solve(%Statement{}, _args, _opts), do: {:error, {:no_relations, %{}}}

  def solve(%Rel{} = root, args, opts), do: solve_rels([root], [root], args, opts)
  def solve([%Rel{} | _rest] = rels, args, opts), do: solve_rels(rels, rels, args, opts)
  def solve([], _args, _opts), do: {:error, {:no_relations, %{}}}

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

  # --- the flow: prepare, ask, extract, lay, judge, journal ---

  @spec solve_rels([Rel.t()], Statement.t() | [Rel.t()], [integer() | :_], keyword()) ::
          {:ok, Interpretation.t()} | {:error, Refusal.t()}
  defp solve_rels(rels, target, args, opts) do
    with {:ok, prep} <- prepared(rels, args, opts) do
      on_question(prep, 256_000_000, fn branch, heap ->
        pred = target_pred(target, prep)

        with {:ok, tree} <- derive(prep, branch, heap),
             facts = extract(tree, prep.names, prep.len?),
             {:ok, banks} <- Derivation.lay(facts, prep.alloc, prep.shape, prep.members, pred),
             {:ok, witness} <- Alloc.interpret(prep.alloc, banks),
             :ok <- judged(pred, witness) do
          count = Interpretation.len(witness)
          event = {:al_solved, %{name: prep.name, count: count, branch: branch.id}}
          Log.push(event, prep.basedon)
          {:ok, witness}
        end
      end)
    end
  end

  # The oracle on the whole witness: banks stacked, every region in it.
  @spec judged(Ast.pred(), Interpretation.t()) :: :ok | {:error, Refusal.t()}
  defp judged(pred, witness) do
    if Zkfol.Semantics.valid?(pred, witness),
      do: :ok,
      else: {:error, {:witness_invalid, %{}}}
  end

  # Everything both asks share, prepared once.
  @spec prepared([Rel.t()], [integer() | atom()], keyword()) ::
          {:ok, prep()} | {:error, Refusal.t()}
  defp prepared([root | _rest] = rels, args, opts) do
    with {:ok, shape} <- Lang.compile(root, rels),
         alloc = Alloc.assign(shape),
         {:ok, linked} <- Alloc.link(shape.pred, alloc),
         members = Enum.filter(rels, &(&1.name in shape.members)),
         {:ok, program} <- question_program(members),
         {:ok, bind} <- bind(Enum.to_list(1..root.arity), args, opts),
         len? = Enum.any?(members, &mentions_len?(&1.clauses)),
         :ok <- len_bound(len?, bind) do
      {:ok,
       %{
         root: root,
         name: Keyword.get(opts, :name, root.name),
         shape: shape,
         alloc: alloc,
         linked: linked,
         members: members,
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
  defp derive(%{root: root, bind: bind, len?: len?, name: name}, branch, heap) do
    args = goal(root.arity, bind, [])
    lenp = if len?, do: [Map.fetch!(bind, 1)], else: []

    with {:ok, bindings, shed} <- ask(plain(root.name, args ++ lenp), branch, heap, name) do
      grounded =
        Enum.map(args, fn
          {nm, [], nil} = var ->
            value = bindings |> AL.Var.deref(:"$#{nm}") |> AL.Var.subst(bindings)
            if is_integer(value), do: value, else: var

          ground ->
            ground
        end)

      if grounded == args do
        {:ok, tree(shed)}
      else
        with {:ok, _bindings, shed} <-
               ask(plain(root.name, grounded ++ lenp), branch, heap, name),
             do: {:ok, tree(shed)}
      end
    end
  end

  @spec plain(atom(), [term()]) :: [struct()]
  defp plain(rname, args), do: [AL.ast_to_pattern({rname, [], [@class | args]})]

  @spec tree(%{domino: AL.Domino.t()}) :: [map()]
  defp tree(shed), do: shed.domino.trace |> Enum.reverse() |> AL.Trace.derivation_tree()

  # One eval against the installed question, refusals typed.
  @spec ask([struct()], AL.Branch.t(), pos_integer(), atom()) ::
          {:ok, AL.Var.bindings(), %{domino: AL.Domino.t()}} | {:error, Refusal.t()}
  defp ask(query, branch, heap, name) do
    case outcome(AL.eval(query, nil, branch, heap: heap)) do
      {:ok, bindings, shed} ->
        {:ok, bindings, shed}

      {:no, %{reason: {:resource_limit_exceeded, n}}} ->
        {:error, {:unresolved_within_budget, %{reductions: n}}}

      {:no, _reason} ->
        {:error, {:no_answer, %{relation: name}}}

      {:error, _reason} = refusal ->
        refusal
    end
  end

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

  # AL's outcome, typed; the caller owns the policy on a no.
  @spec outcome(term()) ::
          {:ok, AL.Var.bindings(), term()} | {:no, term()} | {:error, Refusal.t()}
  defp outcome({:atomic, {bindings, shed}}), do: {:ok, bindings, shed}
  defp outcome({:aborted, reason}), do: {:no, reason}
  defp outcome(exceeded), do: Refusal.from_al(exceeded)

  # The pred the stage already carries, linked; the compiled one linked
  # otherwise. The witness stands on rows, so what judges it must too.
  @spec target_pred(Statement.t() | [Rel.t()], prep()) :: Ast.pred()
  defp target_pred(%Statement{stage: :raw}, prep), do: prep.linked
  defp target_pred(%Statement{} = statement, _prep), do: Statement.pred(statement)
  defp target_pred(_rels, prep), do: prep.linked

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

  # --- extraction: the journal's facts, nothing else ---

  # The committed derivation in post-order: one fact per member call,
  # callees ahead of their callers, duplicates collapsed.
  @spec extract([map()] | map(), MapSet.t(), boolean()) :: [fact()]
  defp extract(tree, names, len?) do
    tree
    |> List.wrap()
    |> Enum.reduce([], &fact_nodes(&1, &2, names, len?))
    |> Enum.reverse()
    |> Enum.uniq()
  end

  @spec fact_nodes(map(), [fact()], MapSet.t(), boolean()) :: [fact()]
  defp fact_nodes(%{label: {_self, m, args}, children: kids, derived: derived}, acc, names, len?) do
    acc = Enum.reduce(kids, acc, &fact_nodes(&1, &2, names, len?))

    if MapSet.member?(names, m) do
      values = Enum.map(args, &resolve(&1, derived))
      [{m, if(len?, do: Enum.drop(values, -1), else: values)} | acc]
    else
      acc
    end
  end

  defp fact_nodes(_node, acc, _names, _len?), do: acc

  @spec resolve(term(), map() | nil) :: term()
  defp resolve(term, derived) do
    case derived && Map.get(derived, term) do
      {:bound, value} -> value
      _other -> term
    end
  end

  # --- apply: every answer, under findall ---

  # The question under a findall that keeps each answer.
  @spec apply_rels([Rel.t()], [integer() | atom()], keyword()) ::
          {:ok, [%{atom() => integer()}]} | {:error, Refusal.t()}
  defp apply_rels([root | _rest] = rels, args, opts) do
    with {:ok, prep} <- prepared(rels, args, opts) do
      names = for a <- args, is_atom(a) and a != :_, do: a
      lenp = if prep.len?, do: [Map.fetch!(prep.bind, 1)], else: []
      call = {root.name, [], [@class | goal(root.arity, prep.bind, args) ++ lenp]}
      template = Enum.map(names, &v/1)
      query = [AL.ast_to_pattern(quote(do: findall(unquote(template), unquote([call]), rs)))]

      on_question(prep, 20_000_000, fn branch, heap ->
        with {:ok, bindings, _shed} <- ask(query, branch, heap, root.name) do
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

  # The clauses as written, calls in body order, equations and guards
  # through `Zkfol.Al.Freeze`; len rides as one more parameter when
  # mentioned.
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
        env = [head | Enum.map(body, &Tuple.to_list/1)] |> qvars() |> Map.new(&{&1, &1})
        lenp = if len?, do: [v(:len)], else: []
        params = Enum.map(head, &qterm/1) ++ lenp

        {calls, defs} =
          body
          |> Enum.filter(&match?({:call, _n, _a}, &1))
          |> Enum.with_index()
          |> Enum.map_reduce([], fn {{:call, n, args}, j}, defs ->
            {args, defs} = Freeze.args(args, i, j, env, defs)
            {{n, [], [v(:self) | args] ++ lenp}, defs}
          end)

        with {:ok, guards} <- Freeze.guards(body, env),
             {:ok, equations} <- Freeze.equations(body, i, env) do
          goals = {:__block__, [], defs ++ guards ++ equations ++ calls}
          {:ok, defmethod(rname, [v(:self) | params], goals)}
        end

      bad ->
        {:error, {:head_not_a_column, %{head: bad}}}
    end
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
      {:ok, _bindings, _shed} -> :ok
      {:no, reason} -> {:error, {:send_failed, %{reason: reason}}}
      {:error, _reason} = refusal -> refusal
    end
  end

  # :head reads as wherever the session is checked out, for the viewer;
  # nothing named falls to the configured branch, if one is configured
  # -- the test suite lands every solve on one branch this way.
  @spec landing(term() | nil) :: term() | nil
  defp landing(:head), do: AL.Branch.head().id
  defp landing(nil), do: Application.get_env(:zkfol, :branch)
  defp landing(other), do: other

  @spec v(atom()) :: Macro.t()
  defp v(name), do: {name, [], nil}
end
