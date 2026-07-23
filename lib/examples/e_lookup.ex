defmodule Examples.ELookup do
  @moduledoc """
  I drive the pinned zinc+'s GKR-LogUp lookup end to end. The statement
  is the index statement, eq(cell(1), X): row 1 carries its own column
  index, one linear constraint the pin verifies. A binary shadow column
  carries that row's bit patterns, declared BitPoly{32, 8}. The pin
  holds the table width to the cell degree D = 32, so every 32-bit
  pattern is in the table; the lookup's teeth show at the proof layer,
  where bending one looked-up chunk lift must turn the verdict into
  refusal.
  """

  use ExExample

  import Bitwise
  import ExUnit.Assertions

  alias Zkfol.Ast
  alias Zkfol.Refusal
  alias Zkfol.Interpretation
  alias Zkfol.Prover
  alias Zkfol.Uair

  @len 1024

  @spec index_predicate() :: Ast.pred()
  example index_predicate do
    Ast.eq(Ast.cell(1), Ast.x())
  end

  @spec index_witness() :: Interpretation.t()
  example index_witness do
    Interpretation.new([Enum.to_list(1..@len)])
  end

  @spec shadowed_uair() :: Uair.t()
  example shadowed_uair do
    witness = index_witness()
    {:ok, uair} = Uair.emit(index_predicate(), witness)

    %{
      uair
      | mode: %Uair.Lookup{
          bin_columns: [bit_shadow(witness, 1, Uair.num_vars(uair))],
          lookups: [%{col: 0, table: {:bit_poly, 32, 8}}]
        }
    }
  end

  @spec lookup_proves() :: Prover.Report.t()
  example lookup_proves do
    {:ok, report, _id} = Uair.prove_uair(shadowed_uair())

    assert %Prover.Report{} = report
    report
  end

  @spec tampered_lookup_is_rejected() :: Refusal.t()
  example tampered_lookup_is_rejected do
    # The bend doubles one chunk lift; an all-zero shadow leaves that
    # lift with empty coefficients and panics the prover, so the shadow
    # under tamper must carry bit variation for the rejection to be real.
    assert Enum.any?(hd(shadowed_uair().mode.bin_columns), &(&1 != 0))

    {:error, reason} = Uair.prove_uair(shadowed_uair(), tamper: true)

    assert {:verifier_rejected, _} = reason
    reason
  end

  @spec tamper_needs_a_lookup() :: Refusal.t()
  example tamper_needs_a_lookup do
    shadowed = shadowed_uair()
    uair = %{shadowed | mode: %{shadowed.mode | lookups: []}}
    {:error, reason} = Uair.prove_uair(uair, tamper: true)

    assert {:prover_failed, _} = reason
    reason
  end

  @spec wide_lookup_is_refused() :: Refusal.t()
  example wide_lookup_is_refused do
    shadowed = shadowed_uair()
    uair = %{shadowed | mode: %{shadowed.mode | lookups: [%{col: 0, table: {:bit_poly, 16, 8}}]}}
    {:error, reason} = Uair.prove_uair(uair)

    assert {:lookup_width_mismatch, _} = reason
    reason
  end

  # The same statement three ways isolates what the lookup costs: the
  # bare emit, the shadow column alone, and the shadow looked up.
  @spec lookup_cost() :: map()
  example lookup_cost do
    {:ok, bare} = Uair.emit(index_predicate(), index_witness())

    with_lookup = shadowed_uair()
    shadow_only = %{with_lookup | mode: %{with_lookup.mode | lookups: []}}

    [bare, shadowed, looked] =
      for uair <- [bare, shadow_only, with_lookup] do
        {:ok, report, _id} = Uair.prove_uair(uair)
        Map.take(report, [:prove_ms, :verify_ms, :proof_bytes])
      end

    %{bare: bare, shadow_only: shadowed, with_lookup: looked}
  end

  # The chosen row's values reversed and padded the way emit lays columns.
  @spec bit_shadow(Interpretation.t(), pos_integer(), pos_integer()) :: [non_neg_integer()]
  defp bit_shadow(witness, row, num_vars) do
    len = Interpretation.len(witness)
    values = for x <- len..1//-1, do: Interpretation.at(witness, row, x)
    values ++ List.duplicate(Interpretation.at(witness, row, 1), (1 <<< num_vars) - len)
  end
end
