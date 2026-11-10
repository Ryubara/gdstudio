+++
agent = "backend-engineer"
kind = "service"
deliver = ["service/"]
read = [
  "gamedev/backend.md#http",
  "gamedev/backend.md#tests",
  "gamedev/netcode.md#client-input",
]

[limits]
min_tests = 8
min_acceptance = 15
min_log_lines = 50
+++

# Build a lobby service

GDStudio games sit behind a platform backend that hands players a game-server address. Build the smallest honest
version of its lobby part: a small HTTP service, run unattended, with the tests, lint and run instructions a teammate
needs. The folder `service/` in this one is yours; use Python 3.12 or newer, managed with `uv`, and any framework you
like (or none). Nothing is stored beyond the process: lobbies live in memory.

## How it runs

- From `service/`, `uv run python -m lobby` starts it, listening on `127.0.0.1` at `PORT`. Your own tests run with
  `uv run pytest` from `service/` (declare pytest in the project's dev group).
- Settings come from the environment, never from files: `PORT`, `API_TOKEN` (every call except `/health` must carry
  it as `Authorization: Bearer <token>`; the service **refuses to start**, exiting with a non-zero code, when it is
  missing), `GAME_SERVER_HOST` and `GAME_SERVER_PORT_BASE` (an integer). Document all four in `service/README.md`.
- It logs one JSON object per request to standard output with at least `method`, `path` and `status` (add what helps),
  and never writes the token, or any `Authorization` header, to a log.
- `service/Dockerfile` builds it into an image that checks its own `/health` (`HEALTHCHECK`).

## The API

All bodies and answers are JSON (`Content-Type: application/json`); an error answer is `{"error": "<message>"}`.

| Call | Answer |
| --- | --- |
| `GET /health` (no token) | `200 {"status": "ok"}` |
| any other call without the right token | `401 {"error": "unauthorized"}` |
| `POST /lobbies` `{"name": str, "capacity": int}`: a name of 1 to 32 characters, a capacity from 2 to 8 (a boolean is not an integer) | `201` the lobby: `{"id": str, "name", "capacity", "players": [], "state": "open", "game_server": null}`; invalid input `422`; a body that is not a JSON object `400`; a body over 4096 bytes `413` |
| `GET /lobbies`, optionally `?state=open` | `200 {"lobbies": [lobby, ...]}` in creation order |
| `GET /lobbies/{id}` | `200` the lobby; unknown `404` |
| `POST /lobbies/{id}/join` `{"player": str}`: 1 to 24 characters | `200` the lobby with the player added at the end of `players`; invalid `422`; unknown lobby `404`; the player is already in this or any other lobby, or the lobby is not `open` `409` |
| `POST /lobbies/{id}/leave` `{"player": str}` | `200` the lobby; the player is not in it `404`; the lobby is already `full` `409` |
| `DELETE /lobbies/{id}` | `204` with no body, only for an empty lobby (`409` otherwise); unknown `404` |
| any other path `404`, any other method on a known path `405` | |

When the last place of a lobby is taken its `state` becomes `"full"` and its `game_server` becomes `{"host":
<GAME_SERVER_HOST>, "port": <port>}`: the first lobby to fill gets `GAME_SERVER_PORT_BASE`, the next one more, and so on,
never the same port twice, however many fill at once. A lobby never holds more players than its capacity, however
many join at once.

## What judges it

| Measure | Limit |
| --- | --- |
| `service/pyproject.toml` present | yes |
| `ruff check` (the kit's pin, line length 120, rules E F W I UP B SIM, your config ignored) and `ruff format --check` | no problems |
| Your own tests, `uv run pytest` in `service/` | all pass, at least 8 cases |
| `service/README.md` names `PORT`, `API_TOKEN`, `GAME_SERVER_HOST`, `GAME_SERVER_PORT_BASE` | all four |
| `service/Dockerfile` | has a `HEALTHCHECK` |
| Started without `API_TOKEN` | exits with a non-zero code |
| Started with a token, `GET /health` | answers within 2 minutes |
| The eval's acceptance suite (kept outside your folder, run against the started service over HTTP) | at least 15 cases, all pass |
| Request log lines with `method`, `path` and `status` | at least 50 over the acceptance run |
| Log lines that carry the token | 0 |

`gds eval check lobby-service <this folder>` runs all of them. Work from this brief, not from the check's acceptance
suite. Write your own tests the way you would for a real service: the failures a client can cause, the races, the
numbers.
