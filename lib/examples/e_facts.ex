defmodule Examples.EFacts do
  @moduledoc """
  I am the facts' evidence: the descriptor read off fibonacci, and the
  statements outside the class refused with their reasons.
  """

  use ExExample

  import ExUnit.Assertions

  alias Examples.EEfficientPower
  alias Examples.EFactorial
  alias Examples.EFibonacci
  alias Zkfol.Ast
  alias Zkfol.Facts

  @spec fibonacci_descriptor() :: Facts.t()
  example fibonacci_descriptor do
    {:ok, descriptor} = Facts.recurrence(EFibonacci.fibonacci_predicate())

    assert %{p: 1, q: 1, index_row: 1, value_row: 2, initial: [{1, 1}, {2, 1}]} =
             Map.from_struct(descriptor)

    descriptor
  end

  @spec factorial_is_refused() :: String.t()
  example factorial_is_refused do
    {:error, reason} = Facts.recurrence(EFactorial.factorial_predicate())
    assert reason =~ "non-constant"
    reason
  end

  @spec efficient_power_is_refused() :: String.t()
  example efficient_power_is_refused do
    {:error, reason} = Facts.recurrence(EEfficientPower.efficient_power_predicate())
    assert reason =~ "branches"
    reason
  end

  @spec shared_offset_is_refused() :: String.t()
  example shared_offset_is_refused do
    # x(k) = x(k-1) + x(k-1) + x(k-2), stated through two pointers at one
    # offset: the coefficients are not separable, so the facts must refuse.
    n = Ast.cell(1)
    value = Ast.cell(2)

    step =
      Ast.conj([
        Ast.eq(n, Ast.add(Ast.cell(1, 3), 1)),
        Ast.eq(n, Ast.add(Ast.cell(1, 4), 2)),
        Ast.eq(n, Ast.add(Ast.cell(1, 5), 1)),
        Ast.eq(value, Ast.add(Ast.cell(2, 3), Ast.add(Ast.cell(2, 5), Ast.cell(2, 4))))
      ])

    {:error, reason} =
      Facts.recurrence(Ast.disj([base_case(1, 1), base_case(2, 1), step]))

    assert reason =~ "share"
    reason
  end

  @spec extra_schedule_is_refused() :: String.t()
  example extra_schedule_is_refused do
    # Fibonacci with one extra value-row schedule bolted onto the step: the
    # equality still constrains the witness, so it must refuse, not drop.
    {:disj, [base1, base2, {:conj, step}]} = EFibonacci.fibonacci_predicate()
    extra = Ast.eq(Ast.cell(2), Ast.add(Ast.cell(2, 3), 5))

    {:error, reason} =
      Facts.recurrence(Ast.disj([base1, base2, Ast.conj(step ++ [extra])]))

    assert reason =~ "outside the recurrence"
    reason
  end

  @doc "I am the pinned base branch at `index`: rows 1, 2 hold index and value."
  @spec base_case(pos_integer(), integer()) :: Zkfol.Ast.pred()
  def base_case(index, value),
    do: Ast.conj([Ast.eq(Ast.cell(1), index), Ast.eq(Ast.cell(2), value)])
end
