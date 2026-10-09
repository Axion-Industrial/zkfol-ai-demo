defmodule Mix.Tasks.Harness do
  @moduledoc """
  I am the demo's command line: `mix harness <command> [options]`, run through `bin/harness`.

      bin/harness demo [--auto] [--injection FILE]
      bin/harness act1 [--topic T] [--from-file F]
      bin/harness act2 [--topic T]
      bin/harness act3 [--edited FILE] [--edited-proof FILE]
      bin/harness act4 [--proof F --public F --pins F]
      bin/harness act5 --injection FILE [--mode live|assume-compromised]
      bin/harness probe-injections [--mode live|assume-compromised]
      bin/harness bench [--runs N]
      bin/harness published
      bin/harness package
      bin/harness lint
      bin/harness fixtures
      bin/harness keygen
      bin/harness sign-allowlist
  """

  use Mix.Task

  alias ZkfolAiDemo.Acts
  alias ZkfolAiDemo.Allowlist
  alias ZkfolAiDemo.Bench
  alias ZkfolAiDemo.Demo
  alias ZkfolAiDemo.Lint

  @requirements ["app.start"]
  @switches [
    auto: :boolean,
    topic: :string,
    from_file: :string,
    edited: :string,
    edited_proof: :string,
    proof: :string,
    public: :string,
    pins: :string,
    injection: :string,
    mode: :string,
    runs: :integer
  ]

  # Every derivation a command makes lands in AL's store, and the store is replayed at each
  # start, so a command runs on a branch that is discarded after it. What a command leaves is
  # its files, never the store.
  @impl Mix.Task
  def run(args) do
    if Mix.env() == :dev,
      do: Mix.raise("run this through bin/harness, which uses the test environment")

    {opts, [command | _]} = OptionParser.parse!(args, strict: @switches)
    finish(on_a_branch(fn -> command(command, opts) end))
  end

  @spec on_a_branch((-> result)) :: result when result: term()
  defp on_a_branch(fun) do
    branch = AL.Branch.fork()
    AL.Branch.checkout(branch)

    try do
      fun.()
    after
      AL.Branch.discard(branch)
    end
  end

  @spec command(String.t(), keyword()) :: :ok | {:ok, term()} | {:error, Zkfol.Refusal.t()}
  defp command(command, opts) do
    case command do
      "demo" ->
        Demo.run(opts)

      "act1" ->
        Acts.act1(opts)

      "act2" ->
        Acts.act2(opts)

      "act3" ->
        Acts.act3(opts)

      "act4" ->
        Acts.act4(opts)

      "lint" ->
        Lint.run()

      "fixtures" ->
        Acts.fixtures()

      "published" ->
        Acts.published()

      "package" ->
        Acts.package()

      "bench" ->
        bench(opts)

      "act5" ->
        Acts.act5(opts)

      "probe-injections" ->
        Acts.probe_injections(opts)

      "keygen" ->
        with {:ok, path} <- Allowlist.keygen(), do: Mix.shell().info("key written to #{path}")

      "sign-allowlist" ->
        Allowlist.sign()

      other ->
        Mix.raise("unknown command #{other}")
    end
  end

  @spec bench(keyword()) :: :ok
  defp bench(opts) do
    Bench.run(Keyword.get(opts, :runs, 5))
    :ok
  end

  @spec finish(:ok | {:ok, term()} | {:error, Zkfol.Refusal.t()}) :: :ok
  defp finish(:ok), do: :ok
  defp finish({:ok, _what_happened}), do: :ok

  defp finish({:error, refusal}) do
    IO.puts(:stderr, "\n#{ZkfolAiDemo.Refusal.message(refusal)}")
    System.halt(1)
  end
end
