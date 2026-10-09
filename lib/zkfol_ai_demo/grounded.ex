defmodule ZkfolAiDemo.Grounded do
  @moduledoc """
  I am the grounding policy in zkFOL's relational language: every numeric figure in an output
  also appears in a supplied set of sources.

  Where the no-dash rule looks at every codepoint, this one is a membership check, so it shows
  the mechanism is not lexical. A figure is an integer (see `ZkfolAiDemo.Figures`), the
  figures of an output are a list, and the sources are a list. `member/2` is the lookup and
  `grounded/2` asks it of every figure.

  This file is the published policy: `source_hash/0` is SHA-256 of it as compiled, so
  `sha256sum lib/zkfol_ai_demo/grounded.ex` reproduces it, and every proof binds it.

  ### Public API

  - `member/2` is a figure standing in a list of sources.
  - `grounded/2` is the policy: every figure of the first list is a member of the second.
  - `source_hash/0` is the hash of this file.
  """

  use Zkfol.Lang

  @external_resource __ENV__.file
  @source_hash :crypto.hash(:sha256, File.read!(__ENV__.file))

  defrel member(x, [x | _rest])

  defrel member(x, [_y | rest]) do
    member(x, rest)
  end

  defrel grounded([], _sources)

  defrel grounded([figure | figures], sources) do
    member(figure, sources)
    grounded(figures, sources)
  end

  @doc "I am the SHA-256 of this file as it was compiled."
  @spec source_hash() :: binary()
  def source_hash, do: @source_hash
end
