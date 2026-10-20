class_name ShaftChunk
extends RefCounted
## Cell data for one horizontal slice of the shaft, stored in packed arrays (no node per block).

var index: int = 0
var first_row: int = 0
var rows: int = 0
var kinds := PackedByteArray()    ## Shaft.Kind per cell, row-major
var ore := PackedByteArray()      ## ore index per cell (blocks only)
var hp := PackedInt32Array()


func _init(chunk_index: int, chunk_rows: int) -> void:
	index = chunk_index
	rows = chunk_rows
	first_row = chunk_index * chunk_rows


## Subtracts damage and returns the HP left. A block at 0 HP becomes empty.
func apply_damage(i: int, damage: int) -> int:
	hp[i] = maxi(hp[i] - damage, 0)
	if hp[i] == 0:
		kinds[i] = Shaft.Kind.EMPTY
	return hp[i]
