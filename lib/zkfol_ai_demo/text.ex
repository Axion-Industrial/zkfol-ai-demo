defmodule ZkfolAiDemo.Text do
  @moduledoc """
  I am the text policy as a statement: a raw output is canonicalised, and the statement says
  every cell of its matrix is within the policy's bound.

  ### Public API

  - `statement/3` builds the statement for a raw output under a policy and a context.
  """

  alias Zkfol.Ast
  alias ZkfolAiDemo.Bindings
  alias ZkfolAiDemo.Canon
  alias ZkfolAiDemo.Canon.Result
  alias ZkfolAiDemo.Context
  alias ZkfolAiDemo.Policy
  alias ZkfolAiDemo.Statement
  alias Zkfol.Refusal

  @doc "I am the statement for `raw` under `policy` and `context`, and its canonical form."
  @spec statement(String.t(), Policy.t(), Context.t()) ::
          {:ok, Statement.t()} | {:error, Refusal.t()}
  def statement(raw, %Policy{} = policy, %Context{} = context) do
    with {:ok, %Result{matrix: matrix, layout: layout} = canon} <- Canon.run(raw, policy) do
      bound = Policy.bound(policy)

      public = [
        {"policy", Bindings.words(policy.hash)},
        {"canonicaliser", Bindings.words(canon.canonicaliser_hash)} | Context.public(context)
      ]

      {:ok,
       %Statement{
         pred:
           Ast.conj([Policy.pred(policy, layout.rows), Ast.natural(Ast.cell(layout.rows + 1))]),
         rows: matrix,
         stand_in: for(row <- matrix, do: Enum.map(row, &if(&1 > bound, do: 0, else: &1))),
         public: public,
         pins: for({name, words} <- public, into: %{}, do: {name, Bindings.hex(words)}),
         output: raw,
         manifest: manifest(canon, context, policy)
       }}
    end
  end

  # The record of a run for whoever audits it. None of it is proved: the proof binds the
  # hashes, and this is what they were hashes of, so anyone can recompute them.
  @spec manifest(Result.t(), Context.t(), Policy.t()) :: map()
  defp manifest(%Result{} = canon, %Context{} = context, %Policy{} = policy) do
    %{
      predicate: "text",
      policy: policy.name,
      policy_sha256: Base.encode16(policy.hash, case: :lower),
      canonicaliser_sha256: Base.encode16(canon.canonicaliser_hash, case: :lower),
      array_sha256: Base.encode16(canon.array_hash, case: :lower),
      layout: %{rows: canon.layout.rows, cols: canon.layout.cols},
      unicode_version: canon.unicode_version,
      model: context.model,
      system_prompt: context.system_prompt,
      user_prompt: context.user_prompt,
      nonce: Base.encode16(context.nonce, case: :lower)
    }
  end
end
