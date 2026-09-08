# Every solve lands on the head branch. The suite checks out a fork
# and discards it after, so its installs and their command log go with
# it and the store the next run finds is the one this run found.
branch = AL.Branch.fork()
AL.Branch.checkout(branch)

# The proving examples are tagged :prove; ZKFOL_PROVE=1 mix test runs them
# too, and with them the whole program space, which is minutes rather than
# the minute a test is given.
proving = System.get_env("ZKFOL_PROVE") == "1"

ExUnit.start(
  exclude: if(proving, do: [], else: [:prove]),
  timeout: if(proving, do: :infinity, else: 60_000)
)

ExUnit.after_suite(fn _results -> AL.Branch.discard(branch) end)
