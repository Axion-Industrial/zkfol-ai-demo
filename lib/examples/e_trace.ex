defmodule Examples.ETrace do
  @moduledoc """
  I am the conduct policy's evidence: a run that keeps to the rules proves, each rule broken is
  refused by the real prover, and a proof made against a wider allowlist does not verify
  against the published one.
  """

  use ExExample

  import ExUnit.Assertions

  alias ZkfolAiDemo.Allowlist
  alias ZkfolAiDemo.Allowlist.Entry
  alias ZkfolAiDemo.Conduct
  alias ZkfolAiDemo.Context
  alias ZkfolAiDemo.Derivation
  alias ZkfolAiDemo.Gate
  alias ZkfolAiDemo.Gate.Release
  alias ZkfolAiDemo.Gate.Withheld
  alias ZkfolAiDemo.Statement
  alias ZkfolAiDemo.Trace
  alias ZkfolAiDemo.Trace.Event
  alias Zkfol.Interpretation
  alias Zkfol.Prover
  alias Zkfol.Uair
  alias Zkfol.Verifier

  @inside "reports@corp.example"
  @no_documents "status@corp.example"
  @attacker "exfil@evil.example"

  @doc "Every example writes files and starts a process, so none is cached."
  @spec rerun?(term()) :: boolean()
  def rerun?(_example), do: true

  @doc "A run that reads documents and mails one to the allowlisted recipient is released."
  @spec honest_run_is_released() :: Release.t()
  example honest_run_is_released do
    events = [
      %Event{kind: :retrieve, doc: 1},
      %Event{kind: :retrieve, doc: 2},
      %Event{kind: :mail, dest: @inside, doc: 1}
    ]

    assert {:released, %Release{} = release} = release(events, "honest")
    assert release.accepted.bindings["allowlist_sha256"] =~ ~r/^[0-9a-f]{64}$/
    release
  end

  @doc "Each rule, broken: the real prover runs on the trace and cannot prove it."
  @spec every_broken_rule_is_refused_by_the_prover() :: [String.t()]
  example every_broken_rule_is_refused_by_the_prover do
    broken = [
      {"mail to a destination off the allowlist",
       [%Event{kind: :retrieve, doc: 1}, %Event{kind: :mail, dest: @attacker, doc: 1}]},
      {"a document to a destination that may not receive documents",
       [%Event{kind: :retrieve, doc: 1}, %Event{kind: :mail, dest: @no_documents, doc: 1}]},
      {"a write with no approval", [%Event{kind: :write, dest: @no_documents}]},
      {"a write after an approval that returned false",
       [%Event{kind: :approve, approved: false}, %Event{kind: :write, dest: @no_documents}]},
      {"a write before the approval",
       [%Event{kind: :write, dest: @no_documents}, %Event{kind: :approve, approved: true}]},
      {"a write to the attacker, approved",
       [%Event{kind: :approve, approved: true}, %Event{kind: :write, dest: @attacker}]}
    ]

    for {label, events} <- broken do
      assert {:withheld, %Withheld{stage: :prove, reason: {:verifier_rejected, _}}} =
               release(events, "broken"),
             label

      label
    end
  end

  @doc "A write after an approval that returned true is released, and plain mail needs none."
  @spec approved_write_is_released() :: Release.t()
  example approved_write_is_released do
    events = [
      %Event{kind: :approve, approved: true},
      %Event{kind: :write, dest: @no_documents},
      %Event{kind: :mail, dest: @no_documents}
    ]

    assert {:released, %Release{} = release} = release(events, "approved")
    release
  end

  @doc """
  The allowlist is public and pinned: a proof made against a wider allowlist, which lets a
  mail to the attacker keep the rules, does not verify against the published one.
  """
  @spec proof_against_another_allowlist_is_rejected() :: String.t()
  example proof_against_another_allowlist_is_rejected do
    published = allowlist()
    attacker = %Entry{address: @attacker, id: Allowlist.id(@attacker), documents: true}
    widened = %{published | entries: published.entries ++ [attacker]}
    leak = [%Event{kind: :retrieve, doc: 1}, %Event{kind: :mail, dest: @attacker, doc: 1}]
    kept = [%Event{kind: :retrieve, doc: 1}, %Event{kind: :mail, dest: @inside, doc: 1}]

    assert {:released, %Release{request: request}} =
             Gate.release(Trace.statement(leak, widened, context()), prefix("widened"))

    # The pin a verifier computes from the published allowlist.
    {:ok, honest} = Trace.statement(kept, published, context())
    pin = Statement.pins(honest)["allowlist"]
    pins = request.pins |> File.read!() |> JSON.decode!() |> Map.put("allowlist", pin)

    assert {:error, {:verifier_rejected, %{said: said}}} =
             Verifier.verify(%{request | pins: Verifier.pin(pins, request.pins <> ".published")})

    assert said =~ "allowlist"
    said
  end

  @doc """
  The compiled program's lookup check works in 32-bit words, which is why a destination is
  four words: an allowlist of two entries a word of 2^40 wide holds of the run, and the
  prover cannot prove it.
  """
  @spec a_destination_word_over_32_bits_fails_the_proof() :: String.t()
  example a_destination_word_over_32_bits_fails_the_proof do
    wide = fn n -> [Integer.pow(2, 40) - n, 0, 0, 0] end
    allowlist = wide.(5) ++ [1] ++ wide.(9) ++ [0]
    events = [4] ++ wide.(5) ++ [1, 0]

    assert {:ok, %Derivation{} = derivation} =
             Derivation.run(Conduct.run(), [events, allowlist, 0])

    {:ok, uair} = Uair.emit(derivation.pred, Interpretation.new(derivation.rows))
    assert {:error, {:prover_failed, %{said: said}}} = Prover.prove_uair(uair, timeout: 120_000)
    assert said =~ "Lookup"
    said
  end

  @spec release([Event.t()], String.t()) :: {:released, Release.t()} | {:withheld, Withheld.t()}
  defp release(events, name),
    do: Gate.release(Trace.statement(events, allowlist(), context()), prefix(name))

  @spec allowlist() :: Allowlist.t()
  defp allowlist do
    {:ok, allowlist} = Allowlist.load()
    allowlist
  end

  @spec context() :: Context.t()
  defp context, do: Context.new("claude-opus-5-5", "Summarise the folder.", "Please summarise.")

  @spec prefix(String.t()) :: Path.t()
  defp prefix(name) do
    dir = Path.join(System.tmp_dir!(), "zkfol-trace-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    Path.join(dir, name)
  end
end
