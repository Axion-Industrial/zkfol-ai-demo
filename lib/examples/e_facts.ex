defmodule Examples.EFacts do
  @moduledoc "I am the facts' evidence: the descriptor read off the clauses, or the refusal."

  use ExExample
  use Zkfol.Lang
  import ExUnit.Assertions

  alias Examples.EUser
  alias Zkfol.Facts
  alias Zkfol.Refusal

  defrel factorial(1, 1)
  defrel factorial(2, 2)

  defrel factorial(x, v) do
    x > 2
    factorial(x - 1, v1)
    v = x * v1
  end

  defrel reduced(1, 1)
  defrel reduced(2, 1)

  defrel reduced(x, v) do
    reduced(x - 1, a)
    reduced(x - 2, b)
    v = mod(a + b, 1000)
  end

  defrel entangled(1, 1)
  defrel entangled(2, 1)

  defrel entangled(x, v) do
    entangled(x - 1, a)
    entangled(x - 2, b)
    v = a * b
  end

  @doc "I read the modulus off the structure, the coefficients those of the unreduced recurrence."
  @spec a_reduced_step_carries_its_modulus() :: Facts.t()
  example a_reduced_step_carries_its_modulus do
    {:ok, descriptor} = Facts.recurrence(reduced())
    {:ok, unreduced} = Facts.recurrence(EUser.fib())

    assert %{p: 1, q: 1, mod: 1000} = Map.from_struct(descriptor)
    assert %{p: 1, q: 1, mod: nil, initial: [{1, 1}, {2, 1}]} = Map.from_struct(unreduced)
    descriptor
  end

  @doc "Outside the order-two class, each shape refuses by its own name."
  @spec refusals_outside_the_class() :: [Refusal.t()]
  example refusals_outside_the_class do
    {:error, order} = Facts.recurrence(factorial())
    {:error, step} = Facts.recurrence(entangled())
    {:error, arity} = Facts.recurrence(EUser.regs())

    assert {:not_order_two, %{offsets: [-1]}} = order
    assert {:step_not_linear, %{term: _term}} = step
    assert {:not_an_index_relation, %{arity: 3}} = arity
    [order, step, arity]
  end
end
