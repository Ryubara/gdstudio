# Studio

How GDStudio itself works: the agents and the loop from issue to merged pull request, the workspace and its pinned
tools, the hooks that enforce the rules, captures as proof, the files the kit syncs into games, and the studies of the
method, written so it can be repeated on another game or engine.

**Belongs here:** the workflow, the conventions and the tooling every game repository shares (`gds`, hooks, CI,
templates, the docs site). **Not here:** making a game (`gamedev/`, `engines/`, `tools/`) or one game's own story
(`games/<game>/`).

| Page | What it covers |
| --- | --- |
| [Workspace](workspace.md) | The folder layout, the bootstrap, and the pinned Godot and Blender. |
| [Agents](agents.md) | The roster, their models, and the loop from issue to merged pull request. |
| [Starting work](starting-work.md) | Issues start oldest first, through `gds issue start`; how the window works. |
| [Hooks](hooks.md) | What the hook dispatcher refuses while agents work, and the proof gate. |
| [Capture](capture.md) | Screenshots, clips and sound as proof you can look at, attached to pull requests. |
| [Sync](sync.md) | The kit-owned files every game carries, and `gds sync`. |
| [References](refs.md) | Fetching third-party models into `refs/` with their licences. |
| [Docs site](docs-site.md) | The topic folders and where a page goes, the Zensical build, its pin and its checks. |
| [Learning in the topic pages](rules.md) | What is learned goes into the topic pages: the entry format, `gds learn`, anchors and the checks. |
| [Building games with agents](building-games-with-agents.md) | The steps from the first prompt to a studio of agents, and how to reproduce it on another engine. |
| [What the maintainer caught](maintainer-corrections.md) | A log of the corrections the agents did not propose first, each linking the topic section it updated. |
| [What to plan from the start](plan-from-the-start.md) | A day-one checklist for the next game, from every gap nobody planned for on Deadnight. |
| [Reading an ask](asks.md) | Numbers, defaults and words about people in an ask; who owns a job already. |
| [CI and deploys](ci.md) | How runs on the default branch finish and how a merge reaches the live deploy. |
