# Large power input size summary

For the practical meaning of power benchmark options such as `--power-profile`, `--skip-256`, `--skip-standard`, and `--allow-large`, see `docs/OPTIONS_REFERENCE.md` or run `./zkfol_zinc_adapter/folzinc options`.

These are local exporter/R1CS-check results from the Python side of version 0.3.0.
They do **not** include Zinc proof-generation or verification timings; collect
those with `zkfol-zinc-bench run-zinc` on a machine with Rust/Cargo >= 1.85.

| case | len(C) | max bits | public inputs | constraints | witness vars | z len | largest integer bits | local Python export+check note |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `standard_power_2_32_public` | 33 | 33 | 4 | 120123 | 116754 | 116759 | 64 | exported and checked |
| `efficient_power_2_32_public` | 7 | 33 | 4 | 7325 | 6608 | 6613 | 65 | exported and checked |
| `efficient_power_2_256_public` | 10 | 257 | 4 | 103063 | 95320 | 95325 | 513 | exported and checked; compact JSON about 18 MiB in this environment |

For the `2^256` case, the public inputs are:

```text
public_zero = 0
claim_final_base = 2
claim_final_exponent = 256
claim_final_output = 115792089237316195423570985008687907853269984665640564039457584007913129639936
```

Constraint breakdown for `efficient_power_2_256_public`:

| category | count |
| --- | ---: |
| `mkq_arithmetic_gates` | 130 |
| `mkq_zero_checks` | 10 |
| `pointer_range_one_hot_checks` | 10 |
| `pointer_range_value_checks` | 10 |
| `pointer_lookup_selector_products` | 77100 |
| `pointer_lookup_bit_equalities` | 7710 |
| `booleanity_bit_checks` | 18090 |
| `public_input_binding_checks` | 3 |
| `other` | 0 |

The pointer-lookup rows dominate.  This is expected for the explicit R1CS/CCS
bridge and is exactly the overhead that a native AIR implementation should try to
avoid or reduce.
