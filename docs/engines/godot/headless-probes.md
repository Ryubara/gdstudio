# Probes and tools in headless Godot

A probe is a throwaway run that builds part of a game and prints what it saw (a navigation path, a night's first
minutes). How it is started decides what it can build.

- **`godot --headless --path <game> -s probe.gd`** (a `SceneTree` script) runs before the project's autoloads exist:
  any script in the chain that names one (`UIRouter`, `Audio`, a settings singleton) fails to compile, the error is
  `Identifier not found: <Autoload>` and the build dies inside `_init`. Fine for a navigation mesh or a scene that has
  no autoload in it; useless for a night. The other way round: a class that `-s`
  tools load (a game's player, its animation, holds and grips) must not name an autoload; find the service by its node
  (`get_tree().root.get_node_or_null(^"Audio")`) and `call` it.
- **A `SceneTree` script's root is not in the tree in `_init` or `_initialize`.** `global_position` then reads the
  origin, and the only trace is `!is_inside_tree()` in the log, so a check that passes when nothing is hit passes from
  the wrong place. Add with `get_root().add_child.call_deferred(node)`, `await process_frame` twice, fail if
  `not node.is_inside_tree()`, and give the check a control that must hit.
- **A scene** (`godot --headless --path <game> res://tests/captures/probe.tscn -- --arg=value`) has them. Read the
  arguments with `OS.get_cmdline_user_args()`, print one line of JSON at the end, end with `get_tree().quit()`, and
  write the output to a file (`> log 2>&1`), then read the file: a pipe into `tail` shows nothing until the run ends.
- **Every run gets a `timeout`**, and the first seconds of its log are searched for `SCRIPT ERROR`: a script that fails
  to compile, or fails in `_init` before `quit()`, never ends.
- **A fresh worktree has no test addon and no import cache**: copy the GdUnit4 addon and run `--import` once before the
  first run (about a minute), as [a fresh checkout](running-gdunit.md#fresh-checkout) says.
- **Write the probe with the file tool, not a heredoc** ([Writing a probe](#writing-a-probe)).

## Writing a probe {#writing-a-probe}

<!-- new section: the page said how a probe is started; nothing said how to write or edit its script safely -->

- **Approach:** Write a probe, a test or an edit script with the Write tool and run an edit script as a `.py` file
  (`python file.py args`); use the Edit tool for text that holds a backslash; keep a shell heredoc for a few plain ASCII
  lines; scan generated files for control characters, lint generated workflows (actionlint) and test generated
  regexes. **Watch out for:** the command text goes through the tool's escape step before the shell: a 200-line file
  with quotes failed with `unexpected EOF` and wrote nothing, a regex word boundary became a backspace (a hook silently
  never matched), a backslash-n became a real newline, and a backslash line continuation in a workflow collapsed.
  **Seen:** Deadnight #457, 2026-11-01; kit #165, 2026-11-02; Deadnight #1080, 2026-11-04 (fix: Write for any body of
  more than a few plain lines; a unit test and actionlint caught the regex and the workflow).
- **Approach:** After a scripted edit of a `.gd` file run `gdformat` on it (it parses) before starting a run that takes
  minutes, build a splice from markers that occur once (assert the order and the count), and read a long run's log
  after ten seconds, not at its end. **Watch out for:** a one-off cut a function between two `index()` calls on
  markers, the first also occurred earlier, so `s[:a] + new + s[b:]` with `b < a` copied half the file twice; two
  ten-minute soaks printed `Could not resolve class "SoakWatch"` and were read only when they ended. **Seen:**
  Deadnight, 2026-11-03 (fix: the splice was rewritten from the intact copy).

## Processes a probe starts {#processes}

<!-- new section: nothing said how a probe cleans up the programs it starts when it is killed -->

- **Approach:** Stop a server a probe starts with `taskkill /T /F /PID <pid>` (the tree) in a `finally`, give the probe
  a hard time limit of its own (`timeout`, `gds quiet --timeout`) shorter than the tool's, and after a killed run find
  what it left by command line (`Get-CimInstance Win32_Process`, filtered on the scratch folder), never by image name,
  and stop those by PID. **Watch out for:** on Windows the console build of Godot is a wrapper that starts the real
  program, so `Popen.kill()` and `OS.kill` end only the wrapper, and nothing runs when the parent is killed: the next
  run failed with `PermissionError: [WinError 32]` on the server's log with two Godot processes and about 600 MB held.
  **Seen:** Deadnight #502, 2026-11-02 (fix: the probe's `finally` and its own time limit).
- **Approach:** Read a Godot program's memory from the largest of `psutil.Process(pid).children(recursive=True)`, never
  from the PID `Popen` returned. **Watch out for:** that PID is the console wrapper's, so a server's memory read 7 MB
  working set; its child held 180 MB. **Seen:** gdstudio #904, 2026-11-10 (the two-process run's harness).

## Runs that never end {#runs-that-never-end}

<!-- new section: the page was one list of bullets with no section for entries; this holds the hang family -->

- **Approach:** Give every headless tool run a short `timeout`, write its log to a file and read the first seconds for
  `SCRIPT ERROR` (or run `godot --headless --check-only -s <script>` first), put `quit()` where an error cannot skip
  it, start the work after `await process_frame`, check `FileAccess.open` for null (`push_error`, `quit(1)`), pass an
  absolute `--out` (a relative one resolves inside the project), and exit 1 when nothing was measured. **Watch out
  for:** a `-s` SceneTree script that fails to parse, or errors in `_init` or `_initialize` before `quit()`, never
  quits: the engine keeps an empty main loop (30 minutes idle; nine runs left at full CPU after `store_string` on a
  null file; six silent minutes through a pipe into `tail`). **Seen:** Deadnight #415, #460, 2026-11-01; Deadnight,
  2026-11-02 (a report script with a parse error in a class it used).

## A parse error is reported on its users {#parse-errors}

<!-- new section: nothing on the page told a probe's author where the real parse error shows -->

- **Approach:** On `Could not parse global class "X"` or `Failed to compile depended scripts`, run `godot --headless
  --path game --check-only --script res://path/to/the_script.gd` on the script the error names before reading the
  files it points at, and grep a class for a name before adding a function or a variable to it. **Watch out for:**
  Godot reports the real error only when that script is loaded on its own: its users get the generic `Cannot infer the
  type of "fight" variable` and nothing names the file that is wrong (a new method `_order` had the name of an
  existing member variable). **Seen:** Deadnight #641, 2026-11-03 (fix: the method got another name).

## An engine error from a player's own file {#engine-errors-from-input}

<!-- new section: the probes above read the engine's error log; nothing said which engine calls write to it on bad
input -->

A smoke run or a probe that fails on `^ERROR` in the log also fails on an error the engine logs for bad input, though
the code handled it.

- **Approach:** Parse text from a player's disk or the network with a `JSON` instance (`var json := JSON.new()`, then
  `json.parse(text) != OK`, and `json.data`), which fails silently, never with `JSON.parse_string`. **Watch out for:**
  `JSON.parse_string` reports a syntax error in the engine's error log as well as returning null, so a test of a
  damaged save printed `ERROR: Parse JSON failed` and the smoke run, which greps for `^ERROR`, went red. **Seen:**
  Deadnight, 2026-11-01 (fix: an instance for every file from a disk or the network).
