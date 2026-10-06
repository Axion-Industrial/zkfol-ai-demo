defmodule Zkfol.Harness.Policy do
  @moduledoc """
  I am a published policy: the codepoints a released text must not contain, read from a
  file an audience can inspect and hash for themselves.

  A banned set is not a range, so a bound cannot say it. I make it one by remapping: the
  banned codepoints swap places with the top of the codepoint range, so a text holds no
  banned codepoint exactly when every remapped cell is at most `bound/1`. That is one
  bounds check per cell, which the prover discharges as a word lookup per row.

  ### Public API

  - `default_path/0` and `load/1` read a policy file.
  - `encode/2` is the remapping of one codepoint.
  - `bound/1` is the largest remapped cell a compliant text can hold.
  - `pred/2` is the predicate a text matrix is proved against.
  """

  use TypedStruct

  alias Zkfol.Ast

  @max_codepoint 0x10FFFF

  typedstruct enforce: true do
    @typedoc "A policy and the hash of the file it was read from."
    field(:name, String.t())
    field(:banned, [non_neg_integer()])
    field(:sentinel, non_neg_integer())
    field(:swaps, %{non_neg_integer() => non_neg_integer()})
    field(:hash, binary())
  end

  @doc "I am where the published no-em-dash policy sits in the source tree."
  @spec default_path() :: Path.t()
  def default_path, do: Path.expand("../../../harness/policy/no-em-dash.json", __DIR__)

  @doc """
  I read a policy file. The hash is SHA-256 of the file's bytes, so `sha256sum` on the file
  gives the same value.
  """
  @spec load(Path.t()) :: t()
  def load(path \\ default_path()) do
    bytes = File.read!(path)
    %{"name" => name, "banned_codepoints" => banned, "sentinel" => sentinel} = JSON.decode!(bytes)
    true = Enum.all?(banned, &(&1 in 0..@max_codepoint)) and sentinel not in banned

    %__MODULE__{
      name: name,
      banned: Enum.sort(banned),
      sentinel: sentinel,
      swaps: swaps(banned),
      hash: :crypto.hash(:sha256, bytes)
    }
  end

  @doc "I remap a codepoint: a banned one goes to the top of the range, and the codepoint there comes down."
  @spec encode(t(), non_neg_integer()) :: non_neg_integer()
  def encode(%__MODULE__{swaps: swaps}, codepoint), do: Map.get(swaps, codepoint, codepoint)

  @doc "I am the largest remapped cell a text with no banned codepoint can hold."
  @spec bound(t()) :: non_neg_integer()
  def bound(%__MODULE__{banned: banned}), do: @max_codepoint - length(banned)

  @doc """
  I am the predicate over a matrix of `rows` rows: every cell of every row is at most the
  bound. It holds at every column, so its size does not grow with the text.
  """
  @spec pred(t(), pos_integer()) :: Ast.pred()
  def pred(%__MODULE__{} = policy, rows),
    do: Ast.conj(for i <- 1..rows, do: Ast.natural(Ast.sub(bound(policy), Ast.cell(i))))

  # The banned codepoints outside the top range pair off with the unbanned codepoints inside
  # it, and each pair swaps. Those inside the top range already sit where they belong.
  @spec swaps([non_neg_integer()]) :: %{non_neg_integer() => non_neg_integer()}
  defp swaps(banned) do
    top = Enum.to_list((@max_codepoint - length(banned) + 1)..@max_codepoint)
    pairs = Enum.zip(Enum.sort(banned -- top), Enum.sort(top -- banned))
    Map.new(pairs ++ Enum.map(pairs, fn {low, high} -> {high, low} end))
  end
end
