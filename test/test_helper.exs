# Every solve without a branch: lands on one shared branch; installs
# retract by name, so examples stay isolated without paying the fork
# and discard per call. The branch is left behind: the test store is
# disposable, and the next run forks its own.
Application.put_env(:zkfol, :branch, AL.Branch.fork().id)
ExUnit.start()
