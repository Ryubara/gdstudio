class_name NetPlayReport
extends RefCounted
## What a predicting client measured, as one dictionary of plain numbers: the same keys from the
## native bot (`tools/net/predict_bot.gd`, its `PREDICT_BOT` line) and the browser's
## `NetPlayProbe` (`window.gdnet`), so one set of thresholds judges both
## (`tools/net/bad_network.py`). The gap is the body's distance to its own entry in the last TICK.


## The report of `client` and its `remote` puppets after `steps` physics steps; `puppet_us` holds
## the puppets' cost of each step (empty: not measured).
static func of(
	client: NetClient, remote: RemotePlayers, steps: int, puppet_us := PackedInt32Array()
) -> Dictionary:
	var reconciler := client.reconciler
	# `RemotePlayers.starved` counts a step once for each puppet that starved on it.
	var starved := remote.starved if remote != null else 0
	var puppets := remote.slots().size() if remote != null else 0
	return {
		"slot": client.slot,
		"steps": steps,
		"commands": client.seq,
		"ticks_read": client.ticks_read,
		"rtt_ms": client.rtt_ms,
		"corrections": reconciler.corrections,
		"snaps": reconciler.snaps,
		"size_snaps_m": millimetres(reconciler.size_snaps),
		"stuck_snaps": reconciler.stuck_snaps,
		"lost": reconciler.lost,
		"worst_error_m": snappedf(reconciler.worst_error, 0.001),
		"worst_stall_error_m": snappedf(reconciler.worst_stall_error, 0.001),
		"most_stacked": reconciler.most_stacked,
		"corrected_m": snappedf(reconciler.corrected, 0.001),
		"gap_m": snappedf(gap(client), 0.0001),
		"stalls": client.stall_guard.resyncs,
		"skipped_ticks": client.stall_guard.skipped,
		"walked_steps": client.silence_walk.steps,
		"puppets": puppets,
		"starved_steps": starved,
		"starved_share": snappedf(float(starved) / maxi(steps * puppets, 1), 0.0001),
		"client_us_p50": percentile(client.frame_times, 0.5),
		"client_us_p95": percentile(client.frame_times, 0.95),
		"puppets_us_p50": percentile(puppet_us, 0.5),
		"puppets_us_p95": percentile(puppet_us, 0.95),
		"drops": client.drops.summary(),
	}


## The distance from the client's body to its own entry in the last TICK, metres (-1 before one).
static func gap(client: NetClient) -> float:
	if client.last_tick == null or client.player == null:
		return -1.0
	for entry in client.last_tick.players:
		if entry.slot == client.slot:
			return client.player.global_position.distance_to(entry.position)
	return -1.0


## `values` in metres, each rounded to the millimetre.
static func millimetres(values: PackedFloat32Array) -> Array[float]:
	var out: Array[float] = []
	for value in values:
		out.append(snappedf(value, 0.001))
	return out


## The value at `share` (0 to 1) of `values` (the nearest rank), -1 for none.
static func percentile(values: PackedInt32Array, share: float) -> int:
	if values.is_empty():
		return -1
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[clampi(ceili(share * sorted.size()) - 1, 0, sorted.size() - 1)]
