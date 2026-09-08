defmodule Examples.EDoubling do
  @moduledoc "I am the doubling rewrite's evidence: one predicate for every n."

  use ExExample

  import ExUnit.Assertions
  require Zkfol.Lang

  alias Examples.EUser
  alias Zkfol.Ast
  alias Zkfol.Doubling
  alias Zkfol.Interpretation
  alias Zkfol.Lang.Rel
  alias Zkfol.Phi
  alias Zkfol.Pipeline
  alias Zkfol.Prover
  alias Zkfol.Semantics
  alias Zkfol.Statement
  alias Zkfol.Uair

  @mod 7919

  @spec rewritten_fibonacci(pos_integer()) :: Statement.t()
  example rewritten_fibonacci(n \\ 8) do
    {:ok, rewritten, _trace} =
      Pipeline.run(doubling(), %Statement{rels: [EUser.fib()], args: [n]})

    {:ok, statement} = Statement.opened(rewritten, [:r, :e])
    witness = Statement.witness(statement)

    assert claimed(statement) == EUser.fib(n)

    assert Enum.all?(
             1..Interpretation.len(witness),
             &Semantics.holds?(Statement.pred(statement), witness, &1)
           )

    statement
  end

  @doc "I am fibonacci reduced at every step: the source that says what it reduces by."
  @spec fibm_rel(pos_integer()) :: Rel.t()
  def fibm_rel(m \\ @mod) do
    Zkfol.Lang.rel :fibm do
      fibm(1, 1)
      fibm(2, 1)

      fibm(x, v) do
        x > 2
        fibm(x - 1, v1)
        fibm(x - 2, v2)
        v = mod(v1 + v2, ^m)
      end
    end
  end

  @spec rewritten_fibonacci_mod(pos_integer(), pos_integer()) :: Statement.t()
  example rewritten_fibonacci_mod(n \\ 1_000, mod \\ @mod) do
    {:ok, rewritten, _trace} =
      Pipeline.run(doubling(), %Statement{rels: [fibm_rel(mod)], args: [n]})

    {:ok, statement} = Statement.opened(rewritten, [:r, :e])
    witness = Statement.witness(statement)

    assert claimed(statement) == fib_mod(n, mod)

    assert Enum.all?(
             1..Interpretation.len(witness),
             &Semantics.holds?(Statement.pred(statement), witness, &1)
           )

    statement
  end

  @doc "Body order is no contract: the kernel's equations ahead of its calls lower the same."
  @spec either_order_of_the_kernel() :: Ast.pred()
  example either_order_of_the_kernel do
    [kernel] = rewritten_fibonacci().rels
    ahead = %{kernel | clauses: for({head, body} <- kernel.clauses, do: {head, equations(body)})}

    assert ahead.clauses != kernel.clauses
    assert {:ok, phi} = Phi.lower(kernel, [kernel])
    assert Phi.lower(ahead, [ahead]) == {:ok, phi}
    phi
  end

  @spec equations([Zkfol.Lang.Term.goal()]) :: [Zkfol.Lang.Term.goal()]
  defp equations(body), do: Enum.sort_by(body, &(elem(&1, 0) != :eq))

  @spec one_predicate_for_every_n() :: Ast.pred()
  example one_predicate_for_every_n do
    small = rewritten_fibonacci(100)
    large = rewritten_fibonacci(10_000)

    assert Statement.pred(small) == Statement.pred(large)
    assert Interpretation.len(Statement.witness(small)) == 7
    assert Interpretation.len(Statement.witness(large)) == 14
    Statement.pred(small)
  end

  @spec a_free_count_passes_the_try() :: Statement.t()
  example a_free_count_passes_the_try do
    # No kernel walk exists for an unknown n, so the try declines and
    # the plain relation solves backward through the front door.
    source = %Statement{rels: [EUser.fib()], args: [:_, 21]}

    {:ok, statement, _trace} = Pipeline.run(Pipeline.default(), source)
    witness = Statement.witness(statement)

    assert Interpretation.len(witness) == 8
    assert Interpretation.at(witness, 1, 8) == 21
    statement
  end

  @spec unclaimed_position_keeps_n_private() :: map()
  example unclaimed_position_keeps_n_private do
    source = %Statement{rels: [EUser.fib()], args: [100]}

    {:ok, rewritten, _trace} = Pipeline.run(doubling(), source)
    {:ok, statement} = Statement.opened(rewritten, [:r])

    {:ok, uair} =
      Uair.emit(
        Statement.pred(statement),
        Statement.witness(statement),
        Statement.claims(statement)
      )

    assert uair.num_public == 2
    {:ok, report, _id} = Prover.prove_uair(uair, name: :private_n)
    assert [{_result, value}, {"in", 1}] = report.claims
    assert value == EUser.fib(100)
    report
  end

  @spec doubling() :: Pipeline.t()
  defp doubling, do: %Pipeline{passes: [{Doubling, []}]}

  @doc "I am the comparator loop: the recurrence stepped n times, reduced at every step."
  @spec fib_mod(pos_integer(), pos_integer()) :: non_neg_integer()
  def fib_mod(n, mod \\ @mod) do
    {value, _next} = Enum.reduce(1..n, {0, 1}, fn _, {a, b} -> {b, rem(a + b, mod)} end)
    value
  end

  @doc "I read the claimed result out of a rewritten statement's witness: the head claim."
  @spec claimed(Statement.t()) :: integer()
  def claimed(%Statement{} = statement) do
    [{_name, row, column} | _rest] = Statement.claims(statement)
    Interpretation.at(Statement.witness(statement), row, column)
  end
end
