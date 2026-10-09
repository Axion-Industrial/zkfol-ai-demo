defmodule Mix.Tasks.Harness do
  @moduledoc """
  I am the demo's command line: `mix harness <command> [options]`, run through `bin/harness`.

      bin/harness demo [--auto] [--injection FILE]
      bin/harness act1 [--topic T] [--from-file F]
      bin/harness act2 [--topic T]
      bin/harness act3 [--edited FILE] [--edited-proof FILE]
      bin/harness act4 [--proof F --public F --pins F]
      bin/harness act5 --injection FILE [--mode live|assume-compromised]
      bin/harness inboxes
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

  @impl Mix.Task
  def run(args) do
    if Mix.env() == :dev,
      do: Mix.raise("run this through bin/harness, which uses the test environment")

    {opts, [command | _]} = OptionParser.parse!(args, strict: @switches)

    case command do
      "demo" ->
        finish(Demo.run(opts))

      "act1" ->
        finish(Acts.act1(opts))

      "act2" ->
        finish(Acts.act2(opts))

      "act3" ->
        finish(Acts.act3(opts))

      "act4" ->
        finish(Acts.act4(opts))

      "lint" ->
        finish(Lint.run())

      "fixtures" ->
        finish(Acts.fixtures())

      "published" ->
        finish(Acts.published())

      "package" ->
        finish(Acts.package())

      "bench" ->
        finish(bench(opts))

      "act5" ->
        finish(Acts.act5(opts))

      "inboxes" ->
        finish(Acts.inboxes())

      "probe-injections" ->
        finish(Acts.probe_injections(opts))

      "keygen" ->
        finish(
          with {:ok, path} <- Allowlist.keygen(), do: Mix.shell().info("key written to #{path}")
        )

      "sign-allowlist" ->
        finish(Allowlist.sign())

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
