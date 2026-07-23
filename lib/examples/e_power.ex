defmodule Examples.EPower do
  @moduledoc """
  I am the paper's Section 5 power example: the predicate phi_pow whose
  witnesses are traces of `base ^ exponent`.

  Rows: 1 = base, 2 = exponent, 3 = value, 4 = pointer to the column
  holding exponent - 1. A column is a base case (exponent 0, value 1)
  or a step whose pointed column has the same base, one smaller
  exponent, and value smaller by a factor of the base.
  """

  use ExExample
  use Zkfol.Lang

  import ExUnit.Assertions

  alias Zkfol.Al
  alias Zkfol.Refusal
  alias Zkfol.Ast
  alias Zkfol.Interpretation
  alias Zkfol.Range
  alias Zkfol.Semantics
  alias Zkfol.Uair

  # The base rides as a value: prover's knowledge enters at construction.
  @spec power_rel(integer()) :: Zkfol.Lang.Rel.t()
  def power_rel(base) do
    rel :power do
      power(1, ^base, 0, 1)

      power(x, b, e, v) do
        power(x - 1, bb, ee, w)
        b = bb
        e = ee + 1
        v = b * w
      end
    end
  end

  @spec power_predicate() :: Ast.pred()
  example power_predicate do
    {:ok, %{pred: pred}} = Zkfol.Lang.compile(power_rel(2), [power_rel(2)])
    pred
  end

  @spec pointer_ranges() :: [Range.check()]
  example pointer_ranges do
    Range.pointer(5)
  end

  @spec power_witness(non_neg_integer()) :: Interpretation.t()
  example power_witness(exponent \\ 3) do
    {:ok, witness} = Al.solve(power_rel(2), [exponent + 1])
    assert Semantics.valid?(power_predicate(), pointer_ranges(), witness)
    witness
  end

  @spec unseeded_base_is_knowledge() :: Refusal.t()
  example unseeded_base_is_knowledge do
    unseeded =
      rel :power do
        power(1, b, 0, 1)

        power(x, b, e, v) do
          power(x - 1, bb, ee, w)
          b = bb
          e = ee + 1
          v = b * w
        end
      end

    {:error, reason} = Al.solve(unseeded, [4])
    assert elem(reason, 0) in [:no_derivation, :no_derivation_at_depth, :witness_value_negative]
    reason
  end

  @spec wrong_value_is_rejected() :: Interpretation.t()
  example wrong_value_is_rejected do
    tampered = tamper(power_witness(), 3, 4, 9)

    refute Semantics.valid?(power_predicate(), pointer_ranges(), tampered)
    tampered
  end

  @spec out_of_range_pointer_is_rejected() :: Interpretation.t()
  example out_of_range_pointer_is_rejected do
    tampered = tamper(power_witness(), 4, 4, 7)

    refute Semantics.valid?(power_predicate(), pointer_ranges(), tampered)
    tampered
  end

  @spec out_of_schedule_pointer_is_refused() :: Refusal.t()
  example out_of_schedule_pointer_is_refused do
    {:error, reason} = Uair.prove(power_predicate(), out_of_range_pointer_is_rejected())
    assert {:witness_unsatisfies_schedule, %{column: 4}} = reason
    reason
  end

  @spec unguarded_out_of_range_is_false() :: boolean()
  example unguarded_out_of_range_is_false do
    # With no range guarding the pointer, the oracle meets the out-of-range
    # dereference itself, and answers false rather than raising.
    result = Semantics.valid?(power_predicate(), [], out_of_range_pointer_is_rejected())
    refute result
    result
  end

  @spec tamper(Interpretation.t(), pos_integer(), pos_integer(), non_neg_integer()) ::
          Interpretation.t()
  defp tamper(witness, i, x, value) do
    witness
    |> Interpretation.rows()
    |> List.update_at(i - 1, &List.replace_at(&1, x - 1, value))
    |> Interpretation.new()
  end
end
