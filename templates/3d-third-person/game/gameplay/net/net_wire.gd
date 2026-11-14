class_name NetWire
extends RefCounted
## The bytes of an online game of this template (protocol version 11): one message to a WebSocket
## frame, a type byte first, then fixed fields, little-endian. Plain code with no node, socket or
## clock, so a server, a client, a test and a tool share one definition. The transport (a
## `WebSocketPeer`, a loopback) carries the arrays as they are.
##
## HELLO    C->S  u8 type=1, u8 version, u32 world hash, u8 flags (`F_WEB`: a browser), u8 name
##                length (<= NAME_BYTES), the name in UTF-8. 8 bytes + the name
## WELCOME  S->C  u8 type=2, u8 version, u8 slot, u8 tick rate, u32 server tick, u32 world hash,
##                u16 entity count, then per world part: u16 id, u8 kind, u8 state length, the
##                state; u8 player count, then per player: its entry (12 to 14 bytes), u8 name
##                length, the name (`SnapshotCodec.welcome`)
## REFUSED  S->C  u8 type=3, u8 reason (`Refusal`), u8 the server's version; the server closes
##                the connection after it. 3 bytes
## COMMAND  C->S  u8 type=4, u32 seq, s8 move x, s8 move y, u16 yaw, s16 pitch, u16 flags, u8
##                more flags (bit 0 the melee press, bits 1 and 2 the lean left and right), u8
##                the hotbar place used + 1 (0 none) (15 bytes); with the `F_SHOT` flag a shot
##                block follows: s16 origin x/y/z (cm),
##                u16 shot yaw, s16 shot pitch, u16 view tick (27 bytes in all; `CommandCodec`)
## TICK     S->C  u8 type=5, u32 server tick, u32 ack (the last command seq applied for this
##                client), u8 event count, the events, u8 player count, the player
##                entries, u8 streamed part count, then per moving prop: u16 id, u8 state length,
##                the state, then the AI block for this client (`AiSnapshot`: u8 mode, and for a
##                full or a delta the rows of the AI characters) (`SnapshotCodec.tick`, events in
##                `NetEvent`, a prop's in `PropState`)
## PING     C->S  u8 type=6, u32 client milliseconds, u16 the last round trip in ms (`NO_RTT`
##                before the first). 7 bytes
## PONG     S->C  u8 type=7, the same u32 and u16, u32 server tick. 11 bytes
##
## A player entry: u8 slot, s16 x/y/z (cm), u16 yaw, u8 state, u8 flags (crouch, aim, sprint,
## air, rising, dead, peek, halt), s8 pitch, with the aim flag s8 the aim's heading off the
## body, and with the peek flag s8 the lean (`SnapshotCodec`). 12 bytes, 13 while aiming or
## leaning, 14 while both.
##
## Every decoder checks each length before it reads, answers null (or -1) for a packet that is
## not exactly one message, and counts why in a `NetDrops` (never silent). The version is read
## before anything else, so an old client is told `Refusal.VERSION` whatever its layout. Raise
## `VERSION` whenever a layout above changes, past the highest number any open pull request names
## (docs: gamedev/netcode.md#parallel-branches).

enum Type { HELLO = 1, WELCOME = 2, REFUSED = 3, COMMAND = 4, TICK = 5, PING = 6, PONG = 7 }
enum Refusal { VERSION = 1, FULL = 2, WORLD = 3 }

## The protocol version of this build.
## 2: the command's flags carry `prone` (bit 15); 3: and the weapon presses (bits 11 to 14:
## reload, next, previous, the empty hands); 4: a SHOT carries the weapon and a HIT the health
## it left (gdstudio #906); 5: a TICK ends with the streamed parts (moving props), a world part's
## state may be 12 bytes (gdstudio #1073); 6: a TICK ends with the AI block, a HELLO carries the
## client's flags, an AI event and a HIT on an AI (gdstudio #970); 7: an aiming player's entry
## ends with the aim's heading off the body (gdstudio #1277); 8: a COMMAND's byte 13 carries
## the melee press, a MELEE event and an AI event's `MELEE` code (gdstudio #1254); 9: a COMMAND's
## byte 14 carries the hotbar place used, and a USE event (gdstudio #1386); 11: a COMMAND's byte
## 13 carries the peek lean and a leaning player's entry ends with it (gdstudio #1400; 10 is named
## by open pull requests beside it); 13: a player entry's flags carry `halt`, asked for no move
## (bit 7, gdstudio #1420; 12 is named by an open pull request beside it); 18: an AI row's speed
## is the speed the body is asked for, not the one it has (gdstudio #1452; 16 and 17 are named by
## open pull requests beside it).
const VERSION := 18
## The oldest client version this build's server takes; equal to `VERSION` while the web client
## and the server ship from one commit.
const MIN_VERSION := 18

## Where the version byte is in a HELLO and a WELCOME.
const VERSION_AT := 1
## Type, version, world hash, flags, name length.
const HELLO_HEADER := 8
## A HELLO's flag: the client runs in a browser (the match's AI population is then the browser's
## cap, `AiDirector.web_cap`, for everyone).
const F_WEB := 1
const MAX_HELLO := HELLO_HEADER + NetLimits.NAME_BYTES
const REFUSED_SIZE := 3
const COMMAND_SIZE := 15
const SHOT_BLOCK_SIZE := 12
const COMMAND_SHOT_SIZE := COMMAND_SIZE + SHOT_BLOCK_SIZE
## Type, tick, ack, event count, player count.
const TICK_HEADER := 11
## After a TICK's players: the streamed part count and the AI block's mode.
const TICK_TAIL := 2
## A streamed row: u16 id, u8 state length (then the state).
const STREAM_ROW_HEADER := 3
## Type, version, slot, tick rate, tick, world hash.
const WELCOME_HEADER := 12
const PING_SIZE := 7
const PONG_SIZE := 11
## What a ping says before the client has measured a round trip, and the most it can say.
const NO_RTT := 0xFFFF
## The longest message a client sends.
const MAX_CLIENT_PACKET := COMMAND_SHOT_SIZE if COMMAND_SHOT_SIZE > MAX_HELLO else MAX_HELLO

const _FNV_OFFSET := 0x811C9DC5
const _FNV_PRIME := 0x01000193


## A HELLO, read.
class Hello:
	extends RefCounted
	var version := 0
	var world_hash := 0
	## `F_WEB` and any later flag.
	var flags := 0
	var player_name := ""


## A PING or a PONG, read (`server_tick` is 0 in a ping).
class Ping:
	extends RefCounted
	var client_ms := 0
	## Milliseconds, or -1 for none yet.
	var rtt := -1
	var server_tick := 0


## Whether a server of this build takes a client of that version.
static func accepts(version: int) -> bool:
	return version >= MIN_VERSION and version <= VERSION


## The type byte of a packet, or -1 for an empty one.
static func type_of(data: PackedByteArray) -> int:
	return -1 if data.is_empty() else data[0]


## The version a HELLO says (its second byte, whatever follows), or -1 when the packet is not a
## hello: a server turns an old client away by it though it cannot read the rest.
static func hello_version(data: PackedByteArray) -> int:
	if data.size() <= VERSION_AT or data[0] != Type.HELLO:
		return -1
	return data[VERSION_AT]


## A HELLO. A name longer than `NetLimits.NAME_BYTES` is cut at the last whole character that
## fits.
static func hello(player_name: String, map_hash: int, flags := 0) -> PackedByteArray:
	var name_bytes := clip_name(player_name)
	var out := PackedByteArray([Type.HELLO, VERSION, 0, 0, 0, 0, flags & 0xFF, name_bytes.size()])
	out.encode_u32(2, map_hash & 0xFFFFFFFF)
	out.append_array(name_bytes)
	return out


## The HELLO in a packet, or null (counted in `drops`). The version is checked before any other
## field.
static func read_hello(data: PackedByteArray, drops: NetDrops = null) -> Hello:
	if data.is_empty():
		return _drop(drops, NetDrops.EMPTY)
	if data[0] != Type.HELLO:
		return _drop(drops, NetDrops.UNKNOWN_TYPE)
	if data.size() <= VERSION_AT:
		return _drop(drops, NetDrops.TOO_SHORT)
	if not accepts(data[VERSION_AT]):
		return _drop(drops, NetDrops.BAD_VERSION)
	if data.size() < HELLO_HEADER:
		return _drop(drops, NetDrops.TOO_SHORT)
	var name_size := data[HELLO_HEADER - 1]
	if name_size > NetLimits.NAME_BYTES:
		return _drop(drops, NetDrops.NAME_TOO_LONG)
	if data.size() != HELLO_HEADER + name_size:
		return _drop(drops, NetDrops.WRONG_SIZE)
	var name_bytes := data.slice(HELLO_HEADER)
	if not valid_name(name_bytes):
		return _drop(drops, NetDrops.BAD_NAME)
	var result := Hello.new()
	result.version = data[VERSION_AT]
	result.world_hash = data.decode_u32(2)
	result.flags = data[HELLO_HEADER - 2]
	result.player_name = name_bytes.get_string_from_utf8()
	return result


static func refused(reason: Refusal) -> PackedByteArray:
	return PackedByteArray([Type.REFUSED, reason, VERSION])


## The reason of a REFUSED (a `Refusal`), or -1 (counted in `drops`).
static func read_refused(data: PackedByteArray, drops: NetDrops = null) -> int:
	if not _is_exactly(data, Type.REFUSED, REFUSED_SIZE, drops):
		return -1
	if not Refusal.values().has(data[1]):
		NetDrops.note(drops, NetDrops.BAD_VALUE)
		return -1
	return data[1]


## `rtt_ms` is the client's last measured round trip (negative for none yet).
static func ping(client_ms: int, rtt_ms := -1) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(PING_SIZE)
	out[0] = Type.PING
	out.encode_u32(1, client_ms & 0xFFFFFFFF)
	out.encode_u16(5, NO_RTT if rtt_ms < 0 else mini(rtt_ms, NO_RTT - 1))
	return out


static func read_ping(data: PackedByteArray, drops: NetDrops = null) -> Ping:
	if not _is_exactly(data, Type.PING, PING_SIZE, drops):
		return null
	return _ping_fields(data)


## The answer to a ping: its milliseconds and round trip back, and the server's tick.
static func pong(ping_packet: Ping, server_tick: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(PONG_SIZE)
	out[0] = Type.PONG
	out.encode_u32(1, ping_packet.client_ms & 0xFFFFFFFF)
	out.encode_u16(5, NO_RTT if ping_packet.rtt < 0 else mini(ping_packet.rtt, NO_RTT - 1))
	out.encode_u32(7, server_tick & 0xFFFFFFFF)
	return out


static func read_pong(data: PackedByteArray, drops: NetDrops = null) -> Ping:
	if not _is_exactly(data, Type.PONG, PONG_SIZE, drops):
		return null
	var result := _ping_fields(data)
	result.server_tick = data.decode_u32(7)
	return result


## A number for the networked parts of a map: FNV-1a (32 bits) of the sorted `path:kind` lines,
## so a client built from another map is refused (`Refusal.WORLD`) before it can desync. The
## order the parts are listed in does not change it.
static func world_hash(parts: PackedStringArray) -> int:
	var sorted := parts.duplicate()
	sorted.sort()
	var value := _FNV_OFFSET
	for byte in "\n".join(sorted).to_utf8_buffer():
		value = ((value ^ byte) * _FNV_PRIME) & 0xFFFFFFFF
	return value


## The name's UTF-8 bytes, cut at the last whole character within `NetLimits.NAME_BYTES`.
static func clip_name(player_name: String) -> PackedByteArray:
	var out := PackedByteArray()
	for character in player_name:
		var bytes := character.to_utf8_buffer()
		if out.size() + bytes.size() > NetLimits.NAME_BYTES:
			break
		out.append_array(bytes)
	return out


## Whether the bytes are a name: well-formed UTF-8 with no control character. Checked here
## because Godot prints an error for every malformed sequence it decodes.
static func valid_name(bytes: PackedByteArray) -> bool:
	var at := 0
	while at < bytes.size():
		var lead := bytes[at]
		var extra := 0
		var code := 0
		if lead < 0x80:
			if lead < 0x20 or lead == 0x7F:
				return false
			at += 1
			continue
		if lead >= 0xC2 and lead <= 0xDF:
			extra = 1
			code = lead & 0x1F
		elif lead >= 0xE0 and lead <= 0xEF:
			extra = 2
			code = lead & 0x0F
		elif lead >= 0xF0 and lead <= 0xF4:
			extra = 3
			code = lead & 0x07
		else:
			return false
		if at + extra >= bytes.size():
			return false
		for index in range(1, extra + 1):
			var next := bytes[at + index]
			if next & 0xC0 != 0x80:
				return false
			code = (code << 6) | (next & 0x3F)
		var shortest: int = [0, 0x80, 0x800, 0x10000][extra]
		if code < shortest or code > 0x10FFFF or (code >= 0xD800 and code <= 0xDFFF):
			return false
		at += extra + 1
	return true


static func _ping_fields(data: PackedByteArray) -> Ping:
	var result := Ping.new()
	result.client_ms = data.decode_u32(1)
	var rtt := data.decode_u16(5)
	result.rtt = -1 if rtt == NO_RTT else rtt
	return result


## Whether the packet is one message of `type` and exactly `size` bytes (a drop is counted).
static func _is_exactly(data: PackedByteArray, type: int, size: int, drops: NetDrops) -> bool:
	if data.is_empty():
		NetDrops.note(drops, NetDrops.EMPTY)
	elif data[0] != type:
		NetDrops.note(drops, NetDrops.UNKNOWN_TYPE)
	elif data.size() < size:
		NetDrops.note(drops, NetDrops.TOO_SHORT)
	elif data.size() > size:
		NetDrops.note(drops, NetDrops.TOO_LONG)
	else:
		return true
	return false


static func _drop(drops: NetDrops, reason: StringName) -> Variant:
	NetDrops.note(drops, reason)
	return null
