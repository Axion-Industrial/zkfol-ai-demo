defmodule Zkfol.Lang do
  @moduledoc """
  I am the relational surface: Prolog-shaped clauses over one index,
  compiled to the core language by one rule. A relation owns an index
  row and a value row per output; every call allocates a pointer row,
  declared through the callee's index row, and reads the value rows
  through it as composed cells.

      defrel fib(1, 1)
      defrel fib(2, 1)

      defrel fib(x, v) do
        fib(x - 1, v1)
        fib(x - 2, v2)
        v = v1 + v2
      end

      Lang.compile(fib(), [fib()])
  """

  @behaviour Zkfol.Pipeline

  alias Zkfol.Ast
  alias Zkfol.Range
  alias Zkfol.Refusal
  alias Zkfol.Statement

  @typep rows :: %{atom() => [pos_integer()]}
  @typep env :: %{atom() => Ast.term_t()}
  @typep pointers :: {%{Ast.term_t() => pos_integer()}, pos_integer()}
  @typep tag :: {pos_integer(), %{atom() => pos_integer()}} | nil

  defmodule Rel do
    @moduledoc "I am a named relation: clauses of one head shape."
    use TypedStruct

    typedstruct enforce: true do
      field(:name, atom())
      field(:arity, pos_integer())
      field(:clauses, [{[term()], [term()]}])
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
        clauses: unquote(Macro.escape(clauses, unquote: true))
      }
    end
  end

  @spec rel_clause(atom(), Macro.t()) :: {[term()], [term()]}
  defp rel_clause(name, {name, _meta, args}) do
    case List.last(args) do
      [do: block] ->
        {args |> Enum.drop(-1) |> Enum.map(&term/1), block |> lines() |> Enum.map(&goal/1)}

      _bare ->
        {Enum.map(args, &term/1), []}
    end
  end

  defp rel_clause(name, {other, _meta, _args}),
    do: raise(ArgumentError, "the clause #{other} does not belong to the relation #{name}")

  @spec store(Macro.t(), [Macro.t()]) :: Macro.t()
  defp store(head, body) do
    {name, _meta, args} = head
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
              clauses: unquote(Macro.escape(clauses))
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
  defp term({:-, _meta, [a, b]}) when is_integer(b), do: {:add, term(a), -b}
  defp term({:-, _meta, [a, b]}), do: {:add, term(a), {:mul, term(b), -1}}

  # Surface goals: equations, guards, and calls.
  @spec goal(Macro.t()) :: term()
  defp goal({:=, _meta, [a, b]}), do: {:eq, term(a), term(b)}

  defp goal({op, _meta, [a, b]}) when op in [:<, :>, :<=, :>=],
    do: {:cmp, op, term(a), term(b)}

  defp goal({name, _meta, args}) when is_atom(name) and is_list(args),
    do: {:call, name, Enum.map(args, &term/1)}

  defp goal(form),
    do: raise(ArgumentError, "a goal is an equation or a call, not #{Macro.to_string(form)}")

  @doc "As a pass I lower a statement's relations to its predicate; the first is the root."
  @impl Zkfol.Pipeline
  @spec run(Statement.t(), keyword()) :: {:ok, Statement.t()} | {:error, Refusal.t()}
  def run(%Statement{rels: []} = statement, _opts), do: {:ok, statement}

  def run(%Statement{rels: [root | _rest] = rels} = statement, _opts) do
    with {:ok, %{pred: pred, ranges: ranges}} <- compile(root, rels),
         do: {:ok, Statement.lowered(%{statement | ranges: ranges}, pred)}
  end

  @impl Zkfol.Pipeline
  @spec verb() :: Zkfol.Pipeline.verdict()
  def verb, do: :lowers

  @doc """
  I compile a root relation against the relations in scope, walking
  its call closure and allocating rows: index and value rows per
  relation in closure order, then one pointer row per call site.

      Lang.compile(fib(), [fib(), double()])
  """
  @spec compile(Rel.t(), [Rel.t()]) ::
          {:ok,
           %{
             pred: Ast.pred(),
             rows: %{atom() => [pos_integer()]},
             ranges: [Range.check()],
             pointers: %{Ast.term_t() => pos_integer()},
             width: pos_integer(),
             tag: pos_integer() | nil,
             tags: %{atom() => pos_integer()}
           }}
          | {:error, Refusal.t()}
  def compile(%Rel{} = root, rels) do
    scope = Map.new(rels, &{&1.name, &1})

    with {:ok, order} <- closure([root.name], scope, MapSet.new(), []) do
      {values, next} =
        Enum.reduce(order, {%{}, 1}, fn name, {values, next} ->
          width = scope[name].arity
          {Map.put(values, name, Enum.to_list(next..(next + width - 1))), next + width}
        end)

      {tag, next} = tag(order, next)

      with {:ok, branches, {pointers, next}} <- branches(order, scope, values, tag, {%{}, next}) do
        ranges = pointers |> Map.values() |> Enum.sort() |> Enum.flat_map(&Range.pointer/1)

        {:ok,
         %{
           pred: Ast.disj(branches),
           rows: values,
           ranges: ranges,
           pointers: pointers,
           width: next - 1,
           tag: with({row, _tags} <- tag, do: row),
           tags: with({_row, tags} <- tag, do: tags) || %{}
         }}
      end
    end
  end

  # A lone relation is anchored by its own descent; a closure's columns
  # wear their relation, so a read can insist on whose column it reads.
  @spec tag([atom()], pos_integer()) ::
          {{pos_integer(), %{atom() => pos_integer()}} | nil, pos_integer()}
  defp tag([_lone], next), do: {nil, next}
  defp tag(order, next), do: {{next, order |> Enum.with_index(1) |> Map.new()}, next + 1}

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

  @spec branches([atom()], %{atom() => Rel.t()}, rows(), tag(), pointers()) ::
          {:ok, [Ast.pred()], pointers()} | {:error, Refusal.t()}
  defp branches(order, scope, values, tag, pointers) do
    with {:ok, branches, pointers} <-
           Refusal.map_reduce(order, pointers, fn name, pointers ->
             rel_branches(scope[name], values[name], values, tag, pointers)
           end),
         do: {:ok, Enum.concat(branches), pointers}
  end

  @spec rel_branches(Rel.t(), [pos_integer()], rows(), tag(), pointers()) ::
          {:ok, [Ast.pred()], pointers()} | {:error, Refusal.t()}
  defp rel_branches(%Rel{name: name, clauses: clauses}, rows, values, tag, pointers) do
    with {:ok, branches, pointers} <-
           Refusal.map_reduce(clauses, pointers, &branch(&1, rows, values, tag, &2)),
         do: {:ok, Enum.map(branches, &claim(&1, name, tag)), pointers}
  end

  # Every branch of a tagged closure claims its column; drop the claim
  # and a column may wear one relation's tag while satisfying another's
  # branch, which is the forgery the tag exists to refuse.
  @spec claim(Ast.pred(), atom(), tag()) :: Ast.pred()
  defp claim(branch, _name, nil), do: branch

  defp claim({:conj, goals}, name, {row, tags}),
    do: Ast.conj(goals ++ [Ast.eq(Ast.cell(row), Map.fetch!(tags, name))])

  # One clause: the head binds the index and value rows, each call
  # binds a pointer row and its outputs, then the equations close over
  # the environment.
  @spec branch({[term()], [term()]}, [pos_integer()], rows(), tag(), pointers()) ::
          {:ok, Ast.pred(), pointers()} | {:error, Refusal.t()}
  defp branch({params, body}, rows, values, tag, pointers) do
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

    with {:ok, goals, env, pointers} <- calls(body, values, tag, env, pointers),
         {:ok, equations} <- equations(body, env),
         do: {:ok, Ast.conj(heads ++ goals ++ equations), pointers}
  end

  # Calls resolving to one target share their pointer row: a pointer
  # is a position, whoever reads through it.
  @spec calls([term()], rows(), tag(), env(), pointers()) ::
          {:ok, [Ast.pred()], env(), pointers()} | {:error, Refusal.t()}
  defp calls(body, values, tag, env, pointers) do
    body
    |> Enum.filter(&match?({:call, _n, _a}, &1))
    |> Refusal.map_reduce({env, pointers}, fn {:call, name, [at | outs]}, {env, pointers} ->
      [index | value_rows] = values[name]

      with {:ok, target} <- resolve(at, env),
           {row, pointers} = point(pointers, target),
           {:ok, env} <- outputs(outs, value_rows, row, env),
           do: {:ok, [schedule(index, row, target) | check(tag, name, row)], {env, pointers}}
    end)
    |> case do
      {:ok, goals, {env, pointers}} -> {:ok, Enum.concat(goals), env, pointers}
      refusal -> refusal
    end
  end

  # A tagged read insists the pointed column is the callee's.
  @spec check(tag(), atom(), pos_integer()) :: [Ast.pred()]
  defp check(nil, _name, _pointer), do: []

  defp check({row, tags}, name, pointer),
    do: [Ast.eq(Ast.cell(row, pointer), Map.fetch!(tags, name))]

  @spec point(pointers(), Ast.term_t()) :: {pos_integer(), pointers()}
  defp point({rows, next} = pointers, target) do
    case rows do
      %{^target => row} -> {row, pointers}
      _rows -> {next, {Map.put(rows, target, next), next + 1}}
    end
  end

  # An affine self-call reads as the paper writes it: the index here is
  # the index there plus the offset. Anything else pins the pointed
  # index to the target directly.
  @spec schedule(pos_integer(), pos_integer(), term()) :: Ast.pred()
  defp schedule(index, pointer, {:add, {:cell, index}, q}) when is_integer(q),
    do: Ast.eq(Ast.cell(index), Ast.add(Ast.cell(index, pointer), -q))

  defp schedule(index, pointer, target), do: Ast.eq(Ast.cell(index, pointer), target)

  # A call's outputs are the callee's value rows read through the pointer.
  @spec outputs([term()], [pos_integer()], pos_integer(), env()) ::
          {:ok, env()} | {:error, Refusal.t()}
  defp outputs(outs, value_rows, pointer, env) do
    outs
    |> Enum.zip(value_rows)
    |> Enum.reduce_while({:ok, env}, fn
      {{:var, name}, row}, {:ok, env} when not is_map_key(env, name) ->
        {:cont, {:ok, Map.put(env, name, Ast.cell(row, pointer))}}

      {out, _row}, _acc ->
        {:halt, {:error, {:call_output_not_fresh, %{output: out}}}}
    end)
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
