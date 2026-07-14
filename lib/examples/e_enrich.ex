defmodule Examples.EEnrich do
  @moduledoc """
  I am the compilation's evidence: the enriched polynomial (Figure 2)
  agrees with the oracle at every column.
  """

  use ExExample

  import ExUnit.Assertions

  alias Examples.EPower
  alias Zkfol.Enrich
  alias Zkfol.Interpretation
  alias Zkfol.Semantics

  @spec figure_two_agrees_with_the_oracle() :: Zkfol.Ast.ep()
  example figure_two_agrees_with_the_oracle do
    witness = EPower.power_witness()
    phi = EPower.power_predicate()
    poly = Enrich.enrich(phi)

    for x <- 1..Interpretation.len(witness) do
      assert Semantics.eval(poly, witness, x) == Semantics.eval(phi, witness, x)
    end

    poly
  end

  @spec figure_two_rejects_what_the_oracle_rejects() :: Interpretation.t()
  example figure_two_rejects_what_the_oracle_rejects do
    # The other direction: on the witness the oracle already rejected,
    # the polynomial must be nonzero exactly where the predicate is.
    tampered = EPower.wrong_value_is_rejected()
    phi = EPower.power_predicate()
    poly = Enrich.enrich(phi)
    columns = 1..Interpretation.len(tampered)

    for x <- columns do
      assert Semantics.eval(poly, tampered, x) == 0 == (Semantics.eval(phi, tampered, x) == 0),
             "column #{x} disagrees"
    end

    assert Enum.any?(columns, &(Semantics.eval(phi, tampered, &1) != 0))
    tampered
  end
end
