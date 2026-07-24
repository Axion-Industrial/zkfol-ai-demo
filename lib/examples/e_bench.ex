defmodule Examples.EBench do
  @moduledoc """
  I am the benchmarker.
  """

  use ExExample

  import ExUnit.Assertions

  alias Examples.EDoubling
  alias Examples.EUser
  alias Zkfol.Interpretation
  alias Zkfol.Pipeline
  alias Zkfol.Statement
  alias Zkfol.Uair

  @spec measured_power(non_neg_integer()) :: map()
  example measured_power(exponent \\ 32) do
    witness = Statement.witness(EUser.power(exponent))
    measurement("power 2^#{exponent}", Statement.pred(EUser.power(exponent)), witness)
  end

  # The pinned code caps traces at 2048 columns; the suite default stays small.
  @spec measured_fibonacci(pos_integer()) :: map()
  example measured_fibonacci(n \\ 32) do
    witness = Statement.witness(EUser.fibonacci(n))
    measurement("fibonacci n=#{n}", Statement.pred(EUser.fibonacci()), witness)
  end

  @spec measured_registers_fibonacci(pos_integer()) :: map()
  example measured_registers_fibonacci(n \\ 32) do
    witness = Statement.witness(EUser.registers(n))
    measurement("fibonacci n=#{n}, registers", Statement.pred(EUser.registers(n)), witness)
  end

  @spec measured_doubled_fibonacci(pos_integer()) :: map()
  example measured_doubled_fibonacci(n \\ 10_000) do
    statement = EDoubling.rewritten_fibonacci(n)

    measurement(
      "fibonacci n=#{n}, doubled",
      Statement.pred(statement),
      Statement.witness(statement),
      statement.claims
    )
  end

  @spec measured_default_fibonacci(pos_integer()) :: map()
  example measured_default_fibonacci(n \\ 10_000) do
    {:ok, statement, _trace} =
      Pipeline.run(Pipeline.default(), %Statement{rels: [EUser.fib()], args: [n]})

    measurement(
      "fibonacci n=#{n}, default",
      Statement.pred(statement),
      Statement.witness(statement)
    )
  end

  # The composed-read fallback proves end to end; dies with Zkfol.Accumulator.
  @spec measured_accumulator_hop() :: map()
  example measured_accumulator_hop do
    # An 8-step trace asks nothing of the machine; a starved one fails loudly here.
    assert available_memory_mb() > 512

    statement = Examples.EAccumulator.expanded_hop()

    measurement(
      "hop n=5, accumulator fallback",
      Statement.pred(statement),
      Statement.witness(statement)
    )
  end

  @spec frozen_shapes() :: [Uair.t()]
  example frozen_shapes do
    # The regression gates: translation growth is a failure, not a drift.
    doubled = EDoubling.rewritten_fibonacci(10_000)
    {:ok, kernel} = Uair.emit(Statement.pred(doubled), Statement.witness(doubled), doubled.claims)

    {:ok, generic} =
      Uair.emit(Statement.pred(EUser.fibonacci()), Statement.witness(EUser.fibonacci(32)))

    assert Zkfol.Uair.num_vars(kernel) == 4
    assert Zkfol.Uair.num_cols(kernel) == 7
    assert Zkfol.Uair.num_vars(generic) == 5
    assert Zkfol.Uair.num_cols(generic) == 5

    # Canonical construction keeps programs at these lengths.
    assert length(kernel.program) == 279
    assert length(generic.program) == 111

    [kernel, generic]
  end

  @spec report() :: [map()]
  example report do
    [
      measured_power(),
      measured_fibonacci(),
      measured_registers_fibonacci(),
      measured_doubled_fibonacci(),
      measured_default_fibonacci(),
      measured_accumulator_hop()
    ]
  end

  @doc "I prove `phi` under `witness` through the journal and keep the numbers."
  @spec measurement(String.t(), Zkfol.Ast.pred(), Interpretation.t(), [Interpretation.claim()]) ::
          map()
  def measurement(statement, phi, witness, claims \\ []) do
    {:ok, uair} = Uair.emit(phi, witness, claims)
    {:ok, report, _id} = Uair.prove_uair(uair, name: statement, timeout: :infinity)

    %{
      statement: statement,
      backend: report.backend,
      prove_ms: report.prove_ms,
      verify_ms: report.verify_ms,
      proof_bytes: report.proof_bytes,
      program: length(uair.program)
    }
  end

  @doc "I am MemAvailable in megabytes, straight from /proc/meminfo."
  @spec available_memory_mb() :: non_neg_integer()
  def available_memory_mb do
    "MemAvailable:" <> rest =
      File.read!("/proc/meminfo")
      |> String.split("\n")
      |> Enum.find(&String.starts_with?(&1, "MemAvailable:"))

    {kb, " kB"} = rest |> String.trim() |> Integer.parse()
    div(kb, 1024)
  end
end
