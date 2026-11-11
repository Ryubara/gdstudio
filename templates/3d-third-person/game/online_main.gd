class_name OnlineMain
extends Node
## The online game: the offline game (`main.tscn`, unchanged, as `Main`) with a `NetClient` that
## joins the server and predicts the local player, `RemotePlayers` that draws the others, and an
## `OnlineStatus` that shows connecting, refused and lost. The main menu's "Play online" loads it
## (`NetClient.next_url` carries the address), and `MenuScene` goes straight to it when the game
## was started with an address: `-- --connect ws://host:8910 [--name Ada] [--bot route|watch]`, or
## on the web `index.html?url=wss://host[&name=Ada][&bot=watch]` (a page served over `https` may
## open only `wss://`).
##
## `--bot` (`?bot`) adds a `PlayerBot` that plays through the player's own input: `route` (the
## default) walks to the door, opens it, shoots and stands; `watch` keeps the nearest other player
## in view and shoots at it. A page opened with `?onlineprobe` also gets an `OnlineProbe`, which
## writes what the client measured to `window.gdonline`.

@export_group("Nodes")
## The client that joins and predicts.
@export var client: NetClient
## The other players.
@export var remote_players: RemotePlayers
## The local player's rig (its body and camera).
@export var player_rig: PlayerRig
## The overlay of connecting, refused and lost.
@export var status: OnlineStatus

## The bot that plays, when one was asked for.
var bot: PlayerBot


func _ready() -> void:
	var args := NetArgs.new()
	if args.has("bot"):
		add_bot(PlayerBot.Plan.WATCH if args.get_string("bot") == "watch" else PlayerBot.Plan.ROUTE)
	OnlineProbe.attach(self, client, remote_players, status)


## Adds a bot that plays the local player with `plan`.
func add_bot(plan: PlayerBot.Plan) -> PlayerBot:
	bot = PlayerBot.new()
	bot.name = &"PlayerBot"
	bot.plan = plan
	bot.player = player_rig.player
	bot.camera_rig = player_rig.camera_rig
	bot.remote_players = remote_players
	add_child(bot)
	return bot
