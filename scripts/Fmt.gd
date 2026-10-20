class_name Fmt
extends RefCounted
## Number formatting for ore amounts.

const UNITS: Array[String] = ["K", "M", "B", "T"]


static func num(v: float) -> String:
	var n := floorf(v + 0.0001)
	if n < 10000.0:
		return str(int(n))
	var i := -1
	while n >= 1000.0 and i < UNITS.size() - 1:
		n /= 1000.0
		i += 1
	return "%.1f%s" % [n, UNITS[i]]
