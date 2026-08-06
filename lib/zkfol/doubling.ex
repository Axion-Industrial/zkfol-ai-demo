defmodule Zkfol.Doubling do
  @moduledoc """
  I am the doubling rewrite: a statement-to-statement morphism at claim
  equivalence. Given a predicate that Zkfol.Facts certifies as an
  order-2 constant-coefficient recurrence, I replace its length-n index
  ladder with a walk over the bits of the position, using the kernel
  pair U (U(1) = 1, U(2) = p):

      U(2e)   = U(e) · (2·U(e+1) − p·U(e))
      U(2e+1) = q·U(e)² + U(e+1)²
      x(n)    = x₂·U(m−1) + q·x₁·U(m−2)    at position m = n − start + 1

  The bits ride a committed row, one bit-guarded branch pair interprets
  them, and the result row carries the combination at every column, so
  the predicate is one statement for every n: only the witness, the
  length, and the claims change. The witness is derived: the walked
  position, bound to the goal, descends and the bits fall out.

  Rows of kernel(x, u, w, e, r): 1 the index, 2 and 3 the kernel
  pair, 4 the position walked so far, ending at m - 2, which is what
  the position claim carries, 5 the result, 6 the pointer; the walked
  bit rides the walk inline, no row of its own. Leaving the position
  unclaimed
  (`private: true`) keeps n secret up to its bit length: the trace
  length stays public. Positions at the base cases become a single
  pinned column.
  """

  @behaviour Zkfol.Pipeline

  alias Zkfol.Al
  alias Zkfol.Facts
  require Zkfol.Lang
  alias Zkfol.Lang.Rel
  alias Zkfol.Refusal
  alias Zkfol.Statement

  @claim "claim_recurrence_n_exact"
  @position "claim_recurrence_position"

  @doc """
  I am the rewrite as a pass, and always a try: statements the facts
  do not certify, or carrying no integer to claim. A free count runs
  backward
  """
  @impl Zkfol.Pipeline
  @spec run(Statement.t(), keyword()) :: {:ok, Statement.t()} | {:error, Refusal.t()}
  def run(%Statement{rels: [root | _rest], args: [n | _args]} = statement, opts)
      when is_integer(n) do
    case Facts.recurrence(root) do
      {:error, _outside} -> {:ok, statement}
      {:ok, descriptor} -> rewritten(descriptor, n, named(statement, opts))
    end
  end

  def run(statement, _opts), do: {:ok, statement}

  @impl Zkfol.Pipeline
  @spec verb() :: Zkfol.Pipeline.verdict()
  def verb, do: :rewrites

  @doc "I rewrite `rel`'s claim about position `n`, or refuse with the facts' reason."
  @spec rewrite(Zkfol.Lang.Rel.t(), integer(), keyword()) ::
          {:ok, Statement.t()} | {:error, Refusal.t()}
  def rewrite(rel, n, opts \\ []) do
    with {:ok, descriptor} <- Facts.recurrence(rel), do: rewritten(descriptor, n, opts)
  end

  @spec rewritten(Facts.t(), integer(), keyword()) ::
          {:ok, Statement.t()} | {:error, Refusal.t()}
  defp rewritten(descriptor, n, opts) do
    [{start, x1}, {_, x2}] = descriptor.initial

    case n - start + 1 do
      m when m < 1 ->
        {:error, {:precedes_base_case, %{n: n, base: start}}}

      1 ->
        trivial(x1, opts)

      2 ->
        trivial(x2, opts)

      m ->
        build(
          descriptor,
          m,
          Keyword.get(opts, :private, false),
          Keyword.take(opts, [:branch, :heap, :name, :basedon])
        )
    end
  end

  # The kernel walks beside the relation it doubles, named after it;
  # one new atom per relation, bounded by the program.
  defp named(%Statement{rels: [root | _rest]}, opts),
    do: Keyword.put_new(opts, :name, :"#{root.name}_kernel")

  defp named(_statement, opts), do: opts

  @spec trivial(integer(), keyword()) :: {:ok, Statement.t()} | {:error, Refusal.t()}
  defp trivial(value, opts) do
    one =
      Zkfol.Lang.rel :one do
        one(1, ^value)
      end

    with {:ok, shape} <- Zkfol.Lang.compile(one, [one]),
         {:ok, pred} <- Zkfol.Alloc.link(shape.pred, Zkfol.Alloc.assign(shape)),
         {:ok, witness} <- Al.solve(one, [1], Keyword.take(opts, [:branch, :heap, :basedon])),
         do:
           {:ok,
            %Statement{
              rels: [one],
              claims: [{@claim, 2, 1}],
              stage: %Statement.Solved{pred: pred, witness: witness}
            }}
  end

  @spec build(Facts.t(), pos_integer(), boolean(), keyword()) ::
          {:ok, Statement.t()} | {:error, Refusal.t()}
  defp build(descriptor, m, private, solve_opts) do
    count = count(m)
    krel = kernel(descriptor)

    with {:ok, shape} <- Zkfol.Lang.compile(krel, [krel]),
         alloc = Zkfol.Alloc.assign(shape),
         {:ok, pred} <- Zkfol.Alloc.link(shape.pred, alloc),
         [_x, _u, _w, walked, result] = Enum.to_list(Zkfol.Alloc.rows(alloc, :kernel)) do
      claims =
        [{@claim, result, count}] ++
          if(private, do: [], else: [{@position, walked, count}])

      with {:ok, witness} <- Al.solve(krel, [count], [bind: %{walked => m - 2}] ++ solve_opts),
           do:
             {:ok,
              %Statement{
                rels: [krel],
                claims: claims,
                stage: %Statement.Solved{pred: pred, witness: witness}
              }}
    end
  end

  @spec count(pos_integer()) :: pos_integer()
  defp count(m), do: (m - 2) |> Integer.digits(2) |> length()

  # The kernel is itself a relation: one base fact, two step clauses
  # interpreting a bit, the result riding every clause.
  @spec kernel(Facts.t()) :: Rel.t()
  defp kernel(%Facts{p: p, q: q, initial: [{_, x1}, {_, x2}]}) do
    Zkfol.Lang.rel :kernel do
      kernel(1, 1, ^p, 1, ^(x2 * p + q * x1))

      kernel(x, u, w, e, r) do
        x > 1
        kernel(x - 1, uu, ww, ee, _rr)
        e = 2 * ee + 0
        u = uu * (2 * ww + ^(-p) * uu)
        w = ^q * (uu * uu) + ww * ww
        r = ^x2 * w + ^(q * x1) * u
      end

      kernel(x, u, w, e, r) do
        x > 1
        kernel(x - 1, uu, ww, ee, _rr)
        e = 2 * ee + 1
        u = ^q * (uu * uu) + ww * ww
        w = ^p * u + ^q * (uu * (2 * ww + ^(-p) * uu))
        r = ^x2 * w + ^(q * x1) * u
      end
    end
  end
end
