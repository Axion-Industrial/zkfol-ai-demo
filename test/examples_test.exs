defmodule Examples.EUserTest do
  use ExExample.ExUnit, for: Examples.EUser
end

defmodule Examples.EUairTest do
  use ExExample.ExUnit, for: Examples.EUair
end

defmodule Examples.EFaceTest do
  use ExExample.ExUnit, for: Examples.EFace
end

defmodule Examples.ELogTest do
  use ExExample.ExUnit, for: Examples.ELog
end

defmodule Examples.EAstTest do
  use ExExample.ExUnit, for: Examples.EAst
end

# Benchmarks assert our published numbers; BENCH=1 mix test runs them.
if System.get_env("BENCH") do
  defmodule Examples.EBenchTest do
    use ExExample.ExUnit, for: Examples.EBench
  end
end

defmodule Examples.EFactsTest do
  use ExExample.ExUnit, for: Examples.EFacts
end

defmodule Examples.EDoublingTest do
  use ExExample.ExUnit, for: Examples.EDoubling
end

defmodule Examples.EPipelineTest do
  use ExExample.ExUnit, for: Examples.EPipeline
end

defmodule Examples.EAlTest do
  use ExExample.ExUnit, for: Examples.EAl
end

defmodule Examples.ELookupTest do
  use ExExample.ExUnit, for: Examples.ELookup
end
