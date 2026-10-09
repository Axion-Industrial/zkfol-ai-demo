defmodule Examples.EMailbox do
  @moduledoc """
  I am the two inboxes, shown as the OTP processes they are: supervised from startup, each
  keeping only what routes to it.
  """

  use ExExample

  import ExUnit.Assertions

  alias ZkfolAiDemo.Mailbox
  alias ZkfolAiDemo.Mailbox.Message

  @doc "Every example changes what the inboxes hold, so none is cached."
  @spec rerun?(term()) :: boolean()
  def rerun?(_example), do: true

  @doc "Both inboxes are children of the application's supervisor, running from startup."
  @spec inboxes_run_under_the_supervisor() :: [atom()]
  example inboxes_run_under_the_supervisor do
    children = ZkfolAiDemo.Supervisor |> Supervisor.which_children() |> Enum.map(&elem(&1, 0))

    assert Enum.sort(children) == [:allowed, :attacker]
    assert Enum.all?(children, &is_pid(Process.whereis(&1)))
    children
  end

  @doc "A message to two recipients is split: each inbox keeps a copy addressed to its own."
  @spec delivery_routes_by_recipient() :: {[Message.t()], [Message.t()]}
  example delivery_routes_by_recipient do
    Mailbox.clear()

    :ok =
      Mailbox.deliver(%Message{
        to: ["reports@corp.example", "someone@elsewhere.example"],
        subject: "first",
        body: "b",
        attachments: [{"list.csv", "a,b"}]
      })

    :ok = Mailbox.deliver(%Message{to: ["REPORTS@Corp.Example"], subject: "second", body: "b"})

    allowed = Mailbox.messages(:allowed)
    attacker = Mailbox.messages(:attacker)

    assert [%{to: ["reports@corp.example"], subject: "first"}, %{subject: "second"}] = allowed
    assert [%{to: ["someone@elsewhere.example"], attachments: [{"list.csv", "a,b"}]}] = attacker
    {allowed, attacker}
  end

  @doc "A crashed inbox is started again by the supervisor, empty."
  @spec a_crashed_inbox_is_restarted() :: pid()
  example a_crashed_inbox_is_restarted do
    Mailbox.clear()
    :ok = Mailbox.deliver(%Message{to: ["x@elsewhere.example"], subject: "s", body: "b"})
    assert [_one] = Mailbox.messages(:attacker)

    old = Process.whereis(:attacker)
    Process.exit(old, :kill)

    new = restarted(old, 100)
    assert Mailbox.messages(:attacker) == []
    new
  end

  @spec restarted(pid(), non_neg_integer()) :: pid()
  defp restarted(_old, 0), do: flunk("the supervisor did not restart the inbox")

  defp restarted(old, tries) do
    case Process.whereis(:attacker) do
      pid when is_pid(pid) and pid != old ->
        pid

      _ ->
        Process.sleep(10)
        restarted(old, tries - 1)
    end
  end
end
