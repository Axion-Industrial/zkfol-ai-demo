defmodule Examples.EBench do
  @moduledoc """
  I am the benchmarker.
  """

  use ExExample

  import ExUnit.Assertions

  alias Examples.EDoubling
  alias Examples.EFibonacci
  alias Examples.EPower
  alias Zkfol.Doubling
  alias Zkfol.Interpretation
  alias Zkfol.Pipeline
  alias Zkfol.Statement
  alias Zkfol.Uair
  alias Zkfol.Witness

  @spec measured_power(non_neg_integer()) :: map()
  example measured_power(exponent \\ 32) do
    witness = EPower.power_witness(exponent)
    measurement("power 2^#{exponent}", EPower.power_predicate(), witness)
  end

  @spec measured_fibonacci(pos_integer()) :: map()
  example measured_fibonacci(n \\ 32) do
    witness = EFibonacci.fibonacci_witness(n)
    measurement("fibonacci n=#{n}", EFibonacci.fibonacci_predicate(), witness)
  end

  @spec measured_doubled_fibonacci(pos_integer()) :: map()
  example measured_doubled_fibonacci(n \\ 10_000) do
    statement = EDoubling.rewritten_fibonacci(n)
    measurement("fibonacci n=#{n}, doubled", statement.pred, statement.witness, statement.claims)
  end

  @spec measured_default_fibonacci(pos_integer()) :: map()
  example measured_default_fibonacci(n \\ 10_000) do
    {:ok, count, seeds} = Doubling.seeds(EFibonacci.fibonacci_predicate(), n)
    goal = {Witness, len: count, seeds: seeds}
    pipeline = %Pipeline{passes: Pipeline.default().passes ++ [goal]}

    {:ok, statement, _trace} =
      Pipeline.run(pipeline, %Statement{pred: EFibonacci.fibonacci_predicate()})

    measurement("fibonacci n=#{n}, default", statement.pred, statement.witness)
  end

  @spec frozen_shapes() :: [map()]
  example frozen_shapes do
    # The regression gates: translation growth is a failure, not a drift.
    doubled = EDoubling.rewritten_fibonacci(10_000)
    {:ok, kernel} = Uair.emit(doubled.pred, doubled.witness, doubled.claims)

    {:ok, generic} =
      Uair.emit(EFibonacci.fibonacci_predicate(), EFibonacci.fibonacci_witness(32))

    assert kernel.num_vars == 4
    assert kernel.num_cols == 7
    assert generic.num_vars == 5
    assert generic.num_cols == 5

    [kernel, generic]
  end

  @spec report() :: [map()]
  example report do
    [
      measured_power(),
      measured_fibonacci(),
      measured_doubled_fibonacci(),
      measured_default_fibonacci()
    ]
  end

  @doc "I prove `phi` under `witness` through the journal and keep the numbers."
  @spec measurement(String.t(), Zkfol.Ast.pred(), Interpretation.t(), [Interpretation.claim()]) ::
          map()
  def measurement(statement, phi, witness, claims \\ []) do
    {:ok, report, _id} = Uair.prove(phi, witness, name: statement, claims: claims)
    assert report.proved

    %{
      statement: statement,
      backend: report.backend,
      prove_ms: report.prove_ms,
      verify_ms: report.verify_ms
    }
  end
end
