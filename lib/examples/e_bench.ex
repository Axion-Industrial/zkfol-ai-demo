defmodule Examples.EBench do
  @moduledoc """
  I am the benchmarker.
  """

  use ExExample

  alias Examples.EDoubling
  alias Examples.EUser
  alias Zkfol.Interpretation
  alias Zkfol.Pipeline
  alias Zkfol.Prover
  alias Zkfol.Statement
  alias Zkfol.Uair

  @spec measured_power(non_neg_integer()) :: map()
  example measured_power(exponent \\ 32) do
    witness = Statement.witness(EUser.power(exponent))
    measurement("power 2^#{exponent}", Statement.pred(EUser.power(exponent)), witness)
  end

  # The pin walls padded traces at 8192 rows; the suite default stays small.
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

  @spec measured_registers_fibonacci_mod(pos_integer()) :: map()
  example measured_registers_fibonacci_mod(n \\ 1000) do
    statement = EUser.registers_mod(n)

    measurement(
      "fibonacci n=#{n}, registers mod 7919",
      Statement.pred(statement),
      Statement.witness(statement)
    )
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

  # Value-addressed reads through zinc+'s pointer query, end to end.
  @spec measured_hop(pos_integer()) :: map()
  example measured_hop(n \\ 64) do
    {:ok, statement, _trace} =
      Pipeline.run(Pipeline.default(), %Statement{rels: [Examples.EAl.hop_rel()], args: [n]})

    measurement(
      "hop n=#{n}, pointer query",
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
      measured_registers_fibonacci_mod(),
      measured_doubled_fibonacci(),
      measured_hop()
    ]
  end

  @doc "I prove `phi` under `witness` through the journal and keep the numbers."
  @spec measurement(String.t(), Zkfol.Ast.pred(), Interpretation.t(), [Interpretation.claim()]) ::
          map()
  def measurement(statement, phi, witness, claims \\ []) do
    {:ok, uair} = Uair.emit(phi, witness, claims)
    {:ok, report, _id} = Prover.prove_uair(uair, name: statement, timeout: :infinity)

    %{
      statement: statement,
      backend: report.backend,
      prove_ms: report.prove_ms,
      verify_ms: report.verify_ms,
      proof_bytes: report.proof_bytes,
      program: length(uair.program)
    }
  end
end
