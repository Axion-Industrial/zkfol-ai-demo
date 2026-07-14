defmodule Zkfol.Enrich do
  @moduledoc """
  I am Figure 2 of the paper: predicates to enriched polynomials.

      t = u   -->  (t - u)^2
      conj    -->  sum
      disj    -->  product

  Enriched polynomials are a subsyntax of terms, `t:Zkfol.Ast.ep/0`:
  reify(phi) denotes it as a term, I am it as data.

  ### Public API

  - `enrich/1`
  """

  alias Zkfol.Ast

  @doc "I am the zero-is-true polynomial of `phi`: a reify-free term."
  @spec enrich(Ast.pred()) :: Ast.ep()
  def enrich(pred) do
    Ast.postwalk(pred, fn
      {:eq, t, u} ->
        d = Ast.add(t, Ast.mul(-1, u))
        Ast.mul(d, d)

      {:conj, preds} ->
        Enum.reduce(preds, &Ast.add/2)

      {:disj, preds} ->
        Enum.reduce(preds, &Ast.mul/2)

      {:reify, t} ->
        t

      node ->
        node
    end)
  end
end
