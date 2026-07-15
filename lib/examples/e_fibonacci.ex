defmodule Examples.EFibonacci do
  @moduledoc """
  I am the two-pointer Fibonacci statement: rows 1 = n, 2 = fib(n),
  3 = pointer to n-1, 4 = pointer to n-2. A column is a base case
  (n in {1, 2}, value 1) or a step whose pointed values sum to it.
  """

  use ExExample

  import ExUnit.Assertions

  alias Examples.EFactorial
  alias Zkfol.Ast
  alias Zkfol.Interpretation
  alias Zkfol.Range
  alias Zkfol.Semantics
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
    {:ok, witness} = Witness.generate(fibonacci_predicate(), n, %{{1, 2} => 2})
    assert Semantics.valid?(fibonacci_predicate(), pointer_ranges(), witness)
    witness
  end

  @spec big_values_prove(pos_integer()) :: map()
  example big_values_prove(n \\ 99) do
    {:ok, report, _id} = Uair.prove(fibonacci_predicate(), fibonacci_witness(n))

    assert report.proved
    assert report.backend =~ "int768"
    report
  end

  @spec tampered_is_rejected() :: String.t()
  example tampered_is_rejected do
    {:ok, uair} = Uair.emit(fibonacci_predicate(), fibonacci_witness())
    tampered = %{uair | columns: List.update_at(uair.columns, 1, &List.replace_at(&1, 4, 999))}

    {:ok, id} = Uair.request(tampered)
    {:error, reason} = Uair.await(id)
    assert reason =~ "failed"
    reason
  end

  @spec concurrent_proves_hold() :: [{:ok, map()}]
  example concurrent_proves_hold do
    reports =
      [
        fn -> Uair.prove(fibonacci_predicate(), fibonacci_witness()) end,
        fn -> Uair.prove(EFactorial.factorial_predicate(), EFactorial.factorial_witness()) end
      ]
      |> Enum.map(&Task.async/1)
      |> Task.await_many(:infinity)

    assert Enum.all?(reports, fn {:ok, r, _id} -> r.proved end)
    reports
  end

  @spec fib(pos_integer()) :: pos_integer()
  def fib(n) do
    {a, _} = Enum.reduce(1..n, {0, 1}, fn _, {a, b} -> {b, a + b} end)
    a
  end
end
