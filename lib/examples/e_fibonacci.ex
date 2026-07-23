defmodule Examples.EFibonacci do
  @moduledoc """
  I am the two-pointer Fibonacci statement: rows 1 = n, 2 = fib(n),
  3 = pointer to n-1, 4 = pointer to n-2. A column is a base case
  (n in {1, 2}, value 1) or a step whose pointed values sum to it.
  """

  use ExExample

  import ExUnit.Assertions

  alias Examples.EFactorial
  alias Examples.ELang
  alias Zkfol.Al
  alias Zkfol.Refusal
  alias Zkfol.Ast
  alias Zkfol.Interpretation
  alias Zkfol.Log
  alias Zkfol.Pipeline
  alias Zkfol.Prover
  alias Zkfol.Range
  alias Zkfol.Semantics
  alias Zkfol.Statement
  alias Zkfol.Uair
  alias Zkfol.Witness

  @spec fibonacci_predicate() :: Ast.pred()
  example fibonacci_predicate do
    n = Ast.cell(1)
    value = Ast.cell(2)

    Ast.disj([
      Ast.conj([Ast.eq(n, 1), Ast.eq(value, 1)]),
      Ast.conj([Ast.eq(n, 2), Ast.eq(value, 1)]),
      Ast.conj([
        Ast.eq(n, Ast.add(Ast.cell(1, 3), 1)),
        Ast.eq(n, Ast.add(Ast.cell(1, 4), 2)),
        Ast.eq(value, Ast.add(Ast.cell(2, 3), Ast.cell(2, 4)))
      ])
    ])
  end

  @spec pointer_ranges() :: [Range.check()]
  example pointer_ranges do
    Enum.flat_map([3, 4], &Range.pointer/1)
  end

  @spec fibonacci_witness(pos_integer()) :: Interpretation.t()
  example fibonacci_witness(n \\ 8) do
    {:ok, witness} = Al.solve(Examples.ELang.fib(), [n])
    assert Semantics.valid?(fibonacci_predicate(), pointer_ranges(), witness)
    witness
  end

  # The zkVM loop as a statement: what the registers relation compiles to.
  @spec registers_predicate() :: Ast.pred()
  example registers_predicate do
    {:ok, %{pred: pred}} = Zkfol.Lang.compile(Examples.ELang.regs(), [Examples.ELang.regs()])
    pred
  end

  @spec registers_witness(pos_integer()) :: Interpretation.t()
  example registers_witness(n \\ 8) do
    {:ok, witness} = Al.solve(Examples.ELang.regs(), [n])

    assert Interpretation.at(witness, 3, n) == fib(n)
    witness
  end

  @spec big_values_prove(pos_integer()) :: Log.Ran.t()
  example big_values_prove(n \\ 99) do
    # The plain route on purpose: the trace's own values need int768.
    route = %Pipeline{passes: [{Zkfol.Lang, []}, {Witness, []}]}
    ran = Zkfol.compile(%Statement{rels: [ELang.fib()], args: [n]}, pipeline: route)

    assert %Prover.Report{} = report = Log.report(Log.snapshot(), ran)
    assert report.backend =~ "int768"
    ran
  end

  @spec tampered_is_rejected() :: Refusal.t()
  example tampered_is_rejected do
    {:ok, uair} = Uair.emit(fibonacci_predicate(), fibonacci_witness())
    tampered = %{uair | columns: List.update_at(uair.columns, 1, &List.replace_at(&1, 4, 999))}

    {:error, reason} = Uair.prove_uair(tampered)
    assert {:verifier_rejected, _} = reason
    reason
  end

  @spec out_of_range_claim_is_refused() :: Refusal.t()
  example out_of_range_claim_is_refused do
    {:error, reason} =
      Uair.prove(fibonacci_predicate(), fibonacci_witness(), claims: [{"n", 9, 1}])

    assert {:claim_outside_witness, _} = reason
    reason
  end

  @spec negative_cell_is_refused() :: Refusal.t()
  example negative_cell_is_refused do
    {:ok, uair} = Uair.emit(fibonacci_predicate(), fibonacci_witness())
    negated = %{uair | columns: List.update_at(uair.columns, 0, &List.replace_at(&1, 0, -1))}

    {:error, reason} = Uair.request(negated)
    assert {:witness_value_negative, %{value: -1}} = reason
    reason
  end

  @spec concurrent_proves_hold() :: [{:ok, Prover.Report.t(), pos_integer()}]
  example concurrent_proves_hold do
    reports =
      [
        fn -> Uair.prove(fibonacci_predicate(), fibonacci_witness()) end,
        fn -> Uair.prove(EFactorial.factorial_predicate(), EFactorial.factorial_witness()) end
      ]
      |> Enum.map(&Task.async/1)
      |> Task.await_many(:infinity)

    assert Enum.all?(reports, &match?({:ok, %Prover.Report{}, _id}, &1))
    reports
  end

  @spec fib(pos_integer()) :: pos_integer()
  def fib(n) do
    {a, _} = Enum.reduce(1..n, {0, 1}, fn _, {a, b} -> {b, a + b} end)
    a
  end
end
