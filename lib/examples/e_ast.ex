defmodule Examples.EAst do
  @moduledoc """
  I am the algebra's evidence: the arithmetized polynomial (Figure 2)
  agrees with the oracle at every column, in both directions, and the
  oracle's judgements reject a witness that lies, guarded by
  meeting the out-of-range dereference itself.
  """

  use ExExample

  import ExUnit.Assertions

  alias Examples.EUser
  alias Zkfol.Ast
  alias Zkfol.Interpretation
  alias Zkfol.Statement
  alias Zkfol.Semantics

  @spec figure_two_agrees_with_the_oracle() :: Zkfol.Ast.ep()
  example figure_two_agrees_with_the_oracle do
    witness = Statement.witness(EUser.power())
    phi = Statement.pred(EUser.power())
    poly = Ast.arithmetize(phi)

    for x <- 1..Interpretation.len(witness) do
      assert Semantics.eval(poly, witness, x) == Semantics.eval(phi, witness, x)
    end

    poly
  end

  @spec wrong_value_is_rejected() :: Interpretation.t()
  example wrong_value_is_rejected do
    tampered = tamper(Statement.witness(EUser.power()), 3, 4, 9)

    refute valid?(Statement.pred(EUser.power()), tampered)
    tampered
  end

  @spec out_of_range_pointer_is_rejected() :: Interpretation.t()
  example out_of_range_pointer_is_rejected do
    tampered = tamper(Statement.witness(EUser.power()), 4, 4, 7)

    refute valid?(Statement.pred(EUser.power()), tampered)
    tampered
  end

  @spec figure_two_rejects_what_the_oracle_rejects() :: Interpretation.t()
  example figure_two_rejects_what_the_oracle_rejects do
    # The other direction: on the witness the oracle already rejected,
    # the polynomial must be nonzero exactly where the predicate is.
    tampered = wrong_value_is_rejected()
    phi = Statement.pred(EUser.power())
    poly = Ast.arithmetize(phi)
    columns = 1..Interpretation.len(tampered)

    for x <- columns do
      assert Semantics.eval(poly, tampered, x) == 0 == (Semantics.eval(phi, tampered, x) == 0),
             "column #{x} disagrees"
    end

    assert Enum.any?(columns, &(Semantics.eval(phi, tampered, &1) != 0))
    tampered
  end

  # The judgement, derived: phi is 0 at every column.
  @spec valid?(Ast.pred(), Interpretation.t()) :: boolean()
  defp valid?(phi, itp),
    do: Enum.all?(1..Interpretation.len(itp), &Semantics.holds?(phi, itp, &1))

  @spec tamper(Interpretation.t(), pos_integer(), pos_integer(), non_neg_integer()) ::
          Interpretation.t()
  defp tamper(witness, i, x, value) do
    witness
    |> Interpretation.rows()
    |> List.update_at(i - 1, &List.replace_at(&1, x - 1, value))
    |> Interpretation.new()
  end
end
