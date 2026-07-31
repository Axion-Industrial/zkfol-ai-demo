defmodule Examples.EUser do
  @moduledoc """
  I am the book of user relations: every statement of the corpus as
  defrel or rel writes it, each carried by the pipeline to the solved
  statement holding its predicate and witness, and the whole
  act through the front door. Inspecting `compiled/1` is the pipeline
  view.
  """

  use ExExample
  use Zkfol.Lang

  import ExUnit.Assertions

  alias Zkfol.Al
  alias Zkfol.Interpretation
  alias Zkfol.Lang
  alias Zkfol.Log
  alias Zkfol.Pipeline
  alias Zkfol.Refusal
  alias Zkfol.Semantics
  alias Zkfol.Statement
  alias Zkfol.Witness

  defrel fib(1, 1)
  defrel fib(2, 1)

  defrel fib(x, v) do
    x > 2
    fib(x - 1, v1)
    fib(x - 2, v2)
    v = v1 + v2
  end

  defrel regs(1, 1, 1)

  defrel regs(x, a, b) do
    x > 1
    regs(x - 1, a1, b1)
    a = a1 + b1
    b = a1
  end

  # The base rides as a value: prover's knowledge enters at construction.
  @spec power_rel(integer()) :: Lang.Rel.t()
  def power_rel(base) do
    rel :power do
      power(1, ^base, 0, 1)

      power(x, b, e, v) do
        x > 1
        power(x - 1, bb, ee, w)
        b = bb
        e = ee + 1
        v = b * w
      end
    end
  end

  defrel epower(1, 0, 1)

  defrel epower(x, e, v) do
    x > 1
    epower(x - 1, ee, h)
    e = ee + ee
    v = h * h
  end

  defrel epower(x, e, v) do
    x > 1
    epower(x - 1, ee, h)
    e = ee + ee + 1
    v = 2 * (h * h)
  end

  # The whole act on the default route; the receipt is what the
  # pipeline views open on.
  @spec compiled(pos_integer()) :: Log.Ran.t()
  example compiled(n \\ 8) do
    ran = Zkfol.compile(%Statement{rels: [fib()], args: [n]})
    assert %Log.Ran{} = ran
    ran
  end

  @spec eval_fills_the_holes(pos_integer()) :: [pos_integer()]
  example eval_fills_the_holes(n \\ 8) do
    assert {:ok, [^n, value]} = Zkfol.eval(fib(), [n, :_], [])
    assert value == fib(n)
    assert {:ok, [^n, ^value]} = Zkfol.eval(fib(), [n, value], [])
    [n, value]
  end

  @spec eval_selects_by_binding(pos_integer()) :: [pos_integer()]
  example eval_selects_by_binding(n \\ 8) do
    assert {:ok, [index, value]} = Zkfol.eval(fib(), [:_, fib(n)], [])
    assert fib(index) == value
    [index, value]
  end

  @spec eval_refuses_a_false_binding(pos_integer()) :: Refusal.t()
  example eval_refuses_a_false_binding(n \\ 8) do
    {:error, reason} = Zkfol.eval(fib(), [n, fib(n) + 1], [])
    assert {:no_derivation_at_count, %{count: ^n, relation: :fib}} = reason
    reason
  end

  # The plain route carries a source to the solved statement: the
  # predicate and the witness, derived off the relation alone.
  @spec fibonacci(pos_integer()) :: Statement.t()
  example fibonacci(n \\ 8) do
    {:ok, statement, _trace} = Pipeline.run(plain(), %Statement{rels: [fib()], args: [n]})

    witness = Statement.witness(statement)
    assert witness |> Interpretation.rows() |> Enum.at(1) == Enum.map(1..n, &fib/1)
    assert Enum.all?(1..n, &Semantics.holds?(Statement.pred(statement), witness, &1))
    statement
  end

  @spec registers(pos_integer()) :: Statement.t()
  example registers(n \\ 8) do
    {:ok, statement, _trace} = Pipeline.run(plain(), %Statement{rels: [regs()], args: [n]})

    assert Interpretation.at(Statement.witness(statement), 3, n) == fib(n)
    statement
  end

  @spec power(non_neg_integer()) :: Statement.t()
  example power(exponent \\ 3) do
    source = %Statement{rels: [power_rel(2)], args: [exponent + 1]}
    {:ok, statement, _trace} = Pipeline.run(plain(), source)

    assert Interpretation.at(Statement.witness(statement), 4, exponent + 1) == 2 ** exponent
    statement
  end

  @spec unseeded_base_is_knowledge() :: Refusal.t()
  example unseeded_base_is_knowledge do
    unseeded =
      rel :power do
        power(1, b, 0, 1)

        power(x, b, e, v) do
          x > 1
          power(x - 1, bb, ee, w)
          b = bb
          e = ee + 1
          v = b * w
        end
      end

    {:error, reason} = Al.solve(unseeded, [4])
    assert elem(reason, 0) in [:no_derivation, :no_derivation_at_count, :witness_value_negative]
    reason
  end

  # A relation built where values live: the pin splices them in.
  example a_relation_pins_runtime_values do
    k = 3

    scaled =
      rel :scaled do
        scaled(1, ^k)

        scaled(x, v) do
          x > 1
          scaled(x - 1, prev)
          v = ^k * prev
        end
      end

    {:ok, _compiled} = Lang.compile(scaled, [scaled])
    {:ok, witness} = Al.solve(scaled, [5])

    assert witness |> Interpretation.rows() |> Enum.at(1) == [3, 9, 27, 81, 243]
    scaled
  end

  # Two recursive clauses put the answer behind an infinite DFS
  # subtree, and unification cannot invert ee + ee; we fail as AL
  # fails. CLP reads the same equation as 2*ee = e and inverts it.
  @spec squaring_backward_awaits_clp() :: Zkfol.Refusal.t()
  example squaring_backward_awaits_clp do
    {:error, {kind, _} = reason} = Al.solve(epower(), [:_, 10], heap: 200_000)

    assert kind in [:heap_exhausted, :unresolved_within_budget]
    reason
  end

  @spec squaring_solves_at_the_base() :: Interpretation.t()
  example squaring_solves_at_the_base do
    {:ok, witness} = Al.solve(epower(), [:_, 0])

    assert Interpretation.len(witness) == 1
    assert witness |> Interpretation.rows() |> Enum.at(0) |> List.last() == 1
    assert witness |> Interpretation.rows() |> Enum.at(1) |> List.last() == 0
    witness
  end

  example unknown_relation_is_refused do
    {:error, reason} = Lang.compile(fib(), [])
    assert {:relation_not_in_scope, _} = reason
    reason
  end

  @doc "I am the module as a program: any defrel roots it, the rest ride as scope."
  @spec the_module_is_the_program() :: [Lang.Rel.t()]
  example the_module_is_the_program do
    [root | _scope] = program = program(:fib)

    assert root.name == :fib
    assert program |> Enum.map(& &1.name) |> Enum.sort() == [:epower, :fib, :regs]

    # The closure walk takes what it calls and ignores the rest.
    {:ok, %{rows: rows}} = Lang.compile(root, program)
    assert Map.keys(rows) == [:fib]
    program
  end

  @spec plain() :: Pipeline.t()
  def plain(), do: %Pipeline{passes: [{Zkfol.Lang, []}, {Witness, []}]}

  @spec fib(pos_integer()) :: pos_integer()
  def fib(n) do
    {a, _} = Enum.reduce(1..n, {0, 1}, fn _, {a, b} -> {b, a + b} end)
    a
  end
end
