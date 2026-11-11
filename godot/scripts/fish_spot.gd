class_name FishSpot
extends Node2D
## Empire Age — a fish spot: a finite-but-large Food source sitting
## on a WATER cell (500 Food). Not a ResourceNode: nodes own a solid
## land cell, while a spot floats on water that is already solid for
## land and is harvested by Fishing Boats, never by villagers.
##
## The marker is deliberately subtle — two slowly breathing ripple
## rings plus an occasional leaping-fish VFX from Main — so a spot
## reads as "fish here" without shouting over the water art.

var cell: Vector2i = Vector2i.ZERO
var amount: int = 500
var max_amount: int = 500

var _t := 0.0


func _ready() -> void:
	z_index = 6


func take(n: int) -> int:
	var t: int = mini(n, amount)
	amount -= t
	return t


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	if amount <= 0:
		return
	# Two ripple rings, phase-offset, gently expanding and fading.
	for i in range(2):
		var ph: float = fmod(_t * 0.45 + float(i) * 0.5, 1.0)
		var r := 5.0 + ph * 11.0
		var a := (1.0 - ph) * 0.5
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 24, Color(0.85, 0.95, 1.0, a), 1.4)
	# A tiny fish-back arc breaking the surface at the centre.
	var bob := sin(_t * 2.2) * 1.5
	draw_arc(Vector2(0, bob), 3.5, PI * 1.15, PI * 1.85, 8,
			Color(0.75, 0.88, 0.98, 0.8), 1.6)
