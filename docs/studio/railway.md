# Railway

<!-- new section: the studio pages cover CI and the workspace; nothing held how an agent deploys and tests a service on
Railway with the logged-in CLI -->

Games run their web build, game server and backend as services of one Railway project, and an agent may create, deploy
and delete test projects and services with the logged-in `railway` CLI (never touching the account's other projects,
never committing tokens, scaling down what is not in use). How a merge reaches the live deploy is [CI and
deploys](ci.md); the game server image is on [Multiplayer in Godot](../engines/godot/multiplayer.md#headless-server-image).

## A throwaway service {#throwaway}

<!-- new section: nothing held the shortest commands for a test service -->

From the folder that holds the Dockerfile: `railway init -n <project>`, `railway add --service <name>`, `railway up
--ci -s <name>` (remote build, about a minute), `railway domain -s <name>` (a public `*.up.railway.app` with TLS at the
edge, so clients use `wss://`), `railway logs -s <name>`. The region is in `railway status --json` under
`multiRegionConfig`; the edge that answered is the `x-railway-edge` response header. `railway down -s <name> -y` stops
the service and keeps the project.

- **Approach:** Assume no inbound UDP on Railway and design the game for WebSocket and HTTP; delete a service with
  `railway service delete -s <name> -y` and a whole project only with `railway delete --project <id> --yes`. **Watch
  out for:** Railway documents HTTP, WebSocket and a TCP proxy only; `railway delete` deletes the project, and the
  project list shows it for two days with a `deletedAt` (a soft delete, not a failure). **Seen:** Deadnight,
  2026-11-01 (fix: the commands above); Deadnight, 2026-11-02 (delete).

## Which project a command acts on {#link}

<!-- new section: nothing covered how the CLI picks the project a command changes -->

- **Approach:** Run every `railway` command from the folder that is linked (`railway link -p <project> -e production`,
  from a scratch folder, never a game checkout) and pass a staging folder as the path (`railway up <stage>
  --path-as-root --service <name> --ci`); read `railway status` first when unsure. **Watch out for:** the link is
  stored per folder, and `railway up` from a folder that was never linked makes a project named after the folder
  instead of failing: a stray project ran a bench beside the account's own. **Seen:** Deadnight, 2026-11-02 (fix:
  `deploy/server/deploy.sh` passes the folder as the path and the stray project was deleted by id).
- **Approach:** Make a script that calls `railway` refuse to run with neither `RAILWAY_TOKEN` nor a linked project
  (`railway status` fails) before anything is uploaded, and probe such a script with its fake in a file under the
  scratch folder first, with `PATH` set to it alone and `command -v railway` checked. **Watch out for:** an `awk` cut
  that failed on a backslash left no fake, so a probe ran the real CLI logged in as the maintainer and made a project
  `stage` in the account. **Seen:** Deadnight #1269, 2026-11-05 (fix: the three deploy scripts refuse; a case in
  `deploy/test_railway_up.sh`).
- **Approach:** Prefix a CLI call whose value starts with a slash with `MSYS_NO_PATHCONV=1`, or run it from PowerShell,
  and read the value back after setting it. **Watch out for:** Git Bash rewrites an argument that looks like a POSIX
  path when it calls a Windows program: a variable set to `/server` arrived as `C:/Program Files/Git/server`, and the
  game server's first heartbeat failed with a 400. **Seen:** Deadnight, 2026-11-02 (fix: the prefix and a read back).

## Settings belong to the service, not the deployment {#service-settings}

<!-- new section: nothing covered what a deployment inherits from the service it belongs to -->

- **Approach:** Run a measurement that needs a different command in a service of its own in the test project (and delete
  it after), never as a change of the service that serves players; if a shared service must change, say so on the
  issue first, change it back in the command that ends the measurement, and read its settings and first log lines.
  **Watch out for:** a start command set with `serviceInstanceUpdate` is a setting of the service, so the next deploy by
  anyone built a deployment that ran the bench for fifteen minutes and listened on no port; `railway redeploy` ignores a
  new start command; setting the field to `null` answers `true` and changes nothing, the value must be written, and
  Railway runs it without a shell (`exec ...` fails). **Seen:** Deadnight #712, 2026-11-03 (fix: the Dockerfile's own
  command was written back and the log read for `event="listening"`).
- **Approach:** Put a bench service's command in the stage's Dockerfile (`CMD ["sh", "/app/bench.sh"]`), keep the script
  inside the uploaded folder, print `RESULT|<label>|<rep>|<json>` lines, end with `sleep`, read them with `railway
  logs --service <name>` and delete the service once the numbers are copied. **Watch out for:** a `railway.toml` with
  `[deploy] startCommand` beside the Dockerfile was not applied (the cause was not established) and the deployment
  started the game server. **Seen:** Deadnight, 2026-11-05 (fix: the command moved into the Dockerfile).

## Services deploy apart {#skew}

<!-- new section: nothing covered the services of one project being on different commits -->

- **Approach:** Before any live check, read `railway deployment list --service <name> --json` for the web build and the
  game server and wait for the same commit with nothing building; land a protocol bump server first, or let the server
  accept the previous version for one deploy. **Watch out for:** the web build and the game server are separate
  services that deploy on their own, minutes apart and in either order, so players were refused in between and a fix
  report was played on a build without the fix. **Seen:** Deadnight, 2026-11-02 (fix: the check above, from a
  scratch folder linked to the project).
- **Approach:** Compare a before and after inside one container, both builds in one image (`/app-before`, `/app-after`)
  run interleaved, with the processor model printed first, and read p95 and the ticks over budget, not the mean.
  **Watch out for:** two separate deploys landed on whatever host the scheduler picked (`Xeon Icelake` against
  `Intel Xeon 6975P-C`, 48 vCPUs on both) and gave step times 2 to 3 times apart, in the wrong direction. **Seen:**
  Deadnight, 2026-11-02 (fix: one image with both builds).
