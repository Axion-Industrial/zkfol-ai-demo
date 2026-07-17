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

  import ExUnit.Assertions

  alias Zkfol.Ast
  alias Zkfol.Interpretation
  alias Zkfol.Range
  alias Zkfol.Semantics
  alias Zkfol.Uair
  alias Zkfol.Witness

  @spec power_predicate() :: Ast.pred()
  example power_predicate do
    base_case = Ast.conj([Ast.eq(Ast.cell(2), 0), Ast.eq(Ast.cell(3), 1)])

    step =
      Ast.conj([
        Ast.eq(Ast.cell(1), Ast.cell(1, 4)),
        Ast.eq(Ast.cell(2), Ast.add(Ast.cell(2, 4), 1)),
        Ast.eq(Ast.cell(3), Ast.mul(Ast.cell(1), Ast.cell(3, 4)))
      ])

    Ast.disj([base_case, step])
  end

  @spec pointer_ranges() :: [Range.check()]
  example pointer_ranges do
    Range.pointer(4)
  end

  @spec power_witness(non_neg_integer()) :: Interpretation.t()
  example power_witness(exponent \\ 3) do
    {:ok, witness} = Witness.generate(power_predicate(), exponent + 1, %{{1, 1} => 2})
    assert Semantics.valid?(power_predicate(), pointer_ranges(), witness)
    witness
  end

  @spec unseeded_base_is_knowledge() :: String.t()
  example unseeded_base_is_knowledge do
    {:error, reason} = Witness.generate(power_predicate(), 4)
    assert reason =~ "row 1"
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

  @spec out_of_schedule_pointer_is_refused() :: String.t()
  example out_of_schedule_pointer_is_refused do
    {:error, reason} = Uair.prove(power_predicate(), out_of_range_pointer_is_rejected())
    assert reason =~ "column 4"
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
