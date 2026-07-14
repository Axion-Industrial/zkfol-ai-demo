defmodule Zkfol.ZincPlus do
  @moduledoc """
  I am the Zinc+ backend behind a NIF: statements queue to the prover
  thread, each call returns an id, and the verdict arrives in-process
  as `{:zinc_plus, id, result}`.

  ### Public API

  - `prove_fol/6`, `prove_fol_big/6`, `prove_fol_huge/6`
  """

  use Rustler, otp_app: :zkfol, crate: "zkfol_zinc_plus", mode: :release

  @doc """
  I queue an interpreted UAIR: int columns of which the first
  `num_public` are read by the verifier, shifts, one postfix constraint
  program, and the padded trace columns.
  """
  @spec prove_fol(
          pos_integer(),
          non_neg_integer(),
          [{non_neg_integer(), pos_integer()}],
          [{atom(), integer()}],
          [[integer()]],
          pos_integer()
        ) :: {:ok, pos_integer()} | {:error, String.t()}
  def prove_fol(_num_cols, _num_public, _shifts, _program, _columns, _num_vars),
    do: :erlang.nif_error(:nif_not_loaded)

  @doc "I am `prove_fol/6` over 768-bit cells; values arrive as u64 limb lists."
  @spec prove_fol_big(
          pos_integer(),
          non_neg_integer(),
          [{non_neg_integer(), pos_integer()}],
          [{atom(), integer()}],
          [[[non_neg_integer()]]],
          pos_integer()
        ) :: {:ok, pos_integer()} | {:error, String.t()}
  def prove_fol_big(_num_cols, _num_public, _shifts, _program, _columns, _num_vars),
    do: :erlang.nif_error(:nif_not_loaded)

  @doc "I am `prove_fol_big/6` at 7040-bit cells, for the flagship statements."
  @spec prove_fol_huge(
          pos_integer(),
          non_neg_integer(),
          [{non_neg_integer(), pos_integer()}],
          [{atom(), integer()}],
          [[[non_neg_integer()]]],
          pos_integer()
        ) :: {:ok, pos_integer()} | {:error, String.t()}
  def prove_fol_huge(_num_cols, _num_public, _shifts, _program, _columns, _num_vars),
    do: :erlang.nif_error(:nif_not_loaded)
end
