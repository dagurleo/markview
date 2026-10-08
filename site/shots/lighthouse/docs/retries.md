# The maths of retries

If a single check fails spuriously with probability $p$, then $k$ retries all failing
spuriously happens with probability $p^{k+1}$. With $p = 0.01$:

| Retries $k$ | False alarm per check | False alarms a month (30 s checks) |
| :---------: | --------------------: | ---------------------------------: |
| 0 | $10^{-2}$ | 864 |
| 1 | $10^{-4}$ | 8.6 |
| 2 | $10^{-6}$ | 0.09 |

Two retries take a monthly false alarm to roughly one a year, at the price of
noticing a real outage $2 \times \text{timeout}$ later.

$$
\Pr[\text{page}] = \sum_{j=0}^{k} \binom{k}{j}\, p^{j}(1-p)^{k-j} \cdot \mathbb{1}[j = k]
$$
