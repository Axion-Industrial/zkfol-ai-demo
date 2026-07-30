defmodule Zkfol.ZincPlus do
  @moduledoc """
  I am the Zinc+ backend behind a NIF: a UAIR queues to the prover thread
  as one payload, the call returns an id, and the verdict arrives
  in-process as `{:zinc_plus, id, result}`.
  """

  use Rustler, otp_app: :zkfol, crate: "zkfol_zinc_plus", mode: :release
  use TypedStruct

  @typedoc "A BitPoly lookup: {binary column, table width, chunk width}."
  @type lookup :: {non_neg_integer(), pos_integer(), pos_integer()}

  @typedoc """
  The trace columns tagged by the cell width they need: narrow cells ride
  as integers, wider ones as little-endian base-2^64 limbs.
  """
  @type cells ::
          {:i64, [[integer()]]}
          | {:big, [[[non_neg_integer()]]]}
          | {:huge, [[[non_neg_integer()]]]}

  typedstruct module: Payload, enforce: true do
    @typedoc "One queued UAIR, as the NIF decodes it."
    field(:num_cols, pos_integer())
    field(:num_public, non_neg_integer())
    field(:shifts, [{non_neg_integer(), pos_integer()}])
    field(:program, [{atom(), integer()}])
    field(:cells, Zkfol.ZincPlus.cells())
    field(:bins, [[non_neg_integer()]], default: [])
    field(:lookups, [Zkfol.ZincPlus.lookup()], default: [])
    field(:reads, [{non_neg_integer(), [non_neg_integer()], non_neg_integer()}], default: [])
    field(:num_vars, pos_integer())
    # Bends one looked-up chunk lift after proving: the verdict must
    # refuse, or the lookup was decorative.
    field(:tamper, boolean(), default: false)
  end

  @doc """
  I queue an interpreted UAIR: its columns tagged by cell width, the
  public prefix the verifier reads in the clear, the shifts, one postfix
  constraint program, the binary shadow columns, and the BitPoly lookups
  declared on them.
  """
  @spec prove_fol(Payload.t()) :: {:ok, pos_integer()} | {:error, String.t()}
  def prove_fol(_payload), do: :erlang.nif_error(:nif_not_loaded)
end
