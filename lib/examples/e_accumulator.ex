defmodule Examples.EAccumulator do
  @moduledoc """
  I am the accumulator fallback's evidence: the default route expands
  hop's composed reads into rows the pinned zinc+ proves today, a
  tampered result row and the coordinated index forge are both refused
  by the constraints rather than the oracle, and an unexpanded uair
  still refuses at the prover's door. I die with `Zkfol.Accumulator`
  when zinc+ ships the pointer query.
  """

  use ExExample

  import ExUnit.Assertions

  alias Examples.EAl
  alias Zkfol.Accumulator
  alias Zkfol.Refusal
  alias Zkfol.Pipeline
  alias Zkfol.Prover
  alias Zkfol.Statement
  alias Zkfol.Uair

  # The statement at the accumulator's door: lowered, solved, unexpanded.
  @spec hop_at_the_door() :: Statement.t()
  example hop_at_the_door do
    {:ok, %{pred: pred}} = Zkfol.Lang.compile(EAl.hop_rel(), [EAl.hop_rel()])

    %Statement{
      rels: [EAl.hop_rel()],
      args: [5],
      stage: %Statement.Solved{
        pred: pred,
        witness: EAl.value_targets_go_straight_down()
      }
    }
  end

  # The default route carries hop to the expansion: the doubling try
  # declines, the witness derives, the accumulator rewrites.
  @spec expanded_hop() :: Statement.t()
  example expanded_hop do
    {:ok, statement, trace} =
      Pipeline.run(Pipeline.default(), %Statement{rels: [EAl.hop_rel()], args: [5]})

    assert [
             {Zkfol.Lang, lowered},
             {Zkfol.Doubling, lowered},
             {Zkfol.Witness, solved},
             {Accumulator, expanded}
           ] = trace

    assert statement == expanded
    assert Statement.pred(expanded) != Statement.pred(solved)
    statement
  end

  # The expanded shape, counted by row kind: mu index bits and prev
  # shared, mu bits per pointer, a result per read, then per column
  # mu broadcasts per pointer and two sum rows per read.
  # Every witness row is referenced, none public: row r is column r - 1.
  # X rides next, then the ones column the index pin adds to hold X to
  # the true column number.
  @spec expanded_hop_emits() :: Uair.t()
  example expanded_hop_emits do
    statement = expanded_hop()
    {:ok, uair} = Uair.emit(Statement.pred(statement), Statement.witness(statement))

    assert %Zkfol.Uair.Plain{} = uair.mode
    assert Zkfol.Uair.num_cols(uair) == 49
    # One forward shift per broadcast, accumulator, and readout row, plus
    # the three the index pin rides: X and ones by one, ones by the head.
    assert length(uair.shifts) == 38
    assert Enum.count(uair.shifts, &match?({_col, 1}, &1)) == 37
    uair
  end

  @spec hop_proves_end_to_end() :: Prover.Report.t()
  example hop_proves_end_to_end do
    {:ok, report, _id} =
      Prover.prove_uair(expanded_hop_emits(), name: "hop, accumulator fallback")

    assert %Prover.Report{} = report
    report
  end

  # The whole point: the result row is enforced, so a lie in R at one
  # column dies in the prover, not in the oracle.
  @spec tampered_result_is_rejected() :: Refusal.t()
  example tampered_result_is_rejected do
    uair = expanded_hop_emits()
    {:ok, plan} = Accumulator.layout(hop_at_the_door())
    column = Accumulator.result(plan, {2, 3}) - 1

    tampered =
      %{uair | columns: List.update_at(uair.columns, column, &List.replace_at(&1, 2, 99))}

    {:error, reason} = Prover.prove_uair(tampered)
    assert {:verifier_rejected, _} = reason
    reason
  end

  # SEV-1, closed: X was a free committed column, so a coordinated
  # witness could flatten it to column one, vacate the running-sum
  # readout, and swap a lie into a base-case result row the affine
  # constraints never reach. Before the index pin this forge proved and
  # verified; the pin now holds X to the true column, so the same
  # witness is refused at the prover.
  @spec coordinated_forge_is_rejected() :: Refusal.t()
  example coordinated_forge_is_rejected do
    uair = expanded_hop_emits()
    {:ok, plan} = Accumulator.layout(hop_at_the_door())
    rows = length(hd(uair.columns))
    cell = fn i -> Enum.at(uair.columns, i - 1) end
    at = fn row -> row - 1 end

    # Flatten X to column one everywhere, its bits reading one then zero.
    [b0, b1, b2] = Accumulator.index_bits(plan)

    # A lie in the base-case result: honest is one, so column one and its
    # padding (from the reversed column len - 1 on) carry it.
    lie = for r <- 0..(rows - 1), do: if(r >= plan.len - 1, do: 99, else: 1)
    {_sink, readout} = Accumulator.sum(plan, 2, 3, 1)

    forged =
      [
        {Zkfol.Uair.num_cols(uair) - 2, List.duplicate(1, rows)},
        {at.(b0), List.duplicate(1, rows)},
        {at.(b1), List.duplicate(0, rows)},
        {at.(b2), List.duplicate(0, rows)},
        {at.(Accumulator.result(plan, {2, 3})), lie},
        {at.(readout), lie}
      ]
      |> Enum.reduce(uair.columns, fn {col, values}, cols ->
        List.replace_at(cols, col, values)
      end)

    # Every accumulator row rides at its single term, so only the readout
    # the pin restores could catch the lie: rebuild them to that shape.
    forged =
      for {i, a} <- plan.pairs, x0 <- 1..plan.len, reduce: forged do
        cols ->
          {acc, _readout} = Accumulator.sum(plan, i, a, x0)
          List.replace_at(cols, at.(acc), cell.(i))
      end

    {:error, reason} = Prover.prove_uair(%{uair | columns: forged})
    assert {:verifier_rejected, _} = reason
    reason
  end

  # The guard at the prover boundary stands: a uair still declaring
  # composed reads never reaches the NIF, expansion or no expansion.
  @spec the_boundary_still_refuses() :: Refusal.t()
  example the_boundary_still_refuses do
    reason = EAl.composed_read_awaits_zinc()

    assert {:composed_read_awaits_backend, _} = reason
    reason
  end
end
