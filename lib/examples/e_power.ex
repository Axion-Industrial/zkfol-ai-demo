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

  @spec rows_for(non_neg_integer()) :: [[non_neg_integer()]]
  example rows_for(exponent \\ 3) do
    [
      List.duplicate(2, exponent + 1),
      Enum.to_list(0..exponent),
      Enum.map(0..exponent, &Integer.pow(2, &1)),
      [1 | Enum.to_list(1..exponent)]
    ]
  end

  @spec power_witness() :: Interpretation.t()
  example power_witness do
    witness = Interpretation.new(rows_for())
    assert Semantics.valid?(power_predicate(), pointer_ranges(), witness)
    witness
  end

  @spec wrong_value_is_rejected() :: non_neg_integer()
  example wrong_value_is_rejected do
    tampered = rows_for() |> tamper(3, 4, 9) |> Interpretation.new()

    refute Semantics.valid?(power_predicate(), pointer_ranges(), tampered)
    Semantics.eval(power_predicate(), tampered, 4)
  end

  @spec out_of_range_pointer_is_rejected() :: Interpretation.t()
  example out_of_range_pointer_is_rejected do
    tampered = rows_for() |> tamper(4, 4, 7) |> Interpretation.new()

    refute Semantics.valid?(power_predicate(), pointer_ranges(), tampered)
    tampered
  end

  @spec out_of_schedule_pointer_is_refused() :: String.t()
  example out_of_schedule_pointer_is_refused do
    {:error, reason} = Uair.prove(power_predicate(), out_of_range_pointer_is_rejected())
    assert reason =~ "column 4"
    reason
  end

  @spec tamper([[non_neg_integer()]], pos_integer(), pos_integer(), non_neg_integer()) ::
          [[non_neg_integer()]]
  defp tamper(rows, i, x, value) do
    List.update_at(rows, i - 1, &List.replace_at(&1, x - 1, value))
  end
end
