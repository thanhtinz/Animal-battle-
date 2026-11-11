extends Node
## Band-targeted home capture for the ping-meter
## correction: boots the game, logs the seeded account in
## against the local relay through the normal Net flow,
## then WAITS until a real ping sample lands in the band
## named by env PING_TARGET ("good" <100 ms, "medium"
## 100–200 ms) before photographing to env PING_OUT.
## Env PING_TIMEOUT (seconds, default 40): on timeout it
## still shoots and prints TIMEOUT with the last sample.
## NOTE: this sandbox's localhost samples floor around
## ~110 ms (relay tick + headless frame pump), so "good"
## may honestly time out here; "medium" is the reachable
## live band, and the all-green drawing is proven by
## tests/capture_ping_bands.tscn.

var _t := 0.0
var _done := false
var _target := "medium"
var _out := "res://shots/empire_age_home_ping_v2_medium.png"
var _timeout := 40.0
var _game = null
var _refreshed := false
var _registered := false


func _ready() -> void:
	_target = OS.get_environment("PING_TARGET") \
			if OS.get_environment("PING_TARGET") != "" else "medium"
	_out = OS.get_environment("PING_OUT") \
			if OS.get_environment("PING_OUT") != "" else _out
	_timeout = float(OS.get_environment("PING_TIMEOUT")) \
			if OS.get_environment("PING_TIMEOUT") != "" else 40.0
	_game = load("res://main.tscn").instantiate()
	add_child(_game)
	# The seeded account already exists, so register comes
	# back as auth_error — fall back to login, exactly like
	# net.gd's own mp-account driver does (its fallback is
	# gated on the auto args this scene doesn't pass).
	Net.auth_error.connect(func(_msg: String) -> void:
		if Net.account_name == "":
			Net.login_account("HiepSi", "secret1"))
	await get_tree().create_timer(0.5).timeout
	Net.connect_to_server(Net.DEFAULT_URL)


func _in_band(ms: int) -> bool:
	if ms < 0:
		return false
	return ms < 100 if _target == "good" else (ms >= 100 and ms <= 200)


func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	# Register only once the socket is actually open —
	# _send is not buffered, so an early call is lost.
	if not _registered and Net.connected:
		_registered = true
		Net.register_account("HiepSi", "secret1")
	# Mirror the driver shot: once auth has landed, refresh
	# the home once so it shows the member face (name/Lv,
	# rank pill) instead of its boot-time guest face.
	if not _refreshed and Net.account_name != "":
		_refreshed = true
		if _game != null and _game.has_method("refresh_home"):
			_game.refresh_home()
	# Only shoot once authed (the home must show the member
	# face) AND a sample sits in the target band.
	if Net.connected and Net.account_name != "" and _in_band(Net.ping_ms):
		_done = true
		# Let the home's 0.5 s tick paint the new band first.
		await get_tree().create_timer(0.8).timeout
		_shoot("%s ms=%d" % [_target, Net.ping_ms])
	elif _t > _timeout:
		_done = true
		_shoot("TIMEOUT target=%s last_ms=%d" % [_target, Net.ping_ms])


func _shoot(note: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(_out)
	print("CAPTURE SAVED ", _out, " ", note)
	get_tree().quit()
