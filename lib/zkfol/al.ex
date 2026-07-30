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
           window: pos_integer(),
           dynamic: [pos_integer()],
           len?: boolean(),
           arity: pos_integer()
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
  I derive the witness at `arguments`, or refuse with the reason.

      solve(Examples.EUser.fib(), [8])
      solve(kernel_statement, [:_, n - 2])
      solve(Examples.EFacts.factorial(), [6], branch: :head)

  A statement's arguments are its claims in order, `:_` free, the
  column count found by deepening; a relation takes its final column
  index. `:bind` fixes final-column cells by row, `:branch` keeps
  the install, `:depth` caps the deepening, `:heap` bounds the
  derivation, `:basedon` bases the journaled derivation, landing it
  on that act's trail.
  """
  @spec solve(Ast.pred() | Statement.t() | Rel.t() | [Rel.t()], [pos_integer() | :_], keyword()) ::
          {:ok, Interpretation.t()} | {:error, Refusal.t()}
  def solve(target, arguments, opts \\ [])

  def solve(%Statement{rels: [root | _rest] = rels, claims: []} = statement, [n | _args], opts)
      when is_integer(n) and n > 0 do
    opts = Keyword.put_new(opts, :name, root.name)

    with {:ok, pred} <- statement_pred(statement),
         {:ok, program, plan} <- clauses_program(rels, Keyword.fetch!(opts, :name)),
         do: run_installed(program, pred, plan, [n], Keyword.get(opts, :bind, %{}), opts)
  end

  def solve(
        %Statement{rels: [root | _rest] = rels, claims: [_ | _] = claims} = statement,
        arguments,
        opts
      ) do
    bind =
      claims
      |> Enum.zip(arguments)
      |> Enum.reject(&match?({_claim, :_}, &1))
      |> Map.new(fn {{_name, i, _col}, value} -> {i, value} end)

    counts = 1..Keyword.get(opts, :depth, 4096)

    opts =
      Keyword.merge(opts, name: root.name, bind: Map.merge(bind, Keyword.get(opts, :bind, %{})))

    with {:ok, program, plan} <- clauses_program(rels, root.name),
         {:ok, pred} <- statement_pred(statement),
         do: run_installed(program, pred, plan, counts, Keyword.fetch!(opts, :bind), opts)
  end

  def solve(%Statement{rels: []}, _arguments, _opts),
    do: {:error, {:no_relations, %{}}}

  def solve(%Statement{}, args, _opts),
    do: {:error, {:one_bound_input_only, %{args: args}}}

  def solve(%Rel{} = root, arguments, opts), do: solve([root], arguments, opts)

  def solve([%Rel{} | _rest] = rels, [n], opts) when is_integer(n) and n > 0 do
    opts = Keyword.put_new(opts, :name, hd(rels).name)

    with {:ok, program, plan} <- clauses_program(rels, Keyword.fetch!(opts, :name)),
         {:ok, %{pred: pred}} <- Lang.compile(hd(rels), rels),
         do: run_installed(program, pred, plan, [n], Keyword.get(opts, :bind, %{}), opts)
  end

  def solve({tag, _parts}, _arguments, _opts) when tag in [:conj, :disj],
    do: {:error, {:raw_predicate_has_no_clauses, %{}}}

  def solve({:eq, _t, _u}, _arguments, _opts),
    do: {:error, {:raw_predicate_has_no_clauses, %{}}}

  def solve(_pred, args, _opts),
    do: {:error, {:one_bound_input_only, %{args: args}}}

  # The pred the stage already carries; compiled only when none does.
  @spec statement_pred(Statement.t()) :: {:ok, Ast.pred()} | {:error, Refusal.t()}
  defp statement_pred(%Statement{stage: :raw, rels: [root | _rest] = rels}) do
    with {:ok, %{pred: pred}} <- Lang.compile(root, rels), do: {:ok, pred}
  end

  defp statement_pred(statement), do: {:ok, Statement.pred(statement)}

  # A free pointer left unbound by everything else enumerates the
  # columns below.
  @spec enumerations(plan()) :: [Macro.t()]
  defp enumerations(plan) do
    for j <- plan.dynamic do
      c = v(row(j, "c"))
      quote(do: alternative([vm_ground(unquote(c))], [between(self, 1, x1, unquote(c))]))
    end
  end

  # A step guards past the window and recurses; its equations wait
  # frozen for whichever side arrives, derefs wait on the trace, and a
  # pointer still free at the end enumerates.
  @spec step(atom(), [Macro.t()], [Macro.t()], [Macro.t()], plan()) :: Macro.t()
  defp step(name, head, current, defining, plan) do
    body =
      quote do
        x > unquote(plan.window)
        vm_is(x1, x - 1)
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

  @spec recurse(atom(), plan()) :: Macro.t()
  defp recurse(name, plan) do
    args = Enum.map(plan.rows, &v(row(&1, "p1"))) ++ if(plan.len?, do: [v(:len)], else: [])
    {name, [], [v(:self), v(:x1) | args] ++ [v(:t)]}
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
  @spec installed(atom(), [Macro.t()]) :: program()
  defp installed(name, clauses) do
    program =
      quote do
        vm_set_class(unquote(@class), :object)

        forall([vm_method(unquote(@class), unquote(name), impl), vm_clause(impl, h, _b)]) do
          vm_retract_oapply(impl, h)
        end

        unquote_splicing(clauses)
      end

    AL.ast_to_pattern(program)
  end

  # --- clauses, directly: a relation is nearly the program ---

  # One self-recursive relation; everything else still derives through
  # the core path, and says so.
  @spec clauses_program([Rel.t()], atom()) ::
          {:ok, program(), plan()} | {:error, Refusal.t()}
  defp clauses_program([%Rel{} = rel | rest], name) do
    with :ok <- lone(rest, rel),
         {:ok, plan, computed} <- rel_plan(rel),
         {:ok, clauses} <- rel_clauses(rel, name, plan, computed),
         do: {:ok, installed(name, clauses), plan}
  end

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
      arity: a + map_size(offsets) + map_size(computed)
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
    head = [v(:self), k | current] ++ if(plan.len?, do: [v(:len)], else: [])

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
         {:ok, equations} <- rel_equations(body, i, env) do
      {:ok, step(name, [v(:self), v(:x) | current] ++ len, current, reads ++ equations, plan)}
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

  @spec run_installed(program(), Ast.pred(), plan(), Enumerable.t(), bind(), keyword()) ::
          {:ok, Interpretation.t()} | {:error, Refusal.t()}
  defp run_installed(program, pred, plan, counts, bind, opts) do
    name = Keyword.get(opts, :name, :col)
    heap = Keyword.get(opts, :heap, 256_000_000)
    basedon = Keyword.get(opts, :basedon)

    AL.Branch.on(landing(Keyword.get(opts, :branch)), fn branch ->
      with {:atomic, _} <- AL.eval(program, nil, branch, heap: heap) do
        Enum.reduce_while(counts, {:error, {:no_derivation, %{}}}, fn count, deepest ->
          query = query(name, count, bind, plan)

          case AL.eval([query], nil, branch, heap: heap) do
            {:atomic, _} = derived ->
              {:halt, deliver(derived, pred, count, plan, branch, name, basedon)}

            {:aborted, _} = refused ->
              {:cont, keep_named(refused, deepest, count, name)}

            exceeded ->
              {:halt, Refusal.from_al(exceeded)}
          end
        end)
      else
        {:aborted, reason} -> {:error, {:send_failed, %{reason: reason}}}
        exceeded -> Refusal.from_al(exceeded)
      end
    end)
  end

  # :head reads as wherever the session is checked out, for the viewer.
  @spec landing(term() | nil) :: term() | nil
  defp landing(:head), do: AL.Branch.head().id
  defp landing(other), do: other

  @spec query(atom(), pos_integer(), bind(), plan()) :: struct()
  defp query(name, count, bind, plan) do
    goal = Enum.map(plan.rows, &Map.get(bind, &1, v(row(&1, "c"))))
    args = [count | goal] ++ if(plan.len?, do: [count], else: []) ++ [v(:t)]
    AL.ast_to_pattern({name, [], [@class | args]})
  end

  # Deepening keeps the deepest refusal for the day none derives.
  @spec keep_named({:aborted, term()}, {:error, Refusal.t()}, pos_integer(), atom()) ::
          {:error, Refusal.t()}
  defp keep_named({:aborted, %{failed_on: goal}}, _deepest, count, name) do
    {:error, {:no_derivation_at_depth, %{depth: count, relation: name, goal: goal}}}
  end

  defp keep_named({:aborted, _reason}, deepest, _count, _name), do: deepest

  # Semantic rows come off the trace, pointer rows off their schedule,
  # unread rows are padding, and the oracle judges every column.
  @spec deliver(
          {:atomic, {AL.Var.bindings(), AL.t()}},
          Ast.pred(),
          pos_integer(),
          plan(),
          AL.Branch.t(),
          atom(),
          pos_integer() | nil
        ) :: {:ok, Interpretation.t()} | {:error, Refusal.t()}
  defp deliver({:atomic, {bindings, _state}}, pred, count, plan, branch, name, basedon) do
    trace = bindings |> AL.Var.deref(:"$t") |> AL.Var.subst(bindings) |> Enum.reverse()

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

      case Enum.find(1..count, &(Semantics.eval(pred, witness, &1) != 0)) do
        nil ->
          Log.push({:al_solved, %{name: name, count: count, branch: branch.id}}, basedon)
          {:ok, witness}

        x ->
          {:error, {:column_unsatisfied, %{column: x}}}
      end
    end
  end

  # --- names ---

  @spec row(pos_integer(), String.t()) :: atom()
  defp row(i, prefix), do: :"#{prefix}#{i}"

  @spec v(atom()) :: Macro.t()
  defp v(name), do: {name, [], nil}
end
