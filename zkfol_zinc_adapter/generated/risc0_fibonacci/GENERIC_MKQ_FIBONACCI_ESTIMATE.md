# Literal generic mkQ/beta Fibonacci size estimate

These are ordinary-integer, non-modular Fibonacci sizes. They estimate the current explicit bit-level mkQ/beta bridge, not the direct benchmark export.

| n | F(n) bits | F(n) decimal digits | max bits | direct B wires | composed B bits | selector wires | lookup product lower bound | current generic constraint lower bound |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 100 | 69 | 21 | 69 | 27600 | 55200 | 20000 | 5520000 | 5623700 |
| 1000 | 694 | 209 | 694 | 2776000 | 5552000 | 2000000 | 5552000000 | 5562337000 |
| 10000 | 6942 | 2090 | 6942 | 277680000 | 555360000 | 200000000 | 5553600000000 | 5554633130000 |

The direct Fibonacci export exists because the current generic bit bridge would be dominated by private pointer lookup products for n=1000 and n=10000.
