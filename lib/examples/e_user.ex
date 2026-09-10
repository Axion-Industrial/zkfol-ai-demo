defmodule Examples.EUser do
  @moduledoc "I am the book of user relations: every statement of the corpus, solved."

  use ExExample
  use Zkfol.Lang

  import ExUnit.Assertions

  alias Zkfol.Alloc
  alias Zkfol.Alloc.Slot
  alias Zkfol.Ast
  alias Zkfol.Interpretation
  alias Zkfol.Lang.Rel
  alias Zkfol.Log
  alias Zkfol.Phi
  alias Zkfol.Pipeline
  alias Zkfol.Prover
  alias Zkfol.Refusal
  alias Zkfol.Semantics
  alias Zkfol.Statement
  alias Zkfol.Witness

  defrel fib(1, 1)
  defrel fib(2, 1)

  defrel fib(x, v) do
    x > 2
    fib(x - 1, v1)
    fib(x - 2, v2)
    v = v1 + v2
  end

  defrel bif(1, 1)
  defrel bif(1, 2)

  defrel bif(v, x) do
    x > 2
    bif(a, x - 1)
    bif(b, x - 2)
    v = a + b
  end

  defrel tab(1, 10)
  defrel tab(2, 20)
  defrel tab(3, 30)
  defrel tab(4, 40)

  defrel shifted(1, 10)

  defrel shifted(x, v) do
    x > 1
    shifted(x - 1, _w)
    tab(x - 1, v)
  end

  defrel regs(1, 1, 1)

  defrel regs(x, a, b) do
    x > 1
    regs(x - 1, a1, b1)
    a = a1 + b1
    b = a1
  end

  defrel regsm(1, 1, 1, 0)

  defrel regsm(x, a, b, q) do
    x > 1
    regsm(x - 1, a1, b1, q1)
    a1 + b1 = q * 7919 + a
    a < 7919
    a + 1 > 0
    q + 1 > 0
    b = a1
  end

  defrel offset(1, 1)

  defrel offset(x, v) do
    x > 1
    offset(x - 1, w)
    v = w + 5
  end

  defrel paired(x, v) do
    fib(x, a)
    offset(x, b)
    v = a + b
  end

  @doc "The base rides as a value: the prover's knowledge enters at construction."
  @spec power_rel(integer()) :: Rel.t()
  def power_rel(base) do
    rel :power do
      power(1, ^base, 0, 1)

      power(x, b, e, v) do
        x > 1
        power(x - 1, bb, ee, w)
        b = bb
        e = ee + 1
        v = b * w
      end
    end
  end

  @step 3

  defrel step(1, ^@step)

  defrel step(x, v) do
    x > 1
    step(x - 1, w)
    v = w + ^@step
  end

  defrel doubled([], [])

  defrel doubled([h | t], [d | s]) do
    d = h + h
    doubled(t, s)
  end

  defrel doubled_fun([], [])

  defrel doubled_fun([h | t], [g | [g | s]]) do
    g = h + h
    doubled_fun(t, s)
  end

  defrel total([], 0)

  defrel total([h | t], s) do
    total(t, r)
    s = r + h
  end

  defrel both(xs, s) do
    doubled_fun(xs, ys)
    total(ys, s)
  end

  defrel chained(a, b) do
    doubled_fun(a, c)
    doubled_fun(c, b)
  end

  defrel widened([], [])

  defrel widened([h | t], [g | [g | s]]) do
    g = h + h
    doubled(t, s)
  end

  defrel twice_widened(a, b) do
    widened(a, c)
    widened(c, b)
  end

  defrel twice_read(xs, s) do
    doubled(xs, _ys)
    total(xs, s)
  end

  defrel joined([], ys, ys)

  defrel joined([h | t], ys, [h | zs]) do
    joined(t, ys, zs)
  end

  defrel tacked(a, b) do
    doubled_fun(a, c)
    joined(c, [9], b)
  end

  defrel fronted(a, b) do
    doubled_fun(a, c)
    doubled_fun(c, d)
    b = [1 | d]
  end

  defrel twinned(a, b) do
    doubled_fun(a, [x | _t])
    b = [x, x]
  end

  defrel cell_of(i, v) do
    doubled([1, 2, 3], c)
    nth(i, c, v)
  end

  defrel topped([a, b, c | _rest]) do
    permutation(3, [a, b, c])
  end

  defrel dropped(1, xs, xs)

  defrel dropped(n, [_ | t], ys) do
    n > 1
    dropped(n - 1, t, ys)
  end

  defrel from_zero(0, 1)

  defrel from_zero(x, v) do
    x > 0
    from_zero(x - 1, w)
    v = w + 1
  end

  defrel rows([], 0)

  defrel rows([[a, b] | t], s) do
    rows(t, r)
    s = r + a + b
  end

  defrel diagonal([[a, _], [_, d]], v) do
    v = a + d
  end

  defrel each([], _r, 0)

  defrel each([c | t], r, n) do
    r(c)
    each(t, r, m)
    n = m + 1
  end

  defrel row_ok([a, b]) do
    a < b
  end

  defrel checked(n) do
    each([[3, 4], [5, 6]], row_ok, n)
  end

  defrel succ(x, y) do
    y = x + 1
  end

  defrel map([], _r, [])

  defrel map([h | t], r, [g | s]) do
    r(h, g)
    map(t, r, s)
  end

  defrel bumped(ys) do
    map([1, 2, 3], succ, ys)
  end

  defrel between(lo, hi, x) do
    x >= lo
    x <= hi
  end

  defrel every(_r, [])

  defrel every(r, [h | t]) do
    r(h)
    every(r, t)
  end

  defrel cells_ok(rs) do
    every(every(between(1, 4)), rs)
  end

  @spec compiled(pos_integer()) :: Log.Ran.t()
  example compiled(n \\ 8) do
    ran = Zkfol.compile(fib(), args: [n])

    assert %Prover.Report{} = Log.report(Log.snapshot(), ran)
    ran
  end

  @spec fibonacci(pos_integer()) :: Statement.t()
  example fibonacci(n \\ 8) do
    {:ok, statement, _trace} = Pipeline.run(plain(), %Statement{rels: [fib()], args: [n]})

    witness = Statement.witness(statement)
    assert witness |> Interpretation.rows() |> Enum.at(0) == Enum.map(1..n, &fib/1)
    assert Enum.all?(1..n, &Semantics.holds?(Statement.pred(statement), witness, &1))
    statement
  end

  @spec one_column() :: Prover.Report.t()
  example one_column do
    ran = Zkfol.compile(%Statement{rels: [fib()], args: [1]})
    assert Interpretation.len(Statement.witness(Log.Ran.final_stage(ran))) == 1
    assert %Prover.Report{} = report = Log.report(Log.snapshot(), ran)
    report
  end

  @spec registers(pos_integer()) :: Statement.t()
  example registers(n \\ 8) do
    {:ok, statement, _trace} = Pipeline.run(plain(), %Statement{rels: [regs()], args: [n]})

    assert Interpretation.at(Statement.witness(statement), 2, n) == fib(n)
    statement
  end

  @spec registers_mod(pos_integer()) :: Statement.t()
  example registers_mod(n \\ 300) do
    source = %Statement{rels: [regsm()], args: [n, :_, :_, :_]}
    {:ok, statement, _trace} = Pipeline.run(plain(), source)

    assert Interpretation.at(Statement.witness(statement), 1, n) == rem(fib(n + 1), 7919)
    statement
  end

  @doc "A guard's slack past 32 bits is a natural all the same; only the Word lookup refuses it."
  @spec a_slack_cannot_outgrow_its_word() :: Refusal.t()
  example a_slack_cannot_outgrow_its_word do
    wide =
      rel :wide do
        wide(1, 1)

        wide(x, v) do
          x > 1
          wide(x - 1, w)
          v = w + 1
          v < 10_000_000_000
        end
      end

    {:ok, statement, _trace} = Pipeline.run(plain(), %Statement{rels: [wide], args: [3]})
    witness = Statement.witness(statement)

    cells = witness |> Interpretation.rows() |> List.flatten()
    assert Enum.min(cells) >= 0
    assert Enum.max(cells) < 2 ** 32

    assert {:error, {:prover_failed, %{said: said}} = refused} =
             Prover.prove(Statement.pred(statement), witness,
               claims: Statement.claims(statement),
               name: :wide_slack
             )

    assert said =~ "Lookup"
    refused
  end

  @spec pinned_step(pos_integer()) :: Rel.t()
  example pinned_step(n \\ 4) do
    step = step()
    assert {[1, @step], []} = hd(step.clauses)

    query = Zkfol.eval!(step, [n, :_], [])
    assert Zkfol.Query.taken(query) == [[n, n * @step]]
    Zkfol.Query.close(query)
    step
  end

  @spec power(non_neg_integer()) :: Statement.t()
  example power(exponent \\ 3) do
    source = %Statement{rels: [power_rel(2)], args: [exponent + 1]}
    {:ok, statement, _trace} = Pipeline.run(plain(), source)

    assert Interpretation.at(Statement.witness(statement), 3, exponent + 1) == 2 ** exponent
    statement
  end

  @doc "Two recurrences read at one index: their facts share the column."
  @spec shared_index(pos_integer()) :: Statement.t()
  example shared_index(n \\ 8) do
    source = %Statement{rels: [paired(), fib(), offset()], args: [n]}
    {:ok, statement, _trace} = Pipeline.run(plain(), source)
    value = fn name -> statement |> Statement.bank(name) |> hd() |> List.last() end

    assert value.(:fib) == fib(n)
    assert value.(:offset) == 5 * n - 4

    assert Enum.take(Zkfol.stream([paired(), fib(), offset()], [n, :_]), 1) ==
             [[n, fib(n) + 5 * n - 4]]

    statement
  end

  @doc "A walk is a column per step, so one predicate stands at any length."
  @spec doubles(pos_integer()) :: Statement.t()
  example doubles(n \\ 3) do
    statement = Log.Ran.final_stage(Zkfol.emit(doubled(), args: [Enum.to_list(1..n), :_]))
    longer = Log.Ran.final_stage(Zkfol.emit(doubled(), args: [Enum.to_list(1..(10 * n)), :_]))

    assert Statement.pred(statement) == Statement.pred(longer)
    statement
  end

  @doc "Two walks at two strides read one member: what one spells the other reads."
  @spec reshaped() :: Statement.t()
  example reshaped do
    statement = Log.Ran.final_stage(Zkfol.emit(both(), args: [[1, 2, 3], :_]))

    assert Enum.take(Zkfol.stream(both(), [[1, 2, 3], :_]), 1) == [[[1, 2, 3], 24]]
    statement
  end

  @doc "One relation walked twice takes a copy per call, so each run stands on rows of its own."
  @spec chained_walks() :: Statement.t()
  example chained_walks do
    statement = Log.Ran.final_stage(Zkfol.emit(chained(), args: [[1, 2, 3], :_]))

    assert Enum.take(Zkfol.stream(chained(), [[1, 2, 3], :_]), 1) ==
             [[[1, 2, 3], [4, 4, 4, 4, 8, 8, 8, 8, 12, 12, 12, 12]]]

    statement
  end

  @doc "A clause writing two cells hands the rest to a walk writing one, each at its own stride."
  @spec strided_handoff() :: Statement.t()
  example strided_handoff do
    ran = Zkfol.compile(twice_widened(), args: [[1, 2, 3], :_])

    assert Enum.take(Zkfol.stream(twice_widened(), [[1, 2, 3], :_]), 1) ==
             [[[1, 2, 3], [4, 4, 4, 8, 12]]]

    assert %Prover.Report{} = Log.report(Log.snapshot(), ran)
    Log.Ran.final_stage(ran)
  end

  @doc "A bank a strided walk wrote is carried on whole: two members hold the cells they share."
  @spec tacked_bank() :: Statement.t()
  example tacked_bank do
    statement = Log.Ran.final_stage(Zkfol.emit(tacked(), args: [[1, 2], :_]))

    assert Enum.take(Zkfol.stream(tacked(), [[1, 2], :_]), 1) == [[[1, 2], [2, 2, 4, 4, 9]]]
    statement
  end

  @doc "A bracket an equation writes is a sequence like a head's; its end name carries the rest."
  @spec fronted_bank() :: Statement.t()
  example fronted_bank do
    statement = Log.Ran.final_stage(Zkfol.emit(fronted(), args: [[1, 2], :_]))

    assert Enum.take(Zkfol.stream(fronted(), [[1, 2], :_]), 1) ==
             [[[1, 2], [1, 4, 4, 4, 4, 8, 8, 8, 8]]]

    assert Semantics.valid?(Statement.pred(statement), Statement.witness(statement))
    statement
  end

  @doc "A bracket the equation closes spells every cell its member holds."
  @spec twinned_cells() :: Statement.t()
  example twinned_cells do
    statement = Log.Ran.final_stage(Zkfol.emit(twinned(), args: [[1, 2], :_]))

    assert Enum.take(Zkfol.stream(twinned(), [[1, 2], :_]), 1) == [[[1, 2], [2, 2]]]
    assert Statement.bank(statement, :"twinned b") == [[0, 2, 2, 0, 0]]
    statement
  end

  @doc "An equation is no contract of order: a bracket ahead of its binding calls lays the same."
  @spec bracket_before_its_calls() :: Ast.pred()
  example bracket_before_its_calls do
    ahead =
      rel :fronted do
        fronted(a, b) do
          b = [1 | d]
          doubled_fun(a, c)
          doubled_fun(c, d)
        end
      end

    statement = Log.Ran.final_stage(Zkfol.emit(ahead, args: [[1, 2], :_]))

    assert Statement.pred(statement) == Statement.pred(fronted_bank())
    Statement.pred(statement)
  end

  @doc "A reading takes a bank the run wrote as the cells standing on its member's rows."
  @spec indexed_cell() :: Statement.t()
  example indexed_cell do
    statement = Log.Ran.final_stage(Zkfol.emit(cell_of(), args: [3, :_]))

    assert Enum.take(Zkfol.stream(cell_of(), [3, :_]), 1) == [[3, 6]]
    statement
  end

  @doc "An index spends no row, so its opening claims the presence whose column names it."
  @spec opened_index(pos_integer()) :: Statement.t()
  example opened_index(n \\ 8) do
    {:ok, statement} = Statement.opened(fibonacci(n), [1])

    assert Statement.claims(statement) == [{"fib.x", 2, n}]
    statement
  end

  @doc "A member no site steps stands where it is read; opening the index claims that cell."
  @spec opened_cell() :: Statement.t()
  example opened_cell do
    statement = Log.Ran.final_stage(Zkfol.emit(tab(), args: [4, :_], public: [1]))

    assert Statement.bank(statement, :tab) == [[4], [40]]
    assert Statement.claims(statement) == [{"tab.a1", 1, 1}, {"in", 3, 1}]
    assert Enum.take(Zkfol.stream(tab(), [:_, 30]), 1) == [[3, 30]]
    statement
  end

  @doc "A table read an offset back stands where its own index puts it, not its reader."
  @spec shifted_table() :: Statement.t()
  example shifted_table do
    statement = Log.Ran.final_stage(Zkfol.emit(shifted(), args: [4, :_]))

    assert Statement.bank(statement, :shifted) == [[10, 10, 20, 30]]
    assert Semantics.valid?(Statement.pred(statement), Statement.witness(statement))
    statement
  end

  @doc "A recurrence written value-first is fibonacci's: the index is where the sites step."
  @spec index_at_either_parameter() :: Ast.pred()
  example index_at_either_parameter do
    {:ok, phi} = Phi.lower(fib(), [fib()])

    assert Phi.lower(bif(), [bif()]) == {:ok, phi}
    phi
  end

  @doc "A passed relation is called through its name and makes the bank the callee returns."
  @spec mapped_bank() :: Statement.t()
  example mapped_bank do
    statement = Log.Ran.final_stage(Zkfol.emit(bumped(), args: [:_]))

    assert Alloc.names(Statement.alloc(statement)) == [:bumped, :"bumped ys"]
    assert Statement.bank(statement, :"bumped ys") == [[0, 4, 3, 2]]
    statement
  end

  @doc "A sequence handed on whole is the one the walk extends: one member's rows, all claimed."
  @spec appended() :: Statement.t()
  example appended do
    statement =
      Log.Ran.final_stage(Zkfol.emit(joined(), args: [[1, 2], [3, 4], :_], public: [3]))

    assert Enum.take(Zkfol.stream(joined(), [[1, 2], [3, 4], :_]), 1) ==
             [[[1, 2], [3, 4], [1, 2, 3, 4]]]

    assert Statement.bank(statement, :"joined a3") == [[0, 4, 3, 2, 1]]

    assert Statement.claims(statement) ==
             for(x <- 2..5, claim <- [{"joined.a3", 3, x}, {"in", 7, x}], do: claim)

    statement
  end

  @doc "A sequence the run computes rather than the statement names is carried the same way."
  @spec remainder() :: Statement.t()
  example remainder do
    statement = Log.Ran.final_stage(Zkfol.emit(dropped(), args: [3, [1, 2, 3, 4], :_]))

    assert Enum.take(Zkfol.stream(dropped(), [3, [1, 2, 3, 4], :_]), 1) ==
             [[3, [1, 2, 3, 4], [3, 4]]]

    assert Statement.bank(statement, :"dropped a2") == [[0, 4, 3, 2, 1]]
    statement
  end

  @doc "A head spelling three cells and ending in an unread name meets the bank below them."
  @spec open_tail() :: Statement.t()
  example open_tail do
    ran = Zkfol.emit(topped(), args: [[3, 1, 2, 4]])
    statement = Log.Ran.final_stage(ran)

    assert Enum.take(Zkfol.stream(topped(), [[3, 1, 2, 4]]), 1) == [[[3, 1, 2, 4]]]

    assert hd(Statement.alloc(statement).members).slots == [
             %Slot{name: :a1, allocation: {:bank, :"topped a1", {:at, :x, 0, 5}}}
           ]

    assert Statement.bank(statement, :"topped a1") == [[0, 4, 2, 1, 3]]
    assert Semantics.valid?(Statement.pred(statement), Statement.witness(statement))
    statement
  end

  @doc "An index counts from where a base clause of it starts, a column from one."
  @spec zero_based(non_neg_integer()) :: Statement.t()
  example zero_based(n \\ 3) do
    statement = Log.Ran.final_stage(Zkfol.emit(from_zero(), args: [n, :_]))

    assert Enum.take(Zkfol.stream(from_zero(), [n, :_]), 1) == [[n, n + 1]]
    assert Statement.bank(statement, :from_zero) == [Enum.to_list(1..(n + 1))]
    statement
  end

  @doc "An inner bracket is an earlier dimension: two rows a column, the columns the walk."
  @spec row_sums() :: Statement.t()
  example row_sums do
    statement = Log.Ran.final_stage(Zkfol.emit(rows(), args: [[[3, 4], [5, 6]], :_]))

    assert Statement.bank(statement, :rows) == [[0, 11, 18]]
    assert Statement.bank(statement, :"rows a1") == [[0, 5, 3], [0, 6, 4]]
    statement
  end

  @doc "The same predicate reads two-row matrices of different lengths without a shape hint."
  @spec rows_without_a_shape_hint() :: [Interpretation.t()]
  example rows_without_a_shape_hint do
    {:ok, pred, alloc} = Phi.compile(rows())
    pred = Alloc.link(pred, alloc)
    assert Alloc.regions(alloc) == [rows: 1, "rows a1": 2, in: 2]

    for grid <- [[[3, 4], [5, 6]], [[1, 2], [3, 4], [5, 6]]] do
      {:ok, derivation} = Zkfol.Al.derived(rows(), [grid, :_])
      witness = derivation |> Zkfol.Lay.of(alloc) |> Zkfol.Lay.witness()
      assert Semantics.valid?(pred, witness)
      assert {:ok, %Prover.Report{}, _id} = Prover.prove(pred, witness)
      witness
    end
  end

  @doc "A cell of a bank is a bank: the dimension is the rows the passed relation spends."
  @spec checked_rows() :: Statement.t()
  example checked_rows do
    statement = Log.Ran.final_stage(Zkfol.emit(checked(), args: [:_]))

    assert Enum.take(Zkfol.stream(checked(), [:_]), 1) == [[2]]
    assert Alloc.names(Statement.alloc(statement)) == [:checked]
    assert Statement.bank(statement, :checked) == [[2]]
    statement
  end

  @doc "A passed relation fixing a passed relation: the inner walks stand on the bank's cells."
  @spec nested_pass() :: Statement.t()
  example nested_pass do
    grid = [[1, 2], [3, 4]]
    ran = Zkfol.emit(cells_ok(), args: [grid])

    assert Enum.take(Zkfol.stream(cells_ok(), [grid]), 1) == [[grid]]
    assert Enum.take(Zkfol.stream(cells_ok(), [[[1, 2], [3, 9]]]), 1) == []

    {:ok, _pred, alloc} = Phi.compile(cells_ok(), [cells_ok()], [grid])

    assert Alloc.names(alloc) == [:cells_ok, :"cells_ok rs", :every]

    statement = Log.Ran.final_stage(ran)
    assert Semantics.valid?(Statement.pred(statement), Statement.witness(statement))
    statement
  end

  @doc "A recursion growing at every step lowers as a chain of pointers; only its base derives."
  @spec spiral() :: Ast.pred()
  example spiral do
    spiral =
      rel :spiral do
        spiral([], 0)

        spiral(xs, n) do
          doubled_fun(xs, ys)
          spiral(ys, m)
          n = m + 1
        end
      end

    assert {:ok, phi} = Phi.lower(spiral, [spiral, doubled_fun()])
    assert Enum.take(Zkfol.stream([spiral, doubled_fun()], [[], :_]), 1) == [[[], 0]]
    phi
  end

  @doc "The relations a prefix fixes are reached like a callee, however deep the passing goes."
  @spec deeper_pass() :: [[Statement.datum()]]
  example deeper_pass do
    deeper =
      rel :deeper do
        deeper(rss) do
          every(every(every(between(1, 4))), rss)
        end
      end

    answers = Enum.take(Zkfol.stream(deeper, [[[[1, 2]], [[3, 4]]]]), 1)

    assert answers == [[[[[1, 2]], [[3, 4]]]]]
    assert Enum.take(Zkfol.stream(deeper, [[[[1, 2]], [[3, 9]]]]), 1) == []
    answers
  end

  @spec plain() :: Pipeline.t()
  def plain(), do: %Pipeline{passes: [{Witness, []}, {Zkfol.Phi, []}]}

  @spec fib(pos_integer()) :: pos_integer()
  def fib(n) do
    {a, _} = Enum.reduce(1..n, {0, 1}, fn _, {a, b} -> {b, a + b} end)
    a
  end
end
