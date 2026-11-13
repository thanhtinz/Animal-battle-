class_name VoiceRec
extends Node

## Empire Age 17e — voice-note capture + playback plumbing.
##
## RECORDING IS ONE FUNCTION: start_recording() arms the mic
## pipeline (a dedicated "VoiceRec" bus with an
## AudioEffectCapture fed by an AudioStreamMicrophone player)
## and stop_recording() returns {"wav": PackedByteArray,
## "dur": float} — a 11025 Hz mono 16-bit WAV, capped at
## MAX_SECONDS. Everything downstream (the chat hub's send
## path) consumes exactly that dictionary, so tests inject a
## synthetic WAV from synth_wav() through the same function
## shape and exercise send -> relay -> render -> playback
## without hardware.
##
## SANDBOX LIMIT: this environment has no microphone, so a
## real recording cannot be verified here; the capture code
## is the standard Godot recipe and degrades to silence (an
## empty/short take is refused by the caller) when no device
## feeds the bus.

const RATE := 11025
const MAX_SECONDS := 30.0

var _capture: AudioEffectCapture = null
var _player: AudioStreamPlayer = null
var _recording := false
var _frames: PackedVector2Array = PackedVector2Array()
var _src_rate := 44100
var _auto_stopped := false


func _ready() -> void:
	_src_rate = int(AudioServer.get_mix_rate())
	var bus := AudioServer.bus_count
	AudioServer.add_bus()
	AudioServer.set_bus_name(bus, "VoiceRec")
	AudioServer.set_bus_volume_db(bus, -80.0)  # never audible
	_capture = AudioEffectCapture.new()
	AudioServer.add_bus_effect(bus, _capture)
	_player = AudioStreamPlayer.new()
	_player.stream = AudioStreamMicrophone.new()
	_player.bus = "VoiceRec"
	add_child(_player)
	_player.play()


func _process(_delta: float) -> void:
	if not _recording or _capture == null:
		return
	var avail := _capture.get_frames_available()
	if avail > 0:
		_frames.append_array(_capture.get_buffer(avail))
	if recorded_seconds() >= MAX_SECONDS:
		_auto_stopped = true
		_recording = false


func is_recording() -> bool:
	return _recording


func auto_stopped() -> bool:
	return _auto_stopped


func recorded_seconds() -> float:
	if _src_rate <= 0:
		return 0.0
	return float(_frames.size()) / float(_src_rate)


func start_recording() -> void:
	_frames = PackedVector2Array()
	_auto_stopped = false
	if _capture != null:
		_capture.clear_buffer()
	_recording = true


## stop_recording ends the take and returns the WAV payload
## ({"wav", "dur"}); an empty take returns dur 0.
func stop_recording() -> Dictionary:
	_recording = false
	var avail := 0
	if _capture != null:
		avail = _capture.get_frames_available()
	if avail > 0:
		_frames.append_array(_capture.get_buffer(avail))
	var dur := recorded_seconds()
	if dur <= 0.05 or _frames.is_empty():
		return {"wav": PackedByteArray(), "dur": 0.0}
	var mono := _downsample(_frames, _src_rate, RATE)
	return {"wav": encode_wav(mono, RATE), "dur": dur}


func _downsample(frames: PackedVector2Array, src_rate: int, dst_rate: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if src_rate <= 0 or frames.is_empty():
		return out
	var count := int(float(frames.size()) * float(dst_rate) / float(src_rate))
	out.resize(count)
	for i in count:
		var begin := int(float(i) * float(src_rate) / float(dst_rate))
		var end := mini(frames.size(), int(float(i + 1) * float(src_rate) / float(dst_rate)))
		if end <= begin:
			end = mini(frames.size(), begin + 1)
		var sum := 0.0
		for j in range(begin, end):
			sum += (frames[j].x + frames[j].y) * 0.5
		out[i] = sum / float(maxi(1, end - begin))
	return out


## encode_wav writes a canonical 44-byte-header PCM16 WAV.
static func encode_wav(samples: PackedFloat32Array, rate: int) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, v)
	var hdr := PackedByteArray()
	hdr.append_array("RIFF".to_ascii_buffer())
	hdr.resize(8)
	hdr.encode_u32(4, 36 + data.size())
	hdr.append_array("WAVEfmt ".to_ascii_buffer())
	hdr.resize(36)
	hdr.encode_u32(16, 16)          # fmt chunk size
	hdr.encode_u16(20, 1)           # PCM
	hdr.encode_u16(22, 1)           # mono
	hdr.encode_u32(24, rate)
	hdr.encode_u32(28, rate * 2)    # byte rate
	hdr.encode_u16(32, 2)           # block align
	hdr.encode_u16(34, 16)          # bits
	hdr.append_array("data".to_ascii_buffer())
	hdr.resize(44)
	hdr.encode_u32(40, data.size())
	hdr.append_array(data)
	return hdr


## synth_wav is the test/capture injector: a short sine take
## in exactly the recorder's output format.
static func synth_wav(seconds: float = 0.6, freq: float = 440.0) -> PackedByteArray:
	var count := int(RATE * seconds)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		samples[i] = 0.35 * sin(TAU * freq * float(i) / float(RATE))
	return encode_wav(samples, RATE)


## wav_info parses a WAV for playback: rate, channels, the
## data chunk offset/size, and the true duration.
static func wav_info(wav: PackedByteArray) -> Dictionary:
	var info := {"rate": 0, "channels": 1, "data_off": -1, "data_size": 0, "dur": 0.0}
	if wav.size() < 44 or wav.slice(0, 4).get_string_from_ascii() != "RIFF":
		return info
	info["channels"] = int(wav.decode_u16(22))
	info["rate"] = int(wav.decode_u32(24))
	var off := 12
	while off + 8 <= wav.size():
		var tag := wav.slice(off, off + 4).get_string_from_ascii()
		var size := int(wav.decode_u32(off + 4))
		if tag == "data":
			info["data_off"] = off + 8
			info["data_size"] = mini(size, wav.size() - off - 8)
			break
		if size < 0:
			break
		off += 8 + size
	var rate := int(info["rate"])
	var ch := maxi(1, int(info["channels"]))
	if rate > 0 and int(info["data_size"]) > 0:
		info["dur"] = float(info["data_size"]) / float(rate * ch * 2)
	return info


## make_stream builds a playable AudioStreamWAV from a full
## WAV payload (header included); null when unparseable.
static func make_stream(wav: PackedByteArray) -> AudioStreamWAV:
	var info := wav_info(wav)
	if int(info["data_off"]) < 0 or int(info["rate"]) <= 0:
		return null
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = int(info["rate"])
	stream.stereo = int(info["channels"]) >= 2
	stream.data = wav.slice(int(info["data_off"]), int(info["data_off"]) + int(info["data_size"]))
	return stream
