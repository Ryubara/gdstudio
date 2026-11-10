class_name WireReader
extends RefCounted
## Reads little-endian numbers from a packet with every length checked before the read: a read
## past the end answers 0 and clears `ok`, so a decoder reads its fields and checks `ok` once,
## and a short packet never makes the engine print an out-of-bounds error.

var data: PackedByteArray
## Where the next read starts.
var at := 0
## False once any read went past the end.
var ok := true


func _init(packet: PackedByteArray, start := 0) -> void:
	data = packet
	at = start


## Bytes not read yet.
func left() -> int:
	return data.size() - at


## There are `count` more bytes (and no read failed so far).
func has(count: int) -> bool:
	return ok and count >= 0 and left() >= count


func u8() -> int:
	if not _need(1):
		return 0
	at += 1
	return data[at - 1]


func s8() -> int:
	if not _need(1):
		return 0
	at += 1
	return data.decode_s8(at - 1)


func u16() -> int:
	if not _need(2):
		return 0
	at += 2
	return data.decode_u16(at - 2)


func s16() -> int:
	if not _need(2):
		return 0
	at += 2
	return data.decode_s16(at - 2)


func u32() -> int:
	if not _need(4):
		return 0
	at += 4
	return data.decode_u32(at - 4)


## The next `count` bytes, or an empty array (and `ok` cleared) when fewer are left.
func take(count: int) -> PackedByteArray:
	if not _need(count):
		return PackedByteArray()
	at += count
	return data.slice(at - count, at)


func _need(count: int) -> bool:
	if has(count):
		return true
	ok = false
	return false
