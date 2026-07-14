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
  length, and the claims change. The witness derives from the bits as
  seeds through the generating semantics.

  Rows: 1 and 2 the kernel pair, 3 the pointer, 4 the result, 5 the
  bit, 6 the position walked so far, ending at m - 2, which is what
  the position claim carries. Leaving the position unclaimed
  (`private: true`) keeps n secret up to its bit length: the trace
  length stays public. Positions at the base cases become a single
  pinned column.

  ### Public API

  - `rewrite/1`, `rewrite/3`
  - `seeds/2`
  """

  alias Zkfol.Ast
  alias Zkfol.Facts
  alias Zkfol.Range
  alias Zkfol.Statement
  alias Zkfol.Witness

  @claim "claim_recurrence_n_exact"
  @position "claim_recurrence_position"
  @result_row 4
  @bit_row 5
  @walked_row 6

  @doc "I am the kernel alone: no n, the witness slot empty, the claims to come."
  @spec rewrite(Ast.pred()) :: {:ok, Statement.t()} | {:error, String.t()}
  def rewrite(pred) do
    with {:ok, descriptor} <- Facts.recurrence(pred) do
      {:ok, %Statement{pred: kernel(descriptor), ranges: Range.pointer(3)}}
    end
  end

  @doc "I rewrite `pred`'s claim about position `n`, or refuse with the facts' reason."
  @spec rewrite(Ast.pred(), integer(), keyword()) ::
          {:ok, Statement.t()} | {:error, String.t()}
  def rewrite(pred, n, opts \\ []) do
    with {:ok, descriptor} <- Facts.recurrence(pred) do
      [{start, x1}, {_, x2}] = descriptor.initial

      case n - start + 1 do
        m when m < 1 -> {:error, "n=#{n} precedes the base case index #{start}"}
        1 -> trivial(x1)
        2 -> trivial(x2)
        m -> build(descriptor, m, Keyword.get(opts, :private, false))
      end
    end
  end

  @doc "I am the goal as seeds: the trace length and the bits walking to position `n`."
  @spec seeds(Ast.pred(), integer()) ::
          {:ok, pos_integer(), Witness.seeds()} | {:error, String.t()}
  def seeds(pred, n) do
    with {:ok, %Facts{initial: [{start, _value} | _rest]}} <- Facts.recurrence(pred) do
      {count, seeds} = goal(n - start + 1)
      {:ok, count, seeds}
    end
  end

  @spec trivial(integer()) :: {:ok, Statement.t()} | {:error, String.t()}
  defp trivial(value) do
    pred = Ast.conj([Ast.eq(Ast.x(), 1), Ast.eq(Ast.cell(@result_row), value)])

    with {:ok, witness} <- Witness.generate(pred, 1),
         do: {:ok, %Statement{pred: pred, witness: witness, claims: [{@claim, @result_row, 1}]}}
  end

  @spec build(Facts.t(), pos_integer(), boolean()) ::
          {:ok, Statement.t()} | {:error, String.t()}
  defp build(descriptor, m, private) do
    {count, seeds} = goal(m)
    pred = kernel(descriptor)

    claims =
      [{@claim, @result_row, count}] ++
        if(private, do: [], else: [{@position, @walked_row, count}])

    with {:ok, witness} <- Witness.generate(pred, count, seeds),
         do:
           {:ok,
            %Statement{pred: pred, ranges: Range.pointer(3), witness: witness, claims: claims}}
  end

  @spec goal(pos_integer()) :: {pos_integer(), Witness.seeds()}
  defp goal(m) do
    bits = bits_after_leading(m - 2)
    seeds = for {bit, x} <- Enum.with_index(bits, 2), into: %{}, do: {{@bit_row, x}, bit}
    {length(bits) + 1, seeds}
  end

  @spec bits_after_leading(pos_integer()) :: [0 | 1]
  defp bits_after_leading(k), do: k |> Integer.digits(2) |> tl()

  # One branch pins the base, two interpret a bit. The pointer binds
  # itself to X, declaring its schedule; the result rides every branch.
  @spec kernel(Facts.t()) :: Ast.pred()
  defp kernel(%Facts{p: p, q: q, initial: [{_, x1}, {_, x2}]}) do
    a = Ast.cell(1, 3)
    b = Ast.cell(2, 3)
    doubled = Ast.mul(a, Ast.add(Ast.mul(2, b), Ast.mul(-p, a)))
    squares = Ast.add(Ast.mul(q, Ast.mul(a, a)), Ast.mul(b, b))

    result =
      Ast.eq(
        Ast.cell(@result_row),
        Ast.add(Ast.mul(x2, Ast.cell(2)), Ast.mul(q * x1, Ast.cell(1)))
      )

    pointed = Ast.eq(Ast.cell(3), Ast.add(Ast.x(), -1))

    walked =
      Ast.eq(
        Ast.cell(@walked_row),
        Ast.add(Ast.mul(2, Ast.cell(@walked_row, 3)), Ast.cell(@bit_row))
      )

    base = [
      Ast.eq(Ast.x(), 1),
      Ast.eq(Ast.cell(1), 1),
      Ast.eq(Ast.cell(2), p),
      Ast.eq(Ast.cell(@walked_row), 1)
    ]

    steps =
      for bit <- [0, 1] do
        pair =
          case bit do
            0 ->
              [Ast.eq(Ast.cell(1), doubled), Ast.eq(Ast.cell(2), squares)]

            1 ->
              [
                Ast.eq(Ast.cell(1), squares),
                Ast.eq(Ast.cell(2), Ast.add(Ast.mul(p, Ast.cell(1)), Ast.mul(q, doubled)))
              ]
          end

        [Ast.eq(Ast.cell(@bit_row), bit), pointed, walked | pair]
      end

    Ast.disj(for parts <- [base | steps], do: Ast.conj(parts ++ [result]))
  end
end
