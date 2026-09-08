defmodule Zkfol.Ast do
  @moduledoc """
  I am the syntax of the logic: Figure 1 of the paper, as data.

      t   ::= q | t + t | t * t | len(C) | reify(phi) | X | C_i(X) | C_i(C_j(X))
      phi ::= t = t | phi and phi | phi or phi | natural(t)
      e   ::= q | e + e | e * e | len(C) | X | C_i(X) | C_i(C_j(X))

  Integers denote themselves. `t:term_t/0` and `t:pred/0` are the grammar;
  the constructors below build well-formed nodes. `e` is the reify-free
  subsyntax: Figure 2's enriched polynomials, `t:ep/0`, of which terms
  are the reify-closure. `natural(t)` extends Figure 1: it has no
  polynomial, and discharges by lookup, so `Zkfol.Uair` lifts it out of
  the predicate before arithmetizing.
  """

  @typedoc """
  A polynomial over some leaf: what `add/2` and `mul/2` build, whatever the
  leaf is. The algebra only ever special-cases integers, so the same two
  constructors serve Figure 1's terms, Figure 2's polynomials, and any
  lowering that carries its own leaves.
  """
  @type poly(leaf) ::
          leaf
          | integer()
          | {:add, poly(leaf), poly(leaf)}
          | {:mul, poly(leaf), poly(leaf)}

  @typedoc "A row reference: a bare row post-link, or {symbol, row} before Alloc links it."
  @type row_ref :: pos_integer() | {atom(), pos_integer()}

  @typedoc "The leaves Figure 2's polynomials stand on."
  @type ep_leaf ::
          :x | :len | {:len, atom()} | {:cell, row_ref()} | {:cell, row_ref(), row_ref()}

  @typedoc "Figure 2's enriched polynomials: the reify-free subsyntax of terms."
  @type ep :: poly(ep_leaf())

  @typedoc "Figure 1's terms: `t:ep/0` plus reify, closed under + and ×."
  @type term_t :: poly(ep_leaf() | {:reify, pred()})

  @type pred ::
          {:eq, term_t(), term_t()}
          | {:conj, [pred()]}
          | {:disj, [pred()]}
          | {:natural, term_t()}

  @doc "I am the index variable X: the current column."
  @spec x() :: term_t()
  def x, do: :x

  @doc "I am len(C): the number of columns."
  @spec len() :: term_t()
  def len, do: :len

  @doc "I am len(M): the column count of the named symbol; `Zkfol.Alloc` folds me to a constant."
  @spec len(atom()) :: term_t()
  def len(sym), do: {:len, sym}

  @doc "I am C_i(X): row `i` at the current column, the row named or already linked."
  @spec cell(row_ref()) :: term_t()
  def cell(i), do: {:cell, i}

  @doc "I am C_i(C_j(X)): row `i` at the column stored in row `j` of the current column."
  @spec cell(row_ref(), row_ref()) :: term_t()
  def cell(i, j), do: {:cell, i, j}

  @doc "I am t + u, born canonical: constants fold and ride right, zero vanishes."
  @spec add(poly(l), poly(l)) :: poly(l) when l: var
  def add(q, r) when is_integer(q) and is_integer(r), do: q + r
  def add(0, t), do: t
  def add(t, 0), do: t
  def add(q, t) when is_integer(q), do: {:add, t, q}
  def add(t, u), do: {:add, t, u}

  @doc "I am t * u, born canonical: constants fold and ride right, zero and one vanish."
  @spec mul(poly(l), poly(l)) :: poly(l) when l: var
  def mul(q, r) when is_integer(q) and is_integer(r), do: q * r
  def mul(0, _t), do: 0
  def mul(_t, 0), do: 0
  def mul(1, t), do: t
  def mul(t, 1), do: t
  def mul(q, t) when is_integer(q), do: {:mul, t, q}
  def mul(t, u), do: {:mul, t, u}

  @doc "I am reify(phi): the truth value of `phi` as a term."
  @spec reify(pred()) :: term_t()
  def reify(phi), do: {:reify, phi}

  @doc "I am t = u."
  @spec eq(term_t(), term_t()) :: pred()
  def eq(t, u), do: {:eq, t, u}

  @doc "I am the conjunction of `preds`; the grammar has no empty conjunction."
  @spec conj([pred(), ...]) :: pred()
  def conj([_ | _] = preds), do: {:conj, preds}

  @doc "I am the disjunction of `preds`; the grammar has no empty disjunction."
  @spec disj([pred(), ...]) :: pred()
  def disj([_ | _] = preds), do: {:disj, preds}

  @doc "I am natural(t): a naturality obligation, discharged by lookup, never a polynomial."
  @spec natural(term_t()) :: pred()
  def natural(t), do: {:natural, t}

  @doc """
  I am the read at a computed index: a disjunction over `cells`, the
  index saying which of them the value stands for. Nothing tells the
  rows of a column apart but their names, so the cost is a branch a cell.
  """
  @spec nth(term_t(), [term_t(), ...], term_t()) :: pred()
  def nth(index, cells, value),
    do:
      disj(for {cell, i} <- Enum.with_index(cells, 1), do: conj([eq(index, i), eq(value, cell)]))

  @doc """
  I am Figure 2's polynomial for `pred`: equality squares the
  difference, conjunction sums, disjunction multiplies, and reify
  unwraps to the polynomial it denotes. Semantics evaluates the same
  rules independently, on purpose: the redundancy is what lets the
  oracle catch a bad lowering.

      Ast.arithmetize(Ast.eq(Ast.x(), 1))
  """
  @spec arithmetize(pred()) :: ep()
  def arithmetize(pred) do
    postwalk(pred, fn
      {:eq, t, u} ->
        difference = add(t, mul(u, -1))
        mul(difference, difference)

      {:conj, preds} ->
        Enum.reduce(preds, &add/2)

      {:disj, preds} ->
        Enum.reduce(preds, &mul/2)

      {:reify, t} ->
        t

      node ->
        node
    end)
  end

  @doc "I am the branches of `pred`: a disjunction's disjuncts, any other predicate alone."
  @spec branches(pred()) :: [pred()]
  def branches({:disj, preds}), do: preds
  def branches(pred), do: [pred]

  @doc "I am the conjuncts of `pred`: a conjunction's members flattened, any other predicate alone."
  @spec conjuncts(pred()) :: [pred()]
  def conjuncts({:conj, preds}), do: Enum.flat_map(preds, &conjuncts/1)
  def conjuncts(pred), do: [pred]

  # Rebuild a node with `fun` applied to each immediate child.
  @spec map_children(node, (node -> node)) :: node when node: var
  defp map_children({:add, t, u}, fun), do: {:add, fun.(t), fun.(u)}
  defp map_children({:mul, t, u}, fun), do: {:mul, fun.(t), fun.(u)}
  defp map_children({:reify, phi}, fun), do: {:reify, fun.(phi)}
  defp map_children({:eq, t, u}, fun), do: {:eq, fun.(t), fun.(u)}
  defp map_children({:natural, t}, fun), do: {:natural, fun.(t)}
  defp map_children({:conj, preds}, fun), do: {:conj, Enum.map(preds, fun)}
  defp map_children({:disj, preds}, fun), do: {:disj, Enum.map(preds, fun)}
  defp map_children(leaf, _fun), do: leaf

  @doc "I rewrite bottom-up: children first, then `fun` on the rebuilt node."
  @spec postwalk(node, (node -> node)) :: node when node: var
  def postwalk(node, fun), do: fun.(map_children(node, &postwalk(&1, fun)))

  # The immediate children of `node`: its subterms and subpredicates, none for a leaf.
  @spec children(node) :: [node] when node: var
  defp children({tag, t, u}) when tag in [:add, :mul, :eq], do: [t, u]
  defp children({:reify, phi}), do: [phi]
  defp children({:natural, t}), do: [t]
  defp children({tag, preds}) when tag in [:conj, :disj], do: preds
  defp children(_leaf), do: []

  @doc "I fold `fun` over every node, each parent before its children (pre-order)."
  @spec reduce(node, acc, (node, acc -> acc)) :: acc when node: var, acc: var
  def reduce(node, acc, fun),
    do: Enum.reduce(children(node), fun.(node, acc), &reduce(&1, &2, fun))

  @doc """
  I am the rows `pred` reads through as pointers, each once, in order.
  I read linked (numeric) predicates; named references resolve through
  `Zkfol.Alloc.link/3` before I run.
  """
  @spec pointer_reads(pred()) :: [pos_integer()]
  def pointer_reads(pred) do
    pred |> pointer_derefs() |> Enum.map(&elem(&1, 1)) |> Enum.uniq() |> Enum.sort()
  end

  @doc "I am the {value row, pointer row} of every composed read, each once, in order."
  @spec pointer_derefs(pred()) :: [{pos_integer(), pos_integer()}]
  def pointer_derefs(pred) do
    pred
    |> reduce([], fn
      {:cell, i, j}, acc -> [{i, j} | acc]
      _node, acc -> acc
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  I am the affine pointer schedules for the rows the predicate reads
  through: an index row constrained to a pointed index row plus a
  constant names the offset, a pointer bound to X declares its own,
  and a branch guarded eq(X, k) that pins a read row corroborates it.
  A composed read pinned to a term names a computed target, so its
  pointer takes no schedule. Ambiguity refuses: conflicting offsets
  and offsets that do not look back have no shift. I read linked
  (numeric) predicates; named references resolve through
  `Zkfol.Alloc.link/3` before I run.
  """
  @spec schedules(pred()) ::
          {:ok, %{pos_integer() => pos_integer()}} | {:error, Zkfol.Refusal.t()}
  def schedules(pred) do
    read = pointer_reads(pred)

    # Relate cell i to itself in a different column/recursion
    syntax =
      pred
      |> branches()
      |> Enum.flat_map(&conjuncts/1)
      |> Enum.flat_map(fn
        # Constants ride right in canonical terms, so one shape suffices.
        {:eq, {:cell, i}, {:add, {:cell, i, j}, k}} when is_integer(k) -> [{j, k}]
        # A pointer bound to X by a constant declares its own schedule.
        {:eq, {:cell, j}, {:add, :x, k}} when is_integer(k) -> [{j, -k}]
        _part -> []
      end)

    # If we fix a computation at a column, we know more info about what m must be.
    # We note this as j may be a pointer
    pins =
      for branch <- branches(pred),
          parts = conjuncts(branch),
          {:eq, :x, k} when is_integer(k) <- parts,
          {:eq, {:cell, j}, m} when is_integer(m) <- parts,
          # We simply note how many rows we must look
          do: {j, k - m}

    # A composed read pinned to a term marks its pointer as computed:
    # the value equation shape must not hand it a schedule.
    computed =
      for branch <- branches(pred),
          {:eq, {:cell, _i, j}, _t} <- conjuncts(branch),
          uniq: true,
          do: j

    by_row =
      (syntax ++ pins)
      # Filter for pointer chases
      |> Enum.filter(fn {j, _} -> j in read and j not in computed end)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Map.new(fn {j, offsets} -> {j, Enum.uniq(offsets)} end)

    # A row with more than one offset demonstrates a conflict.
    case Enum.find(by_row, fn {_j, offsets} -> not match?([_], offsets) end) do
      nil ->
        {:ok,
         by_row
         |> Enum.filter(fn {_j, [offset]} -> offset > 0 end)
         |> Map.new(fn {j, [offset]} -> {j, offset} end)}

      {j, offsets} ->
        {:error, {:conflicting_schedule_offsets, %{row: j, offsets: offsets}}}
    end
  end

  @doc """
  I pin the scheduled pointers into the branches: a read row with a
  schedule and no pin of its own gains the binding to X it already
  obeys, so the polynomial reads it where the schedule says.
  """
  @spec bind_pointers(pred(), %{pos_integer() => pos_integer()}) :: pred()
  def bind_pointers(pred, schedules) do
    pred
    |> branches()
    |> Enum.map(fn branch ->
      parts = conjuncts(branch)
      # Only a pin to a constant or an explicit X-binding already fixes
      # the row to its schedule; an equality to another cell does not,
      # and must not skip the binding.
      pinned =
        Enum.flat_map(parts, fn
          {:eq, {:cell, j}, m} when is_integer(m) -> [j]
          {:eq, {:cell, j}, {:add, :x, m}} when is_integer(m) -> [j]
          _part -> []
        end)

      bindings =
        for j <- pointer_reads(branch),
            j not in pinned,
            is_map_key(schedules, j),
            do: eq(cell(j), add(x(), -Map.get(schedules, j)))

      conj(parts ++ bindings)
    end)
    |> disj()
  end
end
