defmodule Zkfol.Doubling do
  @moduledoc """
  I am the doubling rewrite: an order-2 recurrence's length-n index ladder becomes a walk
  over the bits of the position, on the kernel pair U (U(1) = 1, U(2) = p):

      U(2e)   = U(e) · (2·U(e+1) − p·U(e))
      U(2e+1) = q·U(e)² + U(e+1)²
      x(n)    = x₂·U(m−1) + q·x₁·U(m−2)    at position m = n − start + 1
  """

  @behaviour Zkfol.Pipeline

  alias Zkfol.Al
  alias Zkfol.Facts
  require Zkfol.Lang
  alias Zkfol.Lang.Rel
  alias Zkfol.Refusal
  alias Zkfol.Statement

  @doc "I am the rewrite as a pass, always a try: an uncertified statement passes through."
  @impl Zkfol.Pipeline
  @spec run(Statement.t(), keyword()) :: {:ok, Statement.t()} | {:error, Refusal.t()}
  def run(statement = %Statement{rels: [root | _rest], args: [n | _args]}, opts)
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

  @spec rewritten(Facts.t(), integer(), keyword()) ::
          {:ok, Statement.t()} | {:error, Refusal.t()}
  defp rewritten(descriptor = %Facts{initial: [{start, x1}, {_, x2}], mod: mod}, n, opts) do
    case n - start + 1 do
      m when m < 1 ->
        {:error, {:precedes_base_case, %{n: n, base: start}}}

      1 ->
        trivial(reduced(x1, mod), opts)

      2 ->
        trivial(reduced(x2, mod), opts)

      m ->
        build(descriptor, m, Keyword.take(opts, [:branch, :heap, :name, :basedon]))
    end
  end

  @spec reduced(integer(), pos_integer() | nil) :: integer()
  defp reduced(value, nil), do: value
  defp reduced(value, mod), do: rem(value, mod)

  # One new atom per relation, bounded by the program.
  defp named(%Statement{rels: [root | _rest]}, opts),
    do: Keyword.put_new(opts, :name, :"#{root.name}_kernel")

  defp named(_statement, opts), do: opts

  @spec trivial(integer(), keyword()) :: {:ok, Statement.t()} | {:error, Refusal.t()}
  defp trivial(value, opts) do
    one =
      Zkfol.Lang.rel :one do
        one(1, ^value)
      end

    with {:ok, solved} <- solved(one, [1], Keyword.take(opts, [:branch, :heap, :basedon])),
         do: {:ok, %Statement{rels: [one], stage: solved}}
  end

  @spec build(Facts.t(), pos_integer(), keyword()) ::
          {:ok, Statement.t()} | {:error, Refusal.t()}
  defp build(descriptor, m, solve_opts) do
    statement = %Statement{rels: [kernel(descriptor)]}
    derived(statement, m, solve_opts)
  end

  @spec derived(Statement.t(), pos_integer(), keyword()) ::
          {:ok, Statement.t()} | {:error, Refusal.t()}
  defp derived(statement = %Statement{rels: rels}, m, solve_opts) do
    with {:ok, solved} <- solved(rels, [count(m), :_, :_, m - 2], solve_opts),
         do: {:ok, %{statement | stage: solved}}
  end

  # A statement derived and laid: the two passes the rewrite runs on what it builds.
  @spec solved([Rel.t()] | Rel.t(), [Statement.datum() | :_], keyword()) ::
          {:ok, Statement.Solved.t()} | {:error, Refusal.t()}
  defp solved(rels, arguments, opts) do
    statement = Statement.of(rels)

    with {:ok, derivation} <- Al.derived(statement, arguments, opts),
         {:ok, laid} <- Zkfol.Phi.relaid(statement, derivation),
         do: {:ok, laid.stage}
  end

  @spec base(Facts.t()) :: [integer()]
  defp base(%Facts{p: p, q: q, initial: [{_, x1}, {_, x2}], mod: mod}),
    do: [1, rem(1, mod), rem(p, mod), 1, rem(x2 * p + q * x1, mod)]

  @spec count(pos_integer()) :: pos_integer()
  defp count(m), do: (m - 2) |> Integer.digits(2) |> length()

  @spec kernel(Facts.t()) :: Rel.t()
  defp kernel(%Facts{p: p, q: q, initial: [{_, x1}, {_, x2}], mod: nil}) do
    Zkfol.Lang.rel :kernel do
      kernel(1, 1, ^p, 1, ^(x2 * p + q * x1))

      kernel(x, u, w, e, r) do
        x > 1
        e = 2 * ee + 0
        r = ^x2 * w + ^(q * x1) * u
        kernel(x - 1, uu, ww, ee, _rr)
        u = uu * (2 * ww + ^(-p) * uu)
        w = ^q * (uu * uu) + ww * ww
      end

      kernel(x, u, w, e, r) do
        x > 1
        e = 2 * ee + 1
        r = ^x2 * w + ^(q * x1) * u
        kernel(x - 1, uu, ww, ee, _rr)
        u = ^q * (uu * uu) + ww * ww
        w = ^p * u + ^q * (uu * (2 * ww + ^(-p) * uu))
      end
    end
  end

  # `p * mod` rides the subtraction so every committed value is a natural.
  defp kernel(descriptor = %Facts{p: p, q: q, initial: [{_, x1}, {_, x2}], mod: mod}) do
    [_x, u0, w0, _e, r0] = base(descriptor)

    Zkfol.Lang.rel :kernel do
      kernel(1, ^u0, ^w0, 1, ^r0)

      kernel(x, u, w, e, r) do
        x > 1
        e = 2 * ee + 0
        kernel(x - 1, uu, ww, ee, _rr)
        u = mod(uu * (2 * ww + ^(p * mod) + ^(-p) * uu), ^mod)
        w = mod(^q * (uu * uu) + ww * ww, ^mod)
        r = mod(^x2 * w + ^(q * x1) * u, ^mod)
      end

      kernel(x, u, w, e, r) do
        x > 1
        e = 2 * ee + 1
        kernel(x - 1, uu, ww, ee, _rr)
        u = mod(^q * (uu * uu) + ww * ww, ^mod)
        w = mod(^p * u + ^q * (uu * (2 * ww + ^(p * mod) + ^(-p) * uu)), ^mod)
        r = mod(^x2 * w + ^(q * x1) * u, ^mod)
      end
    end
  end
end
