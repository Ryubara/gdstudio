---
areas: [tools, process]
---
# A refusal counter that never reset let a resumed agent's second stall go free

2026-11-02

- **Saw:** the stall gate (`stop_stall`, kit #155) refuses an agent's stalled end twice, then lets it go. An agent that
  was let go, resumed with a message and stalled again the same day was never refused: kit #156.
- **Cause:** the refusal count is kept per `agent_id` and was dropped only after a day. The first stall spent the
  count, and a resumed agent keeps its `agent_id`, so the second stall started above the limit. The tests ran one stall
  per agent, so none of them resumed an agent.
- **Fix:** an end that is let through (it reads as a report, or the limit was reached) removes the agent's entry, so
  each stall gets its own refusals. The test runs stall, two refusals, an allowed end, a resume and a second stall.
- **Check:** a counter that bounds a gate needs a reset at the event that ends the thing it counts; test the counter
  across the whole life of the key (end, resume, end again), not one pass.
- **Docs:** [Hooks](../studio/hooks.md#stall).
