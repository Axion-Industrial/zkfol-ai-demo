# Every solve without a branch: lands on one shared branch; installs
# retract by name, so examples stay isolated without paying the fork
# and discard per call. The branch goes when the suite does, so the
# store the next run forks from is the one this run started with.
branch = AL.Branch.fork()
Application.put_env(:zkfol, :branch, branch.id)

# The proving examples are tagged :prove; ZKFOL_PROVE=1 mix test runs them
# too, and with them the whole program space, which is minutes rather than
# the minute a test is given.
proving = System.get_env("ZKFOL_PROVE") == "1"

ExUnit.start(
  exclude: if(proving, do: [], else: [:prove]),
  timeout: if(proving, do: :infinity, else: 60_000)
)

ExUnit.after_suite(fn _results -> AL.Branch.discard(branch) end)
