defmodule Examples.EBench do
  @moduledoc """
  I am the benchmarker.
  """

  use ExExample

  import ExUnit.Assertions

  alias Examples.EDoubling
  alias Examples.EUser
  alias Zkfol.Interpretation
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

  @spec report() :: [map()]
  example report do
    [
      measured_power(),
      measured_fibonacci(),
      measured_registers_fibonacci(),
      measured_doubled_fibonacci(),
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
