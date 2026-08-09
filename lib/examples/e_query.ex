defmodule Examples.EQuery do
  @moduledoc """
  I am the query door open: one answer through `Zkfol.eval/3`, every
  answer through a `Zkfol.Query` stepped one at a time, and the same
  answers lazily as `Zkfol.stream/3`. The query is a process because
  AL's search state is the whole continuation and must not be copied;
  what crosses the boundary is a ground answer and nothing else.
  """

  use ExExample
  use Zkfol.Lang

  import ExUnit.Assertions

  alias Examples.EAl
  alias Examples.EUser
  alias Zkfol.Al
  alias Zkfol.Query
  alias Zkfol.Refusal

  # A fact that names a value it does not fix: the row stays open.
  defrel loose(1, v)

  @doc "Every answer of a finite relation, in the order its clauses stand."
  @spec table_streams_every_answer() :: [[pos_integer()]]
  example table_streams_every_answer do
    answers = Zkfol.stream(EAl.tab(), [:_, :_], []) |> Enum.to_list()

    assert answers == [[1, 10], [2, 20], [3, 40], [4, 40]]

    {:ok, applied} = Al.apply(EAl.tab(), [:x, :v], upto: 4)
    assert Enum.map(applied, &[&1.x, &1.v]) == answers
    answers
  end

  @doc "Answer one and answer two are different answers, and only two are taken."
  @spec two_answers_differ() :: [[pos_integer()]]
  example two_answers_differ do
    [first, second] = Zkfol.stream(EUser.fib(), [:_, :_], []) |> Enum.take(2)

    assert first == [1, EUser.fib(1)]
    assert second == [2, EUser.fib(2)]
    assert first != second
    [first, second]
  end

  @doc """
  A query stepped past its last answer is exhausted, closing it twice
  is closing it once, and the branch it forked goes with it.
  """
  @spec a_query_exhausts_then_closes() :: Zkfol.Query.t()
  example a_query_exhausts_then_closes do
    {:ok, query} = Query.open(EAl.tab(), [:_, :_], [])

    assert Enum.map(1..4, fn _ -> Query.next(query) end) ==
             [{:ok, [1, 10]}, {:ok, [2, 20]}, {:ok, [3, 40]}, {:ok, [4, 40]}]

    assert Query.next(query) == :exhausted

    assert Query.close(query) == :ok
    assert Query.close(query) == :ok
    refute Process.alive?(query.pid)
    refute Enum.any?(AL.Branch.list(), &(&1.id == query.branch.id))
    query
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

  @doc """
  An answer fills a prove: statement(k) steps forward to the answer
  and hands it back ready for the route, here the eval-shaped one, no
  doubling. A search that ends before k answers nil.
  """
  @spec an_answer_fills_a_prove() :: Zkfol.Log.Ran.t()
  example an_answer_fills_a_prove do
    query = Zkfol.eval!(EUser.fib(), [:_, :_])
    statement = Query.statement(query, 10)
    Query.close(query)

    assert statement.args == [10, 55]

    ran =
      Zkfol.compile(statement,
        name: :answered_fib,
        pipeline: %Zkfol.Pipeline{passes: [{Zkfol.Witness, []}, {Zkfol.Lang, []}]}
      )

    assert %Zkfol.Prover.Report{} = Zkfol.Log.report(Zkfol.Log.snapshot(), ran)

    finite = Zkfol.eval!(EAl.tab(), [:_, :_])
    assert Query.statement(finite, 10) == nil
    Query.close(finite)
    ran
  end

  @doc "The cap is the query's own: the derivation that outgrows it kills the query, not its caller."
  @spec a_capped_query_refuses(pos_integer()) :: Refusal.t()
  example a_capped_query_refuses(heap \\ 100_000) do
    {:ok, query} = Query.open(EUser.epower(), [:_, 10, :_], heap: heap)
    {:error, reason} = Query.next(query)

    assert {:heap_exhausted, _said} = reason
    refute Process.alive?(query.pid)
    refute Enum.any?(AL.Branch.list(), &(&1.id == query.branch.id))
    reason
  end

  @doc "Every example here holds a process or a branch: nothing about it caches."
  @spec rerun?(term()) :: boolean()
  def rerun?(_example), do: true
end
