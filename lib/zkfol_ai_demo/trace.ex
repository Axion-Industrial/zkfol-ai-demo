defmodule ZkfolAiDemo.Trace do
  @moduledoc """
  I am the trace policy as a statement: a property of what an agent did, not what it wrote.

  An agent's run is a fixed-length array of typed events, one per column, laid out as rows:
  the kind of each event, its destination, the document it touches and whether an approval
  returned true. Kinds are 1 retrieve, 2 approve, 3 write (to an external API), 4 mail, and 0
  for the padding after the last event. Three rules hold at every column:

  1. A write has an approval before it: the prover names an earlier column whose kind is 2
     and whose approval is 1, and the circuit reads it by pointer.
  2. Every write and every mail goes to an allowlisted destination: the prover names the
     allowlist cell holding the destination, and the circuit reads it by pointer.
  3. A mail that carries a document goes only to a destination the allowlist marks as one
     that may receive documents. A document is any nonzero document number: an attachment,
     or text copied from a document that the recorder matched.

  The allowlist is in the public row, so a verifier sees exactly what the destinations were
  checked against, and pins its hash. Its table is also a witness row tied to the public
  one, since pointer reads read witness rows only. The kind and document tests are small
  indicator equations: for a value `v` in `0..n`, `c * [v = i] = prod_(j != i)(v - j)`.

  Rule 3 is implied by rule 2 whenever every document-capable destination is also allowed to
  receive mail, which the signed file guarantees. It is kept as its own constraint so the
  proof still holds if rule 2 is later relaxed for some class of destination.

  The circuit certifies the trace it is given. That the trace is what the agent really did
  is the recorder's job: the destination an action is recorded with is the one it is run
  with, taken from the same parsed call.

  ### Public API

  - `statement/3` builds the statement for a list of events, an allowlist and a context.
  - `capacity/1` is the layout width that holds a number of events.
  """

  use TypedStruct

  alias Zkfol.Ast
  alias ZkfolAiDemo.Allowlist
  alias ZkfolAiDemo.Allowlist.Entry
  alias ZkfolAiDemo.Bindings
  alias ZkfolAiDemo.Canon
  alias ZkfolAiDemo.Context
  alias ZkfolAiDemo.Statement
  alias Zkfol.Refusal

  @policy Path.expand("../../harness/policy/trace.json", __DIR__)
  @external_resource @policy
  @policy_bytes File.read!(@policy)
  @documents 8
  @widths [127, 255, 511]

  # The rows, in the order the statement lays them out.
  @kind 1
  @dest 2
  @doc_row 3
  @approved 4
  @write 5
  @mail 6
  @carries 7
  @pointer 8
  @slack 9
  @entry 10
  @allowed 11
  @table 12
  @public 13

  typedstruct module: Event, enforce: true do
    @typedoc """
    One thing an agent did: retrieve a document, ask for approval (and whether it was given),
    write to an external API, or send mail. `doc` is a document number, 1 to 8, or 0 for none.
    """
    field(:kind, :retrieve | :approve | :write | :mail)
    field(:dest, String.t() | nil, default: nil)
    field(:doc, 0..8, default: 0)
    field(:approved, boolean(), default: false)
  end

  @doc "I am the hash of the published trace policy file."
  @spec policy_hash() :: binary()
  def policy_hash, do: Bindings.hash(@policy_bytes)

  @doc "I am the number of documents a trace can tell apart."
  @spec documents() :: pos_integer()
  def documents, do: @documents

  @doc "I am the smallest layout width that holds `events`, or nil if none does."
  @spec capacity(non_neg_integer()) :: pos_integer() | nil
  def capacity(events), do: Enum.find(@widths, &(&1 >= events))

  @doc "I am the statement that `events` satisfy the three rules against `allowlist`."
  @spec statement([Event.t()], Allowlist.t(), Context.t()) ::
          {:ok, Statement.t()} | {:error, Refusal.t()}
  def statement(events, %Allowlist{} = allowlist, %Context{} = context) do
    case capacity(length(events)) do
      nil ->
        {:error, {:text_exceeds_capacity, %{cells: length(events), capacity: List.last(@widths)}}}

      width ->
        {:ok, build(events, allowlist, context, width)}
    end
  end

  @spec build([Event.t()], Allowlist.t(), Context.t(), pos_integer()) :: Statement.t()
  defp build(events, allowlist, context, width) do
    entries = allowlist.entries
    public = public(allowlist, context)

    offset =
      public
      |> Enum.take_while(&(elem(&1, 0) != "allowlist"))
      |> Enum.flat_map(&elem(&1, 1))
      |> length()

    {table, _bindings, _claims} = Bindings.place(public, width, @public)

    real = rows(events, entries, offset, width, table)
    repaired = rows(repair(events, entries), entries, offset, width, table)

    %Statement{
      pred: pred(offset, length(entries)),
      rows: real,
      stand_in: repaired,
      public: public,
      pins: for({name, words} <- public, into: %{}, do: {name, Bindings.hex(words)}),
      output: describe(events),
      manifest: manifest(events, allowlist, context, width)
    }
  end

  # What a verifier is shown and holds the proof to, in the order every statement binds it.
  @spec public(Allowlist.t(), Context.t()) :: [{String.t(), [non_neg_integer()]}]
  defp public(%Allowlist{entries: entries, hash: hash, signer: signer}, context) do
    [
      {"policy", Bindings.words(policy_hash())},
      {"canonicaliser", Bindings.words(Canon.source_hash())}
      | Context.public(context)
    ] ++
      [
        {"allowlist_sha256", Bindings.words(hash)},
        {"allowlist_signer", Bindings.words(signer)},
        {"allowlist", for(%Entry{id: id} <- entries, do: id)},
        {"allow_documents",
         for(%Entry{documents: documents} <- entries, do: if(documents, do: 1, else: 0))}
      ]
  end

  ############################################################
  #                         The rows                         #
  ############################################################

  # The witness rows for `events`, padded to `width` with the padding event.
  @spec rows([Event.t()], [Entry.t()], non_neg_integer(), pos_integer(), [non_neg_integer()]) ::
          [[non_neg_integer()]]
  defp rows(events, entries, offset, width, table) do
    columns = Enum.zip(events ++ List.duplicate(nil, width - length(events)), 1..width)
    ids = for(%Entry{id: id} <- entries, do: id) |> Enum.with_index(offset + 1) |> Map.new()
    approvals = for {%Event{kind: :approve, approved: true}, x} <- columns, do: x

    cells =
      for {event, x} <- columns do
        kind = kind(event)
        dest = destination(event)
        write = if kind == 3, do: 1, else: 0
        pointer = approvals |> Enum.filter(&(&1 < x)) |> List.last(1)
        entry = Map.get(ids, dest, offset + 1)

        %{
          kind: kind,
          dest: dest,
          doc: (event && event.doc) || 0,
          approved: if(event && event.approved, do: 1, else: 0),
          write: write,
          mail: if(kind == 4, do: 1, else: 0),
          carries: if(event && event.doc != 0, do: 1, else: 0),
          pointer: pointer,
          slack: if(write == 1, do: max(x - pointer - 1, 0), else: 0),
          entry: entry,
          allowed: if(Map.has_key?(ids, dest), do: 1, else: 0)
        }
      end

    for field <- ~w(kind dest doc approved write mail carries pointer slack entry allowed)a do
      for cell <- cells, do: Map.fetch!(cell, field)
    end ++ [table]
  end

  @spec kind(Event.t() | nil) :: 0..4
  defp kind(nil), do: 0
  defp kind(%Event{kind: :retrieve}), do: 1
  defp kind(%Event{kind: :approve}), do: 2
  defp kind(%Event{kind: :write}), do: 3
  defp kind(%Event{kind: :mail}), do: 4

  @spec destination(Event.t() | nil) :: non_neg_integer()
  defp destination(%Event{dest: dest}) when is_binary(dest), do: Allowlist.id(dest)
  defp destination(_event), do: 0

  # A trace that satisfies the rules, near the real one: any event that breaks a rule becomes
  # padding. It is the emitter's stand-in, never what is proved.
  @spec repair([Event.t()], [Entry.t()]) :: [Event.t()]
  defp repair(events, entries) do
    {kept, _approved} =
      Enum.map_reduce(events, false, fn event, approved ->
        cond do
          not sound?(event, entries, approved) -> {%Event{kind: :retrieve, doc: 0}, approved}
          true -> {event, approved or (event.kind == :approve and event.approved)}
        end
      end)

    kept
  end

  @spec sound?(Event.t(), [Entry.t()], boolean()) :: boolean()
  defp sound?(%Event{kind: :write, dest: dest}, entries, approved),
    do: approved and Enum.any?(entries, &(&1.id == Allowlist.id(dest || "")))

  defp sound?(%Event{kind: :mail, dest: dest, doc: doc}, entries, _approved) do
    case Enum.find(entries, &(&1.id == Allowlist.id(dest || ""))) do
      nil -> false
      %Entry{documents: documents} -> doc == 0 or documents
    end
  end

  defp sound?(_event, _entries, _approved), do: true

  ############################################################
  #                       The predicate                      #
  ############################################################

  # `n` allowlist entries sit at columns offset+1 to offset+n of the public row, and their
  # document flags at the n columns after.
  @spec pred(non_neg_integer(), pos_integer()) :: Ast.pred()
  defp pred(offset, n) do
    [k, d, f, a, w, m, nz, j, s, q, al, t, pub] =
      for row <- [
            @kind,
            @dest,
            @doc_row,
            @approved,
            @write,
            @mail,
            @carries,
            @pointer,
            @slack,
            @entry,
            @allowed,
            @table,
            @public
          ],
          do: Ast.cell(row)

    flag = Ast.at(@table, {:cell, @entry}, 1, n)

    Ast.conj([
      # Domains: a kind is 0 to 4, a document 0 to 8, an approval 0 or 1.
      Ast.natural(k),
      Ast.natural(Ast.sub(4, k)),
      Ast.natural(f),
      Ast.natural(Ast.sub(@documents, f)),
      Ast.eq(Ast.mul(a, Ast.sub(a, 1)), 0),
      # Indicators: write is kind 3, mail is kind 4, carries is a nonzero document.
      Ast.eq(Ast.mul(-6, w), product([k, Ast.sub(k, 1), Ast.sub(k, 2), Ast.sub(k, 4)])),
      Ast.eq(Ast.mul(24, m), product([k, Ast.sub(k, 1), Ast.sub(k, 2), Ast.sub(k, 3)])),
      Ast.eq(
        Ast.mul(factorial(@documents), Ast.sub(1, nz)),
        product(for i <- 1..@documents, do: Ast.sub(f, i))
      ),
      # Rule 1: a write reads an earlier approval that returned true.
      Ast.eq(Ast.mul(w, Ast.sub(Ast.cell(@kind, @pointer), 2)), 0),
      Ast.eq(Ast.mul(w, Ast.sub(Ast.cell(@approved, @pointer), 1)), 0),
      Ast.eq(s, Ast.mul(w, Ast.sub(Ast.sub(Ast.x(), j), 1))),
      Ast.natural(s),
      # Rule 2: a write or mail goes to an allowlisted destination, read by pointer.
      Ast.natural(Ast.sub(q, offset + 1)),
      Ast.natural(Ast.sub(offset + n, q)),
      Ast.eq(Ast.mul(al, Ast.sub(al, 1)), 0),
      Ast.eq(Ast.mul(al, Ast.sub(d, Ast.cell(@table, @entry))), 0),
      Ast.eq(Ast.mul(Ast.add(w, m), Ast.sub(1, al)), 0),
      # Rule 3: a mail that carries a document goes where documents are allowed.
      Ast.eq(Ast.mul(Ast.mul(m, nz), Ast.sub(1, flag)), 0),
      # The table is the public row.
      Ast.eq(t, pub)
    ])
  end

  @spec product([Ast.term_t()]) :: Ast.term_t()
  defp product(terms), do: Enum.reduce(terms, &Ast.mul(&2, &1))

  @spec factorial(non_neg_integer()) :: pos_integer()
  defp factorial(n), do: Enum.reduce(1..n//1, 1, &*/2)

  ############################################################
  #                       The record                         #
  ############################################################

  @spec describe([Event.t()]) :: String.t()
  defp describe(events) do
    Enum.map_join(events, "\n", fn %Event{kind: kind, dest: dest, doc: doc, approved: approved} ->
      "#{kind} dest=#{dest || "-"} doc=#{doc} approved=#{approved}"
    end)
  end

  @spec manifest([Event.t()], Allowlist.t(), Context.t(), pos_integer()) :: map()
  defp manifest(events, allowlist, context, width) do
    %{
      predicate: "trace",
      policy_sha256: Base.encode16(policy_hash(), case: :lower),
      allowlist_sha256: Base.encode16(allowlist.hash, case: :lower),
      events: length(events),
      capacity: width,
      model: context.model,
      system_prompt: context.system_prompt,
      user_prompt: context.user_prompt,
      nonce: Base.encode16(context.nonce, case: :lower)
    }
  end
end
