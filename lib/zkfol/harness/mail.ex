defmodule Zkfol.Harness.Mail do
  @moduledoc """
  I send mail over SMTP to the local sinks, and nowhere else.

  A recipient at `corp.example` goes to the sink standing in for a real inbox, and any other
  recipient goes to the sink standing in for the attacker: the rest of the internet is
  modelled as one place, on loopback, that keeps what it receives.

  ### Public API

  - `start_sinks/0` starts the two sinks, empty.
  - `deliver/1` sends one message to the sink its recipient routes to.
  - `ports/0` and `dirs/0` say where the sinks listen and keep their mail.
  """

  use TypedStruct

  alias Zkfol.Harness.Sink
  alias Zkfol.Refusal

  @out Path.expand("../../../harness/out/sinks", __DIR__)
  @inside_port 2525
  @outside_port 2526

  typedstruct module: Outgoing, enforce: true do
    @typedoc "A message to send: recipients, subject, body, and attachments as `{name, bytes}`."
    field(:to, [String.t()])
    field(:subject, String.t())
    field(:body, String.t())
    field(:attachments, [{String.t(), binary()}], default: [])
  end

  @doc "I am the port each sink listens on."
  @spec ports() :: %{allowed: pos_integer(), attacker: pos_integer()}
  def ports, do: %{allowed: @inside_port, attacker: @outside_port}

  @doc "I am the directory each sink keeps its mail in."
  @spec dirs() :: %{allowed: Path.t(), attacker: Path.t()}
  def dirs, do: %{allowed: Path.join(@out, "allowed"), attacker: Path.join(@out, "attacker")}

  @doc "I start the two sinks if they are not running, and empty them either way."
  @spec start_sinks() :: :ok
  def start_sinks do
    for {name, key} <- [sink_allowed: :allowed, sink_attacker: :attacker] do
      dir = Map.fetch!(dirs(), key)

      case Process.whereis(name) do
        nil -> {:ok, _pid} = Sink.start_link(name: name, port: Map.fetch!(ports(), key), dir: dir)
        _pid -> Sink.clear(dir)
      end
    end

    :ok
  end

  @doc "I send `message` to each recipient's sink, one delivery per sink."
  @spec deliver(Outgoing.t()) :: :ok | {:error, Refusal.t()}
  def deliver(%Outgoing{to: recipients} = message) do
    recipients
    |> Enum.group_by(&port/1)
    |> Enum.reduce_while(:ok, fn {port, group}, :ok ->
      case send_to(port, group, message) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  @spec port(String.t()) :: pos_integer()
  defp port(recipient) do
    if recipient |> String.downcase() |> String.ends_with?("@corp.example"),
      do: @inside_port,
      else: @outside_port
  end

  @spec send_to(pos_integer(), [String.t()], Outgoing.t()) :: :ok | {:error, Refusal.t()}
  defp send_to(port, recipients, message) do
    with {:ok, socket} <- connect(port),
         :ok <- expect(socket, "220"),
         :ok <- command(socket, "HELO harness", "250"),
         :ok <- command(socket, "MAIL FROM:<assistant@corp.example>", "250"),
         :ok <- each_recipient(socket, recipients),
         :ok <- command(socket, "DATA", "354"),
         :ok <- :gen_tcp.send(socket, mime(%{message | to: recipients}) <> "\r\n.\r\n"),
         :ok <- expect(socket, "250"),
         :ok <- command(socket, "QUIT", "221") do
      :gen_tcp.close(socket)
    else
      {:error, reason} -> {:error, {:send_failed, %{reason: reason}}}
    end
  end

  @spec connect(pos_integer()) :: {:ok, port()} | {:error, term()}
  defp connect(port),
    do: :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, packet: :line, active: false], 5_000)

  @spec each_recipient(port(), [String.t()]) :: :ok | {:error, term()}
  defp each_recipient(socket, recipients) do
    Enum.reduce_while(recipients, :ok, fn recipient, :ok ->
      case command(socket, "RCPT TO:<#{recipient}>", "250") do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  @spec command(port(), String.t(), String.t()) :: :ok | {:error, term()}
  defp command(socket, line, code) do
    with :ok <- :gen_tcp.send(socket, line <> "\r\n"), do: expect(socket, code)
  end

  @spec expect(port(), String.t()) :: :ok | {:error, term()}
  defp expect(socket, code) do
    case :gen_tcp.recv(socket, 0, 10_000) do
      {:ok, <<^code::binary-size(3), _::binary>>} -> :ok
      {:ok, other} -> {:error, {:unexpected_reply, String.trim(other)}}
      {:error, _} = error -> error
    end
  end

  @spec mime(Outgoing.t()) :: String.t()
  defp mime(%Outgoing{to: to, subject: subject, body: body, attachments: attachments}) do
    boundary = "harness-" <> Base.encode16(:crypto.strong_rand_bytes(6), case: :lower)

    parts =
      for {name, bytes} <- attachments do
        [
          "--#{boundary}\r\nContent-Type: application/octet-stream\r\n",
          "Content-Disposition: attachment; filename=\"#{name}\"\r\n",
          "Content-Transfer-Encoding: base64\r\n\r\n",
          bytes |> Base.encode64() |> chunk(),
          "\r\n"
        ]
      end

    IO.iodata_to_binary([
      "From: assistant@corp.example\r\nTo: #{Enum.join(to, ", ")}\r\nSubject: #{subject}\r\n",
      "MIME-Version: 1.0\r\nContent-Type: multipart/mixed; boundary=\"#{boundary}\"\r\n\r\n",
      "--#{boundary}\r\nContent-Type: text/plain; charset=utf-8\r\n\r\n#{dot_stuff(body)}\r\n",
      parts,
      "--#{boundary}--"
    ])
  end

  @spec chunk(String.t()) :: String.t()
  defp chunk(text),
    do: text |> String.graphemes() |> Enum.chunk_every(76) |> Enum.map_join("\r\n", &Enum.join/1)

  # A body line holding only a dot would end the message early.
  @spec dot_stuff(String.t()) :: String.t()
  defp dot_stuff(body),
    do:
      body
      |> String.replace("\r\n", "\n")
      |> String.replace(~r/^\./m, "..")
      |> String.replace("\n", "\r\n")
end
