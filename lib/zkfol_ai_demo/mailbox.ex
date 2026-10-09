defmodule ZkfolAiDemo.Mailbox do
  @moduledoc """
  I am an inbox: a process that keeps every message it is given and sends nothing anywhere.
  Two of them run under the application's supervisor from startup, standing in for a real
  recipient and for an attacker, so what the demo shows is an inbox that filled and an inbox
  that did not.

  A recipient at `corp.example` is the `:allowed` inbox's, and any other recipient is the
  `:attacker` inbox's: the rest of the internet is modelled as one place that keeps what it
  receives. Nothing leaves the VM.

  ### Public API

  - `inboxes/0` names the two inboxes.
  - `start_link/1` starts one, under its own name.
  - `deliver/1` sends a message to the inbox each of its recipients routes to.
  - `messages/1` lists what an inbox holds, oldest first.
  - `clear/0` empties both inboxes.
  """

  use GenServer
  use TypedStruct

  typedstruct module: Message, enforce: true do
    @typedoc "A message: recipients, subject, body, and attachments as `{name, bytes}`."
    field(:to, [String.t()])
    field(:subject, String.t())
    field(:body, String.t())
    field(:attachments, [{String.t(), binary()}], default: [])
  end

  @type inbox :: :allowed | :attacker

  @inboxes [:allowed, :attacker]

  ############################################################
  #                        Public API                        #
  ############################################################

  @doc "I name the two inboxes."
  @spec inboxes() :: [inbox()]
  def inboxes, do: @inboxes

  @doc "I start the inbox `inbox`, registered under its own name."
  @spec start_link(inbox()) :: GenServer.on_start()
  def start_link(inbox), do: GenServer.start_link(__MODULE__, [], name: inbox)

  @doc "I send `message` to each inbox one of its recipients routes to, with only those recipients."
  @spec deliver(Message.t()) :: :ok
  def deliver(%Message{to: recipients} = message) do
    for {inbox, group} <- Enum.group_by(recipients, &inbox/1),
        do: GenServer.call(inbox, {:deliver, %{message | to: group}})

    :ok
  end

  @doc "I list the messages an inbox holds, oldest first."
  @spec messages(inbox()) :: [Message.t()]
  def messages(inbox), do: GenServer.call(inbox, :messages)

  @doc "I empty both inboxes."
  @spec clear() :: :ok
  def clear do
    for inbox <- @inboxes, do: GenServer.call(inbox, :clear)
    :ok
  end

  ############################################################
  #                    GenServer Callbacks                   #
  ############################################################

  @impl true
  def init([]), do: {:ok, []}

  @impl true
  def handle_call({:deliver, message}, _from, held), do: {:reply, :ok, [message | held]}
  def handle_call(:messages, _from, held), do: {:reply, Enum.reverse(held), held}
  def handle_call(:clear, _from, _held), do: {:reply, :ok, []}

  ############################################################
  #                   Private Implementation                 #
  ############################################################

  @spec inbox(String.t()) :: inbox()
  defp inbox(recipient) do
    if recipient |> String.downcase() |> String.ends_with?("@corp.example"),
      do: :allowed,
      else: :attacker
  end
end
