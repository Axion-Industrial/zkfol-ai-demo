defmodule Examples.EAl do
  @moduledoc """
  I am the statement running as clauses: the derivation is the
  witness, resending replaces rather than stacks, and a row nothing
  determines refuses by name. The value-addressed hop also emits here
  by Section 4, bits and result row on the trace, and zinc+'s pointer
  query proves its reads natively.
  """

  use ExExample
  use Zkfol.Lang

  import ExUnit.Assertions

  alias Examples.EDoubling
  alias Examples.EUser
  alias Zkfol.Al
  alias Zkfol.Statement
  alias Zkfol.Refusal
  alias Zkfol.Interpretation
  alias Zkfol.Prover
  alias Zkfol.Uair
  alias Zkfol.ZincPlus

  defrel pick(x, v) do
    tab(3, w)
    v = w + 1
  end

  defrel tab(1, 10)
  defrel tab(2, 20)
  defrel tab(3, 40)
  defrel tab(4, 40)

  @spec registers_program() :: Al.program()
  example registers_program do
    {:ok, program} = Al.question(Examples.EUser.regs())

    # The class row, the retraction, one clause per clause: facts first.
    assert [%AL.Goal.SetClass{}, %AL.Goal.Forall{}, base, step] = program
    assert %AL.Goal.OApply{method_id: :defmethod, args: [:zkfol, :regs, _head, [_ | _]]} = step
    assert %AL.Goal.OApply{method_id: :defmethod, args: [:zkfol, :regs, _head, []]} = base
    program
  end

  defrel odd(1, 1)

  defrel odd(x, v) do
    x > 1
    even(x - 1, v)
  end

  defrel even(1, 0)

  defrel even(x, v) do
    x > 1
    odd(x - 1, v)
  end

  defrel named_odd(1, 1)

  defrel named_odd(x, v) do
    x > 1
    named_even(x - 1, w)
    v = w
  end

  defrel named_even(1, 0)

  defrel named_even(x, v) do
    x > 1
    named_odd(x - 1, w)
    v = w
  end

  defrel pairs(1, 3, 5)
  defrel pairs(2, 4, 4)

  defrel twinned(x, v) do
    pairs(x, v, v)
  end

  defrel mate(x, v) do
    pairs(x, 3, v)
  end

  defrel loose(x) do
    pairs(x, _, _)
  end

  defrel step(1, 2)
  defrel step(2, 3)
  defrel step(3, 1)

  defrel leap(x, v) do
    step(2, k)
    step(k, w)
    v = w
  end

  @doc "I solve one relation both ways, one answer being the other's question."
  @spec fib_solves_both_ways() :: Interpretation.t()
  example fib_solves_both_ways do
    n = 12
    branch = AL.Branch.fork()
    {:ok, forward} = Al.solve(EUser.fib(), [n], branch: branch.id)
    value = Interpretation.at(forward, 2, Interpretation.len(forward))

    {:ok, backward} = Al.solve(EUser.fib(), [:_, value], branch: branch.id)
    AL.Branch.discard(branch)

    assert Interpretation.len(backward) == n
    assert backward == forward
    backward
  end

  @doc "I name the rows I want back, and a finite ask answers whole, either way around."
  @spec every_answer_is_named() :: [%{atom() => integer()}]
  example every_answer_is_named do
    {:ok, answers} = Al.apply(tab(), [:n, :a])

    assert [%{n: 1, a: 10}, %{n: 2, a: 20}, %{n: 3, a: 40}, %{n: 4, a: 40}] =
             Enum.sort_by(answers, & &1.n)

    {:ok, backward} = Al.apply(tab(), [:a, 40])
    assert Enum.sort_by(backward, & &1.a) == [%{a: 3}, %{a: 4}]
    answers
  end

  @doc "I pick an answer and derive it, since bindings alone do not prove."
  @spec an_answer_derives_when_chosen() :: Interpretation.t()
  example an_answer_derives_when_chosen do
    # findall backtracks, so each answer's trace is gone with it. The
    # bindings say which derivation to want; solve/3 rebuilds it whole.
    {:ok, [%{a: a}]} = Al.apply(EUser.fib(), [8, :a])

    {:ok, witness} = Al.solve(EUser.fib(), [8, a])

    assert Interpretation.len(witness) == 8
    assert Interpretation.at(witness, 2, 8) == a
    witness
  end

  @spec resending_replaces_declarations() :: Interpretation.t()
  example resending_replaces_declarations do
    branch = AL.Branch.fork()
    {:ok, first} = Al.solve(Examples.EUser.regs(), [8], branch: branch.id)
    {:ok, second} = Al.solve(Examples.EUser.regs(), [8], branch: branch.id)
    AL.Branch.discard(branch)

    assert first == second
    second
  end

  @spec al_descends_the_kernel() :: Interpretation.t()
  example al_descends_the_kernel do
    n = 50_000
    statement = EDoubling.rewritten_fibonacci()

    # kernel(x, u, w, e, r): e is row four, at n - 2 since the kernel
    # claims F(e + 2). Bits and depth arrive by descent, not from the
    # caller, and the result row stays free.
    {:ok, witness} = Al.solve(statement, [:_, :_, :_, n - 2])

    # kernel(x, u, w, e, r): e walks in row 4, the result rides row 5.
    last = Interpretation.len(witness)
    assert Interpretation.at(witness, 4, last) == n - 2
    assert Interpretation.at(witness, 5, last) == EUser.fib(n)
    witness
  end

  @doc "I bind nothing, spelled two ways, so the first count answers."
  @spec no_arguments_lands_on_the_first_count() :: Interpretation.t()
  example no_arguments_lands_on_the_first_count do
    {:ok, witness} = Al.solve(EUser.fib(), [])

    assert {:ok, ^witness} = Al.solve(EUser.fib(), [:_, :_])
    assert Interpretation.len(witness) == 1
    witness
  end

  # Forty columns of unguided doubling squares its cells past any
  # machine; the bound turns the blowup into a named refusal.
  @spec runaway_growth_is_refused() :: Refusal.t()
  example runaway_growth_is_refused do
    kernel = EDoubling.rewritten_fibonacci().rels |> hd()
    {:error, reason} = Al.solve(kernel, [40], heap: 200_000)

    assert {:heap_exhausted, _} = reason
    reason
  end

  # The direct path: clauses to clauses, no core in between; the core
  # projection derives the same witness, which is the parity net.
  @spec clauses_go_straight_down() :: Interpretation.t()
  example clauses_go_straight_down do
    {:ok, direct} = Al.solve(EUser.fib(), [8])

    assert direct == Statement.witness(EUser.fibonacci(8))
    direct
  end

  # Outside doubling's class, inside the direct path's: order one,
  # a coefficient that is the column itself. The derivation bottoms at
  # the fact it reached, so the trace starts there: no column below
  # the base the derivation consumed.
  @spec factorial_goes_straight_down() :: Interpretation.t()
  example factorial_goes_straight_down do
    {:ok, witness} = Al.solve(Examples.EFacts.factorial(), [5])

    assert witness |> Interpretation.rows() |> Enum.at(1) == [2, 6, 24, 120]
    witness
  end

  # reify and len in clauses: the flag is the squared gap to the end.
  @spec reify_and_len_go_straight_down() :: Interpretation.t()
  example reify_and_len_go_straight_down do
    gap =
      rel :gap do
        gap(1, v) do
          v = reify(1 = len)
        end

        gap(x, v) do
          x > 1
          gap(x - 1, _w)
          v = reify(x = len)
        end
      end

    {:ok, direct} = Al.solve(gap, [5])
    assert direct |> Interpretation.rows() |> Enum.at(1) == [16, 9, 4, 1, 0]
    direct
  end

  @doc "I negate in a clause: one node, the term times -1."
  @spec negation_goes_straight_down() :: Interpretation.t()
  example negation_goes_straight_down do
    flip =
      rel :flip do
        flip(1, 0)

        flip(x, v) do
          flip(x - 1, w)
          v = -w + 1
        end
      end

    {:ok, direct} = Al.solve(flip, [5])
    assert direct |> Interpretation.rows() |> Enum.at(1) == [0, 1, 0, 1, 0]
    direct
  end

  # A value aims the pointer: the call reads the column another row names.
  @spec hop_rel() :: Zkfol.Lang.Rel.t()
  example hop_rel do
    rel :hop do
      hop(1, 1)

      hop(x, v) do
        x > 0
        hop(v - 1, w)
        v = w + 1
      end
    end
  end

  # The derivation consumes two facts, so the witness is two columns:
  # position is identity, and the count is nobody's argument.
  @spec value_targets_go_straight_down() :: Interpretation.t()
  example value_targets_go_straight_down do
    {:ok, witness} = Al.solve(hop_rel(), [5])
    assert witness |> Interpretation.rows() |> Enum.take(2) == [[1, 5], [1, 2]]
    witness
  end

  # An offset row takes a row number without taking a trace slot, so a
  # relation holding both an affine call and a computed one is the only
  # shape where naming the head by count and naming the pins by row
  # disagree. Here the head must reach c5, past the four slots it has.
  @spec offsets_and_pointers_share_one_head() :: Interpretation.t()
  example offsets_and_pointers_share_one_head do
    mixed =
      rel :mixed do
        mixed(1, 1, 1)

        mixed(x, v, w) do
          x > 1
          mixed(x - 1, a, _b)
          mixed(v - 1, _c, d)
          v = a + 1
          w = d
        end
      end

    {:ok, witness} = Al.solve(mixed, [5])

    # v climbs by one, and w reads it back through the computed pointer.
    assert [_index, v, w | _derived] = Interpretation.rows(witness)
    assert v == [1, 2, 3, 4, 5]
    assert w == [1, 1, 1, 1, 1]
    witness
  end

  # Section 4 on the wire: the dynamic deref emits bit rows that are
  # bits, a reconstruction the columns corroborate, a result row per
  # read, and the Word lookup, all judged by the oracle inside emit.
  @spec composed_hop_emits() :: Uair.t()
  example composed_hop_emits do
    {:ok, pred} = Zkfol.Lang.lower(hop_rel(), [hop_rel()])
    witness = value_targets_go_straight_down()
    {:ok, uair} = Uair.emit(pred, witness)
    len = Interpretation.len(witness)

    assert [%{row: pointer, table: {:word, _mu}}] = uair.mode.lookups
    assert [%{value_row: 0, bit_rows: bits, result_row: _r1}, second] = uair.mode.reads
    assert %{value_row: 1, bit_rows: ^bits, result_row: _r2} = second

    bit_columns = for b <- bits, do: Enum.at(uair.columns, b)
    assert bit_columns |> List.flatten() |> Enum.all?(&(&1 in [0, 1]))

    weighted =
      Enum.zip_with(bit_columns, fn cells ->
        cells |> Enum.with_index() |> Enum.map(fn {b, i} -> b * 2 ** i end) |> Enum.sum()
      end)

    # The bits spell the cube index of the address, len - a(x), so the
    # reversed committed layout reads directly.
    assert weighted == Enum.map(Enum.at(uair.columns, pointer), &(len - &1))

    # Each result row reads its value row at the spelled position.
    for %{value_row: v, result_row: r} <- uair.mode.reads do
      value = Enum.at(uair.columns, v)
      assert Enum.at(uair.columns, r) == Enum.map(weighted, &Enum.at(value, &1))
    end

    assert uair.shifts == []
    uair
  end

  # Section 4 all the way down: the emitted composed reads prove on
  # zinc+'s pointer query, no emulation in between.
  @spec composed_hop_proves() :: Zkfol.Prover.Report.t()
  example composed_hop_proves do
    {:ok, report, _id} = Prover.prove_uair(composed_hop_emits(), name: :composed_hop)

    assert %Zkfol.Prover.Report{} = report
    report
  end

  # A claim makes its row public, and the pointer query binds witness
  # columns only: the overlap refuses by name at the prover's door.
  @spec claimed_read_row_is_refused() :: Refusal.t()
  example claimed_read_row_is_refused do
    {:ok, pred} = Zkfol.Lang.lower(hop_rel(), [hop_rel()])
    witness = value_targets_go_straight_down()
    {:ok, uair} = Uair.emit(pred, witness, [{"out", 2, 2}])

    {:error, reason} = ZincPlus.request(uair)
    assert {:read_row_claimed, _} = reason
    reason
  end

  # Class 1 pays no toll: an affine schedule still lowers to shifts
  # alone, with no bit rows, no lookup, and no composed read.
  @spec scheduled_pointers_skip_the_bits() :: Uair.t()
  example scheduled_pointers_skip_the_bits do
    {:ok, uair} =
      Uair.emit(Statement.pred(EUser.registers()), Statement.witness(EUser.registers()))

    assert %Zkfol.Uair.Plain{} = uair.mode
    assert uair.shifts != []
    uair
  end

  @doc "I bound a step from both ends, and past the top it derives nothing."
  @spec a_guard_bounds_from_either_end() :: Zkfol.Lang.Rel.t()
  example a_guard_bounds_from_either_end do
    band =
      rel :band do
        band(1, 1)

        band(x, v) do
          x > 1
          x <= 5
          band(x - 1, w)
          v = w + 1
        end
      end

    {:ok, witness} = Al.solve(band, [5])
    assert witness |> Interpretation.rows() |> Enum.at(1) == [1, 2, 3, 4, 5]

    assert {:error, _past_the_top} = Al.solve(band, [9])
    band
  end

  defrel capped(x, v) do
    x < 4
    v = x + 1
  end

  @doc """
  I hold a guard nothing structural implies: `x < 4` reaches the
  predicate as the room it leaves, and a cell claiming other room is
  no witness.
  """
  @spec a_guard_binds_its_slack() :: Interpretation.t()
  example a_guard_binds_its_slack do
    {:ok, shape} = Zkfol.Lang.compile(capped())
    alloc = Zkfol.Alloc.assign(shape)

    assert shape.slack == 1
    assert Enum.to_list(Zkfol.Alloc.rows(alloc, :slack)) == [3]

    {:ok, pred} = Zkfol.Lang.lower(capped(), [capped()])
    {:ok, witness} = Al.solve(capped(), [2])

    assert Interpretation.rows(witness) == [[2], [3], [1]]
    assert Zkfol.Semantics.valid?(pred, witness)

    refute Zkfol.Semantics.valid?(pred, Interpretation.new([[2], [3], [0]]))
    witness
  end

  defrel forked(1, 0)

  defrel forked(x, v) do
    x > 1
    forked(x - 1, w)
    v = w + 1
    v < 100
  end

  defrel forked(x, v) do
    x > 1
    forked(x - 1, w)
    v = w + 10
    v < 1000
  end

  @doc """
  I differ between my two step clauses only in what their bodies
  equate: both heads admit the same tuple and both call once, so
  nothing about the fact says which ran. The room the column carries
  is the second clause's because the journal names the clause the
  derivation committed to.
  """
  @spec the_fired_clause_is_named_by_the_journal() :: Interpretation.t()
  example the_fired_clause_is_named_by_the_journal do
    {:ok, pred} = Zkfol.Lang.lower(forked(), [forked()])
    {:ok, witness} = Al.solve(forked(), [2, 10])

    assert Interpretation.rows(witness) == [[1, 2], [0, 10], [1, 1], [0, 0], [0, 989]]
    assert Zkfol.Semantics.valid?(pred, witness)
    witness
  end

  defrel regsm(1, 1, 1)

  defrel regsm(x, a, c) do
    x > 1
    regsm(x - 1, b, a)
    c = mod(a + b, 7919)
  end

  # The same reduction spelled out, the quotient smuggled through the
  # head because a hand cannot freshen a row.
  defrel regsh(1, 1, 1, 0)

  defrel regsh(x, a, b, q) do
    x > 1
    regsh(x - 1, a1, b1, q1)
    a1 + b1 = q * 7919 + a
    a < 7919
    a + 1 > 0
    q + 1 > 0
    b = a1
  end

  @doc """
  I recur under a modulus: the head is three wide, the quotient
  nowhere in it, and the value at each column is the fibonacci number
  reduced. Two reduced summands cross the modulus at most once, so
  the quotient bank the compiler opened is a bit.
  """
  @spec a_mod_relation_reduces(pos_integer()) :: Interpretation.t()
  example a_mod_relation_reduces(n \\ 25) do
    {:ok, shape} = Zkfol.Lang.compile(regsm())
    alloc = Zkfol.Alloc.assign(shape)

    assert shape.quot == 1
    assert Enum.to_list(Zkfol.Alloc.rows(alloc, :quot)) == [7]

    {:ok, witness} = Al.solve(regsm(), [n])

    assert Interpretation.at(witness, 3, n) == rem(EUser.fib(n + 1), 7919)

    [quotients] = Interpretation.rows(Zkfol.Alloc.region(witness, alloc, :quot))
    assert quotients |> Enum.uniq() |> Enum.sort() == [0, 1]

    witness
  end

  @doc """
  I am one derivation reached two ways: `mod` as sugar, and spelled
  out by hand. Every row the sugar stands on the hand also has: its
  quotient bank holds what the hand's head row held. The hand pays two
  slack columns more, for the signs the sugar never asks the predicate
  to carry.
  """
  @spec the_sugar_and_the_hand_agree(pos_integer()) :: Interpretation.t()
  example the_sugar_and_the_hand_agree(n \\ 25) do
    {:ok, sugar} = Zkfol.Lang.compile(regsm())
    {:ok, spelled} = Zkfol.Lang.compile(regsh())

    {:ok, sugared} = Al.solve(regsm(), [n])
    {:ok, by_hand} = Al.solve(regsh(), [n])

    bank = fn witness, shape, sym ->
      Interpretation.rows(Zkfol.Alloc.region(witness, Zkfol.Alloc.assign(shape), sym))
    end

    head = bank.(by_hand, spelled, :regsh)

    # The sugar names its head (x, a, c) with the sum last; the hand
    # wrote (x, sum, prev, q), so the value rows cross.
    assert bank.(sugared, sugar, :regsm) ==
             [Enum.at(head, 0), Enum.at(head, 2), Enum.at(head, 1)]

    assert bank.(sugared, sugar, :quot) == Enum.drop(head, 3)
    assert bank.(sugared, sugar, :ptr) == bank.(by_hand, spelled, :ptr)
    assert bank.(sugared, sugar, :slack) == Enum.take(bank.(by_hand, spelled, :slack), 2)
    assert spelled.slack - sugar.slack == 2

    sugared
  end

  @doc "I prove a reduction on zinc+ through the front door."
  @spec a_mod_relation_proves(pos_integer()) :: Zkfol.Log.Ran.t()
  example a_mod_relation_proves(n \\ 25) do
    ran =
      Zkfol.compile(%Statement{rels: [regsm()], args: [n]},
        pipeline: EUser.plain(),
        name: :registers_mod
      )

    assert %Prover.Report{} = Zkfol.Log.report(Zkfol.Log.snapshot(), ran)
    ran
  end

  defrel shifty(m, x, v) do
    v = mod(x, m)
  end

  @doc """
  I refuse a modulus the clause does not know: m times the quotient is
  a product of two unknowns, which nothing here can suspend.
  """
  @spec a_variable_modulus_is_refused() :: Refusal.t()
  example a_variable_modulus_is_refused do
    {:error, refusal} = Zkfol.Lang.compile(shifty())

    assert {:modulus_not_literal, %{modulus: {:var, :m}}} = refusal
    refusal
  end

  # A call between relations derives on one trace: pick reads tab
  # through the pointer row, the fact it reaches takes a column of its
  # own, and the three facts nothing reached never materialize.
  @spec a_call_between_relations_derives() :: Interpretation.t()
  example a_call_between_relations_derives do
    {:ok, shape} = Zkfol.Lang.compile(pick())
    alloc = Zkfol.Alloc.assign(shape)

    assert Enum.to_list(Zkfol.Alloc.rows(alloc, :pick)) == [1, 2]
    assert Enum.to_list(Zkfol.Alloc.rows(alloc, :tab)) == [3, 4]
    assert Enum.to_list(Zkfol.Alloc.rows(alloc, :tag)) == [5]
    assert Enum.to_list(Zkfol.Alloc.rows(alloc, :ptr)) == [6]
    assert Zkfol.Alloc.width(alloc) == 6

    # The list reads root then scope, and the arguments are pick's own
    # two: its index free, its value asked for. Nothing determines the
    # index, so unification leaves it and the witness fills it.
    {:ok, [%{v: 41}]} = Al.apply([pick(), tab()], [:_, :v])
    {:ok, witness} = Al.solve([pick(), tab()], [:_, 41])

    assert Interpretation.len(witness) == 2
    assert Interpretation.at(witness, 2, 2) == 41
    assert Interpretation.at(witness, 3, 1) == 3
    assert Interpretation.at(witness, 4, 1) == 40

    # Each column wears its relation: tab below, pick above.
    assert Interpretation.at(witness, 5, 1) == 2
    assert Interpretation.at(witness, 5, 2) == 1
    witness
  end

  defrel five(1, 5)
  defrel seven(1, 7)

  defrel sums(x, v) do
    five(x, a)
    seven(x, b)
    v = a + b
  end

  @doc "I pin the pointer's identity: two callees at one address are two pointers."
  @spec two_callees_take_two_pointers() :: Interpretation.t()
  example two_callees_take_two_pointers do
    {:ok, shape} = Zkfol.Lang.compile(sums())

    assert [{:five, _at}, {:seven, _same}] = shape.pointers

    {:ok, witness} = Al.solve([sums(), five(), seven()], [1, :_])

    assert Interpretation.len(witness) == 3
    assert Interpretation.at(witness, 1, 3) == 1
    assert Interpretation.at(witness, 2, 3) == 12
    witness
  end

  # The tag anchors the read. A column is what it wears: wearing tab, a
  # forged (3, 99) satisfies no tab fact; wearing pick, the self-read
  # demands the pointed column wear tab. The math objects either way.
  @spec a_forged_fact_is_rejected() :: Interpretation.t()
  example a_forged_fact_is_rejected do
    {:ok, pred} = Zkfol.Lang.lower(pick(), [pick(), tab()])

    honest = Interpretation.new([[0, 2], [0, 41], [3, 0], [40, 0], [2, 1], [1, 1]])
    assert Zkfol.Semantics.valid?(pred, honest)

    for tag <- [1, 2] do
      forged = Interpretation.new([[0], [100], [3], [99], [tag], [1]])
      refute Zkfol.Semantics.valid?(pred, forged)
    end

    honest
  end

  # Recursion across members derives on one chain: odd and even
  # alternate columns, each read binding the next index down to the
  # fact that anchors the parity, and the tag row oscillates with it.
  @spec recursion_between_relations_derives() :: Interpretation.t()
  example recursion_between_relations_derives do
    {:ok, odd5} = Al.solve([odd(), even()], [5, :_])

    assert Interpretation.len(odd5) == 5
    assert Interpretation.at(odd5, 2, 5) == 1
    assert for(x <- 1..5, do: Interpretation.at(odd5, 5, x)) == [1, 2, 1, 2, 1]

    {:ok, odd4} = Al.solve([odd(), even()], [4, :_])
    assert Interpretation.at(odd4, 2, 4) == 0
    odd5
  end

  @doc "I thread the head through the call, and the intermediary I spared says the same."
  @spec threading_a_head_names_no_intermediary() :: Interpretation.t()
  example threading_a_head_names_no_intermediary do
    {:ok, threaded} = Zkfol.Lang.lower(odd(), [odd(), even()])
    {:ok, spelled} = Zkfol.Lang.lower(named_odd(), [named_odd(), named_even()])
    {:ok, witness} = Al.solve([named_odd(), named_even()], [5, :_])

    assert threaded == spelled
    assert witness == recursion_between_relations_derives()
    witness
  end

  @doc "I name one row twice in a call, so the two reads meet as a join."
  @spec one_name_in_two_outputs_joins() :: Interpretation.t()
  example one_name_in_two_outputs_joins do
    {:ok, [%{x: 2, v: 4}]} = Al.apply([twinned(), pairs()], [:x, :v])

    {:ok, witness} = Al.solve([twinned(), pairs()], [2, :_])
    assert Interpretation.at(witness, 2, 2) == 4
    witness
  end

  @doc "I do not care twice, and each underscore keeps to itself: no join."
  @spec an_underscore_is_anonymous_each_time() :: [%{atom() => integer()}]
  example an_underscore_is_anonymous_each_time do
    {:ok, answers} = Al.apply([loose(), pairs()], [:x])

    assert Enum.sort_by(answers, & &1.x) == [%{x: 1}, %{x: 2}]
    answers
  end

  @doc "I pin an output to a value, so the call reads only the row that carries it."
  @spec a_literal_output_pins_the_row() :: [%{atom() => integer()}]
  example a_literal_output_pins_the_row do
    {:ok, answers} = Al.apply([mate(), pairs()], [:x, :v])

    assert answers == [%{x: 1, v: 5}]
    answers
  end

  @doc "I refuse an unanswerable question by its finite failure, fast."
  @spec an_unanswerable_question_refuses() :: Refusal.t()
  example an_unanswerable_question_refuses do
    # No pick derives 42: the question fails finitely; no size walked.
    {:error, reason} = Al.solve([pick(), tab()], [:_, 42])

    assert {:no_answer, _} = reason
    reason
  end

  @doc "I ignore scope the closure never calls, so a module rides whole."
  @spec extra_scope_rides_along() :: Interpretation.t()
  example extra_scope_rides_along do
    stray =
      rel :stray do
        stray(1, v) do
          v = reify(1 = len)
        end
      end

    {:ok, witness} = Al.solve([pick(), tab(), odd(), even(), stray], [:_, 41])

    assert Interpretation.at(witness, 2, 2) == 41
    witness
  end

  @doc "I aim a later call where an earlier one landed; deriving me awaits CLP."
  @spec a_call_targets_an_earlier_answer() :: Interpretation.t()
  example a_call_targets_an_earlier_answer do
    # Two steps from 2: through 3, landing on 1. Built by hand,
    # judged whole below.
    witness =
      Interpretation.new([
        [0, 0, 3],
        [0, 0, 1],
        [3, 2, 0],
        [1, 3, 0],
        [2, 2, 1],
        [1, 1, 2],
        [1, 1, 1]
      ])

    assert Interpretation.at(witness, 2, 3) == 1

    k = Interpretation.at(witness, 4, Interpretation.at(witness, 6, 3))
    assert Interpretation.at(witness, 3, Interpretation.at(witness, 7, 3)) == k

    {:ok, pred} = Zkfol.Lang.lower(leap(), [leap(), step()])
    assert Zkfol.Semantics.valid?(pred, witness)
    witness
  end

  # A row nothing determines is anybody's value: unification leaves
  # the cell free, the witness fills it, and the oracle is content at
  # any choice.
  @spec a_row_nothing_determines_is_free() :: Interpretation.t()
  example a_row_nothing_determines_is_free do
    loose =
      rel :loose do
        loose(1, 1, 1)

        loose(x, v, w) do
          x > 1
          loose(x - 1, a, _b)
          v = a + 1
        end
      end

    {:ok, witness} = Al.solve(loose, [5])

    assert witness |> Interpretation.rows() |> Enum.at(2) == [1, 0, 0, 0, 0]
    witness
  end

  # The surface admits more than the lowering does. Each excess shape
  # refuses by name rather than raising out of the middle of a pass.
  @spec shapes_beyond_the_lowering_refuse() :: [Refusal.t()]
  example shapes_beyond_the_lowering_refuse do
    reify_of_a_call =
      rel :rc do
        rc(1, 1)

        rc(x, v) do
          x > 1
          rc(x - 1, w)
          v = reify(rc(3, w))
        end
      end

    head_that_is_a_term =
      rel :bad do
        bad(1, 1)

        bad(x + 1, v) do
          x > 1
          bad(x - 1, w)
          v = w + 1
        end
      end

    {:error, lifted} = Zkfol.Lang.compile(reify_of_a_call)
    {:error, headed} = Al.solve(head_that_is_a_term, [5])

    assert {:unliftable_term, %{term: {:reify, {:call, :rc, _args}}}} = lifted
    assert {:head_not_a_column, %{head: {:add, {:var, :x}, 1}}} = headed
    [lifted, headed]
  end
end
