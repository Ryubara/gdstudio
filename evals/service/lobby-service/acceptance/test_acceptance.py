"""Acceptance suite of the lobby-service eval (kit evals/service/lobby-service/TASK.md).

`gds eval check` starts the delivered service on a free port with a known environment and runs this file against it
(`LOBBY_URL`, `LOBBY_TOKEN`, `LOBBY_HOST`, `LOBBY_PORT_BASE`). It uses the standard library only, so it needs nothing
installed, and it talks HTTP like any client: it never imports the delivery. The service is shared by every case, and
the cases that count fills (`test_01...`) run first, in name order.
"""

from __future__ import annotations

import itertools
import json
import os
import threading
import unittest
import uuid
import urllib.error
import urllib.request

URL = os.environ.get("LOBBY_URL", "http://127.0.0.1:8080")
TOKEN = os.environ.get("LOBBY_TOKEN", "eval-token")
HOST = os.environ.get("LOBBY_HOST", "games.example.test")
PORT_BASE = int(os.environ.get("LOBBY_PORT_BASE", "7000"))
_players = itertools.count(1)
_RUN = uuid.uuid4().hex[:6]  # another run against the same service never meets this one's players


def call(method: str, path: str, body=None, token: str | None = TOKEN, raw: bytes | None = None):
    """(status, parsed JSON or None, content type) of one request."""
    data = raw if raw is not None else (None if body is None else json.dumps(body).encode())
    request = urllib.request.Request(URL + path, data=data, method=method)
    if data is not None:
        request.add_header("Content-Type", "application/json")
    if token is not None:
        request.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            payload, status, kind = response.read(), response.status, response.headers.get("Content-Type", "")
    except urllib.error.HTTPError as error:
        payload, status, kind = error.read(), error.code, error.headers.get("Content-Type", "")
        error.close()
    try:
        return status, (json.loads(payload) if payload else None), kind
    except ValueError:
        return status, None, kind


def player() -> str:
    return f"p-{_RUN}-{next(_players)}"


def lobby(capacity: int = 4, name: str = "arena") -> dict:
    status, body, _ = call("POST", "/lobbies", {"name": name, "capacity": capacity})
    assert status == 201, (status, body)
    return body


def join(lobby_id: str, who: str):
    return call("POST", f"/lobbies/{lobby_id}/join", {"player": who})


class LobbyContract(unittest.TestCase):
    def test_01_the_first_full_lobby_gets_the_base_port_and_the_next_the_following_one(self) -> None:
        ports = []
        for _ in range(2):
            made = lobby(2)
            join(made["id"], player())
            status, body, _ = join(made["id"], player())
            self.assertEqual(status, 200)
            self.assertEqual(body["state"], "full")
            self.assertEqual(body["game_server"]["host"], HOST)
            ports.append(body["game_server"]["port"])
        self.assertEqual(ports, [PORT_BASE, PORT_BASE + 1])

    def test_health_answers_without_a_token(self) -> None:
        status, body, kind = call("GET", "/health", token=None)
        self.assertEqual((status, body), (200, {"status": "ok"}))
        self.assertIn("application/json", kind)

    def test_everything_else_needs_the_bearer_token(self) -> None:
        for token in (None, "wrong-token", ""):
            for method, path in (("GET", "/lobbies"), ("POST", "/lobbies"), ("GET", "/lobbies/x")):
                status, body, _ = call(method, path, {"name": "x", "capacity": 2}, token=token)
                self.assertEqual(status, 401, (method, path, token))
                self.assertEqual(body, {"error": "unauthorized"})

    def test_a_lobby_is_created_open_and_empty(self) -> None:
        made = lobby(4, "night shift")
        self.assertEqual(
            {k: made[k] for k in ("name", "capacity", "players", "state", "game_server")},
            {"name": "night shift", "capacity": 4, "players": [], "state": "open", "game_server": None},
        )
        self.assertIsInstance(made["id"], str)
        self.assertTrue(made["id"])
        self.assertEqual(call("GET", f"/lobbies/{made['id']}")[:2], (200, made))

    def test_invalid_lobbies_are_422_with_an_error(self) -> None:
        bad = [
            {"name": "", "capacity": 4},
            {"name": "x" * 33, "capacity": 4},
            {"name": 5, "capacity": 4},
            {"capacity": 4},
            {"name": "x", "capacity": 1},
            {"name": "x", "capacity": 9},
            {"name": "x", "capacity": "4"},
            {"name": "x", "capacity": 4.5},
            {"name": "x", "capacity": True},
            {"name": "x"},
        ]
        for body in bad:
            status, answer, _ = call("POST", "/lobbies", body)
            self.assertEqual(status, 422, body)
            self.assertIsInstance(answer.get("error"), str, body)

    def test_a_body_that_is_not_json_is_400(self) -> None:
        self.assertEqual(call("POST", "/lobbies", raw=b"{not json")[0], 400)
        self.assertEqual(call("POST", "/lobbies", raw=b"[1, 2]")[0], 400)

    def test_a_body_over_four_kilobytes_is_413(self) -> None:
        big = json.dumps({"name": "x", "capacity": 4, "pad": "y" * 5000}).encode()
        self.assertEqual(call("POST", "/lobbies", raw=big)[0], 413)

    def test_lobbies_are_listed_in_creation_order_and_filtered_by_state(self) -> None:
        names = [f"order-{i}" for i in range(3)]
        made = [lobby(2, name) for name in names]
        join(made[1]["id"], player())
        join(made[1]["id"], player())
        listed = call("GET", "/lobbies")[1]["lobbies"]
        ours = [item["name"] for item in listed if item["name"] in names]
        self.assertEqual(ours, names)
        open_names = [item["name"] for item in call("GET", "/lobbies?state=open")[1]["lobbies"]]
        self.assertIn(names[0], open_names)
        self.assertNotIn(names[1], open_names)
        self.assertTrue(all(item["state"] == "open" for item in call("GET", "/lobbies?state=open")[1]["lobbies"]))

    def test_an_unknown_lobby_is_404_for_every_verb(self) -> None:
        for method, path in (
            ("GET", "/lobbies/nope"),
            ("POST", "/lobbies/nope/join"),
            ("POST", "/lobbies/nope/leave"),
            ("DELETE", "/lobbies/nope"),
        ):
            status, body, _ = call(method, path, {"player": "p"})
            self.assertEqual(status, 404, (method, path))
            self.assertIn("error", body)

    def test_unknown_routes_are_404_and_wrong_methods_405_both_as_json(self) -> None:
        status, body, _ = call("GET", "/nothing-here")
        self.assertEqual(status, 404)
        self.assertIn("error", body)
        status, body, _ = call("PUT", "/lobbies", {"name": "x", "capacity": 2})
        self.assertEqual(status, 405)
        self.assertIn("error", body)

    def test_players_join_and_the_lobby_lists_them_in_order(self) -> None:
        made = lobby(4)
        who = [player(), player(), player()]
        for index, name in enumerate(who, start=1):
            status, body, _ = join(made["id"], name)
            self.assertEqual((status, body["players"], body["state"]), (200, who[:index], "open"))

    def test_a_player_cannot_join_twice_or_two_lobbies(self) -> None:
        first, second = lobby(4), lobby(4)
        who = player()
        self.assertEqual(join(first["id"], who)[0], 200)
        self.assertEqual(join(first["id"], who)[0], 409)
        self.assertEqual(join(second["id"], who)[0], 409)

    def test_invalid_players_are_422(self) -> None:
        made = lobby(4)
        for body in ({"player": ""}, {"player": "p" * 25}, {"player": 7}, {}):
            self.assertEqual(call("POST", f"/lobbies/{made['id']}/join", body)[0], 422, body)

    def test_a_full_lobby_takes_no_one_else_and_cannot_be_left(self) -> None:
        made = lobby(2)
        a, b = player(), player()
        join(made["id"], a)
        join(made["id"], b)
        self.assertEqual(join(made["id"], player())[0], 409)
        self.assertEqual(call("POST", f"/lobbies/{made['id']}/leave", {"player": a})[0], 409)
        self.assertEqual(call("GET", f"/lobbies/{made['id']}")[1]["state"], "full")

    def test_leaving_frees_the_place_and_the_player_may_join_another_lobby(self) -> None:
        first, second = lobby(2), lobby(2)
        who = player()
        join(first["id"], who)
        status, body, _ = call("POST", f"/lobbies/{first['id']}/leave", {"player": who})
        self.assertEqual((status, body["players"]), (200, []))
        self.assertEqual(call("POST", f"/lobbies/{first['id']}/leave", {"player": who})[0], 404)
        self.assertEqual(join(second["id"], who)[0], 200)

    def test_only_an_empty_lobby_can_be_deleted(self) -> None:
        made = lobby(3)
        who = player()
        join(made["id"], who)
        self.assertEqual(call("DELETE", f"/lobbies/{made['id']}")[0], 409)
        call("POST", f"/lobbies/{made['id']}/leave", {"player": who})
        status, body, _ = call("DELETE", f"/lobbies/{made['id']}")
        self.assertEqual((status, body), (204, None))
        self.assertEqual(call("GET", f"/lobbies/{made['id']}")[0], 404)

    def test_a_lobby_never_holds_more_than_its_capacity_under_concurrent_joins(self) -> None:
        made = lobby(4)
        codes: list[int] = []
        names = [player() for _ in range(12)]
        start = threading.Barrier(len(names))

        def go(name: str) -> None:
            start.wait()
            codes.append(join(made["id"], name)[0])

        threads = [threading.Thread(target=go, args=(name,)) for name in names]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()
        self.assertEqual(sorted(codes), [200] * 4 + [409] * 8)
        final = call("GET", f"/lobbies/{made['id']}")[1]
        self.assertEqual((len(final["players"]), final["state"]), (4, "full"))
        self.assertIsNotNone(final["game_server"])

    def test_concurrent_fills_get_distinct_game_server_ports(self) -> None:
        lobbies = [lobby(2) for _ in range(6)]
        ports: list[int] = []
        start = threading.Barrier(len(lobbies) * 2)

        def go(lobby_id: str, name: str) -> None:
            start.wait()
            status, body, _ = join(lobby_id, name)
            if status == 200 and body["state"] == "full":
                ports.append(body["game_server"]["port"])

        threads = [
            threading.Thread(target=go, args=(item["id"], player())) for item in lobbies for _ in range(2)
        ]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()
        self.assertEqual(len(ports), 6)
        self.assertEqual(len(set(ports)), 6)
        self.assertTrue(all(port >= PORT_BASE for port in ports))


if __name__ == "__main__":
    unittest.main()
