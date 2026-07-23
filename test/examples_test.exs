defmodule Examples.EPowerTest do
  use ExExample.ExUnit, for: Examples.EPower
end

defmodule Examples.ELogTest do
  use ExExample.ExUnit, for: Examples.ELog
end

defmodule Examples.EAstTest do
  use ExExample.ExUnit, for: Examples.EAst
end

defmodule Examples.ELangTest do
  use ExExample.ExUnit, for: Examples.ELang
end

# Benchmarks assert our published numbers; BENCH=1 mix test runs them.
if System.get_env("BENCH") do
  defmodule Examples.EBenchTest do
    use ExExample.ExUnit, for: Examples.EBench
  end
end

defmodule Examples.EFibonacciTest do
  use ExExample.ExUnit, for: Examples.EFibonacci
end

defmodule Examples.EFactorialTest do
  use ExExample.ExUnit, for: Examples.EFactorial
end

defmodule Examples.EFactsTest do
  use ExExample.ExUnit, for: Examples.EFacts
end

defmodule Examples.EEfficientPowerTest do
  use ExExample.ExUnit, for: Examples.EEfficientPower
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

defmodule Examples.EAccumulatorTest do
  use ExExample.ExUnit, for: Examples.EAccumulator
end

defmodule Examples.ELookupTest do
  use ExExample.ExUnit, for: Examples.ELookup
end
