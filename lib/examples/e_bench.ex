defmodule Examples.EBench do
  @moduledoc "I am the benchmarker."

  use ExExample

  alias Examples.EDoubling
  alias Examples.EUser
  alias Zkfol.Pipeline
  alias Zkfol.Prover
  alias Zkfol.Statement
  alias Zkfol.Uair

  @spec measured_power(non_neg_integer()) :: map()
  example measured_power(exponent \\ 32) do
    measurement("power 2^#{exponent}", EUser.power(exponent))
  end

  @doc "The trace wall in the pinned prover bounds the padded rows, so the default stays small."
  @spec measured_fibonacci(pos_integer()) :: map()
  example measured_fibonacci(n \\ 32) do
    measurement("fibonacci n=#{n}", EUser.fibonacci(n))
  end

  @spec measured_registers_fibonacci(pos_integer()) :: map()
  example measured_registers_fibonacci(n \\ 32) do
    measurement("fibonacci n=#{n}, registers", EUser.registers(n))
  end

  @spec measured_registers_fibonacci_mod(pos_integer()) :: map()
  example measured_registers_fibonacci_mod(n \\ 1000) do
    measurement("fibonacci n=#{n}, registers mod 7919", EUser.registers_mod(n))
  end

  @spec measured_doubled_fibonacci(pos_integer()) :: map()
  example measured_doubled_fibonacci(n \\ 10_000) do
    measurement("fibonacci n=#{n}, doubled", EDoubling.rewritten_fibonacci(n))
  end

  @spec measured_doubled_fibonacci_mod(pos_integer(), pos_integer()) :: map()
  example measured_doubled_fibonacci_mod(n \\ 10_000, mod \\ 7919) do
    measurement("fibonacci n=#{n} mod #{mod}, doubled", EDoubling.rewritten_fibonacci_mod(n, mod))
  end

  @spec measured_hop(pos_integer()) :: map()
  example measured_hop(n \\ 64) do
    {:ok, statement, _trace} =
      Pipeline.run(Pipeline.default(), %Statement{rels: [Examples.EAl.hop_rel()], args: [n]})

    measurement("hop n=#{n}, pointer query", statement)
  end

  @doc "I am the fib table: one function four ways, reduced and not, rewritten and not."
  @spec measured_fibonacci_four_ways(pos_integer()) :: [map()]
  example measured_fibonacci_four_ways(n \\ 1000) do
    [
      measured_doubled_fibonacci(n),
      measured_registers_fibonacci(n),
      measured_doubled_fibonacci_mod(n),
      measured_registers_fibonacci_mod(n)
    ]
  end

  @doc "I am the whole fib grid: four ways at every n, one call."
  @spec measured_fibonacci_grid([pos_integer()]) :: [map()]
  example measured_fibonacci_grid(sizes \\ [1_000, 10_000]) do
    Enum.flat_map(sizes, &measured_fibonacci_four_ways/1)
  end

  @spec report() :: [map()]
  example report do
    [
      measured_power(),
      measured_fibonacci(),
      measured_registers_fibonacci(),
      measured_registers_fibonacci_mod(),
      measured_doubled_fibonacci(),
      measured_doubled_fibonacci_mod(),
      measured_hop()
    ]
  end

  @doc "I prove a solved statement and keep the numbers; the rss peak resets at entry."
  @spec measurement(String.t(), Statement.t()) :: map()
  def measurement(name, statement) do
    rss_baseline_mb = reset_peak_rss()

    {:ok, uair} =
      Uair.emit(
        Statement.pred(statement),
        Statement.witness(statement),
        Statement.claims(statement)
      )

    {:ok, report, _id} = Prover.prove_uair(uair, name: name, timeout: :infinity)

    %{
      statement: name,
      backend: report.backend,
      prove_ms: report.prove_ms,
      verify_ms: report.verify_ms,
      proof_bytes: report.proof_bytes,
      program: length(uair.program),
      rss_baseline_mb: rss_baseline_mb,
      rss_peak_mb: peak_mb(:os.type())
    }
  end

  @spec reset_peak_rss() :: non_neg_integer()
  defp reset_peak_rss do
    Enum.each(Process.list(), &:erlang.garbage_collect/1)
    with {:unix, :linux} <- :os.type(), do: File.write!("/proc/self/clear_refs", "5")
    rss_mb(:os.type())
  end

  @typep host() :: {:unix | :win32, atom()}

  @spec rss_mb(host()) :: non_neg_integer()
  defp rss_mb({:unix, :linux}), do: div(proc_status("VmRSS:"), 1024)

  defp rss_mb({:unix, _os}) do
    {rss, 0} = System.cmd("ps", ["-o", "rss=", "-p", System.pid()])
    rss |> String.trim() |> String.to_integer() |> div(1024)
  end

  @spec peak_mb(host()) :: non_neg_integer()
  defp peak_mb({:unix, :linux}), do: div(proc_status("VmHWM:"), 1024)
  defp peak_mb(host), do: rss_mb(host)

  @spec proc_status(String.t()) :: non_neg_integer()
  defp proc_status(key) do
    "/proc/self/status"
    |> File.read!()
    |> String.split("\n")
    |> Enum.find(&String.starts_with?(&1, key))
    |> String.split()
    |> Enum.at(1)
    |> String.to_integer()
  end
end
