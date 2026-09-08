defmodule Examples.EFol do
  @moduledoc "I am the standard relations' evidence: a program leans on them by name."

  use ExExample
  use Zkfol.Lang

  import ExUnit.Assertions

  alias Examples.ESudoku
  alias Examples.EUser
  alias Zkfol.Alloc
  alias Zkfol.FOL
  alias Zkfol.Phi
  alias Zkfol.Pipeline
  alias Zkfol.Prover
  alias Zkfol.Refusal
  alias Zkfol.Statement
  alias Zkfol.Uair
  alias Zkfol.Witness

  defrel counted(xs) do
    length(xs, n)
    each(between(1, n), xs)
  end

  defrel joined(zs) do
    append([1, 2], [3], zs)
  end

  defrel columns_apart(x) do
    column(x, cols)
    each(all_distinct, cols)
  end

  defrel literal_columns(cs) do
    column([[1, 2], [3, 4]], cs)
  end

  defrel there_and_back(x) do
    column(x, cs)
    column(cs, back)
    each(all_distinct, back)
  end

  defrel rising([_last])

  defrel rising([a, b | t]) do
    a < b
    rising([b | t])
  end

  @spec ranged() :: Statement.t()
  example ranged do
    plain = %Pipeline{passes: [{Witness, []}, {Phi, []}]}

    {:ok, statement, _trace} =
      Pipeline.run(plain, %Statement{rels: [counted()], args: [[3, 1, 2]]})

    assert Zkfol.Semantics.valid?(Statement.pred(statement), Statement.witness(statement))
    statement
  end

  @spec concatenation() :: Statement.t()
  example concatenation do
    assert Enum.take(Zkfol.stream(joined(), [:_]), 1) == [[[1, 2, 3]]]

    plain = %Pipeline{passes: [{Witness, []}, {Phi, []}]}
    {:ok, statement, _trace} = Pipeline.run(plain, %Statement{rels: [joined()], args: [:_]})
    statement
  end

  @doc "The transpose is one relation over any list of lists, with one answer."
  @spec transpose() :: [[pos_integer()]]
  example transpose do
    grid = [[1, 2, 3], [4, 5, 6]]
    cols = ESudoku.columns(grid)

    assert Enum.take(Zkfol.stream(FOL.column(), [grid, :_]), 2) == [[grid, cols]]
    cols
  end

  @doc "A row of the bank is a column of the grid, so the transpose lays no bank of its own."
  @spec transposed_columns() :: Statement.t()
  example transposed_columns do
    {:ok, statement, _trace} =
      Pipeline.run(EUser.plain(), %Statement{rels: [columns_apart()], args: [hd(ESudoku.act())]})

    assert Alloc.regions(Statement.alloc(statement)) == ["columns_apart x": 9, in: 2]
    statement
  end

  @doc "Nine groups over the bank's rows are nine selections, and no Word table."
  @spec looked_up_columns() :: Uair.t()
  example looked_up_columns do
    statement = transposed_columns()
    {:ok, uair} = Uair.emit(Statement.pred(statement), Statement.witness(statement))

    assert [%{values: values, selections: selections}] = uair.selected_lookups
    assert values == Enum.to_list(1..9)
    assert length(selections) == 9
    assert uair.word_lookups == []
    uair
  end

  @doc "The nine lookups are the proof, and they verify."
  @spec columns_proved() :: Prover.Report.t()
  example columns_proved do
    {:ok, report, _id} = Prover.prove_uair(looked_up_columns(), name: :columns_apart)
    report
  end

  @doc "An index into a bank opens the nine values at that column; the groups stay private."
  @spec opened_column() :: Prover.Report.t()
  example opened_column do
    {:ok, statement} = Statement.opened(transposed_columns(), [{:columns_apart, :x, 9}])
    claims = Statement.claims(statement)

    {:ok, uair} = Uair.emit(Statement.pred(statement), Statement.witness(statement), claims)

    assert for({"columns_apart.x", value} <- uair.claims, do: value) ==
             hd(hd(ESudoku.act()))

    [%{columns: columns, selections: selections}] = uair.selected_lookups
    assert Enum.all?(columns, &(&1 >= uair.num_public))
    assert length(selections) == 9

    {:ok, report, _id} = Prover.prove_uair(uair, name: :opened_column)
    report
  end

  @doc "The lookup is the whole claim: a repeated value is refused by the verifier alone."
  @spec a_repeated_column_is_no_proof() :: Refusal.t()
  example a_repeated_column_is_no_proof do
    uair = looked_up_columns()
    repeated = List.update_at(uair.columns, 0, &List.replace_at(&1, 1, hd(&1)))

    assert {:error, {:verifier_rejected, _said} = refused} =
             Prover.prove_uair(%{uair | columns: repeated}, name: :repeated_column)

    refused
  end

  @doc "A reading is cells like any other, so a call handed one reads it again, laying nothing."
  @spec chained_columns() :: Statement.t()
  example chained_columns do
    {:ok, statement, _trace} =
      Pipeline.run(EUser.plain(), %Statement{rels: [there_and_back()], args: [hd(ESudoku.act())]})

    assert Alloc.regions(Statement.alloc(statement)) == ["there_and_back x": 9, in: 2]
    refute :column in Alloc.names(Statement.alloc(statement))
    statement
  end

  @doc "A relation reading a cell's value is no rearrangement: `rising` and its bank are laid."
  @spec a_read_value_is_laid() :: [atom()]
  example a_read_value_is_laid do
    {:ok, statement, _trace} =
      Pipeline.run(EUser.plain(), %Statement{rels: [rising()], args: [[1, 2, 3]]})

    names = Alloc.names(Statement.alloc(statement))

    assert :rising in names
    assert :"rising a1" in names
    names
  end

  @doc "Concrete data is read, not walked: only the root stands."
  @spec laid_transpose() :: [atom()]
  example laid_transpose do
    {:ok, _pred, alloc} = Phi.compile(literal_columns(), [literal_columns()], [:_])

    assert Alloc.names(alloc) == [:literal_columns]
    refute :column in Alloc.names(alloc)
    Alloc.names(alloc)
  end
end
