defmodule Zkfol.Ast do
  @moduledoc """
  I am the syntax of the logic: Figure 1 of the paper, as data.

      t   ::= q | t + t | t * t | len(C) | reify(phi) | X | C_i(X) | C_i(C_j(X))
      phi ::= t = t | phi and phi | phi or phi
      e   ::= q | e + e | e * e | len(C) | X | C_i(X) | C_i(C_j(X))

  Integers denote themselves. `t:term_t/0` and `t:pred/0` are the grammar;
  the constructors below build well-formed nodes. `e` is the reify-free
  subsyntax: Figure 2's enriched polynomials, `t:ep/0`, of which terms
  are the reify-closure.

  ### Public API

  - `x/0`, `len/0`, `cell/1`, `cell/2`, `add/2`, `mul/2`, `reify/1`
  - `eq/2`, `conj/1`, `disj/1`
  - `branches/1`, `conjuncts/1`, `children/1`, `map_children/2`, `postwalk/2`, `reduce/3`
  """

  @typedoc "Figure 2's enriched polynomials: the reify-free subsyntax of terms."
  @type ep ::
          integer()
          | :x
          | :len
          | {:cell, pos_integer()}
          | {:cell, pos_integer(), pos_integer()}
          | {:add, ep(), ep()}
          | {:mul, ep(), ep()}

  @typedoc "Figure 1's terms: `t:ep/0` plus reify, closed under + and ×."
  @type term_t ::
          ep()
          | {:reify, pred()}
          | {:add, term_t(), term_t()}
          | {:mul, term_t(), term_t()}

  @type pred ::
          {:eq, term_t(), term_t()}
          | {:conj, [pred()]}
          | {:disj, [pred()]}

  @doc "I am the index variable X: the current column."
  @spec x() :: term_t()
  def x, do: :x

  @doc "I am len(C): the number of columns."
  @spec len() :: term_t()
  def len, do: :len

  @doc "I am C_i(X): row `i` at the current column."
  @spec cell(pos_integer()) :: term_t()
  def cell(i), do: {:cell, i}

  @doc "I am C_i(C_j(X)): row `i` at the column stored in row `j` of the current column."
  @spec cell(pos_integer(), pos_integer()) :: term_t()
  def cell(i, j), do: {:cell, i, j}

  @doc "I am t + u, born canonical: constants fold and ride right, zero vanishes."
  @spec add(term_t(), term_t()) :: term_t()
  def add(q, r) when is_integer(q) and is_integer(r), do: q + r
  def add(0, t), do: t
  def add(t, 0), do: t
  def add(q, t) when is_integer(q), do: {:add, t, q}
  def add(t, u), do: {:add, t, u}

  @doc "I am t * u, born canonical: constants fold and ride right, zero and one vanish."
  @spec mul(term_t(), term_t()) :: term_t()
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

  @doc "I am the branches of `pred`: a disjunction's disjuncts, any other predicate alone."
  @spec branches(pred()) :: [pred()]
  def branches({:disj, preds}), do: preds
  def branches(pred), do: [pred]

  @doc "I am the conjuncts of `pred`: a conjunction's members flattened, any other predicate alone."
  @spec conjuncts(pred()) :: [pred()]
  def conjuncts({:conj, preds}), do: Enum.flat_map(preds, &conjuncts/1)
  def conjuncts(pred), do: [pred]

  @doc "I rebuild a node with `fun` applied to each immediate child."
  @spec map_children(node, (node -> node)) :: node when node: var
  def map_children({:add, t, u}, fun), do: {:add, fun.(t), fun.(u)}
  def map_children({:mul, t, u}, fun), do: {:mul, fun.(t), fun.(u)}
  def map_children({:reify, phi}, fun), do: {:reify, fun.(phi)}
  def map_children({:eq, t, u}, fun), do: {:eq, fun.(t), fun.(u)}
  def map_children({:conj, preds}, fun), do: {:conj, Enum.map(preds, fun)}
  def map_children({:disj, preds}, fun), do: {:disj, Enum.map(preds, fun)}
  def map_children(leaf, _fun), do: leaf

  @doc "I rewrite bottom-up: children first, then `fun` on the rebuilt node."
  @spec postwalk(node, (node -> node)) :: node when node: var
  def postwalk(node, fun), do: fun.(map_children(node, &postwalk(&1, fun)))

  @doc "I am the immediate children of `node`: its subterms and subpredicates, none for a leaf."
  @spec children(node) :: [node] when node: var
  def children({tag, t, u}) when tag in [:add, :mul, :eq], do: [t, u]
  def children({:reify, phi}), do: [phi]
  def children({tag, preds}) when tag in [:conj, :disj], do: preds
  def children(_leaf), do: []

  @doc "I fold `fun` over every node, each parent before its children (pre-order)."
  @spec reduce(node, acc, (node, acc -> acc)) :: acc when node: var, acc: var
  def reduce(node, acc, fun),
    do: Enum.reduce(children(node), fun.(node, acc), &reduce(&1, &2, fun))
end
