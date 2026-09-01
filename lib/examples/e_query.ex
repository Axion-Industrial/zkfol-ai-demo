defmodule Examples.EQuery do
  @moduledoc "I am the query door open: answers stepped one at a time."

  use ExExample
  use Zkfol.Lang

  import ExUnit.Assertions

  alias Examples.EAl
  alias Examples.EUser
  alias Zkfol.Query
  alias Zkfol.Refusal

  # A fact that names a value it does not fix: the row stays open.
  defrel loose(1, v)

  # A relation whose clauses name len: the flag is the squared gap to
  # the end, so the count has to be there before the first answer is.
  defrel gap(1, v) do
    v = reify(1 = len)
  end

  defrel gap(x, v) do
    x > 1
    gap(x - 1, _w)
    v = reify(x = len)
  end

  @doc "A relation handed alone brings its scope; a name no home answers refuses."
  @spec a_lone_relation_brings_its_scope() :: Refusal.t()
  example a_lone_relation_brings_its_scope do
    query = Zkfol.eval!(EAl.hop_rel(), [2, :_], [])
    assert Query.taken(query) == [[2, 2]]
    Query.close(query)

    stray =
      Zkfol.Lang.rel :stray do
        stray(x) do
          nowhere(x)
        end
      end

    {:error, reason} = Zkfol.eval(stray, [1], [])
    assert {:relation_not_in_scope, %{relation: :nowhere}} = reason
    reason
  end

  @doc "Closed, what a query posted is gone from its branch and the branch is not."
  @spec a_query_exhausts_then_closes() :: Zkfol.Query.t()
  example a_query_exhausts_then_closes do
    {:ok, query} = Query.open(EAl.tab(), [:_, :_], [])
    branch = query.ask.branch
    assert answers?(branch)

    assert Enum.map(1..4, fn _ -> Query.next(query) end) ==
             [{:ok, [1, 10]}, {:ok, [2, 20]}, {:ok, [3, 40]}, {:ok, [4, 40]}]

    assert Query.next(query) == :exhausted
    assert Query.statement(query, 10) == nil

    assert Query.close(query) == :ok
    assert Query.close(query) == :ok
    refute Process.alive?(query.pid)
    refute answers?(branch)
    assert branch in [AL.Branch.main() | AL.Branch.list()]
    query
  end

  @spec answers?(AL.Branch.t()) :: boolean()
  defp answers?(branch) do
    goal = [AL.ast_to_pattern(quote(do: tab(:zkfol, _x, _v)))]
    match?({:atomic, _answer}, AL.eval(goal, nil, branch, []))
  end

  @doc "An answer is every asked row ground; a row left open is residue, not an answer."
  @spec an_open_row_is_residue() :: Refusal.t()
  example an_open_row_is_residue do
    {:ok, query} = Query.open(loose(), [:_, :_], [])
    {:error, reason} = Query.next(query)
    Query.close(query)

    assert {:residue, %{answer: [1, open]}} = reason
    refute is_integer(open)
    reason
  end

  @doc "len names the trace, which only a bound count sizes: a free count refuses."
  @spec a_len_query_wants_its_count() :: Refusal.t()
  example a_len_query_wants_its_count do
    assert {:error, reason} = Query.open(gap(), [:_, :_], [])
    assert reason == {:len_needs_a_bound_count, %{}}

    {:ok, query} = Query.open(gap(), [5, :_], [])
    assert Query.next(query) == {:ok, [5, 0]}
    Query.close(query)
    reason
  end

  @doc "An answer is a statement: statement(k) steps forward to it and hands it back."
  @spec an_answer_is_a_statement() :: Zkfol.Statement.t()
  example an_answer_is_a_statement do
    query = Zkfol.eval!(EUser.fib(), [:_, :_])
    statement = Query.statement(query, 10)
    Query.close(query)

    assert statement.args == [10, 55]
    statement
  end

  @doc "The line at the keyboard: an answer taken is a statement, and the front door proves it."
  @spec an_answer_compiles() :: Zkfol.Log.Ran.t()
  example an_answer_compiles do
    ran = Zkfol.eval!(EUser.fib(), [8, :_], []) |> Query.statement() |> Zkfol.compile()

    assert %Zkfol.Prover.Report{claims: []} = Zkfol.Log.report(Zkfol.Log.snapshot(), ran)
    assert {:ok, %Zkfol.Statement{args: [8, 21]}} = Zkfol.Log.Ran.stage(ran, 0)
    ran
  end

  @doc "Every example here holds a process or a branch: nothing about it caches."
  @spec rerun?(term()) :: boolean()
  def rerun?(_example), do: true
end
