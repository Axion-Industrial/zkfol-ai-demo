defmodule Zkfol.Harness.Show do
  @moduledoc """
  I am how the demo prints: wide banners, one fact a line, and colour that survives a
  projector. Nothing here decides anything; every verdict is printed by the caller.

  ### Public API

  - `title/1`, `step/1`, `good/1`, `bad/1`, `rejected/1`, `note/1` and `kv/2` print one line each.
  - `banner/2` prints a boxed, coloured banner, and `inbox/3` an inbox.
  - `text/1` prints a text with every dash highlighted, and `dashes/1` counts them.
  """

  @dash_pattern ~r/[\x{2012}-\x{2015}\x{2E3A}\x{2E3B}\x{2E40}]|-{2,}/u

  @doc "I print a full-width heading."
  @spec title(String.t()) :: :ok
  def title(text) do
    rule = String.duplicate("=", width())

    IO.puts([
      "\n",
      IO.ANSI.bright(),
      rule,
      "\n  ",
      String.upcase(text),
      "\n",
      rule,
      IO.ANSI.reset()
    ])
  end

  @doc "I print a step heading."
  @spec step(String.t()) :: :ok
  def step(text),
    do: IO.puts(["\n", IO.ANSI.bright(), IO.ANSI.cyan(), ">> ", text, IO.ANSI.reset()])

  @doc "I print a success line, in green."
  @spec good(String.t()) :: :ok
  def good(text),
    do: IO.puts([IO.ANSI.bright(), IO.ANSI.green(), "   [PASS] ", text, IO.ANSI.reset()])

  @doc "I print a failure line, in red."
  @spec bad(String.t()) :: :ok
  def bad(text),
    do: IO.puts([IO.ANSI.bright(), IO.ANSI.red(), "   [FAIL] ", text, IO.ANSI.reset()])

  @doc "I print a rejection, in red: what the verifier does with a proof that does not hold."
  @spec rejected(String.t()) :: :ok
  def rejected(text),
    do: IO.puts([IO.ANSI.bright(), IO.ANSI.red(), "   [REJECTED] ", text, IO.ANSI.reset()])

  @doc "I print an inbox: its title, and a line for each message, or a large `(empty)`."
  @spec inbox(String.t(), atom(), [Zkfol.Harness.Sink.Message.t()]) :: :ok
  def inbox(title, colour, messages) do
    IO.puts([
      "\n",
      IO.ANSI.bright(),
      apply(IO.ANSI, colour, []),
      "   +-- ",
      title,
      " : #{length(messages)} message(s)",
      IO.ANSI.reset()
    ])

    case messages do
      [] ->
        IO.puts([IO.ANSI.bright(), "   |      (empty)", IO.ANSI.reset()])

      messages ->
        for {message, n} <- Enum.with_index(messages, 1) do
          attached =
            if message.attachments == [],
              do: "",
              else: "   [attached: #{Enum.join(message.attachments, ", ")}]"

          IO.puts([
            "   |  ",
            to_string(n),
            ". to ",
            Enum.join(message.to, ", "),
            ": ",
            message.subject,
            attached
          ])
        end
    end

    :ok
  end

  @doc "I print a plain note."
  @spec note(String.t()) :: :ok
  def note(text), do: IO.puts(["   ", text])

  @doc "I print a labelled value."
  @spec kv(String.t(), term()) :: :ok
  def kv(label, value), do: IO.puts(["   ", String.pad_trailing(label, 26), to_string(value)])

  @doc "I print a banner of `lines`, in `colour` (`:red`, `:green` or `:yellow`), full width."
  @spec banner(atom(), [String.t()]) :: :ok
  def banner(colour, lines) do
    rule = String.duplicate("#", width())
    body = for line <- lines, do: ["#  ", line, "\n"]

    IO.puts([
      "\n",
      IO.ANSI.bright(),
      apply(IO.ANSI, colour, []),
      rule,
      "\n",
      body,
      rule,
      IO.ANSI.reset()
    ])
  end

  @doc "I print `text` indented, every dash reverse-highlighted in red."
  @spec text(String.t()) :: :ok
  def text(text) do
    marked =
      Regex.replace(@dash_pattern, text, fn dash ->
        IO.ANSI.red_background() <> IO.ANSI.white() <> IO.ANSI.bright() <> dash <> IO.ANSI.reset()
      end)

    for line <- String.split(marked, "\n"), do: IO.puts(["   | ", line])
    :ok
  end

  @doc "I count the dashes `text/1` would highlight."
  @spec dashes(String.t()) :: non_neg_integer()
  def dashes(text), do: @dash_pattern |> Regex.scan(text) |> length()

  @spec width() :: pos_integer()
  defp width do
    case :io.columns() do
      {:ok, columns} -> min(columns, 100)
      {:error, _} -> 80
    end
  end
end
