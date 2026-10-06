defmodule Zkfol.Harness.Acts do
  @moduledoc """
  I am the demo's acts, one function each, in the order they are run on stage.

  Each act prints what it does as it does it and returns `:ok`, or `{:error, refusal}` when
  something outside the demo's claims failed (no API key, a model error). A refusal by the
  gate or the verifier is not an error: it is the result being shown.

  ### Public API

  - `act1/1`: an unconstrained model, and the gate refusing it.
  - `act2/1`: a compliant output, proved, and verified by a separate process.
  - `act3/1`: an edited output and a tampered proof, and the prover failing on a false one.
  - `act4/1`: verification from two files alone.
  - `fixtures/0`: the replay texts, written where `--from-file` can read them.
  """

  alias Zkfol.Harness.Agent
  alias Zkfol.Harness.Agent.Generation
  alias Zkfol.Harness.Canon
  alias Zkfol.Harness.Context
  alias Zkfol.Harness.Gate
  alias Zkfol.Harness.Gate.Release
  alias Zkfol.Harness.Gate.Withheld
  alias Zkfol.Harness.Policy
  alias Zkfol.Harness.Show
  alias Zkfol.Harness.Statement
  alias Zkfol.Harness.Text
  alias Zkfol.Refusal
  alias Zkfol.Verifier
  alias Zkfol.Verifier.Accepted
  alias Zkfol.Verifier.Request

  @out Path.expand("../../../harness/out", __DIR__)
  @accepted Path.join(@out, "accepted")
  @attempts 3

  @free_system "You are a thoughtful essayist. Write in a flowing, literary style with natural asides."
  @careful_system "You are a careful writer. Never use em dashes, en dashes or double hyphens anywhere. Use commas, colons, brackets or full stops instead."

  @type options :: keyword()

  @doc "I am the directory the acts leave their files in."
  @spec out() :: Path.t()
  def out, do: @out

  ############################################################
  #                          Act 1                           #
  ############################################################

  @doc "I ask the model for text with no constraint, and show the gate refusing it."
  @spec act1(options()) :: :ok | {:error, Refusal.t()}
  def act1(opts) do
    Show.title("Act 1: an unconstrained model")
    user = essay(topic(opts))

    with {:ok, %Generation{} = generation} <- generated(opts, @free_system, user) do
      Show.step("What the model wrote (every dash highlighted)")
      Show.text(generation.text)
      Show.kv("dashes in the output", Show.dashes(generation.text))

      Show.step("The gate: canonicalise, then ask the prover for a proof")
      prefix = fresh(Path.join(@out, "act1"))

      case Gate.release(
             Text.statement(generation.text, Policy.load(), generation.context),
             prefix
           ) do
        {:withheld, %Withheld{} = withheld} ->
          withheld(withheld, prefix)

        {:released, %Release{}} ->
          Show.note("This output happened to comply, so the gate released it.")
      end
    end
  end

  ############################################################
  #                          Act 2                           #
  ############################################################

  @doc "I get a compliant output, prove it, verify it in a separate process, and keep the files."
  @spec act2(options()) :: :ok | {:error, Refusal.t()}
  def act2(opts) do
    Show.title("Act 2: a compliant output, proved")
    limit = if Keyword.has_key?(opts, :from_file), do: 1, else: @attempts
    compliant(opts, essay(topic(opts)), 1, limit)
  end

  @spec compliant(options(), String.t(), pos_integer(), pos_integer()) ::
          :ok | {:error, Refusal.t()}
  defp compliant(_opts, _user, attempt, limit) when attempt > limit do
    Show.banner(:red, ["NO COMPLIANT OUTPUT AFTER #{limit} ATTEMPTS", "Nothing was released."])
  end

  defp compliant(opts, user, attempt, limit) do
    Show.step("Attempt #{attempt} of #{limit}: ask the model, told to avoid dashes")

    with {:ok, %Generation{} = generation} <- generated(opts, @careful_system, user) do
      Show.text(generation.text)
      Show.kv("model", generation.context.model)
      prefix = fresh(@accepted)

      case Gate.release(
             Text.statement(generation.text, Policy.load(), generation.context),
             prefix
           ) do
        {:released, %Release{} = release} ->
          released(release, prefix)

        {:withheld, %Withheld{} = withheld} ->
          withheld(withheld, prefix)
          compliant(opts, retry(user), attempt + 1, limit)
      end
    end
  end

  @spec released(Release.t(), Path.t()) :: :ok
  defp released(%Release{report: report, accepted: accepted, request: request}, prefix) do
    Show.banner(:green, ["OUTPUT RELEASED", "A proof of the policy was produced and verified."])
    Show.step("The proof")
    Show.kv("proof size", size(File.stat!(request.proof).size))
    Show.kv("proof generation time", "#{round(report.prove_ms)} ms")
    Show.kv("committed columns", "2^#{report.num_vars} rows")

    Show.step("The verifier: a separate process, given only the two files")
    Show.kv("proof file", request.proof)
    Show.kv("public inputs file", request.public)
    Show.kv("verification time", "#{round(accepted.verify_ms)} ms")
    Show.good("proof ACCEPTED")

    Show.step("What the proof binds (public inputs)")
    bindings(accepted)
    Show.kv("witness commitment", accepted.commitment)
    Show.note("files: #{prefix}.*")
  end

  ############################################################
  #                          Act 3                           #
  ############################################################

  @doc """
  I take an edited version of the accepted output. The old proof is checked against it and
  fails on the commitment, a hand-edited proof file fails, and the real prover is run on
  the edited text.
  """
  @spec act3(options()) :: :ok | {:error, Refusal.t()}
  def act3(opts) do
    Show.title("Act 3: tampering")

    with {:ok, manifest} <- manifest(),
         {:ok, accepted} <- Verifier.verify(request(@accepted)) do
      policy = Policy.load()
      context = context(manifest)
      edited = edited_text(opts)

      Show.step("The accepted output, and your edit of it")
      Show.text(File.read!(@accepted <> ".txt"))
      Show.note("edited:")
      Show.text(edited)

      stale_commitment(edited, policy, context, accepted)
      edited_proof(opts, accepted)
      prover_on_edit(edited, policy, context)
    end
  end

  @spec stale_commitment(String.t(), Policy.t(), Context.t(), Accepted.t()) :: :ok
  defp stale_commitment(edited, policy, context, accepted) do
    Show.step("Re-verify the OLD proof against the EDITED text")
    {:ok, statement} = Text.statement(edited, policy, context)
    {:ok, commitment} = Statement.commit(statement)
    Show.kv("proof's commitment", short(accepted.commitment))
    Show.kv("edited text's commitment", short(commitment))

    request = %{request(@accepted) | pins: pins(@accepted, statement, commitment)}

    case Verifier.verify(request) do
      {:error, {:verifier_rejected, %{said: said}}} -> Show.rejected(said)
      {:ok, _} -> Show.note("The edit changed nothing the canonical form sees: same commitment.")
    end
  end

  @spec edited_proof(options(), Accepted.t()) :: :ok
  defp edited_proof(opts, _accepted) do
    Show.step("A hand-edited proof file")

    path =
      case Keyword.get(opts, :edited_proof) do
        nil ->
          flipped = Path.join(@out, "tampered.proof")
          bytes = File.read!(@accepted <> ".proof")
          <<head::binary-size(1000), byte, tail::binary>> = bytes
          File.write!(flipped, <<head::binary, Bitwise.bxor(byte, 255), tail::binary>>)
          Show.note("no file given: one byte of the proof was flipped, in #{flipped}")
          flipped

        path ->
          path
      end

    case Verifier.verify(%{request(@accepted) | proof: path}) do
      {:error, {:verifier_rejected, %{said: said}}} -> Show.rejected(said)
      {:ok, _} -> Show.note("That proof file still verifies: it is the original.")
    end
  end

  @spec prover_on_edit(String.t(), Policy.t(), Context.t()) :: :ok
  defp prover_on_edit(edited, policy, context) do
    Show.step("Run the REAL PROVER on the edited text")
    prefix = fresh(Path.join(@out, "act3"))

    case Gate.release(Text.statement(edited, policy, context), prefix) do
      {:withheld, %Withheld{} = withheld} ->
        withheld(withheld, prefix)

      {:released, %Release{request: request, accepted: accepted}} ->
        Show.note("The edit complies with the policy, so a proof exists for it.")
        Show.kv("its commitment", short(accepted.commitment))
        Show.kv("its proof", request.proof)
    end
  end

  ############################################################
  #                          Act 4                           #
  ############################################################

  @doc """
  I verify from a proof file and a public inputs file alone, with no plaintext. Pins come
  from `--pins`, or are built from the published policy and canonicaliser.
  """
  @spec act4(options()) :: :ok | {:error, Refusal.t()}
  def act4(opts) do
    Show.title("Act 4: verification with no plaintext")
    proof = Keyword.get(opts, :proof, @accepted <> ".proof")
    public = Keyword.get(opts, :public, @accepted <> ".public.json")
    pins = Keyword.get(opts, :pins) || published_pins()

    Show.kv("proof file", proof)
    Show.kv("public inputs file", public)
    Show.kv("pins file", pins)
    Show.kv("plaintext available", "no: the verifier is never given any")

    case Verifier.verify(%Request{proof: proof, public: public, pins: pins}) do
      {:ok, %Accepted{} = accepted} ->
        Show.banner(:green, ["PROOF ACCEPTED", "verified in #{round(accepted.verify_ms)} ms"])
        bindings(accepted)
        Show.kv("witness commitment", accepted.commitment)

      {:error, {:verifier_rejected, %{said: said}}} ->
        Show.banner(:red, ["PROOF REJECTED", said])
    end
  end

  ############################################################
  #                        Fixtures                          #
  ############################################################

  @doc """
  I write the replay texts into the output directory. They are templates with an `[EM]`
  token, so the source never holds a dash and the files do.
  """
  @spec fixtures() :: :ok
  def fixtures do
    File.mkdir_p!(@out)
    dash = <<0x2014::utf8>>
    templates = Path.expand("../../../harness/fallback", __DIR__)

    for template <- Path.wildcard(Path.join(templates, "*.template.txt")) do
      name = template |> Path.basename() |> String.replace(".template.txt", ".txt")

      File.write!(
        Path.join(@out, "sample-" <> name),
        template |> File.read!() |> String.replace("[EM]", dash)
      )

      Show.note("wrote #{Path.join(@out, "sample-" <> name)}")
    end

    :ok
  end

  ############################################################
  #                         Helpers                          #
  ############################################################

  @spec generated(options(), String.t(), String.t()) ::
          {:ok, Generation.t()} | {:error, Refusal.t()}
  defp generated(opts, system, user) do
    case Keyword.get(opts, :from_file) do
      nil ->
        Agent.generate(system, user)

      path ->
        Show.banner(:yellow, ["REPLAYED OUTPUT, NOT A LIVE MODEL CALL", "Text read from #{path}"])

        {:ok,
         %Generation{
           text: File.read!(path),
           context: Context.new("replayed", system, user),
           ms: 0
         }}
    end
  end

  @spec withheld(Withheld.t(), Path.t()) :: :ok
  defp withheld(%Withheld{stage: stage, reason: reason}, prefix) do
    Show.kv("stopped at", stage)
    Show.kv("why", plain(stage))
    Show.kv("prover detail", Refusal.message(reason))
    Show.kv("a proof file exists", File.exists?(prefix <> ".proof"))
    Show.kv("an output file exists", File.exists?(prefix <> ".txt"))

    Show.banner(:red, [
      "OUTPUT WITHHELD",
      "No proof could be produced, so nothing was released.",
      "Escalated to a human reviewer."
    ])
  end

  @spec plain(atom()) :: String.t()
  defp plain(:prove),
    do: "the prover could not make a valid proof that this text meets the policy"

  defp plain(:canonicalise),
    do: "the text could not be put into the fixed form the policy is proved over"

  defp plain(:bind), do: "the proof could not be tied to this text"
  defp plain(:verify), do: "the separate verifier did not accept the proof"

  @spec bindings(Accepted.t()) :: :ok
  defp bindings(%Accepted{bindings: bindings}) do
    for {name, value} <- Enum.sort(bindings), do: Show.kv(name, short(value))
    :ok
  end

  @spec manifest() :: {:ok, map()} | {:error, Refusal.t()}
  defp manifest do
    case File.read(@accepted <> ".manifest.json") do
      {:ok, json} ->
        {:ok, JSON.decode!(json)}

      {:error, _} ->
        {:error, {:prover_failed, %{said: "run act 2 first: there is no accepted output"}}}
    end
  end

  @spec context(map()) :: Context.t()
  defp context(manifest),
    do: %Context{
      model: manifest["model"],
      system_prompt: manifest["system_prompt"],
      user_prompt: manifest["user_prompt"],
      nonce: Base.decode16!(manifest["nonce"], case: :lower)
    }

  @spec pins(Path.t(), Statement.t(), String.t()) :: Path.t()
  defp pins(prefix, statement, commitment),
    do:
      Verifier.pin(Map.put(statement.pins, "commitment", commitment), prefix <> ".edit.pins.json")

  @spec published_pins() :: Path.t()
  defp published_pins do
    pins = %{
      "policy" => Zkfol.Harness.Bindings.hex(Zkfol.Harness.Bindings.words(Policy.load().hash)),
      "canonicaliser" =>
        Zkfol.Harness.Bindings.hex(Zkfol.Harness.Bindings.words(Canon.source_hash()))
    }

    Verifier.pin(pins, Path.join(@out, "published.pins.json"))
  end

  @spec request(Path.t()) :: Request.t()
  defp request(prefix), do: %Request{proof: prefix <> ".proof", public: prefix <> ".public.json"}

  @spec topic(options()) :: String.t()
  defp topic(opts) do
    case Keyword.get(opts, :topic) do
      nil -> "Topic for the model to write about? " |> IO.gets() |> String.trim()
      topic -> topic
    end
  end

  @spec edited_text(options()) :: String.t()
  defp edited_text(opts) do
    case Keyword.get(opts, :edited) do
      nil ->
        IO.puts("Type the edited text, then a line containing only END:") && read_until_end([])

      "-" ->
        IO.read(:stdio, :eof)

      path ->
        File.read!(path)
    end
  end

  @spec read_until_end([String.t()]) :: String.t()
  defp read_until_end(lines) do
    case IO.gets("") do
      line when line in [:eof, "END\n", "END"] -> lines |> Enum.reverse() |> Enum.join()
      line -> read_until_end([line | lines])
    end
  end

  @spec essay(String.t()) :: String.t()
  defp essay(topic), do: "Write about 250 words on: #{topic}"

  @spec retry(String.t()) :: String.t()
  defp retry(user),
    do: user <> "\n\nYour previous answer contained a dash. Rewrite it with no dash of any kind."

  @spec fresh(Path.t()) :: Path.t()
  defp fresh(prefix) do
    File.mkdir_p!(Path.dirname(prefix))
    for path <- Path.wildcard(prefix <> ".*"), do: File.rm!(path)
    prefix
  end

  @spec short(String.t()) :: String.t()
  defp short(hex),
    do: String.slice(hex, 0, 32) <> if(String.length(hex) > 32, do: "...", else: "")

  @spec size(non_neg_integer()) :: String.t()
  defp size(bytes), do: "#{Float.round(bytes / 1024, 1)} KB (#{bytes} bytes)"
end
