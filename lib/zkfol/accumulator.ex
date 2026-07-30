defmodule Zkfol.Accumulator do
  @moduledoc """
  I am the stand-in for the pointer query of Section 4: a pipeline
  pass, riding the default route until zinc+ ships the real step,
  that makes composed reads provable today by emulating the missing
  verifier step inside the constraint language. I spell the column
  index in committed bit rows, broadcast each pointer's bits and each
  read's result across the trace, and walk an eq-weighted running sum
  whose endpoint pins the result row at every column, with a product
  pin keeping every pointer inside the matrix, so the values the
  refused path only declares become enforced constraints and the
  statement emits with no composed reads left. Statements whose
  pointers all carry schedules pass through untouched. I am throwaway
  by design: when zinc+ lands the pointer query, delete me, my
  examples, and my slot in the default pipeline.

      Zkfol.Pipeline.run(
        Zkfol.Pipeline.default(),
        %Zkfol.Statement{rels: [hop], args: [5]}
      )
  """

  @behaviour Zkfol.Pipeline

  import Bitwise

  alias Zkfol.Ast
  alias Zkfol.Interpretation
  alias Zkfol.Refusal
  alias Zkfol.Statement
  alias Zkfol.Uair.Composed
  alias Zkfol.Uair

  @typedoc "The plan's irreducible facts; every derived row is a query over these."
  @type layout :: %{
          pairs: [{pos_integer(), pos_integer()}],
          len: pos_integer(),
          arity: pos_integer()
        }

  @typedoc "Why there is no plan: nothing to expand, or nothing to look at yet."
  @type idle :: :no_dynamic_reads | :not_solved

  @doc "I am the expansion as a pass; a statement with no composed read passes through."
  @impl Zkfol.Pipeline
  @spec run(Statement.t(), keyword()) :: {:ok, Statement.t()} | {:error, Refusal.t()}
  def run(statement, _opts), do: expand(statement)

  @impl Zkfol.Pipeline
  @spec verb() :: Zkfol.Pipeline.verdict()
  def verb, do: :expands

  # I expand every pointer read into the accumulator encoding. I am a
  # try: a statement whose pointers all carry schedules, or one still
  # missing its predicate or witness, passes through untouched. The
  # expanded statement emits through `Zkfol.Uair` with
  # `composed_reads: []`, so the prover boundary has nothing to refuse.
  @spec expand(Statement.t()) :: {:ok, Statement.t()} | {:error, Refusal.t()}
  defp expand(%Statement{stage: %Statement.Solved{pred: pred, witness: witness}} = statement) do
    with {:ok, plan} <- planned(pred, witness) do
      case plan do
        :no_dynamic_reads ->
          {:ok, statement}

        plan ->
          {:ok,
           %Statement{
             statement
             | stage: %Statement.Solved{
                 pred: build(pred, plan),
                 witness: extend(witness, plan)
               }
           }}
      end
    end
  end

  # Only a solved statement has both a predicate to expand and a witness to
  # extend; anything earlier passes through untouched.
  defp expand(%Statement{stage: stage} = statement)
       when stage == :raw or is_struct(stage, Statement.Lowered),
       do: {:ok, statement}

  @doc """
  I am the row plan the expansion follows, on the statement as it
  stands before the pass. Two states are not a plan and are not the
  same: `:no_dynamic_reads` means I looked and every pointer already
  carries a schedule, `:not_solved` means there is nothing to look at
  yet. The examples read row counts and tamper targets through my
  queries.
  """
  @spec layout(Statement.t()) :: {:ok, layout() | idle()} | {:error, Refusal.t()}
  def layout(%Statement{stage: %Statement.Solved{pred: pred, witness: witness}}),
    do: planned(pred, witness)

  def layout(%Statement{stage: stage})
      when stage == :raw or is_struct(stage, Statement.Lowered),
      do: {:ok, :not_solved}

  # The bit width shared by the index and every pointer.
  @spec mu(layout()) :: pos_integer()
  defp mu(plan), do: Uair.num_vars(plan.len)

  # The distinct pointer rows, in allocation order.
  @spec pointers(layout()) :: [pos_integer()]
  defp pointers(plan), do: plan.pairs |> Enum.map(&elem(&1, 1)) |> Enum.uniq() |> Enum.sort()

  @typep descriptor ::
           {:index_bit, pos_integer()}
           | :prev
           | {:pointer_bit, pos_integer(), pos_integer()}
           | {:result, {pos_integer(), pos_integer()}}
           | {:broadcast, pos_integer(), pos_integer(), pos_integer()}
           | {:acc | :readout, pos_integer(), pos_integer(), pos_integer()}

  # The one allocation order: every derived row named once, in place.
  # Row numbers and witness values are both read off this list, so the
  # constraints and the extension cannot drift apart.
  @spec derived(layout()) :: [descriptor()]
  defp derived(plan) do
    mu = mu(plan)

    for(nu <- 1..mu, do: {:index_bit, nu}) ++
      [:prev] ++
      for(a <- pointers(plan), nu <- 1..mu, do: {:pointer_bit, a, nu}) ++
      for(pair <- plan.pairs, do: {:result, pair}) ++
      for(x0 <- 1..plan.len, a <- pointers(plan), nu <- 1..mu, do: {:broadcast, a, x0, nu}) ++
      for(x0 <- 1..plan.len, {i, a} <- plan.pairs, kind <- [:acc, :readout], do: {kind, i, a, x0})
  end

  # A derived row's number: its place in the order, past the witness.
  @spec row(layout(), descriptor()) :: pos_integer()
  defp row(plan, descriptor),
    do: plan.arity + 1 + Enum.find_index(derived(plan), &(&1 == descriptor))

  @doc "I am the committed index bit rows, low bit first."
  @spec index_bits(layout()) :: [pos_integer()]
  def index_bits(plan), do: for(nu <- 1..mu(plan), do: row(plan, {:index_bit, nu}))

  # The row carrying each column's predecessor.
  @spec prev(layout()) :: pos_integer()
  defp prev(plan), do: row(plan, :prev)

  # Pointer `a`'s committed bit rows.
  @spec pointer_bits(layout(), pos_integer()) :: [pos_integer()]
  defp pointer_bits(plan, a), do: for(nu <- 1..mu(plan), do: row(plan, {:pointer_bit, a, nu}))

  @doc "I am the derived result row of the read `{i, a}`."
  @spec result(layout(), {pos_integer(), pos_integer()}) :: pos_integer()
  def result(plan, pair), do: row(plan, {:result, pair})

  # The rows broadcasting pointer `a`'s bits for column `x0`.
  @spec broadcast(layout(), pos_integer(), pos_integer()) :: [pos_integer()]
  defp broadcast(plan, a, x0), do: for(nu <- 1..mu(plan), do: row(plan, {:broadcast, a, x0, nu}))

  @doc "I am the accumulator and readout rows of the read `{i, a}` at column `x0`."
  @spec sum(layout(), pos_integer(), pos_integer(), pos_integer()) ::
          {pos_integer(), pos_integer()}
  def sum(plan, i, a, x0), do: {row(plan, {:acc, i, a, x0}), row(plan, {:readout, i, a, x0})}

  # The plan behind expand and layout.
  @spec planned(Ast.pred(), Interpretation.t()) ::
          {:ok, layout() | idle()} | {:error, Refusal.t()}
  defp planned(pred, witness) do
    # One dynamic pointer sends every read down: the wrap hides the
    # affine shapes from emit, so scheduled reads ride along.
    len = Interpretation.len(witness)
    plan = %{pairs: Ast.pointer_derefs(pred), len: len, arity: Interpretation.arity(witness)}
    mu = mu(plan)

    with {:ok, schedules} <- Ast.schedules(pred) do
      cond do
        Enum.all?(pointers(plan), &is_map_key(schedules, &1)) ->
          {:ok, :no_dynamic_reads}

        len >= 1 <<< mu ->
          {:error, {:len_exceeds_index_bits, %{len: len, bits: mu}}}

        true ->
          with :ok <- Composed.admits(plan.pairs, witness), do: {:ok, plan}
      end
    end
  end

  # The expanded predicate: two branches, the shared constraints in
  # both, every shifted read confined to the step branch where the
  # zero-padded shift tail never applies.
  @spec build(Ast.pred(), layout()) :: Ast.pred()
  defp build(pred, plan) do
    common = [rewrite(pred, plan) | shared(plan)]
    guard = Ast.eq(selector(1, index_bits(plan)), 1)
    binding = Ast.eq(Ast.cell(prev(plan)), Ast.add(Ast.x(), -1))

    Ast.disj([
      Ast.conj([guard | common]),
      Ast.conj([binding | stepwise(plan) ++ common])
    ])
  end

  # Each composed cell becomes a plain read of its result row.
  @spec rewrite(Ast.pred(), layout()) :: Ast.pred()
  defp rewrite(pred, plan) do
    Ast.postwalk(pred, fn
      {:cell, i, j} -> Ast.cell(result(plan, {i, j}))
      node -> node
    end)
  end

  # The constraints alive at every trace step, padding included.
  @spec shared(layout()) :: [Ast.pred()]
  defp shared(plan) do
    Composed.spelled(index_bits(plan), Ast.x()) ++
      Enum.flat_map(pointers(plan), fn a ->
        Composed.spelled(pointer_bits(plan, a), Ast.cell(a)) ++ [in_matrix(a, plan.len)]
      end) ++
      Enum.flat_map(sites(plan), fn {a, x0} -> pinned(plan, a, x0) end) ++
      Enum.flat_map(instances(plan), fn {i, a, x0} -> summed(plan, i, a, x0) end)
  end

  # The constraints alive only on the step branch: everything reading
  # through prev, off at column 1 and at the padding steps.
  @spec stepwise(layout()) :: [Ast.pred()]
  defp stepwise(plan) do
    constancy =
      Enum.flat_map(sites(plan), fn {a, x0} ->
        for bb <- broadcast(plan, a, x0), do: Ast.eq(Ast.cell(bb), Ast.cell(bb, prev(plan)))
      end)

    recurrences =
      Enum.flat_map(instances(plan), fn {i, a, x0} ->
        {acc, rb} = sum(plan, i, a, x0)
        step = Ast.mul(eqt(plan, a, x0), Ast.cell(i))

        [
          Ast.eq(Ast.cell(rb), Ast.cell(rb, prev(plan))),
          Ast.eq(Ast.cell(acc), Ast.add(Ast.cell(acc, prev(plan)), step))
        ]
      end)

    constancy ++ recurrences
  end

  @spec sites(layout()) :: [{pos_integer(), pos_integer()}]
  defp sites(plan), do: for(a <- pointers(plan), x0 <- 1..plan.len, do: {a, x0})

  @spec instances(layout()) :: [{pos_integer(), pos_integer(), pos_integer()}]
  defp instances(plan), do: for({i, a} <- plan.pairs, x0 <- 1..plan.len, do: {i, a, x0})

  # The product pin closing the bit range down to the matrix: it stands
  # in for the Word lookup, which the expanded uair no longer declares.
  @spec in_matrix(pos_integer(), pos_integer()) :: Ast.pred()
  defp in_matrix(a, len) do
    product =
      1..len
      |> Enum.map(&Ast.add(Ast.cell(a), -&1))
      |> Enum.reduce(&Ast.mul(&2, &1))

    Ast.eq(product, 0)
  end

  # The broadcast rows equal the pointer's bits at their column.
  @spec pinned(layout(), pos_integer(), pos_integer()) :: [Ast.pred()]
  defp pinned(plan, a, x0) do
    sel = selector(x0, index_bits(plan))

    Enum.zip(broadcast(plan, a, x0), pointer_bits(plan, a))
    |> Enum.map(fn {bb, ab} ->
      Ast.eq(Ast.mul(sel, Ast.cell(bb)), Ast.mul(sel, Ast.cell(ab)))
    end)
  end

  # The accumulator pins: anchored at column 1, read out at len into
  # the broadcast result, which the read's column equates to the result row.
  @spec summed(layout(), pos_integer(), pos_integer(), pos_integer()) :: [Ast.pred()]
  defp summed(plan, i, a, x0) do
    {acc, rb} = sum(plan, i, a, x0)
    sel1 = selector(1, index_bits(plan))
    sel0 = selector(x0, index_bits(plan))
    sell = selector(plan.len, index_bits(plan))
    first = Ast.mul(eqt(plan, a, x0), Ast.cell(i))

    [
      Ast.eq(Ast.mul(sel1, Ast.cell(acc)), Ast.mul(sel1, first)),
      Ast.eq(Ast.mul(sel0, Ast.cell(rb)), Ast.mul(sel0, Ast.cell(result(plan, {i, a})))),
      Ast.eq(Ast.mul(sell, Ast.cell(acc)), Ast.mul(sell, Ast.cell(rb)))
    ]
  end

  # eq-tilde inline: the full product of agreeing factors.
  @spec eqt(layout(), pos_integer(), pos_integer()) :: Ast.term_t()
  defp eqt(plan, a, x0), do: Enum.reduce(eq_factors(plan, a, x0), &Ast.mul(&2, &1))

  # The factors of eq-tilde: broadcast bit against index bit, agreeing.
  @spec eq_factors(layout(), pos_integer(), pos_integer()) :: [Ast.term_t()]
  defp eq_factors(plan, a, x0) do
    Enum.zip(broadcast(plan, a, x0), index_bits(plan))
    |> Enum.map(fn {bb, xb} ->
      Ast.add(
        Ast.mul(Ast.cell(bb), Ast.cell(xb)),
        Ast.mul(off(Ast.cell(bb)), off(Ast.cell(xb)))
      )
    end)
  end

  # The bit-selector of column x0: 1 exactly there, on honest index bits.
  @spec selector(pos_integer(), [pos_integer()]) :: Ast.term_t()
  defp selector(x0, index_bits) do
    index_bits
    |> Enum.with_index()
    |> Enum.map(fn {b, nu} ->
      if (x0 >>> nu &&& 1) == 1, do: Ast.cell(b), else: off(Ast.cell(b))
    end)
    |> Enum.reduce(&Ast.mul(&2, &1))
  end

  # 1 - t, canonically.
  @spec off(Ast.term_t()) :: Ast.term_t()
  defp off(t), do: Ast.add(1, Ast.mul(t, -1))

  # The honest values of every derived row, read off the one order.
  @spec extend(Interpretation.t(), layout()) :: Interpretation.t()
  defp extend(witness, plan) do
    at = &Interpretation.at(witness, &1, &2)
    rows = for d <- derived(plan), do: for(y <- 1..plan.len, do: value(d, y, at))
    Interpretation.new(Interpretation.rows(witness) ++ rows)
  end

  # A derived row's honest value at column y.
  @spec value(descriptor(), pos_integer(), (pos_integer(), pos_integer() -> integer())) ::
          integer()
  defp value({:index_bit, nu}, y, _at), do: y >>> (nu - 1) &&& 1
  defp value(:prev, y, _at), do: max(y - 1, 1)
  defp value({:pointer_bit, a, nu}, y, at), do: at.(a, y) >>> (nu - 1) &&& 1
  defp value({:result, {i, a}}, y, at), do: at.(i, at.(a, y))
  defp value({:broadcast, a, x0, nu}, _y, at), do: at.(a, x0) >>> (nu - 1) &&& 1
  defp value({:readout, i, a, x0}, _y, at), do: at.(i, at.(a, x0))

  defp value({:acc, i, a, x0}, y, at) do
    target = at.(a, x0)
    if y >= target, do: at.(i, target), else: 0
  end
end
