defmodule Examples.EUair do
  @moduledoc """
  I am the prover boundary's evidence: a tampered witness rejected, a
  claim outside the witness refused, a negative cell refused at the
  door, a pointer off its schedule refused, values past int64 riding
  the wider backend, two acts proving at once, and the emission
  shapes frozen against translation growth.
  """

  use ExExample

  import ExUnit.Assertions

  alias Examples.EAst
  alias Examples.EDoubling
  alias Examples.EFacts
  alias Examples.EUser
  alias Zkfol.Al
  alias Zkfol.Lang
  alias Zkfol.Log
  alias Zkfol.Prover
  alias Zkfol.Refusal
  alias Zkfol.Statement
  alias Zkfol.Uair

  @spec big_values_prove(pos_integer()) :: Log.Ran.t()
  example big_values_prove(n \\ 99) do
    # The plain route on purpose: the trace's own values need int768.
    route = EUser.plain()
    ran = Zkfol.compile(%Statement{rels: [EUser.fib()], args: [n]}, pipeline: route)

    assert %Prover.Report{} = report = Log.report(Log.snapshot(), ran)
    assert report.backend =~ "int768"
    ran
  end

  @spec tampered_is_rejected() :: Refusal.t()
  example tampered_is_rejected do
    {:ok, uair} =
      Uair.emit(Statement.pred(EUser.fibonacci()), Statement.witness(EUser.fibonacci()))

    tampered = %{uair | columns: List.update_at(uair.columns, 1, &List.replace_at(&1, 4, 999))}

    {:error, reason} = Uair.prove_uair(tampered)
    assert {:verifier_rejected, _} = reason
    reason
  end

  @spec out_of_range_claim_is_refused() :: Refusal.t()
  example out_of_range_claim_is_refused do
    {:error, reason} =
      Uair.prove(Statement.pred(EUser.fibonacci()), Statement.witness(EUser.fibonacci()),
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

    {:error, reason} = Uair.request(negated)
    assert {:witness_value_negative, %{value: -1}} = reason
    reason
  end

  @spec out_of_schedule_pointer_is_refused() :: Refusal.t()
  example out_of_schedule_pointer_is_refused do
    {:error, reason} =
      Uair.prove(Statement.pred(EUser.power()), EAst.out_of_range_pointer_is_rejected())

    assert {:witness_unsatisfies_schedule, %{column: 4}} = reason
    reason
  end

  @spec concurrent_proves_hold() :: [{:ok, Prover.Report.t(), pos_integer()}]
  example concurrent_proves_hold do
    factorial = EFacts.factorial()
    {:ok, %{pred: factorial_pred}} = Lang.compile(factorial, [factorial])
    {:ok, factorial_witness} = Al.solve(factorial, [6])

    reports =
      [
        fn ->
          Uair.prove(Statement.pred(EUser.fibonacci()), Statement.witness(EUser.fibonacci()))
        end,
        fn -> Uair.prove(factorial_pred, factorial_witness) end
      ]
      |> Enum.map(&Task.async/1)
      |> Task.await_many(:infinity)

    assert Enum.all?(reports, &match?({:ok, %Prover.Report{}, _id}, &1))
    reports
  end

  @spec frozen_shapes() :: [Uair.t()]
  example frozen_shapes do
    # The regression gates: translation growth is a failure, not a
    # drift. v0.1.0 froze 279/111 opcodes at 7/5 columns; the X-forge
    # fix costs its four index pins (60 opcodes) and the ones column.
    doubled = EDoubling.rewritten_fibonacci(10_000)
    {:ok, kernel} = Uair.emit(Statement.pred(doubled), Statement.witness(doubled), doubled.claims)

    {:ok, generic} =
      Uair.emit(Statement.pred(EUser.fibonacci()), Statement.witness(EUser.fibonacci(32)))

    assert Uair.num_cols(kernel) == 8
    assert Uair.num_cols(generic) == 6
    assert length(kernel.program) == 339
    assert length(generic.program) == 171

    [kernel, generic]
  end
end
