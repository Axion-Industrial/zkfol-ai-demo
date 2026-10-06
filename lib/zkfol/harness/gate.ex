defmodule Zkfol.Harness.Gate do
  @moduledoc """
  I am the gate: an output is released only if a proof that it satisfies the policy
  verifies in a separate process, and the proof says what the gate expects it to say.

  The checks, in order: the statement builds, the real prover produces a proof, the
  standalone verifier accepts it against the statement's pins (the policy, the
  canonicaliser, the model, both prompts and the nonce), and the commitment the verifier
  read from the proof equals the one the gate recomputes from the witness. Any failure
  withholds the output, and nothing is released without a proof.

  ### Public API

  - `release/2` runs the gate on one statement.
  """

  use TypedStruct

  alias Zkfol.Harness.Statement
  alias Zkfol.Refusal
  alias Zkfol.Verifier
  alias Zkfol.Verifier.Request

  typedstruct module: Release, enforce: true do
    @typedoc "An output the gate released, and the proof that licensed it."
    field(:statement, Zkfol.Harness.Statement.t())
    field(:request, Zkfol.Verifier.Request.t())
    field(:accepted, Zkfol.Verifier.Accepted.t())
    field(:report, Zkfol.Prover.Report.t())
  end

  typedstruct module: Withheld, enforce: true do
    @typedoc "An output the gate withheld: where it stopped, and why."
    field(:stage, :canonicalise | :prove | :verify | :bind)
    field(:reason, Zkfol.Refusal.t())
  end

  @doc """
  I run the gate on a built statement, or on the refusal that building one ended in. A
  released output leaves `<prefix>.proof`, `<prefix>.public.json`, `<prefix>.pins.json`,
  `<prefix>.manifest.json` and `<prefix>.txt` behind.
  """
  @spec release({:ok, Statement.t()} | {:error, Refusal.t()}, Path.t()) ::
          {:released, Release.t()} | {:withheld, Withheld.t()}
  def release(built, prefix) do
    with {:ok, statement} <- staged(:canonicalise, built),
         {:ok, report} <- staged(:prove, Statement.prove(statement, prefix)),
         {:ok, commitment} <- staged(:bind, Statement.commit(statement)),
         request = request(prefix, Map.put(statement.pins, "commitment", commitment)),
         {:ok, accepted} <- staged(:verify, Verifier.verify(request)) do
      File.write!(prefix <> ".txt", statement.output)
      File.write!(prefix <> ".manifest.json", JSON.encode!(statement.manifest))

      {:released,
       %Release{statement: statement, request: request, accepted: accepted, report: report}}
    else
      {:stage, stage, reason} -> {:withheld, %Withheld{stage: stage, reason: reason}}
    end
  end

  @spec request(Path.t(), %{String.t() => String.t()}) :: Request.t()
  defp request(prefix, pins) do
    %Request{
      proof: prefix <> ".proof",
      public: prefix <> ".public.json",
      pins: Verifier.pin(pins, prefix <> ".pins.json")
    }
  end

  @spec staged(atom(), tuple()) :: tuple()
  defp staged(_stage, {:ok, _value} = ok), do: ok
  defp staged(stage, {:error, reason}), do: {:stage, stage, reason}
end
