defmodule Examples.EFacts do
  @moduledoc """
  I am the facts' evidence: the descriptor read off the fibonacci
  clauses, and relations outside the class refused with reasons.
  """

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

  defrel sub(1, 1)
  defrel sub(2, 2)

  defrel sub(x, v) do
    x > 2
    sub(x - 1, a)
    sub(x - 2, b)
    v = a - b
  end

  defrel reduced(1, 1)
  defrel reduced(2, 1)

  defrel reduced(x, v) do
    reduced(x - 1, a)
    reduced(x - 2, b)
    v = mod(a + b, 1000)
  end

  defrel lopsided(1, 1)
  defrel lopsided(2, 1)

  defrel lopsided(x, v) do
    lopsided(x - 1, a)
    lopsided(x - 3, b)
    v = a + b
  end

  defrel entangled(1, 1)
  defrel entangled(2, 1)

  defrel entangled(x, v) do
    entangled(x - 1, a)
    entangled(x - 2, b)
    v = a * b
  end

  @spec fibonacci_descriptor() :: Facts.t()
  example fibonacci_descriptor do
    {:ok, descriptor} = Facts.recurrence(EUser.fib())

    assert %{p: 1, q: 1, initial: [{1, 1}, {2, 1}]} = Map.from_struct(descriptor)
    descriptor
  end

  @spec subtraction_reads_its_signs() :: Facts.t()
  example subtraction_reads_its_signs do
    {:ok, descriptor} = Facts.recurrence(sub())

    assert %{p: 1, q: -1} = Map.from_struct(descriptor)
    descriptor
  end

  @doc """
  I read the modulus off the structure: the same coefficients as the
  unreduced recurrence, and the bound the step reduces by, so nobody
  has to be told it.
  """
  @spec a_reduced_step_carries_its_modulus() :: Facts.t()
  example a_reduced_step_carries_its_modulus do
    {:ok, descriptor} = Facts.recurrence(reduced())

    assert %{p: 1, q: 1, mod: 1000} = Map.from_struct(descriptor)
    assert %{mod: nil} = Map.from_struct(fibonacci_descriptor())
    descriptor
  end

  @spec factorial_is_refused() :: Refusal.t()
  example factorial_is_refused do
    {:error, refusal} = Facts.recurrence(factorial())
    assert {:not_order_two, %{offsets: [-1]}} = refusal
    refusal
  end

  @spec a_lopsided_history_is_refused() :: Refusal.t()
  example a_lopsided_history_is_refused do
    {:error, refusal} = Facts.recurrence(lopsided())
    assert {:not_order_two, %{offsets: [-1, -3]}} = refusal
    refusal
  end

  @spec an_entangled_step_is_refused() :: Refusal.t()
  example an_entangled_step_is_refused do
    {:error, refusal} = Facts.recurrence(entangled())
    assert {:step_not_linear, %{term: _term}} = refusal
    refusal
  end

  @spec a_squaring_relation_is_refused() :: Refusal.t()
  example a_squaring_relation_is_refused do
    {:error, refusal} = Facts.recurrence(EUser.epower())
    assert {:not_an_index_relation, %{arity: 3}} = refusal
    refusal
  end
end
