defmodule Examples.ESudoku do
  @moduledoc "I am the sudoku's evidence: the game as a program over its grid."

  use ExExample
  use Zkfol.Lang

  import ExUnit.Assertions

  alias Examples.EUser
  alias Zkfol.Alloc.Bank
  alias Zkfol.Log
  alias Zkfol.Pipeline
  alias Zkfol.Prover
  alias Zkfol.Refusal
  alias Zkfol.Statement
  alias Zkfol.Uair
  alias Zkfol.Witness

  defrel triple(a, b, c) do
    all_distinct([a, b, c])
  end

  @solution [
    [9, 8, 7, 6, 5, 4, 3, 2, 1],
    [2, 4, 6, 1, 7, 3, 9, 8, 5],
    [3, 5, 1, 9, 2, 8, 7, 4, 6],
    [1, 2, 8, 5, 3, 7, 6, 9, 4],
    [6, 3, 4, 8, 9, 2, 1, 5, 7],
    [7, 9, 5, 4, 6, 1, 8, 3, 2],
    [5, 1, 9, 2, 8, 6, 4, 7, 3],
    [4, 7, 2, 3, 1, 9, 5, 6, 8],
    [8, 6, 3, 7, 4, 5, 2, 1, 9]
  ]

  @solution16 for r <- 0..15, do: for(c <- 0..15, do: rem(4 * rem(r, 4) + div(r, 4) + c, 16) + 1)

  @doc "The seventeen clues and the rules find the one grid: labeling drives AL's search."
  @spec answer() :: [[pos_integer()]]
  example answer do
    {t, {:ok, query}} = :timer.tc(fn -> Zkfol.eval(solved(), [:_], []) end)
    [[grid]] = Zkfol.Query.taken(query)
    assert grid == @solution
    assert t < 5_000_000
    grid
  end

  @doc "Cells apart but not 1..n derive and refuse to prove: distinct's proof says 1..n exactly."
  @spec distinct_wants_one_to_n() :: Refusal.t()
  example distinct_wants_one_to_n do
    {:ok, statement, _trace} =
      Pipeline.run(EUser.plain(), %Statement{rels: [triple()], args: [2, 3, 4]})

    {:error, refusal} =
      Prover.prove(Statement.pred(statement), Statement.witness(statement),
        claims: Statement.claims(statement),
        name: :not_from_one
      )

    assert {:witness_unsatisfies_schedule, _detail} = refusal
    refusal
  end

  @doc "The columns and boxes are a selection each, the rows a selection a column."
  @spec pattern_selected() :: Statement.t()
  example pattern_selected do
    {:ok, statement, _trace} =
      Pipeline.run(EUser.plain(), %Statement{rels: [solved()], args: act()})

    {:ok, uair} = Uair.emit(Statement.pred(statement), Statement.witness(statement))

    assert length(uair.word_lookups) == 18
    [%{values: values, selections: selections}] = uair.selected_lookups
    assert values == Enum.to_list(1..9)
    assert length(selections) == 18 + uair.len
    statement
  end

  @doc "The rows' selection stands at every column: a digit repeated in the padding is refused."
  @spec a_repeated_padding_is_no_proof() :: Refusal.t()
  example a_repeated_padding_is_no_proof do
    statement = pattern_selected()
    {:ok, uair} = Uair.emit(Statement.pred(statement), Statement.witness(statement))
    [%{columns: columns, selections: selections}] = uair.selected_lookups
    padded = Enum.find(selections, &Enum.all?(&1, fn {_slot, at} -> at == uair.len - 1 end))
    cells = for {slot, at} <- padded, do: {Enum.at(columns, slot), at}

    assert for({col, at} <- cells, do: uair.columns |> Enum.at(col) |> Enum.at(at)) ==
             Enum.to_list(1..9)

    repeated =
      Enum.reduce(cells, uair.columns, fn {col, at}, acc ->
        List.update_at(acc, col, &List.replace_at(&1, at, 1))
      end)

    assert {:error, {:verifier_rejected, _said} = refused} =
             Prover.prove_uair(%{uair | columns: repeated}, name: :repeated_padding)

    refused
  end

  @doc "Twenty-seven families over the grid's own cells, one selected group carrying the lot."
  @spec families_selected() :: Uair.t()
  example families_selected do
    {:ok, statement, _trace} =
      Pipeline.run(EUser.plain(), %Statement{rels: [families()], args: act()})

    {:ok, uair} = Uair.emit(Statement.pred(statement), Statement.witness(statement))
    [%{columns: columns, values: values, selections: selections}] = uair.selected_lookups

    assert uair.word_lookups == []
    assert columns == Enum.to_list(0..8)
    assert values == Enum.to_list(1..9)
    assert length(selections) == 27
    assert for(r <- 6..8, s <- 6..8, do: {s, r}) in selections
    uair
  end

  @doc "Different private grids prove on the same allocation; every family shares one puzzle bank."
  @spec private_grids_share_one_allocation() :: [Prover.Report.t()]
  example private_grids_share_one_allocation do
    {:ok, pred, alloc} = Zkfol.Phi.compile(families(), nil, act())
    assert [%Bank{depth: 9}] = Enum.filter(alloc.members, &is_struct(&1, Bank))

    for grid <- [@solution, relabelled()] do
      assert {:ok, ^pred, ^alloc} = Zkfol.Phi.compile(families(), nil, [grid])
      {:ok, derivation} = Zkfol.Al.derived(families(), [grid])
      witness = derivation |> Zkfol.Lay.of(alloc) |> Zkfol.Lay.witness()

      assert {:ok, report = %Prover.Report{}, _id} =
               Prover.prove(Zkfol.Alloc.link(pred, alloc), witness)

      report
    end
  end

  @doc "A trade down one column keeps that column's multiset; the selections across it refuse."
  @spec a_traded_cell_is_no_proof() :: Refusal.t()
  example a_traded_cell_is_no_proof do
    uair = families_selected()
    traded = List.update_at(uair.columns, 0, fn [a, b | rest] -> [b, a | rest] end)

    assert Enum.sort(hd(traded)) == Enum.sort(hd(uair.columns))

    assert {:error, {:verifier_rejected, _said} = refused} =
             Prover.prove_uair(%{uair | columns: traded}, name: :traded_cell)

    refused
  end

  @doc "Two cells opened say their eighteen values and nothing else of the answer."
  @spec opened_cells() :: Prover.Report.t()
  example opened_cells do
    {:ok, statement} =
      Statement.opened(pattern_selected(), [{:solved, :x, 9}, {:solved, :x, 8}])

    {:ok, uair} =
      Uair.emit(
        Statement.pred(statement),
        Statement.witness(statement),
        Statement.claims(statement)
      )

    assert for({"solved.x", value} <- uair.claims, do: value) ==
             Enum.concat(Enum.take(@solution, 2))

    {:ok, report, _id} = Prover.prove_uair(uair, name: :opened_cells)
    report
  end

  defrel puzzle(
           1,
           [
             [_, _, _, _, _, _, _, _, _],
             [_, _, _, _, _, 3, _, 8, 5],
             [_, _, 1, _, 2, _, _, _, _],
             [_, _, _, 5, _, 7, _, _, _],
             [_, _, 4, _, _, _, 1, _, _],
             [_, 9, _, _, _, _, _, _, _],
             [5, _, _, _, _, _, _, 7, 3],
             [_, _, 2, _, 1, _, _, _, _],
             [_, _, _, _, 4, _, _, _, 9]
           ]
         )

  defrel puzzle(
           2,
           [
             [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16],
             [5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 1, 2, 3, 4],
             [9, 10, 11, 12, 13, 14, 15, 16, 1, 2, 3, 4, 5, 6, 7, 8],
             [13, 14, 15, 16, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
             [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 1],
             [6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 1, 2, 3, 4, 5],
             [10, 11, 12, 13, 14, 15, 16, 1, 2, 3, 4, 5, 6, 7, 8, 9],
             [14, 15, 16, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13],
             [3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 1, 2],
             [7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 1, 2, 3, 4, 5, 6],
             [11, 12, 13, 14, 15, 16, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
             [15, 16, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14],
             [4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 1, 2, 3],
             [8, 9, 10, 11, 12, 13, 14, 15, 16, 1, 2, 3, 4, 5, 6, 7],
             [12, 13, 14, 15, 16, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11],
             [16, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]
           ]
         )

  defrel families(x) do
    column(x, cols)
    each(all_distinct, cols)
    column(cols, rs)
    each(all_distinct, rs)
    boxes(3, x, bs)
    each(all_distinct, bs)
  end

  defrel boxes(n, rows, bs) do
    map(chunk(n), rows, runs)
    chunk(n, runs, bands)
    map(column, bands, stacks)
    map(map(concat), stacks, grouped)
    concat(grouped, bs)
  end

  defrel sudoku(x, blocks) do
    length(x, n)
    n = blocks ** 2
    blocks > 0
    each(each(between(1, n)), x)
    each(all_distinct, x)
    column(x, cols)
    each(all_distinct, cols)
    boxes(blocks, x, bs)
    each(all_distinct, bs)
    each(each(label), x)
  end

  defrel solved(x) do
    puzzle(1, x)
    sudoku(x, 3)
  end

  defrel clued(x) do
    puzzle(1, x)
    families(x)
  end

  defrel families16(x) do
    column(x, cols)
    each(all_distinct, cols)
    column(cols, rs)
    each(all_distinct, rs)
    boxes(4, x, bs)
    each(all_distinct, bs)
  end

  defrel clued16(x) do
    puzzle(2, x)
    families16(x)
  end

  @doc "Every clue reads a named cell; orders nine and sixteen share one selected group apiece."
  @spec clued_selected(9 | 16) :: Uair.t()
  example clued_selected(order \\ 9) do
    {relation, args} = if order == 9, do: {clued(), act()}, else: {clued16(), act16()}

    {:ok, statement, _trace} =
      Pipeline.run(EUser.plain(), %Statement{rels: [relation], args: args})

    {:ok, uair} = Uair.emit(Statement.pred(statement), Statement.witness(statement))

    assert uair.word_lookups == []
    assert uair.mode == %Uair.Plain{}
    assert [%{values: values, selections: selections}] = uair.selected_lookups
    assert values == Enum.to_list(1..order)
    assert length(selections) == 3 * order
    assert Enum.all?(uair.point_ties, &match?(%{target: {:broadcast, _}}, &1))

    if order == 9 do
      assert length(uair.point_ties) == 17
      assert Uair.num_cols(uair) == 30
      assert length(uair.program) == 363
    end

    uair
  end

  @doc "Both grid sizes prove their clues through the selected group."
  @spec clued_proved([9 | 16]) :: [Prover.Report.t()]
  example clued_proved(orders \\ [9, 16]) do
    for order <- orders do
      {:ok, report, _id} = Prover.prove_uair(clued_selected(order), name: :clued)
      report
    end
  end

  @doc "The forty-eight order-sixteen families over the grid's own cells, one selected group."
  @spec families16_proved() :: Prover.Report.t()
  example families16_proved do
    {:ok, statement, _trace} =
      Pipeline.run(EUser.plain(), %Statement{rels: [families16()], args: act16()})

    {:ok, uair} = Uair.emit(Statement.pred(statement), Statement.witness(statement))
    assert uair.word_lookups == []
    assert [%{selections: selections}] = uair.selected_lookups
    assert length(selections) == 48

    {:ok, report, _id} = Prover.prove_uair(uair, name: :families16)
    report
  end

  @doc "Relabelled digits still form a Sudoku; the clue ties alone refuse that grid."
  @spec a_clue_unmet_is_no_proof() :: Refusal.t()
  example a_clue_unmet_is_no_proof do
    uair = clued_selected()
    [%{columns: columns}] = uair.selected_lookups

    unmet =
      for {cells, column} <- Enum.with_index(uair.columns) do
        if column in columns, do: Enum.map(cells, &(10 - &1)), else: cells
      end

    assert {:ok, %Prover.Report{}, _id} =
             Prover.prove_uair(%{uair | columns: unmet, point_ties: []})

    assert {:error, {:verifier_rejected, _said} = refused} =
             Prover.prove_uair(%{uair | columns: unmet}, name: :clue_unmet)

    refused
  end

  @doc "I am the columns of a grid, the bank `column` unifies against it."
  @spec columns([[pos_integer()]]) :: [[pos_integer()]]
  def columns(grid), do: Enum.zip_with(grid, & &1)

  @doc "I am the three by three boxes of a grid, band by band, as `boxes/0` derives them."
  @spec boxed([[pos_integer()]]) :: [[pos_integer()]]
  def boxed(grid),
    do:
      for(
        band <- Enum.chunk_every(grid, 3),
        stack <- 0..2,
        do: Enum.flat_map(band, &Enum.slice(&1, stack * 3, 3))
      )

  @doc "I am the act: the grid the relations check, and the prover's alone."
  @spec act([[pos_integer()]]) :: [[[pos_integer()]]]
  def act(grid \\ @solution), do: [grid]

  @doc "I am the sixteen-by-sixteen act, the completed grid `puzzle(2, …)` names."
  @spec act16() :: [[[pos_integer()]]]
  def act16, do: [@solution16]

  @doc "I am the solution with every digit relabelled, a sudoku again and another grid."
  @spec relabelled() :: [[pos_integer()]]
  def relabelled, do: for(row <- @solution, do: for(v <- row, do: 10 - v))

  @doc "The proof says a grid stands under the clues, and says nothing of which."
  @spec proof() :: Prover.Report.t()
  example proof do
    ran = Zkfol.compile(solved(), args: act())

    assert Enum.take(Zkfol.stream(solved(), act()), 1) == [act()]
    assert %Prover.Report{} = report = Log.report(Log.snapshot(), ran)
    assert report.claims == []
    report
  end

  @doc "Relabelled digits are a sudoku again, and no answer to this puzzle's clues."
  @spec a_clue_unmet_is_no_answer() :: Refusal.t()
  example a_clue_unmet_is_no_answer do
    grid = relabelled()

    assert held?(grid ++ columns(grid) ++ boxed(grid))
    assert {:no_answer, %{relation: :solved}} = refusal = refused(act(grid))
    refusal
  end

  @doc "A swap keeps the row and its box; the columns refuse it at the derivation."
  @spec a_repeated_column_is_no_answer() :: Refusal.t()
  example a_repeated_column_is_no_answer do
    swapped = List.replace_at(@solution, 0, [8, 9, 7, 6, 5, 4, 3, 2, 1])

    assert held?(swapped ++ boxed(swapped))
    refute held?(columns(swapped))
    assert {:no_answer, %{relation: :solved}} = refusal = refused(act(swapped))
    refusal
  end

  @doc "A Latin square with shared boxes: refused over boxes the act never handed in."
  @spec a_shared_box_is_no_answer() :: Refusal.t()
  example a_shared_box_is_no_answer do
    latin = for i <- 0..8, do: for(j <- 0..8, do: rem(i + j, 9) + 1)

    assert held?(latin ++ columns(latin))
    refute held?(boxed(latin))

    {:error, Witness, refusal, []} =
      Pipeline.run(EUser.plain(), %Statement{rels: [sudoku()], args: [latin, 3]})

    assert {:no_answer, %{relation: :sudoku}} = refusal
    refusal
  end

  @doc "The boxes derive from the grid alone, as `boxed/1` says them."
  @spec boxes_derived() :: [[pos_integer()]]
  example boxes_derived do
    [[3, _grid, bs]] = Enum.take(Zkfol.stream(boxes(), [3, @solution, :_]), 1)
    four = [[1, 2, 3, 4], [3, 4, 1, 2], [2, 1, 4, 3], [4, 3, 2, 1]]

    assert bs == boxed(@solution)

    assert Enum.take(Zkfol.stream(boxes(), [2, four, :_]), 1) ==
             [[2, four, [[1, 2, 3, 4], [3, 4, 1, 2], [2, 1, 4, 3], [4, 3, 2, 1]]]]

    bs
  end

  @doc "The peeling transpose is the grid's own cells: the columns handed are tied cell for cell."
  @spec peeled_transpose() :: Prover.Report.t()
  example peeled_transpose do
    heads =
      rel :heads do
        heads([], [], [])

        heads([[h | t] | rs], [h | hs], [t | ts]) do
          heads(rs, hs, ts)
        end
      end

    peeled =
      rel :peeled do
        peeled([[] | _], [])

        peeled(rows, [hs | cs]) do
          heads(rows, hs, rest)
          peeled(rest, cs)
        end
      end

    args = [@solution, :_]
    assert Enum.take(Zkfol.stream([peeled, heads], args), 1) == [[@solution, columns(@solution)]]

    {:ok, statement, _trace} =
      Pipeline.run(EUser.plain(), %Statement{rels: [peeled, heads], args: args})

    banks = Statement.alloc(statement).members

    assert for(%Bank{name: name} <- banks, do: name) == [:"peeled rows", :"peeled a2"]

    {:ok, uair} = Uair.emit(Statement.pred(statement), Statement.witness(statement))
    assert length(uair.point_ties) == 81
    assert uair.selected_lookups == []

    {:ok, report, _id} = Prover.prove_uair(uair, name: :peeled_transpose)
    report
  end

  @spec refused([[[pos_integer()]]]) :: Refusal.t()
  defp refused(args) do
    {:error, Witness, refusal, []} =
      Pipeline.run(EUser.plain(), %Statement{rels: [solved()], args: args})

    refusal
  end

  @spec held?([[pos_integer()]]) :: boolean()
  defp held?(groups), do: Enum.all?(groups, &(Enum.sort(&1) == Enum.to_list(1..9)))
end
