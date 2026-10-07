defmodule ZkfolAiDemo.Canon do
  @moduledoc """
  I am the canonicaliser: I turn raw model output into the fixed-shape matrix of integers a
  policy is proved over, and I commit to it.

  The text a reader sees and the text a policy judges must not differ in a way that hides a
  banned character, so I only ever err towards seeing more of it. Every step below can add
  a banned character to what is judged, and none can remove one.

  ### What I normalise

  Each pass, until nothing changes:

  1. HTML entities, named (a short fixed table) and numeric, with or without the semicolon.
  2. Backslash escapes: `\\uXXXX` with surrogate pairs joined, `\\u{X..}` and `\\UXXXXXXXX`.
  3. Percent-encoded runs that decode to valid UTF-8.
  4. Unicode NFKC, then Unicode tag characters read as the ASCII they spell.
  5. Format characters (zero-width and soft hyphens, byte order marks) removed.
  6. Every dash look-alike (U+2012 to U+2015, U+2E3A, U+2E3B, U+2E40) folded to U+2014.
  7. A run of two or more hyphens folded to U+2014, so `--` is a dash.
  8. NUL replaced by U+FFFD, so the padding sentinel can never occur in a text.

  Text that still changes after eight passes is refused: a nesting that deep cannot be
  normalised, so no proof about it should exist.

  ### Base64 and other payloads

  A base64 token (standard or URL-safe, four or more characters) that decodes to valid UTF-8
  is normalised in turn, and when the result holds a dash it is appended to the canonical
  text. The token stays, and a decoding with no dash adds nothing, so ordinary words that
  happen to decode add no noise. Nested base64 is followed to eight levels, then refused.

  I do not decode anything else: hex, base32, ROT13, other character sets, MIME-wrapped
  base64 split across lines, or a cipher the model invents. A proof about a text says the
  string released has no dash after the steps above. It says nothing about what a consumer
  that decodes further would see.

  ### The matrix and its hashes

  The canonical codepoints are remapped by the policy, padded with its sentinel to a layout
  of `rows` by `cols` cells, and committed to with SHA-256. `source_hash/0` is SHA-256 of
  this file as compiled, so `sha256sum lib/zkfol_ai_demo/canon.ex` reproduces it.

  ### Public API

  - `run/3` canonicalises raw output under a policy.
  - `text/1` is the text half alone.
  - `source_hash/0` is the hash of this file.
  """

  use TypedStruct

  alias ZkfolAiDemo.Policy
  alias Zkfol.Refusal

  @external_resource __ENV__.file
  @source_hash :crypto.hash(:sha256, File.read!(__ENV__.file))

  @max_depth 8
  @max_rows 16
  @dashes [0x2012, 0x2013, 0x2015, 0x2E3A, 0x2E3B, 0x2E40]
  @named %{
    "amp" => ?&,
    "lt" => ?<,
    "gt" => ?>,
    "quot" => ?",
    "apos" => ?',
    "nbsp" => 0xA0,
    "mdash" => 0x2014,
    "ndash" => 0x2013,
    "horbar" => 0x2015,
    "hyphen" => 0x2010,
    "dash" => 0x2010
  }
  @em <<0x2014::utf8>>
  @replacement <<0xFFFD::utf8>>

  typedstruct module: Layout, enforce: true do
    @typedoc """
    The shape of the matrix: `rows` rows of `cols` cells. A trace column needs `cols` plus a
    padding row to fill a power of two, so `cols` is one less than one.
    """
    field(:rows, pos_integer())
    field(:cols, pos_integer())
  end

  typedstruct module: Result, enforce: true do
    @typedoc "A text canonicalised, and everything a proof about it binds."
    field(:text, String.t())
    field(:matrix, [[non_neg_integer()]])
    field(:layout, ZkfolAiDemo.Canon.Layout.t())
    field(:array_hash, binary())
    field(:canonicaliser_hash, binary())
    field(:policy_hash, binary())
    field(:unicode_version, String.t())
  end

  @doc "I canonicalise `raw` under `policy`, into `layout` or the smallest standard one."
  @spec run(String.t(), Policy.t(), Layout.t() | nil) :: {:ok, Result.t()} | {:error, Refusal.t()}
  def run(raw, %Policy{} = policy, layout \\ nil) do
    with {:ok, text} <- text(raw),
         cells = for(cp <- String.to_charlist(text), do: Policy.encode(policy, cp)),
         {:ok, layout} <- fit(layout, length(cells)) do
      padding = List.duplicate(policy.sentinel, layout.rows * layout.cols - length(cells))
      matrix = Enum.chunk_every(cells ++ padding, layout.cols)

      {:ok,
       %Result{
         text: text,
         matrix: matrix,
         layout: layout,
         array_hash: commit(layout, matrix),
         canonicaliser_hash: @source_hash,
         policy_hash: policy.hash,
         unicode_version: String.Unicode.version() |> Tuple.to_list() |> Enum.join(".")
       }}
    end
  end

  @doc "I am the canonical text of `raw`: its normal form, then any dash its base64 holds."
  @spec text(String.t()) :: {:ok, String.t()} | {:error, Refusal.t()}
  def text(raw), do: text(raw, @max_depth)

  @doc "I am the SHA-256 of this file as it was compiled."
  @spec source_hash() :: binary()
  def source_hash, do: @source_hash

  @spec text(String.t(), non_neg_integer()) :: {:ok, String.t()} | {:error, Refusal.t()}
  defp text(raw, depth) do
    with {:ok, body} <- settle(String.replace_invalid(raw, @replacement), @max_depth),
         {:ok, hidden} <- hidden(body, depth) do
      {:ok, Enum.join([body | hidden], "\n")}
    end
  end

  # Passes until a fixed point, so an encoding inside an encoding is read all the way down.
  @spec settle(String.t(), non_neg_integer()) :: {:ok, String.t()} | {:error, Refusal.t()}
  defp settle(text, 0) do
    if pass(text) == text,
      do: {:ok, text},
      else: {:error, {:encoding_unbounded, %{depth: @max_depth}}}
  end

  defp settle(text, passes) do
    case pass(text) do
      ^text -> {:ok, text}
      next -> settle(next, passes - 1)
    end
  end

  @spec pass(String.t()) :: String.t()
  defp pass(text) do
    text
    |> entities()
    |> escapes()
    |> percents()
    |> String.normalize(:nfkc)
    |> tags()
    |> then(&Regex.replace(~r/\p{Cf}/u, &1, ""))
    |> String.replace(for(cp <- @dashes, do: <<cp::utf8>>), @em)
    |> then(&Regex.replace(~r/[-\x{2010}]{2,}/u, &1, @em))
    |> String.replace(<<0>>, @replacement)
  end

  @spec entities(String.t()) :: String.t()
  defp entities(text) do
    ~r/&(?:#[xX]([0-9a-fA-F]{1,6})|#([0-9]{1,7})|([a-zA-Z]{2,6}));?/
    |> Regex.replace(text, fn whole, hex, dec, name ->
      cond do
        hex != "" -> scalar(String.to_integer(hex, 16), whole)
        dec != "" -> scalar(String.to_integer(dec), whole)
        true -> named(name, whole)
      end
    end)
  end

  @spec escapes(String.t()) :: String.t()
  defp escapes(text) do
    ~r/\\(?:u\{([0-9a-fA-F]{1,6})\}|U([0-9a-fA-F]{8})|u([dD][89abAB][0-9a-fA-F]{2})\\u([dD][c-fC-F][0-9a-fA-F]{2})|u([0-9a-fA-F]{4}))/
    |> Regex.replace(text, fn whole, braced, wide, high, low, four ->
      cond do
        braced != "" ->
          scalar(hex(braced), whole)

        wide != "" ->
          scalar(hex(wide), whole)

        high != "" ->
          scalar(0x10000 + Bitwise.bsl(hex(high) - 0xD800, 10) + hex(low) - 0xDC00, whole)

        true ->
          scalar(hex(four), whole)
      end
    end)
  end

  @spec percents(String.t()) :: String.t()
  defp percents(text) do
    Regex.replace(~r/(?:%[0-9a-fA-F]{2})+/, text, fn run ->
      bytes = for <<"%", byte::binary-size(2) <- run>>, into: <<>>, do: <<hex(byte)>>
      if String.valid?(bytes), do: bytes, else: run
    end)
  end

  # The tag block spells ASCII invisibly: a hyphen there is a hyphen to whoever reads it.
  @spec tags(String.t()) :: String.t()
  defp tags(text) do
    for <<cp::utf8 <- text>>, into: "" do
      if cp in 0xE0020..0xE007E, do: <<cp - 0xE0000::utf8>>, else: <<cp::utf8>>
    end
  end

  @spec named(String.t(), String.t()) :: String.t()
  defp named(name, whole) do
    case Map.fetch(@named, name) do
      {:ok, cp} -> <<cp::utf8>>
      :error -> whole
    end
  end

  @spec scalar(integer(), String.t()) :: String.t()
  defp scalar(cp, _whole) when cp in 0..0xD7FF or cp in 0xE000..0x10FFFF, do: <<cp::utf8>>
  defp scalar(_cp, whole), do: whole

  @spec hex(String.t()) :: non_neg_integer()
  defp hex(digits), do: String.to_integer(digits, 16)

  # Each base64 token that decodes to text holding a dash, canonicalised in turn.
  @spec hidden(String.t(), non_neg_integer()) :: {:ok, [String.t()]} | {:error, Refusal.t()}
  defp hidden(body, depth) do
    case decodings(body) do
      [] ->
        {:ok, []}

      _payloads when depth == 0 ->
        {:error, {:encoding_unbounded, %{depth: @max_depth}}}

      payloads ->
        with {:ok, texts} <- Refusal.map(payloads, &text(&1, depth - 1)),
             do: {:ok, Enum.filter(texts, &String.contains?(&1, @em))}
    end
  end

  @spec decodings(String.t()) :: [String.t()]
  defp decodings(body) do
    for [token] <- Regex.scan(~r/[A-Za-z0-9+\/_-]{4,}={0,2}/, body),
        bare = String.trim_trailing(token, "="),
        {:ok, bytes} <- [
          Base.decode64(bare, padding: false),
          Base.url_decode64(bare, padding: false)
        ],
        String.valid?(bytes),
        do: bytes
  end

  @spec fit(Layout.t() | nil, non_neg_integer()) :: {:ok, Layout.t()} | {:error, Refusal.t()}
  defp fit(nil, cells) do
    cols = if cells <= 2047, do: 2047, else: 4095
    fit(%Layout{rows: max(1, div(cells + cols - 1, cols)), cols: cols}, cells)
  end

  defp fit(%Layout{rows: rows, cols: cols} = layout, cells) do
    capacity = min(rows, @max_rows) * cols

    if cells <= capacity and rows <= @max_rows,
      do: {:ok, layout},
      else: {:error, {:text_exceeds_capacity, %{cells: cells, capacity: capacity}}}
  end

  @spec commit(Layout.t(), [[non_neg_integer()]]) :: binary()
  defp commit(%Layout{rows: rows, cols: cols}, matrix) do
    cells = for row <- matrix, cell <- row, into: <<>>, do: <<cell::32>>
    :crypto.hash(:sha256, ["zkfol.harness.canon-array.v1", <<rows::32, cols::32>>, cells])
  end
end
