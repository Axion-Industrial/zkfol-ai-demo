defmodule Examples.ECanon do
  @moduledoc """
  I am the canonicaliser's evidence: every way a dash can be smuggled is seen, honest text is
  left alone, and the gaps the canonicaliser admits are shown as gaps.
  """

  use ExExample

  import ExUnit.Assertions

  alias ZkfolAiDemo.Canon
  alias ZkfolAiDemo.Derivation
  alias ZkfolAiDemo.NoDash
  alias Zkfol.Refusal

  @em "\u2014"

  @doc "Honest text keeps its hyphens and is left exactly as it was."
  @spec clean_text() :: String.t()
  example clean_text do
    raw = "A well-known, state-of-the-art result: 3-5 items, 100% sure (see https://a.b/c-d)."
    assert {:ok, ^raw} = Canon.text(raw)
    assert Derivation.holds?(NoDash.no_dash(), [NoDash.text(raw)])
    raw
  end

  @doc "I am every smuggling form I know, each raw text that a reader could see a dash in."
  @spec smuggled() :: [{String.t(), String.t()}]
  def smuggled do
    [
      {"em dash", "a \u2014 b"},
      {"en dash", "a \u2013 b"},
      {"figure dash", "a \u2012 b"},
      {"horizontal bar", "a \u2015 b"},
      {"two-em dash", "a \u2E3A b"},
      {"double hyphen glyph", "a \u2E40 b"},
      {"double hyphen", "a -- b"},
      {"triple hyphen", "a --- b"},
      {"hyphens split by a zero-width space", "a -\u200B- b"},
      {"hyphens split by a soft hyphen", "a -\u00AD- b"},
      {"hyphen and a unicode hyphen", "a -\u2010 b"},
      {"fullwidth hyphens", "a \uFF0D\uFF0D b"},
      {"small em dash", "a \uFE58 b"},
      {"entity, named", "a &mdash; b"},
      {"entity, named en", "a &ndash; b"},
      {"entity, named, no semicolon", "a &mdash b"},
      {"entity, decimal", "a &#8212; b"},
      {"entity, hex", "a &#x2014; b"},
      {"entity, hex, upper", "a &#X2014; b"},
      {"entity, hyphens", "a &#45;&#45; b"},
      {"entity, doubly encoded", "a &amp;mdash; b"},
      {"entity, numeric ampersand", "a &#38;#8212; b"},
      {"escape, four digits", "a \\u2014 b"},
      {"escape, upper hex digits", "a \\u2E3A b"},
      {"escape, lower hex digits", "a \\u2e3a b"},
      {"escape, braces", "a \\u{2014} b"},
      {"escape, eight digits", "a \\U00002014 b"},
      {"escape, hyphens", "a \\u002d\\u002d b"},
      {"percent", "a %E2%80%94 b"},
      {"percent, lower", "a %e2%80%94 b"},
      {"percent, inside an escape", "a \\u0025E2%80%94 b"},
      {"tag characters spelling a double hyphen", "a \u{E002D}\u{E002D} b"},
      {"base64", "a 4oCU b"},
      {"base64, unpadded url-safe", "a 4oCUYQ b"},
      {"base64, padded", "a 4oCUYQ== b"},
      {"base64 of an escape", "a " <> Base.encode64("\\u2014") <> " b"},
      {"base64 of base64", "a " <> Base.encode64(Base.encode64("\u2014")) <> " b"}
    ]
  end

  @doc """
  Every smuggling form lands as an em dash in the canonical text, and the no-dash relation has
  no answer for it: the canonicaliser and the policy meet here.
  """
  @spec smuggled_dashes_are_seen() :: [String.t()]
  example smuggled_dashes_are_seen do
    for {label, raw} <- smuggled() do
      assert {:ok, text} = Canon.text(raw)
      assert String.contains?(text, @em), "not seen: #{label}"
      refute Derivation.holds?(NoDash.no_dash(), [NoDash.text(text)]), "not refused: #{label}"
      label
    end
  end

  @doc "Honest text that merely resembles an encoding is left alone."
  @spec honest_lookalikes_are_unflagged() :: [String.t()]
  example honest_lookalikes_are_unflagged do
    texts = [
      "state-of-the-art",
      "x-y and 10-20 and a_b-c",
      "AT&T and R&D and &nbsp; and &unknown; and 5 &lt; 6",
      "price 20%25 or %zz or 100%",
      "path C:\\users\\name and \\u12 and \\uZZZZ",
      "an encoded run %E2%80 with no complete character",
      "words like Introduction, Mississippi and abcdefgh decode to nothing with a dash",
      "SGVsbG8gd29ybGQ= is hello world",
      "emoji \\ud83d\\ude00 and a lone surrogate \\ud83d"
    ]

    for raw <- texts do
      assert {:ok, text} = Canon.text(raw)
      refute String.contains?(text, @em), raw
      raw
    end
  end

  @doc "The gaps are real, and listed here so no one has to guess where the policy stops."
  @spec known_gaps() :: [String.t()]
  example known_gaps do
    gaps = [
      {"minus sign", "a \u2212 b"},
      {"box drawing line", "a \u2500 b"},
      {"hex of the bytes", "a E28094 b"},
      {"base32 of the dash", "a " <> Base.encode32("\u2014") <> " b"},
      {"rot13 is a cipher, not a text encoding", "a bm-gb-ab b"},
      {"utf-16 inside base64", "a " <> Base.encode64(<<0x14, 0x20>>) <> " b"},
      {"base64 split across lines", "a 4o\nCU b"},
      {"the words em dash", "a em dash b"}
    ]

    for {label, raw} <- gaps do
      assert {:ok, text} = Canon.text(raw)
      refute String.contains?(text, @em), label
      label
    end
  end

  @doc "Nesting is followed eight levels, and a ninth is refused rather than guessed at."
  @spec nesting_is_bounded() :: Refusal.t()
  example nesting_is_bounded do
    nested = fn levels -> "&" <> String.duplicate("amp;", levels - 1) <> "mdash;" end

    assert {:ok, text} = Canon.text(nested.(8))
    assert text =~ @em
    assert {:error, refusal = {:encoding_unbounded, %{depth: 8}}} = Canon.text(nested.(9))

    deep = Enum.reduce(1..9, "\u2014", fn _, acc -> Base.encode64(acc) end)
    assert {:error, {:encoding_unbounded, %{depth: 8}}} = Canon.text(deep)
    refusal
  end

  @doc "Invalid bytes and NUL cannot become the padding sentinel or break the encoding."
  @spec invalid_bytes_and_nul() :: String.t()
  example invalid_bytes_and_nul do
    assert {:ok, text} = Canon.text(<<"a", 0, 0xFF, "b">>)
    assert text == "a\uFFFD\uFFFDb"
    refute 0 in NoDash.text(text)
    text
  end

  @doc "The canonicaliser hash is SHA-256 of its own source, which anyone can recompute."
  @spec source_hash() :: binary()
  example source_hash do
    source = Path.expand("../zkfol_ai_demo/canon.ex", __DIR__)
    assert Canon.source_hash() == :crypto.hash(:sha256, File.read!(source))
    Canon.source_hash()
  end
end
