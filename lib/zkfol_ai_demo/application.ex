defmodule ZkfolAiDemo.Application do
  @moduledoc """
  I am the demo's OTP application: on startup I put the two inboxes under a supervisor, so
  they are running before any act asks for them, and a crashed inbox is started again.
  """

  use Application

  alias ZkfolAiDemo.Mailbox

  @impl true
  def start(_type, _args) do
    children =
      for inbox <- Mailbox.inboxes(), do: Supervisor.child_spec({Mailbox, inbox}, id: inbox)

    Supervisor.start_link(children, strategy: :one_for_one, name: ZkfolAiDemo.Supervisor)
  end
end
