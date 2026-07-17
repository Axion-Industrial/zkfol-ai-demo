defmodule Examples.EEfficientPower do
  @moduledoc """
  I am the repeated-squaring power statement: rows 1 = base, 2 = exponent,
  3 = value, 4 = pointer to the half-exponent column. I am refused by the
  doubling rewrite on shape, two pointer-using branches (even and odd),
  before my nonlinear step is even examined; a parametric witness joins
  when the corpus needs one.
  """

  use ExExample

  alias Zkfol.Ast

  @spec efficient_power_predicate() :: Ast.pred()
  example efficient_power_predicate do
    exponent = Ast.cell(2)
    value = Ast.cell(3)
    half = Ast.cell(3, 4)

    Ast.disj([
      Ast.conj([Ast.eq(exponent, 0), Ast.eq(value, 1)]),
      Ast.conj([
        Ast.eq(exponent, Ast.add(Ast.cell(2, 4), Ast.cell(2, 4))),
        Ast.eq(value, Ast.mul(half, half))
      ]),
      Ast.conj([
        Ast.eq(exponent, Ast.add(Ast.add(Ast.cell(2, 4), Ast.cell(2, 4)), 1)),
        Ast.eq(value, Ast.mul(Ast.cell(1), Ast.mul(half, half)))
      ])
    ])
  end
end
