defmodule Zkfol.ZincPlus do
  @moduledoc """
  I am the Zinc+ backend behind a NIF: `request/2` marshals a UAIR to
  the one payload the prover thread takes, the call returns an id, and
  the verdict arrives in-process as `{:zinc_plus, id, result}`. What
  the pinned backend cannot carry refuses here: a mode it cannot
  prove, a negative cell, a value or constant past its cell widths.
  """

  use Rustler, otp_app: :zkfol, crate: "zkfol_zinc_plus", mode: :release
  use TypedStruct

  import Bitwise

  alias Zkfol.Refusal
  alias Zkfol.Uair
  alias Zkfol.Uair.Composed
  alias Zkfol.Uair.Lookup
  alias Zkfol.Uair.Plain

  # One addition of headroom under each cell width: narrow cells are i64,
  # wide cells 768 or 7040 bits, and values must be non-negative past i64,
  # since limbs carry no sign.
  @i64_bound Integer.pow(2, 62)
  @big_bound Integer.pow(2, 766)
  @huge_bound Integer.pow(2, 7038)

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

  @doc "I queue the UAIR with the prover fitting its magnitude and return an id."
  @spec request(Uair.t(), keyword()) :: {:ok, pos_integer()} | {:error, Refusal.t()}
  def request(%Uair{} = uair, opts \\ []) do
    values = List.flatten(uair.columns)

    with {:ok, bins, lookups} <- mode_payload(uair.mode),
         :ok <- non_negative(values) do
      queued =
        prove_fol(%Payload{
          num_cols: Uair.num_cols(uair),
          num_public: uair.num_public,
          shifts: uair.shifts,
          program: uair.program,
          cells: cells(uair, values),
          bins: bins,
          lookups: lookups,
          num_vars: Uair.num_vars(uair),
          tamper: Keyword.get(opts, :tamper, false)
        })

      # The backend answers in prose either way; it is read into a
      # refusal here so no caller has to tell a rejected proof from a
      # malformed lookup by matching on text.
      with {:error, said} <- queued, do: {:error, Refusal.from_backend(said)}
    end
  end

  @doc "I hold every cell value under the widest width I carry, non-negative."
  @spec fits([[integer()]]) :: :ok | {:error, Refusal.t()}
  def fits(columns) do
    Refusal.refute(
      List.flatten(columns),
      &(&1 >= @huge_bound or &1 < 0),
      &{:value_exceeds_cell, %{value: &1}}
    )
  end

  @doc "I hold every program constant inside the i64 the interpreter reads."
  @spec constants_fit([{atom(), integer()}]) :: :ok | {:error, Refusal.t()}
  def constants_fit(program) do
    Refusal.refute(
      program,
      &match?({:const, k} when abs(k) >= @i64_bound, &1),
      fn {:const, k} -> {:constant_exceeds_cell, %{constant: k}} end
    )
  end

  # The shadow columns and lookup tuples the mode owes the NIF, or the
  # refusal that keeps it away.
  @spec mode_payload(Uair.mode()) ::
          {:ok, [[non_neg_integer()]], [lookup()]} | {:error, Refusal.t()}
  defp mode_payload(%Plain{}), do: {:ok, [], []}
  defp mode_payload(%Composed{}), do: Composed.refusal()

  defp mode_payload(%Lookup{bin_columns: bins, lookups: lookups}) do
    with {:ok, tuples} <- lookup_tuples(lookups), do: {:ok, bins, tuples}
  end

  # BitPoly lookups as the tuples the NIF takes; any other table still
  # waits on zinc+.
  @spec lookup_tuples([Uair.lookup()]) :: {:ok, [lookup()]} | {:error, Refusal.t()}
  defp lookup_tuples(lookups) do
    Refusal.map(lookups, fn
      %{col: col, table: {:bit_poly, width, chunk}} -> {:ok, {col, width, chunk}}
      %{table: table} -> {:error, {:lookup_awaits_backend, %{table: table}}}
    end)
  end

  # The widest value decides the transport; the limbing stays on this side
  # of the NIF, so Rust only unpacks what it is handed.
  @spec cells(Uair.t(), [integer()]) :: cells()
  defp cells(uair, values) do
    cond do
      Enum.any?(values, &(&1 >= @big_bound)) -> {:huge, limbed(uair)}
      Enum.any?(values, &(&1 >= @i64_bound)) -> {:big, limbed(uair)}
      true -> {:i64, uair.columns}
    end
  end

  # Unsigned limbs have no negative; refuse before the NIF decode crashes.
  @spec non_negative([integer()]) :: :ok | {:error, Refusal.t()}
  defp non_negative(values),
    do: Refusal.refute(values, &(&1 < 0), &{:witness_value_negative, %{value: &1}})

  # Values as little-endian base-2^64 digits, the wide cells' transport.
  @spec limbed(Uair.t()) :: [[[non_neg_integer()]]]
  defp limbed(uair),
    do:
      for(
        col <- uair.columns,
        do: for(v <- col, do: v |> Integer.digits(1 <<< 64) |> Enum.reverse())
      )
end
