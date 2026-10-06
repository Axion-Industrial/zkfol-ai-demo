defmodule Examples.ETrace do
  @moduledoc """
  I am the trace policy's evidence: a run that keeps to the rules proves, each rule broken is
  refused by the real prover, and a witness forged to hide a break is refused by the circuit.
  """

  use ExExample

  import ExUnit.Assertions

  alias Zkfol.Harness.Allowlist
  alias Zkfol.Harness.Context
  alias Zkfol.Harness.Gate
  alias Zkfol.Harness.Gate.Release
  alias Zkfol.Harness.Gate.Withheld
  alias Zkfol.Harness.Statement
  alias Zkfol.Harness.Trace
  alias Zkfol.Harness.Trace.Event
  alias Zkfol.Refusal

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
  A witness forged to hide a break is refused by the circuit: a destination claimed allowed
  when it is not, a write recorded as no write, and an approval pointer aimed at a refusal.
  """
  @spec forged_witnesses_are_refused() :: [Refusal.t()]
  example forged_witnesses_are_refused do
    attacker_mail = [%Event{kind: :retrieve, doc: 1}, %Event{kind: :mail, dest: @attacker}]

    declined = [
      %Event{kind: :approve, approved: false},
      %Event{kind: :write, dest: @no_documents}
    ]

    unapproved = [%Event{kind: :write, dest: @no_documents}]

    forgeries = [
      {attacker_mail, [{:allowed, 2, 1}]},
      {unapproved, [{:write, 1, 0}]},
      {declined, [{:pointer, 2, 1}, {:slack, 2, 0}]}
    ]

    for {events, edits} <- forgeries do
      {:ok, honest} = Trace.statement(events, allowlist(), context())
      forged = %{honest | rows: Enum.reduce(edits, honest.rows, &edit/2)}

      assert {:error, {:verifier_rejected, _} = refusal} =
               Statement.prove(forged, prefix("forged"))

      refusal
    end
  end

  @doc "A run too long for one layout moves to the next width, and one too long for any is refused."
  @spec capacity_grows_with_the_run() :: [pos_integer()]
  example capacity_grows_with_the_run do
    widths = for n <- [1, 127, 128, 255, 256, 511], do: Trace.capacity(n)
    assert widths == [127, 127, 255, 255, 511, 511]
    assert Trace.capacity(512) == nil

    long = List.duplicate(%Event{kind: :retrieve, doc: 1}, 512)
    assert {:error, {:text_exceeds_capacity, _}} = Trace.statement(long, allowlist(), context())
    widths
  end

  # Row `name` of column `x` set to `value`, on rows in the order the statement lays them out.
  @spec edit({atom(), pos_integer(), integer()}, [[integer()]]) :: [[integer()]]
  defp edit({name, x, value}, rows) do
    row =
      Enum.find_index(
        ~w(kind dest doc approved write mail carries pointer slack entry allowed)a,
        &(&1 == name)
      )

    List.update_at(rows, row, &List.replace_at(&1, x - 1, value))
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
