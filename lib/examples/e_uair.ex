defmodule Examples.EUair do
  @moduledoc "I am the prover boundary's evidence: what it refuses, and the shapes it emits."

  use ExExample

  import ExUnit.Assertions

  alias Examples.EAst
  alias Examples.EDoubling
  alias Examples.EFacts
  alias Examples.EUser
  alias Zkfol.Ast
  alias Zkfol.Interpretation
  alias Zkfol.Log
  alias Zkfol.Prover
  alias Zkfol.Refusal
  alias Zkfol.Statement
  alias Zkfol.Uair
  alias Zkfol.ZincPlus

  @doc "I take the plain route on purpose: the trace's own values need int768."
  @spec big_values_prove(pos_integer()) :: Log.Ran.t()
  example big_values_prove(n \\ 98) do
    route = EUser.plain()
    ran = Zkfol.compile(%Statement{rels: [EFacts.factorial()], args: [n]}, pipeline: route)

    assert %Prover.Report{} = report = Log.report(Log.snapshot(), ran)
    assert report.backend =~ "int768"
    ran
  end

  @doc "I am the pinned code's own parameters, not a copy of them."
  @spec the_code_answers_its_parameters() :: ZincPlus.pcs_params()
  example the_code_answers_its_parameters do
    pcs = ZincPlus.pcs_params()

    assert pcs.rep_factor > 1
    assert pcs.column_openings > 0
    assert pcs.degree > 0
    assert pcs.backend =~ "zinc-plus"
    pcs
  end

  @doc "Pointer bounds keep their degree as the trace grows; forged bounds fail at the prover."
  @spec pointer_bounds_have_fixed_degree() :: Uair.t()
  example pointer_bounds_have_fixed_degree do
    emitted =
      for len <- [8, 65] do
        values = Enum.to_list(1..len)
        pointers = tl(values) ++ [1]
        witness = Interpretation.new([values, pointers, pointers])
        {:ok, uair} = Uair.emit(Ast.eq(Ast.cell(1, 2), Ast.cell(3)), witness)
        assert {:ok, %Prover.Report{}, _id} = Prover.prove_uair(uair)
        uair
      end

    [short, long] = emitted
    assert short.degree == long.degree
    assert long.degree < ZincPlus.pcs_params().degree
    [%{row: pointer, bit_rows: [bit | _]}] = long.mode.reads
    [{^pointer, 32, 8}, {slack, 32, 8}] = long.word_lookups

    for {row, value} <- [{pointer, 0}, {pointer, long.len + 1}, {slack, 2 ** 32}, {bit, 2}] do
      forged = List.update_at(long.columns, row, &List.replace_at(&1, 0, value))
      assert {:error, _refusal} = Prover.prove_uair(%{long | columns: forged})
    end

    # The final cube row is exempt from the polynomial, but still belongs to Word.
    forged = List.update_at(long.columns, slack, &List.replace_at(&1, -1, 2 ** 32))
    assert {:error, {:prover_failed, _}} = Prover.prove_uair(%{long | columns: forged})

    assert {:ok, %Prover.Report{}, _id} =
             Prover.prove_uair(%{long | columns: forged, word_lookups: [{pointer, 32, 8}]})

    long
  end

  @spec tampered_is_rejected() :: Refusal.t()
  example tampered_is_rejected do
    {:ok, uair} =
      Uair.emit(Statement.pred(EUser.fibonacci()), Statement.witness(EUser.fibonacci()))

    tampered = %{uair | columns: List.update_at(uair.columns, 1, &List.replace_at(&1, 4, 999))}

    {:error, reason} = Prover.prove_uair(tampered)
    assert {:verifier_rejected, _} = reason
    reason
  end

  @spec out_of_range_claim_is_refused() :: Refusal.t()
  example out_of_range_claim_is_refused do
    {:error, reason} =
      Prover.prove(Statement.pred(EUser.fibonacci()), Statement.witness(EUser.fibonacci()),
        claims: [{"n", 9, 1}]
      )

    assert {:claim_outside_witness, _} = reason
    reason
  end

  @spec negative_cell_is_refused() :: Refusal.t()
  example negative_cell_is_refused do
    {:ok, uair} =
      Uair.emit(Statement.pred(EUser.fibonacci()), Statement.witness(EUser.fibonacci()))

    negated = %{uair | columns: List.update_at(uair.columns, 0, &List.replace_at(&1, 0, -1))}

    {:error, reason} = ZincPlus.request(negated)
    assert {:witness_value_negative, %{value: -1}} = reason
    reason
  end

  @spec a_forged_presence_is_refused() :: Refusal.t()
  example a_forged_presence_is_refused do
    forged = EAst.tamper(Statement.witness(EUser.power()), 4, 4, 7)
    {:error, reason} = Prover.prove(Statement.pred(EUser.power()), forged)

    assert {:witness_unsatisfies_schedule, %{column: 4}} = reason
    reason
  end

  @doc "Cells a head spells at named columns are ties: no address, no bits, no Word."
  @spec named_cells_are_tied() :: Uair.t()
  example named_cells_are_tied do
    statement = EUser.open_tail()
    {:ok, uair} = Uair.emit(Statement.pred(statement), Statement.witness(statement))

    assert uair.word_lookups == []
    assert uair.mode == %Uair.Plain{}
    assert [%{selections: [_one]}] = uair.selected_lookups

    assert uair.point_ties == []
    assert Uair.num_cols(uair) == 5
    assert length(uair.program) == 91
    assert {:ok, %Prover.Report{}, _id} = Prover.prove_uair(uair, name: :named_cells)
    uair
  end

  @doc "The counts are a gate: growth in the translation is a regression, not a drift."
  @spec frozen_shapes() :: [Uair.t()]
  example frozen_shapes do
    doubled = EDoubling.rewritten_fibonacci(100)

    {:ok, kernel} =
      Uair.emit(Statement.pred(doubled), Statement.witness(doubled), Statement.claims(doubled))

    {:ok, generic} =
      Uair.emit(Statement.pred(EUser.fibonacci()), Statement.witness(EUser.fibonacci(12)))

    assert Uair.num_cols(kernel) == 8
    assert Uair.num_cols(generic) == 5
    assert length(kernel.program) == 351
    assert length(generic.program) == 167

    assert generic.shifts == [{0, 1}, {0, 2}, {1, 1}, {1, 2}, {3, 1}, {4, 1}, {4, 5}]
    assert kernel.shifts == [{1, 1}, {2, 1}, {3, 1}, {4, 1}, {6, 1}, {7, 1}, {7, 2}]

    [kernel, generic]
  end
end
