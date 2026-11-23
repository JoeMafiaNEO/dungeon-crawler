extends RefCounted

## Issue #264: the WorkerThreadPool target for one
## threaded train-network derivation. TrainNetwork's
## async layer snapshots the record state (its entry /
## platform / parent / link dictionaries), hands the
## snapshot to an instance of this class, and queues
## work() on the pool; the main thread later reaps the
## task (is_task_completed first, wait in the same
## breath — the #253 discipline) and publishes the
## detached result into the live caches.
##
## Everything work() touches is either its own fields
## or pure functions of them: the computation never
## reads or writes TrainNetwork's live record state,
## so a derivation in flight cannot race a consumer.
## The record file IS written here, on the worker,
## from the snapshot-merged record the computation
## produced (monotone: it contains every entry the
## snapshot held plus every entry this run derived).

const TrainNetwork := preload(
	"res://scripts/world/train_network.gd")

var seed: int = 0
var discovered: Array = []
var home_center: Vector2 = Vector2.ZERO
var home_station: Vector2 = Vector2.ZERO
## The snapshot state dictionary (TrainNetwork's st
## shape) and the progress box [done, total] — the
## worker writes both; the main thread only reads.
var st: Dictionary = {}
var progress: Array = [0, 0]
var result: Dictionary = {}


func work() -> void:
	var bundle: Dictionary = TrainNetwork \
		._bundle_compute(seed, discovered,
			home_center, home_station, st, progress)
	TrainNetwork._persist_write(st["entries"],
		st["platforms"])
	result = {"bundle": bundle, "st": st}
