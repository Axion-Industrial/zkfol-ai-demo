defmodule Zkfol.Harness.Sink do
  @moduledoc """
  I am a mail sink: a minimal SMTP server on the loopback interface that keeps every message
  it is given as a file and sends nothing anywhere. Two of them stand in for a real recipient
  and a real attacker, so what the demo shows is an inbox that filled and an inbox that did not.

  Each message is one `.eml` file in the sink's directory, so a second terminal can watch the
  inbox with nothing but `ls`.

  ### Public API

  - `start_link/1` starts a sink on a port, keeping its mail in a directory.
  - `messages/1` lists the messages in a sink's directory, oldest first.
  - `clear/1` empties a sink's directory.
  """

  use GenServer
  use TypedStruct

  typedstruct module: Message, enforce: true do
    @typedoc "A message a sink kept: who it was for, its subject, and the attachments it carried."
    field(:to, [String.t()])
    field(:subject, String.t())
    field(:attachments, [String.t()])
    field(:path, Path.t())
  end

  @type option :: {:name, atom()} | {:port, :inet.port_number()} | {:dir, Path.t()}

  ############################################################
  #                        Public API                        #
  ############################################################

  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))

  @doc "I list the messages kept in `dir`, oldest first."
  @spec messages(Path.t()) :: [Message.t()]
  def messages(dir) do
    for path <- dir |> Path.join("*.eml") |> Path.wildcard() |> Enum.sort(), do: parse(path)
  end

  @doc "I empty `dir`, making it first if it is missing."
  @spec clear(Path.t()) :: :ok
  def clear(dir) do
    File.mkdir_p!(dir)
    for path <- Path.wildcard(Path.join(dir, "*.eml")), do: File.rm!(path)
    :ok
  end

  ############################################################
  #                    GenServer Callbacks                   #
  ############################################################

  @impl true
  def init(opts) do
    dir = Keyword.fetch!(opts, :dir)
    clear(dir)

    # Loopback only: there is no route out of this socket.
    {:ok, listener} =
      :gen_tcp.listen(Keyword.fetch!(opts, :port), [
        :binary,
        packet: :line,
        active: false,
        reuseaddr: true,
        ip: {127, 0, 0, 1}
      ])

    {:ok, _pid} = Task.start_link(fn -> accept(listener, dir) end)
    {:ok, %{listener: listener, dir: dir}}
  end

  ############################################################
  #                   Private Implementation                 #
  ############################################################

  @spec accept(port(), Path.t()) :: no_return()
  defp accept(listener, dir) do
    {:ok, socket} = :gen_tcp.accept(listener)
    {:ok, pid} = Task.start(fn -> session(socket, dir) end)
    :ok = :gen_tcp.controlling_process(socket, pid)
    accept(listener, dir)
  end

  @spec session(port(), Path.t()) :: :ok
  defp session(socket, dir) do
    reply(socket, "220 sink ready")
    converse(socket, dir)
  end

  @spec converse(port(), Path.t()) :: :ok
  defp converse(socket, dir) do
    case :gen_tcp.recv(socket, 0, 30_000) do
      {:ok, line} -> command(String.upcase(line), socket, dir)
      {:error, _} -> :gen_tcp.close(socket)
    end
  end

  @spec command(String.t(), port(), Path.t()) :: :ok
  defp command("DATA" <> _, socket, dir) do
    reply(socket, "354 end data with a line holding only a dot")
    body = read_data(socket, [])

    path =
      Path.join(
        dir,
        "#{System.unique_integer([:monotonic, :positive]) |> Integer.to_string() |> String.pad_leading(8, "0")}.eml"
      )

    File.write!(path, body)
    reply(socket, "250 kept")
    converse(socket, dir)
  end

  defp command("QUIT" <> _, socket, _dir) do
    reply(socket, "221 bye")
    :gen_tcp.close(socket)
  end

  defp command(_other, socket, dir) do
    reply(socket, "250 ok")
    converse(socket, dir)
  end

  @spec read_data(port(), [String.t()]) :: String.t()
  defp read_data(socket, lines) do
    case :gen_tcp.recv(socket, 0, 30_000) do
      {:ok, ".\r\n"} -> lines |> Enum.reverse() |> Enum.join()
      {:ok, line} -> read_data(socket, [line | lines])
      {:error, _} -> lines |> Enum.reverse() |> Enum.join()
    end
  end

  @spec reply(port(), String.t()) :: :ok
  defp reply(socket, line), do: :gen_tcp.send(socket, line <> "\r\n")

  @spec parse(Path.t()) :: Message.t()
  defp parse(path) do
    text = File.read!(path)

    %Message{
      to: header(text, "To") |> String.split(~r/[,;]/, trim: true) |> Enum.map(&String.trim/1),
      subject: header(text, "Subject"),
      attachments: for([_, name] <- Regex.scan(~r/filename="([^"]+)"/, text), do: name),
      path: path
    }
  end

  @spec header(String.t(), String.t()) :: String.t()
  defp header(text, name) do
    case Regex.run(~r/^#{name}: (.*)\r?$/m, text) do
      [_, value] -> String.trim(value)
      nil -> ""
    end
  end
end
