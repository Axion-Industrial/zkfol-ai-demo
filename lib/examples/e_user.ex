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
  alias Zkfol.Prover
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

  # Mod 7919 by existential witness: the quotient rides the head until
  # fresh body names get columns, and the sign guards are Z-side only.
  defrel regsm(1, 1, 1, 0)

  defrel regsm(x, a, b, q) do
    x > 1
    regsm(x - 1, a1, b1, q1)
    a1 + b1 = q * 7919 + a
    a < 7919
    a + 1 > 0
    q + 1 > 0
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
    {:ok, query} = Zkfol.eval(fib(), [n, :_], [])
    assert [[^n, value]] = Zkfol.Query.taken(query)
    assert value == fib(n)
    Zkfol.Query.close(query)

    again = Zkfol.eval!(fib(), [n, value], [])
    assert Zkfol.Query.taken(again) == [[n, value]]
    Zkfol.Query.close(again)
    [n, value]
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

  @spec one_column() :: Prover.Report.t()
  example one_column do
    ran = Zkfol.compile(%Statement{rels: [fib()], args: [1]})
    assert Interpretation.len(Statement.witness(Log.Ran.final_stage(ran))) == 1
    assert %Prover.Report{} = report = Log.report(Log.snapshot(), ran)
    report
  end

  @spec registers(pos_integer()) :: Statement.t()
  example registers(n \\ 8) do
    {:ok, statement, _trace} = Pipeline.run(plain(), %Statement{rels: [regs()], args: [n]})

    assert Interpretation.at(Statement.witness(statement), 3, n) == fib(n)
    statement
  end

  @spec registers_mod(pos_integer()) :: Statement.t()
  example registers_mod(n \\ 300) do
    source = %Statement{rels: [regsm()], args: [n, :_, :_, :_]}
    {:ok, statement, _trace} = Pipeline.run(plain(), source)

    assert Interpretation.at(Statement.witness(statement), 2, n) == rem(fib(n + 1), 7919)
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
    assert elem(reason, 0) == :no_answer
    reason
  end

  # Two recursive clauses put the answer behind an infinite DFS subtree
  # for unification, which cannot invert ee + ee. CLP reads the same
  # equation as 2*ee = e and runs the exponent backward.
  @spec squaring_runs_backward() :: Interpretation.t()
  example squaring_runs_backward do
    {:ok, witness} = Al.solve(epower(), [:_, 10])

    assert witness |> Interpretation.rows() |> Enum.at(1) |> List.last() == 10
    assert witness |> Interpretation.rows() |> Enum.at(2) |> List.last() == 1024
    witness
  end

  @doc "I am the module as a program: any defrel roots it, the rest ride as scope."
  @spec the_module_is_the_program() :: [Lang.Rel.t()]
  example the_module_is_the_program do
    [root | _scope] = program = program(:fib)

    assert root.name == :fib
    assert program |> Enum.map(& &1.name) |> Enum.sort() == [:epower, :fib, :regs, :regsm]

    # The closure walk takes what it calls and ignores the rest.
    {:ok, shape} = Lang.compile(root, program)
    assert shape.members == [:fib]
    program
  end

  @spec plain() :: Pipeline.t()
  def plain(), do: %Pipeline{passes: [{Witness, []}, {Zkfol.Lang, []}]}

  @spec fib(pos_integer()) :: pos_integer()
  def fib(n) do
    {a, _} = Enum.reduce(1..n, {0, 1}, fn _, {a, b} -> {b, a + b} end)
    a
  end
end
