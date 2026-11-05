---
areas: [net, backend]
---
# A closed socket was read as a choice to leave, and the night's own hang-up emptied the reopened lobby

2026-11-05

- **Saw:** while making a finished night reopen its lobby only for the people still connected (Deadnight #1177), the
  first version dropped everyone from the room's list of who returns when a socket closed after the night closed. The
  reopened-lobby test then said "the lobby never reopened": nobody was left in it.
- **Cause:** a socket that closes is not a decision. The client closes its own link the moment it reads `night_closed`
  (it leaves the server at once), so after the intermission every player's socket closes "on purpose" within a tick,
  exactly like a player who pressed Leave. The room could not tell the two apart from the connection alone, so reading
  the close as "this person left" removed the very people the lobby was to reopen for.
- **Fix:** the room keeps who was there when the night closed (`returning`) and does not edit it from closes after
  that; a person leaving earlier is reported to the backend as a seat that is empty, and not at all once the night is
  closed. Who is really gone after that is the backend's business, by what a member does next (a read, a leave, a
  move), and an unread reopened lobby is dropped a minute after it opens.
- **Check for next time:** before deriving "the player chose to leave" from a connection event, list every reason the
  client closes its own socket (a night that ended, a screen that was left, a page that went away, an error) and what
  each does to the state the event would change. Write the test that plays the normal end of the flow, with the
  clients doing what the real screen does, before the one for the odd exit.
- **Docs:** the game's `docs/design/lobby.md#leaving-and-moving-every-state-and-what-ends-it`.
