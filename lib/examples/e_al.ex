defmodule Examples.EAl do
  @moduledoc """
  I am the statement running as clauses: the derivation is the
  witness, resending replaces rather than stacks, and a row nothing
  determines refuses by name. The value-addressed hop also emits here
  by Section 4, bits and result row on the trace, and its proof waits
  at the prover boundary for the zinc+ pointer query.
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
  alias Zkfol.Uair

  @spec registers_program() :: Al.program()
  example registers_program do
    {:ok, program} = Al.translate(Examples.EUser.regs())

    # The class row, the retraction, one clause per clause: facts first.
    assert [%AL.Goal.SetClass{}, %AL.Goal.Forall{}, base, step] = program
    assert %AL.Goal.OApply{method_id: :defmethod, args: [:zkfol, :regs, _head, [_ | _]]} = step
    assert %AL.Goal.OApply{method_id: :defmethod, args: [:zkfol, :regs, _head, []]} = base
    program
  end

  @doc "I ask the emitted relation for its count rather than telling it."
  @spec the_program_runs_backward() :: pos_integer()
  example the_program_runs_backward do
    {:ok, program} = Al.translate(EUser.fib())
    branch = AL.Branch.fork()
    {:atomic, _} = AL.eval(program, nil, branch, heap: 20_000_000)

    # fib(self, x, v, t): row one is the count, so leaving it free is
    # the whole question, and F(8) pins the value row.
    x = {:x, [], nil}
    goal = AL.ast_to_pattern({:fib, [], [:zkfol, x, EUser.fib(8), {:t, [], nil}]})
    {:atomic, {bindings, _}} = AL.eval([goal], nil, branch, heap: 20_000_000)
    AL.Branch.discard(branch)

    count = bindings |> AL.Var.deref(:"$x") |> AL.Var.subst(bindings)
    assert count == 8
    count
  end

  @doc "I solve one relation both ways, one answer being the other's question."
  @spec fib_solves_both_ways() :: Interpretation.t()
  example fib_solves_both_ways do
    n = 40
    branch = AL.Branch.fork()
    {:ok, forward} = Al.solve(EUser.fib(), [n], branch: branch.id)
    value = Interpretation.at(forward, 2, Interpretation.len(forward))

    {:ok, backward} = Al.solve(EUser.fib(), [:_, value], branch: branch.id)
    AL.Branch.discard(branch)

    assert Interpretation.len(backward) == n
    assert backward == forward
    backward
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

    # The claims are the arguments: the value claim stays free and the
    # position claim carries e, at n - 2 since the kernel claims
    # F(e + 2). Bits and depth arrive by descent, not from the caller.
    {:ok, witness} = Al.solve(statement, [:_, n - 2])

    # kernel(x, u, w, e, r): e walks in row 4, the result rides row 5.
    last = Interpretation.len(witness)
    assert Interpretation.at(witness, 4, last) == n - 2
    assert Interpretation.at(witness, 5, last) == EUser.fib(n)
    witness
  end

  @spec al_binds_a_bound_claim_too() :: Interpretation.t()
  example al_binds_a_bound_claim_too do
    statement = EDoubling.rewritten_fibonacci(10)
    {:ok, witness} = Al.solve(statement, [55, 8], heap: 2_000_000)

    last = Interpretation.len(witness)
    assert last == 4
    assert Interpretation.at(witness, 5, last) == 55
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

  @spec registers_go_straight_down() :: Interpretation.t()
  example registers_go_straight_down do
    {:ok, direct} = Al.solve(Examples.EUser.regs(), [8])

    assert direct == Statement.witness(EUser.registers(8))
    direct
  end

  # Outside doubling's class, inside the direct path's: order one,
  # a coefficient that is the column itself.
  @spec factorial_goes_straight_down() :: Interpretation.t()
  example factorial_goes_straight_down do
    {:ok, witness} = Al.solve(Examples.EFacts.factorial(), [5])

    assert witness |> Interpretation.rows() |> Enum.at(1) == [1, 2, 6, 24, 120]
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
          gap(x - 1, _w)
          v = reify(x = len)
        end
      end

    {:ok, direct} = Al.solve(gap, [5])
    assert direct |> Interpretation.rows() |> Enum.at(1) == [16, 9, 4, 1, 0]
    direct
  end

  # A value aims the pointer: the call reads the column another row names.
  @spec hop_rel() :: Zkfol.Lang.Rel.t()
  example hop_rel do
    rel :hop do
      hop(1, 1)

      hop(x, v) do
        hop(v - 1, w)
        v = w + 1
      end
    end
  end

  # The pointer enumerates when nothing binds it.
  @spec value_targets_go_straight_down() :: Interpretation.t()
  example value_targets_go_straight_down do
    {:ok, witness} = Al.solve(hop_rel(), [5])
    assert witness |> Interpretation.rows() |> Enum.at(1) == [1, 2, 2, 2, 2]
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
    {:ok, %{pred: pred}} = Zkfol.Lang.compile(hop_rel(), [hop_rel()])
    witness = value_targets_go_straight_down()
    {:ok, uair} = Uair.emit(pred, witness)
    len = Interpretation.len(witness)

    assert [%{row: pointer, table: {:word, 3}}] = uair.mode.lookups
    assert [%{value_row: 0, bit_rows: bits, result_row: 6}, second] = uair.mode.reads
    assert %{value_row: 1, bit_rows: ^bits, result_row: 7} = second

    [b1, b2, b3] = for b <- bits, do: Enum.at(uair.columns, b)
    assert Enum.all?(b1 ++ b2 ++ b3, &(&1 in [0, 1]))
    weighted = Enum.zip_with([b1, b2, b3], fn [u, v, w] -> u + 2 * v + 4 * w end)
    assert weighted == Enum.at(uair.columns, pointer)

    # Each result row reads its value row at the pointer, r(x) = R(addr(x)).
    # Columns store a row reversed, so position p lands at index len - p.
    for %{value_row: v, result_row: r} <- uair.mode.reads do
      value = Enum.at(uair.columns, v)
      assert Enum.at(uair.columns, r) == Enum.map(weighted, &Enum.at(value, len - &1))
    end

    assert uair.shifts == []
    uair
  end

  # The lowering is total; the missing zinc+ capability refuses at the
  # prover boundary, not in the middle of the compiler.
  @spec composed_read_awaits_zinc() :: Refusal.t()
  example composed_read_awaits_zinc do
    {:error, reason} = Uair.request(composed_hop_emits())

    assert {:composed_read_awaits_backend, _} = reason
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

  # A row nothing determines is the prover's knowledge, not the witness's:
  # the derivation ends with that cell still an AL variable, and the
  # refusal names the cell rather than calling it a negative number.
  @spec a_row_nothing_determines_is_refused() :: Refusal.t()
  example a_row_nothing_determines_is_refused do
    loose =
      rel :loose do
        loose(1, 1, 1)

        loose(x, v, w) do
          loose(x - 1, a, _b)
          v = a + 1
        end
      end

    {:error, reason} = Al.solve(loose, [5])

    assert {:row_undetermined, %{cell: _cell}} = reason
    reason
  end

  # The surface admits more than the lowering does. Each excess shape
  # refuses by name rather than raising out of the middle of a pass.
  @spec shapes_beyond_the_lowering_refuse() :: [Refusal.t()]
  example shapes_beyond_the_lowering_refuse do
    reify_of_a_call =
      rel :rc do
        rc(1, 1)

        rc(x, v) do
          rc(x - 1, w)
          v = reify(rc(3, w))
        end
      end

    head_that_is_a_term =
      rel :bad do
        bad(1, 1)

        bad(x + 1, v) do
          bad(x - 1, w)
          v = w + 1
        end
      end

    {:error, lifted} = Zkfol.Lang.compile(reify_of_a_call, [reify_of_a_call])
    {:error, headed} = Al.solve(head_that_is_a_term, [5])

    assert {:unliftable_term, %{term: {:reify, {:call, :rc, _args}}}} = lifted
    assert {:head_not_a_column, %{head: {:add, {:var, :x}, 1}}} = headed
    [lifted, headed]
  end

  # A predicate is not a relation, whichever connective it is built from.
  @spec a_bare_predicate_has_no_clauses() :: Refusal.t()
  example a_bare_predicate_has_no_clauses do
    {:error, reason} = Al.solve(Zkfol.Ast.eq(Zkfol.Ast.x(), 1), [3])

    assert {:raw_predicate_has_no_clauses, _} = reason
    reason
  end
end
