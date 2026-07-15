defmodule Zkfol.Application do
  @moduledoc """
  I bring the node up: the command log's mnesia table exists before any
  statement writes to it, so no operation carries its own setup.
  """

  use Application

  @impl true
  @spec start(Application.start_type(), term()) :: {:ok, pid()}
  def start(_type, _args) do
    Zkfol.Log.setup()
    Supervisor.start_link([Zkfol.Prover], strategy: :one_for_one, name: Zkfol.Supervisor)
  end
end
