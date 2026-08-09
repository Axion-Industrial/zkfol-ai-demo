defmodule Zkfol.Refusal do
  @moduledoc """
  I am the index of every refusal the compiler can make. A refusal is
  `{reason, detail}`: an atom naming it, and the values behind it.

      {:error, {:precedes_base_case, %{n: 0, base: 1}}}

  The prose is not stored, it is derived. A refusal carries no sentence
  at the place it is made, so the wording lives here once, the reason is
  what callers match on, and no one greps for a substring.

  A refusal's kind says what the caller should do, and is a property
  of the reason rather than a thing each site repeats:

  - `:restructure` — the statement's shape is not one I compile. Rewrite it.
  - `:out_of_range` — a bound was exceeded. Shrink it, or raise the bound.
  - `:capability` — I could compile this; the pinned backend cannot prove
    it yet. Wait, or take another path.
  - `:false_statement` — nothing is wrong with the statement except that
    it is not true. The honest refusal, and the only one that is a result.
  - `:transport` — the prover died, timed out, or never answered. Nothing
    is wrong with the statement at all. Retry.
  """

  @typedoc "What the caller should do about a refusal."
  @type kind :: :restructure | :out_of_range | :capability | :false_statement | :transport

  @typedoc "The values the message needs, and a view can point at."
  @type detail :: map()

  @typedoc "A refusal: what it is, and what it is about."
  @type t :: {reason(), detail()}

  @typedoc """
  A refusal drawn from `reason` only, so a pass can say in its spec which
  refusals it is able to make: `Refusal.t(Refusal.restructure())`.
  """
  @type t(reason) :: {reason, detail()}

  # The index proper, grouped by the response rather than repeating it:
  # a refusal is named once, under what it asks the caller to do. Adding
  # one means a name here and a message clause below.
  @by_kind %{
    restructure: ~w(not_an_index_relation facts_not_consecutive fact_not_ground step_clauses
         step_head_not_indexed step_beyond_history
         step_needs_an_equation not_order_two step_not_linear no_relations
         raw_predicate_has_no_clauses unbound_variable relation_not_in_scope
         call_output_not_fresh conflicting_schedule_offsets lookup_column_unshadowed
         read_row_claimed
         row_undetermined unliftable_term head_not_a_column arguments_exceed_rows
         free_index_needs_a_bound residue
         lookup_width_mismatch lookup_chunk_indivisible)a,
    out_of_range: ~w(precedes_base_case read_row_outside_witness
         pointer_row_outside_matrix claim_outside_witness witness_value_negative
         heap_exhausted unresolved_within_budget value_exceeds_cell
         constant_exceeds_cell)a,
    capability: ~w(calls_between_relations)a,
    false_statement: ~w(no_derivation no_derivation_at_count witness_invalid
         witness_unsatisfies_schedule verifier_rejected)a,
    transport: ~w(prover_timeout prover_died prover_failed send_failed)a
  }

  @index for {kind, reasons} <- @by_kind, reason <- reasons, into: %{}, do: {reason, kind}

  @union fn reasons -> Enum.reduce(reasons, &{:|, [], [&1, &2]}) end

  @typedoc "Every refusal the compiler can make."
  @type reason :: unquote(@union.(Map.keys(@index)))

  for {kind, reasons} <- @by_kind, reasons != [] do
    @typedoc "The refusals that ask the caller to #{kind}."
    @type unquote({kind, [], nil}) :: unquote(@union.(reasons))
  end

  @doc """
  I hold that no element of `enum` satisfies `bad?`. The first that does is
  the offender, and `refusal` names it.
  """
  @spec refute(Enumerable.t(), (term() -> boolean()), (term() -> t())) :: :ok | {:error, t()}
  def refute(enum, bad?, refusal) do
    case Enum.find(enum, bad?) do
      nil -> :ok
      offender -> {:error, refusal.(offender)}
    end
  end

  @doc """
  I map each element through `fun`, and the first refusal halts the walk.
  """
  @spec map(Enumerable.t(), (term() -> {:ok, term()} | {:error, t()})) ::
          {:ok, [term()]} | {:error, t()}
  def map(enum, fun) do
    enum
    |> Enum.reduce_while({:ok, []}, fn elem, {:ok, acc} ->
      case fun.(elem) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        refusal -> {:halt, refusal}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      refusal -> refusal
    end
  end

  @doc "I am `map/2` with the results concatenated, for steps that yield lists."
  @spec flat_map(Enumerable.t(), (term() -> {:ok, [term()]} | {:error, t()})) ::
          {:ok, [term()]} | {:error, t()}
  def flat_map(enum, fun) do
    with {:ok, chunks} <- map(enum, fun), do: {:ok, Enum.concat(chunks)}
  end

  @doc """
  I am `map/2` threading a state through the walk, as `Enum.map_reduce/3`
  would were a step able to refuse.
  """
  @spec map_reduce(Enumerable.t(), state, (term(), state -> {:ok, term(), state} | {:error, t()})) ::
          {:ok, [term()], state} | {:error, t()}
        when state: term()
  def map_reduce(enum, state, fun) do
    enum
    |> Enum.reduce_while({:ok, [], state}, fn elem, {:ok, acc, state} ->
      case fun.(elem, state) do
        {:ok, value, state} -> {:cont, {:ok, [value | acc], state}}
        refusal -> {:halt, refusal}
      end
    end)
    |> case do
      {:ok, values, state} -> {:ok, Enum.reverse(values), state}
      refusal -> refusal
    end
  end

  @doc """
  I read the backend's prose back into a refusal. zinc+ answers with a
  sentence, so the classifying happens once here rather than at every
  caller that has to tell a false statement from a dead prover.
  """
  @spec from_backend(String.t()) :: t()
  def from_backend("verifier failed" <> _rest = said), do: {:verifier_rejected, %{said: said}}

  def from_backend("lookup column " <> _rest = said),
    do: {:lookup_column_unshadowed, %{said: said}}

  def from_backend("lookup width " <> _rest = said), do: {:lookup_width_mismatch, %{said: said}}
  def from_backend("chunk width " <> _rest = said), do: {:lookup_chunk_indivisible, %{said: said}}
  def from_backend(said), do: {:prover_failed, %{said: said}}

  @doc """
  I read AL's prose back into a refusal, the way `from_backend/1` reads
  zinc+'s. AL answers a blown bound with a sentence and otherwise with
  its own tuples, which pass through untouched.
  """
  @spec from_al(term()) :: term()
  def from_al({:error, said}) when is_binary(said), do: {:error, {:heap_exhausted, %{said: said}}}
  def from_al(other), do: other

  @doc "I read `refusal` out as prose, for a human at the end of the line."
  @spec message(t()) :: String.t()
  def message({:not_an_index_relation, %{relation: name, arity: arity}}),
    do: "#{name}/#{arity} is not a relation between an index and one value"

  def message({:facts_not_consecutive, %{indices: indices}}),
    do: "an order-2 recurrence needs facts at two consecutive indices, got #{inspect(indices)}"

  def message({:fact_not_ground, %{fact: fact}}),
    do: "a base fact is a ground index and value, got #{inspect(fact)}"

  def message({:step_clauses, %{clauses: n}}), do: "#{n} step clauses; need exactly one"

  def message({:step_head_not_indexed, %{head: head}}),
    do: "the step head is an index and a value, not #{inspect(head)}"

  def message({:step_beyond_history, %{extra: vars}}),
    do: "the step combines more than the history: #{inspect(vars)}"

  def message({:step_needs_an_equation, _detail}),
    do: "the step needs one equation defining its value"

  def message({:not_order_two, %{offsets: offsets}}),
    do: "an order-2 recurrence calls itself once and twice back, got #{inspect(offsets)}"

  def message({:step_not_linear, %{term: term}}),
    do: "the step is not a linear combination of the history: #{inspect(term)}"

  def message({:precedes_base_case, %{n: n, base: base}}),
    do: "n=#{n} precedes the base case index #{base}"

  def message({:arguments_exceed_rows, %{args: args, rows: rows}}),
    do: "#{args} arguments for a relation of #{rows} rows"

  def message({:free_index_needs_a_bound, _detail}),
    do: "a free index has no last answer; say :upto how far to look"

  def message({:no_relations, _detail}),
    do: "the statement carries no relations; supply its witness instead"

  def message({:raw_predicate_has_no_clauses, _detail}),
    do: "a raw predicate has no clauses to run; write it as relations"

  def message({:calls_between_relations, _detail}),
    do: "not yet: calls between relations derive through the core path"

  def message({:unbound_variable, %{variable: name}}),
    do: "the variable #{name} is not bound by the head or a call"

  def message({:read_row_claimed, %{row: row}}),
    do:
      "row #{row} is both claimed and part of a composed read; " <>
        "the pointer query binds witness columns only"

  def message({:row_undetermined, %{cell: cell}}),
    do: "the derivation left a row free: nothing in the relation determines #{inspect(cell)}"

  def message({:unliftable_term, %{term: term}}),
    do: "no clause lowers the term #{inspect(term)}"

  def message({:head_not_a_column, %{head: head}}),
    do: "a clause head names its column with a constant or a variable, not #{inspect(head)}"

  def message({:relation_not_in_scope, %{relation: name}}),
    do: "the relation #{name} is not in scope"

  def message({:call_output_not_fresh, %{output: out}}),
    do: "a call output must be a fresh variable, got #{inspect(out)}"

  def message({:conflicting_schedule_offsets, %{row: row, offsets: offsets}}),
    do: "pointer row #{row} has conflicting schedule offsets #{inspect(offsets)}"

  def message({:read_row_outside_witness, %{row: row}}),
    do: "the composed read names row #{row} outside the witness"

  def message({:pointer_row_outside_matrix, %{row: row}}),
    do: "pointer row #{row} leaves the matrix: a composed read needs 1 <= A <= len"

  def message({:claim_outside_witness, %{claim: name, row: row, column: x}}),
    do: "claim #{inspect(name)} names cell (#{row}, #{x}) outside the witness"

  def message({:witness_value_negative, %{value: value}}),
    do: "witness value #{value} is negative; cells carry no sign"

  def message({:no_derivation, _detail}), do: "no derivation at any depth"

  def message({:no_derivation_at_count, %{count: count, relation: name}}),
    do: "nothing derives #{name} on #{count} columns"

  def message({:no_answer, %{relation: name}}),
    do: "the question found no answer: nothing derives #{name} at those values"

  def message({:residue, %{answer: answer}}),
    do: "the search answered with rows still open: #{inspect(answer)}; pin one and ask again"

  def message({:unresolved_within_budget, %{reductions: n}}),
    do: "no verdict within #{n} reductions; CLP or a bound count may reach it"

  def message({:len_needs_a_bound_count, %{}}),
    do: "len is the trace length, which only a bound count names"

  def message({:witness_invalid, %{}}),
    do: "the derived witness does not satisfy the judgement"

  def message({:witness_unsatisfies_schedule, %{column: x}}),
    do: "the witness does not satisfy the scheduled statement at column #{x}"

  def message({:value_exceeds_cell, %{value: value}}),
    do: "witness value #{value} does not fit 7040-bit cells"

  def message({:constant_exceeds_cell, %{constant: k}}),
    do: "predicate constant #{k} does not fit the program's i64 cells"

  def message({:send_failed, %{reason: reason}}), do: "the send failed: " <> clip(reason)

  def message({:prover_timeout, %{intent: id}}),
    do: "the prover did not settle intent #{id} in time"

  def message({:prover_died, _detail}), do: "the prover died before the verdict"

  # What the backend said, kept as it said it.
  def message({_reason, %{said: said}}), do: said

  @clip 120

  @spec clip(term()) :: String.t()
  defp clip(term) when is_binary(term), do: String.slice(term, 0, @clip)
  defp clip(term), do: term |> inspect(limit: 8) |> String.slice(0, @clip)
end
