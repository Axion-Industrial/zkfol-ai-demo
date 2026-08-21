defmodule Zkfol.Al do
  @moduledoc """
  I am the AL backend: a statement becomes clauses and runs as written,
  so the derivation is the witness.
  """

  alias Zkfol.Al.Ask
  alias Zkfol.Derivation
  alias Zkfol.Lang
  alias Zkfol.Lang.Rel
  alias Zkfol.Lang.Term
  alias Zkfol.Ast
  alias Zkfol.Refusal
  alias Zkfol.Log
  alias Zkfol.Statement

  @class :zkfol

  @heap 256_000_000

  @typedoc "An emitted AL program: goal structs ready for AL.eval/3."
  @type program :: [struct()]

  @typep bind :: %{optional(pos_integer()) => integer()}

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

  @doc "I am the program as AL holds it: the class object on `branch`."
  @spec program(atom()) :: AL.Object.t()
  def program(branch), do: %AL.Object{id: @class, branch: branch}

  @doc "I am the derivation `arguments` establish."
  @spec derived(Statement.t() | Rel.t() | [Rel.t()], [Statement.datum() | :_], keyword()) ::
          {:ok, Derivation.t()} | {:error, Refusal.t()}
  def derived(target, arguments, opts \\ []) do
    with {:ok, rels} <- rels(target), do: derive_rels(rels, arguments, opts)
  end

  @doc """
  I open a stepping ask at `arguments`: the question of `target` installed
  on a branch of my own, and the goal that runs against it.

  The ask holds AL's search state, so the process that opens it is the
  process that must step it.
  """
  @spec open(Statement.t() | Rel.t() | [Rel.t()], [Statement.datum() | :_], keyword()) ::
          {:ok, Ask.t()} | {:error, Refusal.t()}
  def open(target, arguments, opts) do
    with {:ok, rels} <- rels(target),
         {:ok, prep} <- prepared(rels, arguments, opts) do
      branch = AL.Branch.fork(:tip, based(landing(prep.branch)))

      case install(prep.program, branch, prep.heap || @heap) do
        :ok ->
          {:ok,
           %Ask{
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

  @doc "I take the ask's next answer, and the ask to step again."
  @spec step(Ask.t()) :: {Ask.outcome(), Ask.t()}
  def step(%Ask{state: nil} = ask), do: answered(AL.eval(ask.goal, nil, ask.branch, []), ask)
  def step(%Ask{state: state} = ask), do: answered(AL.next_solution(state), ask)

  @doc "I discard the ask's branch: the install and its journal go with it."
  @spec close(Ask.t()) :: :ok
  def close(%Ask{branch: branch}), do: AL.Branch.discard(branch)

  @spec answered(term(), Ask.t()) :: {Ask.outcome(), Ask.t()}
  defp answered(evaluated, ask) do
    case outcome(evaluated) do
      {:ok, bindings, state} -> {ground(bindings, ask.arguments), %{ask | state: state}}
      {:no, _reason} -> {:exhausted, ask}
      {:error, _reason} = refusal -> {refusal, ask}
    end
  end

  @spec ground(AL.Var.store(), [Statement.datum() | :_]) ::
          {:ok, [Statement.datum()]} | {:error, Refusal.t()}
  defp ground(bindings, arguments) do
    answer =
      for {argument, row} <- Enum.with_index(arguments, 1) do
        if argument == :_,
          do: bindings |> AL.Var.deref(:"$qa#{row}") |> AL.Var.subst(bindings),
          else: argument
      end

    if Enum.all?(answer, &ground?/1),
      do: {:ok, answer},
      else: {:error, {:residue, %{answer: answer}}}
  end

  # A run that built a sequence leaves the tail open until the last call closes it.
  @spec ground?(term()) :: boolean()
  defp ground?(q) when is_integer(q), do: true
  defp ground?(cells) when is_list(cells), do: Enum.all?(cells, &ground?/1)
  defp ground?(_open), do: false

  @spec derive_rels([Rel.t()], [Statement.datum() | :_], keyword()) ::
          {:ok, Derivation.t()} | {:error, Refusal.t()}
  defp derive_rels(rels, args, opts) do
    with {:ok, prep} <- prepared(rels, args, opts) do
      on_question(prep, @heap, fn branch, heap ->
        with {:ok, derivation} <- derive(prep, branch, heap) do
          count = length(derivation.facts)
          event = {:al_solved, %{name: prep.name, count: count, branch: branch.id}}
          Log.push(event, prep.basedon)

          {:ok, derivation}
        end
      end)
    end
  end

  @spec rels(Statement.t() | Rel.t() | [Rel.t()]) :: {:ok, [Rel.t()]} | {:error, Refusal.t()}
  defp rels(%Statement{rels: [root | _rest] = rels}), do: Lang.reached(root, rels)
  defp rels(%Rel{} = root), do: Lang.reached(root, [root])
  defp rels([%Rel{} = root | _rest] = list), do: Lang.reached(root, list)
  defp rels(_none), do: {:error, {:no_relations, %{}}}

  @spec prepared([Rel.t()], [integer() | atom()], keyword()) ::
          {:ok, prep()} | {:error, Refusal.t()}
  defp prepared([root | _rest] = rels, args, opts) do
    len? = Enum.any?(rels, &mentions_len?(&1.clauses))

    with {:ok, program} <- question_program(rels, len?),
         {:ok, bind} <- bind(Enum.to_list(1..root.arity//1), args),
         :ok <- len_bound(len?, bind) do
      {:ok,
       %{
         root: root,
         name: Keyword.get(opts, :name, root.name),
         names: MapSet.new(Enum.reject(rels, & &1.phi), & &1.name),
         program: program,
         bind: bind,
         len?: len?,
         branch: Keyword.get(opts, :branch),
         basedon: Keyword.get(opts, :basedon),
         heap: Keyword.get(opts, :heap)
       }}
    end
  end

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

  # AL keeps every call under the frame that made it, so its journal is the derivation.
  @spec derive(prep(), AL.Branch.t(), pos_integer()) ::
          {:ok, Derivation.t()} | {:error, Refusal.t()}
  defp derive(
         %{root: root, bind: bind, name: name, names: names, len?: len?} = prep,
         branch,
         heap
       ) do
    digest = &Derivation.of(&1, names, len?)

    with {:ok, _bindings, derivation} <-
           ask(plain(call(prep, goal(root.arity, bind, []))), branch, heap, name, digest),
         do: {:ok, derivation}
  end

  @spec call(prep(), [Macro.t() | integer()]) :: Macro.t()
  defp call(%{root: root, len?: false}, args), do: {root.name, [], [@class | args]}

  defp call(%{root: root, len?: true, bind: bind}, args),
    do: {root.name, [], [@class | args ++ [Map.fetch!(bind, 1)]]}

  @spec plain(Macro.t()) :: [struct()]
  defp plain(goal), do: [AL.ast_to_pattern(goal)]

  # The heap cap is ours, not AL's: its guarded eval sheds the state to
  # nothing, and the derivation is what we came for.
  @spec ask([struct()], AL.Branch.t(), pos_integer(), atom(), (AL.t() -> Derivation.t())) ::
          {:ok, AL.Var.store(), Derivation.t()} | {:error, Refusal.t()}
  defp ask(query, branch, heap, name, digest) do
    case outcome(capped_eval(query, branch, heap, digest)) do
      {:ok, bindings, derived} -> {:ok, bindings, derived}
      {:no, _reason} -> {:error, {:no_answer, %{relation: name}}}
      {:error, _reason} = refusal -> refusal
    end
  end

  # An exit reason is copied onto the parent's uncapped heap, so only what
  # `digest` made of the state leaves the capped process.
  @spec capped_eval([struct()], AL.Branch.t(), pos_integer(), (AL.t() -> Derivation.t())) ::
          term()
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

  @spec digested(term(), (AL.t() -> Derivation.t())) :: term()
  defp digested({:atomic, {bindings, state}}, digest), do: {:atomic, {bindings, digest.(state)}}
  defp digested(other, _digest), do: other

  @spec goal(pos_integer(), bind(), [integer() | atom()]) :: [Macro.t() | integer()]
  defp goal(arity, bind, args) do
    Enum.zip(1..arity//1, Stream.concat(args, Stream.cycle([:_])))
    |> Enum.map(fn
      {_row, a} when is_atom(a) and a != :_ -> v(a)
      {row, _} -> Map.get(bind, row, v(:"qa#{row}"))
    end)
  end

  # A search stopped by the budget never reached a no, so it refuses as itself.
  @spec outcome(term()) ::
          {:ok, AL.Var.store(), term()} | {:no, term()} | {:error, Refusal.t()}
  defp outcome({:atomic, {bindings, state}}), do: {:ok, bindings, state}

  defp outcome({:aborted, %{reason: {:resource_limit_exceeded, n}}}),
    do: {:error, {:unresolved_within_budget, %{reductions: n}}}

  defp outcome({:aborted, reason}), do: {:no, reason}
  defp outcome(exceeded), do: Refusal.from_al(exceeded)

  # An argument past the last row addresses nothing, and zipping it away
  # would answer a question no one asked.
  @spec bind([pos_integer()], [integer() | atom()]) :: {:ok, bind()} | {:error, Refusal.t()}
  defp bind(rows, args) when length(args) > length(rows),
    do: {:error, {:arguments_exceed_rows, %{args: length(args), rows: length(rows)}}}

  defp bind(rows, args),
    do: {:ok, rows |> Enum.zip(args) |> Enum.reject(fn {_row, a} -> is_atom(a) end) |> Map.new()}

  @spec question_program([Rel.t()], boolean()) :: {:ok, program()} | {:error, Refusal.t()}
  defp question_program(rels, len?) do
    hints =
      Map.new(
        for %Rel{al: al, clauses: [{head, _body} | _rest]} = rel <- rels,
            al != nil,
            do: {rel.name, {head, al}}
      )

    # A relation with no clauses of its own says nothing a send could add.
    said =
      MapSet.new(
        for %Rel{al: al, clauses: clauses} = rel <- rels,
            al != nil,
            Enum.all?(clauses, fn {_head, body} -> body == [] end),
            do: rel.name
      )

    rels
    |> Enum.flat_map(fn rel -> Enum.map(rel.clauses, &{rel.name, rel.al, &1}) end)
    |> Enum.with_index()
    |> Refusal.map(fn {{rname, al, clause}, i} ->
      question_clause(rname, al, clause, i, len?, hints, said)
    end)
    |> case do
      {:ok, clauses} -> {:ok, installed(Enum.map(rels, & &1.name), clauses)}
      refusal -> refusal
    end
  end

  @spec question_clause(
          atom(),
          Macro.t() | nil,
          {[term()], [term()]},
          non_neg_integer(),
          boolean(),
          %{atom() => {[term()], Macro.t()}},
          MapSet.t()
        ) :: {:ok, Macro.t()} | {:error, Refusal.t()}
  defp question_clause(rname, al, {head, body}, i, len?, hints, said) do
    case Enum.find(head, &(not Term.seatable?(&1))) do
      nil ->
        lenp = if len?, do: [v(:len)], else: []
        reading = if al, do: [saying(al, %{})], else: []

        {entry, written} =
          body |> Enum.reject(&saying?(&1, said)) |> numbered() |> Enum.split_with(&postable?/1)

        with {:ok, params} <- Refusal.map(head, &arith/1),
             {:ok, posted} <- Refusal.flat_map(body, &hinted(&1, hints)),
             {:ok, goals} <- Refusal.flat_map(entry ++ written, &goals(&1, i, lenp)) do
          {:ok,
           defmethod(
             rname,
             [v(:self) | params ++ lenp],
             {:__block__, [], reading ++ posted ++ goals}
           )}
        end

      bad ->
        {:error, {:head_not_a_column, %{head: bad}}}
    end
  end

  @spec saying?(term(), MapSet.t()) :: boolean()
  defp saying?({:call, q, _args}, said), do: MapSet.member?(said, q)
  defp saying?(_goal, _said), do: false

  # The fixpoint narrows from a bound, not from the slack standing for it, so the reading posts.
  @spec hinted(term(), %{atom() => {[term()], Macro.t()}}) ::
          {:ok, [Macro.t()]} | {:error, Refusal.t()}
  defp hinted({:call, q, args}, hints) when is_map_key(hints, q) do
    {params, al} = hints[q]

    with {:ok, lowered} <- Refusal.map(args, &arith/1),
         do:
           {:ok,
            [saying(al, Map.new(Enum.zip(params, lowered), fn {{:var, p}, t} -> {p, t} end))]}
  end

  defp hinted(_goal, _hints), do: {:ok, []}

  # Substituted once, so a caller's name of its own cannot be taken for the callee's.
  @spec saying(Macro.t(), %{atom() => Macro.t()}) :: Macro.t()
  defp saying(al, by) do
    filled = Map.new(by, fn {name, term} -> {{:hole, name}, term} end)

    al
    |> Macro.prewalk(fn
      {name, _meta, ctx} when is_atom(name) and is_atom(ctx) ->
        if is_map_key(by, name), do: {:hole, name}, else: {name, [], nil}

      node ->
        node
    end)
    |> Macro.prewalk(&Map.get(filled, &1, &1))
  end

  # A call's place among the calls is what tells its fresh argument names from another's.
  @spec numbered([term()]) :: [{term(), non_neg_integer()}]
  defp numbered(body) do
    body
    |> Enum.map_reduce(0, fn
      {:call, _n, _a} = call, j -> {{call, j}, j + 1}
      other, j -> {{other, j}, j}
    end)
    |> elem(0)
  end

  # AL's fixpoint carries a linear constraint open; a product of two unknowns waits in place.
  @spec postable?({term(), non_neg_integer()}) :: boolean()
  defp postable?({{:eq, t, u}, _j}), do: linear?(t) and linear?(u)
  defp postable?({_statement, _j}), do: false

  @spec linear?(term()) :: boolean()
  defp linear?({:mul, t, u}), do: (is_integer(t) or is_integer(u)) and linear?(t) and linear?(u)
  defp linear?({:add, t, u}), do: linear?(t) and linear?(u)
  defp linear?({:reify, {:eq, t, u}}), do: linear?(Ast.arithmetize(Ast.eq(t, u)))
  defp linear?(_term), do: true

  @spec goals({term(), non_neg_integer()}, non_neg_integer(), [Macro.t()]) ::
          {:ok, [Macro.t()]} | {:error, Refusal.t()}
  defp goals({{:eq, t, u}, _j}, _i, _lenp) do
    op = if Term.sequence?(t) or Term.sequence?(u), do: :unify, else: :eq
    with {:ok, goal} <- binary(op, t, u), do: {:ok, [goal]}
  end

  defp goals({{:call, callee, args}, j}, i, lenp) do
    with {:ok, passed} <- Refusal.map(Enum.with_index(args), &argument(&1, i, j)) do
      {defs, args} = Enum.unzip(passed)
      {:ok, Enum.concat(defs) ++ sent(callee, args ++ lenp, i, j)}
    end
  end

  # A call through a passed name is Prolog's call/N: rebuild the term, call_term it.
  @spec sent(atom() | {:var, atom()}, [Macro.t()], non_neg_integer(), non_neg_integer()) ::
          [Macro.t()]
  defp sent({:var, carrier}, args, i, j) do
    [nm, ps, as, g] = for tail <- ~w(nm ps as g), do: v(:"q#{i}c#{j}#{tail}")

    [
      functor(v(carrier), nm, ps),
      {:concat, [], [ps, args, as]},
      functor(g, nm, as),
      {:call_term, [], [g]}
    ]
  end

  defp sent(name, args, _i, _j), do: [{name, [], [v(:self) | args]}]

  @spec argument({term(), term()}, non_neg_integer(), non_neg_integer()) ::
          {:ok, {[Macro.t()], Macro.t()}} | {:error, Refusal.t()}
  defp argument({{:papply, name, prefix}, k}, i, j) do
    fresh = v(:"q#{i}c#{j}a#{k}")

    with {:ok, fixed} <-
           Refusal.map(Enum.with_index(prefix), fn {held, p} ->
             argument({held, "#{k}p#{p}"}, i, j)
           end) do
      {built, bound} = Enum.unzip(fixed)
      {:ok, {Enum.concat(built) ++ [functor(fresh, name, [v(:self) | bound])], fresh}}
    end
  end

  defp argument({term, k}, i, j) do
    fresh = v(:"q#{i}c#{j}a#{k}")

    with {:ok, lifted} <- arith(term) do
      if is_integer(term) or match?({:var, _nm}, term) or Term.sequence?(term),
        do: {:ok, {[], lifted}},
        else: {:ok, {[{:eq, [], [fresh, lifted]}], fresh}}
    end
  end

  @spec functor(Macro.t(), Macro.t(), [Macro.t()]) :: Macro.t()
  defp functor(term, name, args), do: {:vm_functor, [], [term, name, args]}

  @spec arith(term()) :: {:ok, Macro.t()} | {:error, Refusal.t()}
  defp arith(q) when is_integer(q), do: {:ok, q}
  defp arith(:len), do: {:ok, v(:len)}
  defp arith({:var, nm}), do: {:ok, v(nm)}
  defp arith({:reify, {:eq, t, u}}), do: arith(Ast.arithmetize(Ast.eq(t, u)))
  defp arith({:add, t, u}), do: binary(:+, t, u)
  defp arith({:mul, t, u}), do: binary(:*, t, u)
  defp arith(nil), do: {:ok, []}

  defp arith({:cons, head, tail}) do
    with {:ok, head} <- arith(head),
         {:ok, tail} <- arith(tail),
         do: {:ok, [{:|, [], [head, tail]}]}
  end

  defp arith(term), do: {:error, {:unliftable_term, %{term: term}}}

  @spec binary(atom(), term(), term()) :: {:ok, Macro.t()} | {:error, Refusal.t()}
  defp binary(op, t, u) do
    with {:ok, a} <- arith(t),
         {:ok, b} <- arith(u),
         do: {:ok, {op, [], [a, b]}}
  end

  @spec mentions_len?([{[Term.t()], [Term.goal()]}]) :: boolean()
  defp mentions_len?(clauses) do
    Enum.any?(clauses, fn {head, body} ->
      Term.reduce(head ++ body, false, &(&2 or &1 == :len))
    end)
  end

  @spec defmethod(atom(), [Macro.t()], Macro.t()) :: Macro.t()
  defp defmethod(name, head, body), do: {:defmethod, [], [@class, name, head, [do: body]]}

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

  @spec install(program(), AL.Branch.t(), pos_integer()) :: :ok | {:error, Refusal.t()}
  defp install(program, branch, heap) do
    case outcome(AL.eval(program, nil, branch, heap: heap)) do
      {:ok, _bindings, _state} -> :ok
      {:no, reason} -> {:error, {:send_failed, %{reason: reason}}}
      {:error, _reason} = refusal -> refusal
    end
  end

  @spec based(term() | nil) :: AL.Branch.t()
  defp based(nil), do: AL.Branch.head()
  defp based(id), do: %AL.Branch{id: id}

  # Nothing named falls to the configured branch: how the test suite lands
  # every solve on one branch.
  @spec landing(term() | nil) :: term() | nil
  defp landing(:head), do: AL.Branch.head().id
  defp landing(nil), do: Application.get_env(:zkfol, :branch)
  defp landing(other), do: other

  @spec v(atom()) :: Macro.t()
  defp v(name), do: {name, [], nil}
end
