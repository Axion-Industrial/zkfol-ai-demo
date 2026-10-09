defmodule ZkfolAiDemo.Conduct do
  @moduledoc """
  I am the conduct policy in zkFOL's relational language: three rules about what an agent
  did, not what it wrote.

  A run is a flat list of events, seven cells each: `[kind, d1, d2, d3, d4, document, approved]`.
  The kinds are 1 retrieve, 2 approve, 3 write (to an external API) and 4 mail. A document is
  any nonzero document number: an attachment, or text copied from a document that the recorder
  matched. A destination is four 32-bit words, the first 128 bits of the hash of its address:
  the compiled program's lookup check works in 32-bit words, and an allowlist of two entries
  wider than that fails to prove, so a hash is carried in four. The allowlist is a flat list
  of entries: `[d1, d2, d3, d4, may_receive_documents, ...]`.
  The third argument of `run/3` says whether an approval that returned true has happened yet.

  1. A write has an earlier approval that returned true: the clause for a write holds only
     once that argument is 1.
  2. Every write and every mail goes to an allowlisted destination, found by `entry/3`.
  3. A mail that carries a document goes only to a destination the allowlist marks as one that
     may receive documents.

  A run the rules do not hold of has no derivation. This file is the published policy:
  `source_hash/0` is SHA-256 of it as compiled, so `sha256sum lib/zkfol_ai_demo/conduct.ex`
  reproduces it, and every proof binds it.

  The relation certifies the run it is given. That the run is what the agent really did is the
  recorder's job: the destination an action is recorded with is the one it is run with, taken
  from the same parsed call.

  ### Public API

  - `entry/3` finds a destination in an allowlist, with its flag.
  - `run/3` is the policy: the events, the allowlist, and whether an approval has happened.
  - `source_hash/0` is the hash of this file.
  """

  use Zkfol.Lang

  @external_resource __ENV__.file
  @source_hash :crypto.hash(:sha256, File.read!(__ENV__.file))

  defrel entry(d1, d2, d3, d4, flag, [d1, d2, d3, d4, flag | _rest])

  defrel entry(d1, d2, d3, d4, flag, [_e1, _e2, _e3, _e4, _flag | rest]) do
    entry(d1, d2, d3, d4, flag, rest)
  end

  defrel run([], _allowlist, _approved)

  defrel run([1, _d1, _d2, _d3, _d4, _doc, _ok | events], allowlist, approved) do
    run(events, allowlist, approved)
  end

  defrel run([2, _d1, _d2, _d3, _d4, _doc, 0 | events], allowlist, approved) do
    run(events, allowlist, approved)
  end

  defrel run([2, _d1, _d2, _d3, _d4, _doc, 1 | events], allowlist, _approved) do
    run(events, allowlist, 1)
  end

  defrel run([3, d1, d2, d3, d4, _doc, _ok | events], allowlist, 1) do
    entry(d1, d2, d3, d4, _flag, allowlist)
    run(events, allowlist, 1)
  end

  defrel run([4, d1, d2, d3, d4, 0, _ok | events], allowlist, approved) do
    entry(d1, d2, d3, d4, _flag, allowlist)
    run(events, allowlist, approved)
  end

  defrel run([4, d1, d2, d3, d4, doc, _ok | events], allowlist, approved) do
    doc > 0
    entry(d1, d2, d3, d4, 1, allowlist)
    run(events, allowlist, approved)
  end

  @doc "I am the SHA-256 of this file as it was compiled."
  @spec source_hash() :: binary()
  def source_hash, do: @source_hash
end
