defmodule Examples.ELang do
  @moduledoc """
  I write statements in the relational surface and derive their
  witnesses through the usual backend.
  """

  use ExExample
  use Zkfol.Lang
  import ExUnit.Assertions

  alias Zkfol.Al
  alias Zkfol.Interpretation
  alias Zkfol.Lang

  defrel fib(1, 1)
  defrel fib(2, 1)

  defrel fib(x, v) do
    fib(x - 1, v1)
    fib(x - 2, v2)
    v = v1 + v2
  end

  defrel regs(1, 1, 1)

  defrel regs(x, a, b) do
    regs(x - 1, a1, b1)
    a = a1 + b1
    b = a1
  end

  example fib_compiles do
    {:ok, %{pred: pred, rows: rows}} = Lang.compile(fib(), [fib()])

    # Index and value rows, then a pointer row per call site; the
    # compiled statement is the hand-written one, byte for byte.
    assert rows == %{fib: [1, 2]}
    assert pred == Examples.EFibonacci.fibonacci_predicate()
    pred
  end

  example fib_relation_derives do
    fib_compiles()
    {:ok, witness} = Al.solve(fib(), [8])

    assert witness |> Interpretation.rows() |> Enum.at(1) == [1, 1, 2, 3, 5, 8, 13, 21]
    witness
  end

  example registers_relation_derives do
    {:ok, %{rows: rows}} = Lang.compile(regs(), [regs()])
    assert rows == %{regs: [1, 2, 3]}

    {:ok, witness} = Al.solve(regs(), [8])
    assert witness |> Interpretation.rows() |> Enum.at(1) == [1, 2, 3, 5, 8, 13, 21, 34]
    witness
  end

  # The surface meets the prover: same pred, same pipeline.
  example relational_fibonacci_proves do
    pred = fib_compiles()
    {:ok, witness} = Al.solve(fib(), [8])
    {:ok, report, _id} = Zkfol.Uair.prove(pred, witness)
    report
  end

  # A relation built where values live: the pin splices them in.
  example a_relation_pins_runtime_values do
    k = 3

    scaled =
      rel :scaled do
        scaled(1, ^k)

        scaled(x, v) do
          scaled(x - 1, prev)
          v = ^k * prev
        end
      end

    {:ok, _compiled} = Lang.compile(scaled, [scaled])
    {:ok, witness} = Al.solve(scaled, [5])

    assert witness |> Interpretation.rows() |> Enum.at(1) == [3, 9, 27, 81, 243]
    scaled
  end

  example unknown_relation_is_refused do
    {:error, reason} = Lang.compile(fib(), [])
    assert {:relation_not_in_scope, _} = reason
    reason
  end
end
