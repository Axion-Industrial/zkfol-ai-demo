defmodule Mix.Tasks.Harness do
  @moduledoc """
  I am the demo's command line: `mix harness <command> [options]`, run through `bin/harness`.

      bin/harness act1 [--topic T] [--from-file F]
      bin/harness act2 [--topic T]
      bin/harness act3 [--edited FILE] [--edited-proof FILE]
      bin/harness act4 [--proof F --public F --pins F]
      bin/harness lint
      bin/harness fixtures
  """

  use Mix.Task

  alias Zkfol.Harness.Acts
  alias Zkfol.Harness.Lint

  @requirements ["app.start"]
  @switches [
    topic: :string,
    from_file: :string,
    edited: :string,
    edited_proof: :string,
    proof: :string,
    public: :string,
    pins: :string
  ]

  @impl Mix.Task
  def run(args) do
    if Mix.env() == :dev,
      do: Mix.raise("run this through bin/harness, which uses the test environment")

    {opts, [command | _]} = OptionParser.parse!(args, strict: @switches)

    case command do
      "act1" -> finish(Acts.act1(opts))
      "act2" -> finish(Acts.act2(opts))
      "act3" -> finish(Acts.act3(opts))
      "act4" -> finish(Acts.act4(opts))
      "lint" -> finish(Lint.run())
      "fixtures" -> finish(Acts.fixtures())
      other -> Mix.raise("unknown command #{other}")
    end
  end

  @spec finish(:ok | {:error, Zkfol.Refusal.t()}) :: :ok
  defp finish(:ok), do: :ok

  defp finish({:error, refusal}) do
    IO.puts(:stderr, "\n#{Zkfol.Refusal.message(refusal)}")
    System.halt(1)
  end
end
