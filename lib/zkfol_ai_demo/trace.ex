defmodule ZkfolAiDemo.Trace do
  @moduledoc """
  I am the conduct policy as a statement: a property of what an agent did, not what it wrote.
  The statement is that `ZkfolAiDemo.Conduct.run/3` holds of the agent's events and the signed
  allowlist, and zkFOL derives the witness and the predicate from the relation.

  The allowlist is opened as public, so a verifier sees exactly what the destinations were
  checked against, and pins both its cells and the hash of the signed file. The events stay
  private. A run shorter than `@min_events` is padded with retrievals that touch no document,
  which no rule is about, so that the values a proof binds fit in the one public row.

  A run that breaks a rule has no derivation. It still reaches the real prover, as
  `ZkfolAiDemo.Statement` explains: I derive the nearest run that keeps the rules, by asking
  the relation itself which events it refuses, and put the real events in its place.

  ### Public API

  - `statement/3` builds the statement for a list of events, an allowlist and a context.
  """

  use TypedStruct

  alias Zkfol.Refusal
  alias ZkfolAiDemo.Allowlist
  alias ZkfolAiDemo.Allowlist.Entry
  alias ZkfolAiDemo.Bindings
  alias ZkfolAiDemo.Conduct
  alias ZkfolAiDemo.Context
  alias ZkfolAiDemo.Derivation
  alias ZkfolAiDemo.Statement

  # The public row holds 52 words, one to a column, and a derived witness has a column more
  # than the events have cells.
  @min_events 8

  # Where the derivation keeps the events: the bank of `run`'s first argument.
  @bank :"run a1"

  @kinds %{retrieve: 1, approve: 2, write: 3, mail: 4}

  typedstruct module: Event, enforce: true do
    @typedoc """
    One thing an agent did: retrieve a document, ask for approval (and whether it was given),
    write to an external API, or send mail. `doc` is a document number from 1, or 0 for none.
    """
    field(:kind, :retrieve | :approve | :write | :mail)
    field(:dest, String.t() | nil, default: nil)
    field(:doc, non_neg_integer(), default: 0)
    field(:approved, boolean(), default: false)
  end

  @doc "I am the statement that `events` keep the conduct rules against `allowlist`."
  @spec statement([Event.t()], Allowlist.t(), Context.t()) ::
          {:ok, Statement.t()} | {:error, Refusal.t()}
  def statement(events, %Allowlist{} = allowlist, %Context{} = context) do
    padded =
      events ++ List.duplicate(%Event{kind: :retrieve}, max(@min_events - length(events), 0))

    with {:ok, derivation, rows} <- witnessed(padded, allowlist) do
      {:ok,
       %Statement{
         derivation: derivation,
         rows: rows,
         public: public(allowlist, context),
         output: describe(events),
         manifest: manifest(events, allowlist, context)
       }}
    end
  end

  # The witness: derived from the events when the rules hold of them, and otherwise from the
  # nearest events they do hold of, with the real events put in the events' row.
  @spec witnessed([Event.t()], Allowlist.t()) ::
          {:ok, Derivation.t(), [[integer()]]} | {:error, Refusal.t()}
  defp witnessed(events, allowlist) do
    case derive(events, allowlist) do
      {:ok, derivation} ->
        {:ok, derivation, derivation.rows}

      :no_answer ->
        with {:ok, derivation} <- derive(repaired(events, allowlist), allowlist),
             do: {:ok, derivation, Derivation.forged(derivation, @bank, cells(events))}

      {:error, _refusal} = error ->
        error
    end
  end

  @spec derive([Event.t()], Allowlist.t()) ::
          {:ok, Derivation.t()} | :no_answer | {:error, Refusal.t()}
  defp derive(events, allowlist),
    do: Derivation.run(Conduct.run(), arguments(events, allowlist), :allowlist)

  @spec arguments([Event.t()], Allowlist.t()) :: [term()]
  defp arguments(events, %Allowlist{entries: entries}) do
    table =
      for %Entry{id: id, documents: documents} <- entries,
          cell <- id ++ [flag(documents)],
          do: cell

    [cells(events), table, 0]
  end

  @spec cells([Event.t()]) :: [non_neg_integer()]
  defp cells(events) do
    for %Event{kind: kind, dest: dest, doc: doc, approved: approved} <- events,
        cell <- [Map.fetch!(@kinds, kind)] ++ destination(dest) ++ [doc, flag(approved)],
        do: cell
  end

  @spec destination(String.t() | nil) :: [non_neg_integer()]
  defp destination(nil), do: [0, 0, 0, 0]
  defp destination(dest), do: Allowlist.id(dest)

  @spec flag(boolean()) :: 0 | 1
  defp flag(true), do: 1
  defp flag(false), do: 0

  # The nearest events the rules hold of: an event they refuse, given what came before it, is
  # replaced by a retrieval. The relation is asked; no rule is repeated here.
  @spec repaired([Event.t()], Allowlist.t()) :: [Event.t()]
  defp repaired(events, allowlist), do: repaired([], events, allowlist)

  @spec repaired([Event.t()], [Event.t()], Allowlist.t()) :: [Event.t()]
  defp repaired(kept, [], _allowlist), do: kept

  defp repaired(kept, [event | rest], allowlist) do
    next = kept ++ [event]

    if Derivation.holds?(Conduct.run(), arguments(next, allowlist)),
      do: repaired(next, rest, allowlist),
      else: repaired(kept ++ [%Event{kind: :retrieve}], rest, allowlist)
  end

  # What a verifier is shown and holds the proof to, in the order every statement binds it.
  @spec public(Allowlist.t(), Context.t()) :: [{String.t(), [non_neg_integer()]}]
  defp public(%Allowlist{hash: hash, signer: signer}, context) do
    [{"policy", Bindings.words(Conduct.source_hash())} | Context.public(context)] ++
      [
        {"allowlist_sha256", Bindings.words(hash)},
        {"allowlist_signer", Bindings.words(signer)}
      ]
  end

  ############################################################
  #                       The record                         #
  ############################################################

  @spec describe([Event.t()]) :: String.t()
  defp describe(events) do
    Enum.map_join(events, "\n", fn %Event{kind: kind, dest: dest, doc: doc, approved: approved} ->
      "#{kind} dest=#{dest || "-"} doc=#{doc} approved=#{approved}"
    end)
  end

  @spec manifest([Event.t()], Allowlist.t(), Context.t()) :: map()
  defp manifest(events, allowlist, context) do
    %{
      predicate: "trace",
      policy: "conduct",
      policy_sha256: Base.encode16(Conduct.source_hash(), case: :lower),
      allowlist_sha256: Base.encode16(allowlist.hash, case: :lower),
      events: length(events),
      model: context.model,
      system_prompt: context.system_prompt,
      user_prompt: context.user_prompt,
      nonce: Base.encode16(context.nonce, case: :lower)
    }
  end
end
