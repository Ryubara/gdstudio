---
areas: [backend, tests]
---
# A before and after measured on two Railway deploys disagreed by a processor generation

2026-11-02

- **Saw:** the server bench of `main` and of a branch, each deployed to Railway on its own, gave step times 2 to 3 times
  apart in the wrong direction: the second deploy reported `Intel Xeon 6975P-C`, the first `Xeon Icelake`.
- **Cause:** a service lands on whatever host the scheduler picks; the container sees 48 vCPUs on both, so nothing
  but `/proc/cpuinfo` says the processor changed.
- **Fix:** one image with both builds (`/app-before`, `/app-after`) running interleaved in one container, the model name
  printed first; and read `p95` and the ticks over budget, not the mean, on a shared machine.
- **Docs:** [Deadnight crowd budget](https://github.com/Ryubara/deadnight/blob/main/docs/research/crowd-budget.md).
