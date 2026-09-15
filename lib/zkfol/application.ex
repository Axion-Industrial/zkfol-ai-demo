defmodule Zkfol.Application do
  @moduledoc "I bring the node up: the command log, then the prover."

  use Application

  @impl true
  @spec start(Application.start_type(), term()) :: {:ok, pid()}
  def start(_type, _args) do
    Zkfol.Log.setup()
    GtBridge.View.register(Zkfol.Face)
    Supervisor.start_link([Zkfol.Prover], strategy: :one_for_one, name: Zkfol.Supervisor)
  end
end
