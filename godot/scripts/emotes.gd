class_name Emotes
extends RefCounted

## Empire Age 17e — the drawn emoticon set shared by every
## chat surface. A token in chat text is the literal string
## "[e:<id>]"; the server validates ids against this same
## list (EmoteIDs in server/chathub.go) and strips unknown
## ones, so anything that reaches a client renders. Assets:
## assets/emotes/<id>.png, built by tools/build_emotes.py —
## one painted family, NO unicode emoji anywhere.
##
## Surfaces render tokens through here:
##   - chat-hub / alliance line bodies: fill_rich() swaps
##     tokens for [img] bbcode in a RichTextLabel;
##   - in-match speech bubbles (chat_bubbles.gd): wrap/paint
##     work on parse_atoms() so a token is drawn as an image
##     in the text flow;
##   - plain-text surfaces (marquee, transcripts) strip them.

const IDS: Array[String] = [
	"vui", "cuoi", "cuoi_khoc", "khoc", "buon", "gian",
	"ngac_nhien", "so", "choang", "ngu", "yeu", "tim",
	"like", "dislike", "yes", "no", "le_luoi", "xau_ho",
	"nghi", "om", "cuoi_deu", "hun", "kho_hieu", "met",
]

const PATH_FMT := "res://assets/emotes/%s.png"
## Pixel size a token renders at in rich chat lines.
const RICH_PX := 22
## Pixel size inside speech bubbles (chat_bubbles.gd).
const BUBBLE_PX := 18.0

static var _tex_cache: Dictionary = {}


static func is_valid_id(id: String) -> bool:
	return IDS.has(id)


static func token_of(id: String) -> String:
	return "[e:" + id + "]"


static func texture(id: String) -> Texture2D:
	if _tex_cache.has(id):
		return _tex_cache[id]
	var tex: Texture2D = null
	if is_valid_id(id):
		tex = load(PATH_FMT % id) as Texture2D
	_tex_cache[id] = tex
	return tex


static func path_of(id: String) -> String:
	return PATH_FMT % id


## parse_atoms splits a chat line into render atoms:
##   {"k": "w", "s": <word>, "sp": <space before>}
##   {"k": "e", "id": <emote id>, "sp": <space before>}
## Whitespace runs collapse to the single "sp" flag; an
## invalid "[e:...]" sequence stays literal text.
static func parse_atoms(text: String) -> Array:
	var atoms: Array = []
	var pos := 0
	var pending_space := false
	var n := text.length()
	while pos < n:
		var start := text.find("[e:", pos)
		var seg_end := n if start == -1 else start
		if seg_end > pos:
			pending_space = _push_words(atoms, text.substr(pos, seg_end - pos), pending_space)
		if start == -1:
			break
		var close := text.find("]", start)
		if close == -1:
			_push_words(atoms, text.substr(start), pending_space)
			break
		var inner := text.substr(start + 3, close - start - 3)
		if is_valid_id(inner):
			atoms.append({"k": "e", "id": inner, "sp": pending_space and not atoms.is_empty()})
			pending_space = false
			pos = close + 1
		else:
			pending_space = _push_words(atoms, text.substr(start, close - start + 1), pending_space)
			pos = close + 1
	return atoms


static func _push_words(atoms: Array, seg: String, pending_space: bool) -> bool:
	var word := ""
	for i in seg.length():
		var ch := seg[i]
		if ch == " " or ch == "\t" or ch == "\n":
			if word != "":
				atoms.append({"k": "w", "s": word, "sp": pending_space and not atoms.is_empty()})
				word = ""
			pending_space = true
		else:
			word += ch
	if word != "":
		atoms.append({"k": "w", "s": word, "sp": pending_space and not atoms.is_empty()})
		pending_space = false
	return pending_space


static func has_token(text: String) -> bool:
	return text.find("[e:") != -1


## strip_tokens removes every token (valid or not), leaving
## readable plain text for surfaces that cannot draw images.
static func strip_tokens(text: String) -> String:
	var out := ""
	for a in parse_atoms(text):
		if a["k"] == "w":
			if bool(a["sp"]) and out != "":
				out += " "
			out += String(a["s"])
	return out


static func _bb_escape(s: String) -> String:
	return s.replace("[", "[lb]")


## fill_rich renders a token-bearing line into a
## RichTextLabel's bbcode: text escaped, tokens as images.
static func fill_rich(rtl: RichTextLabel, text: String) -> void:
	var bb := ""
	for a in parse_atoms(text):
		if bool(a["sp"]) and bb != "":
			bb += " "
		if a["k"] == "e":
			bb += "[img=%dx%d]%s[/img]" % [RICH_PX, RICH_PX, path_of(String(a["id"]))]
		else:
			bb += _bb_escape(String(a["s"]))
	rtl.text = bb


## make_rich builds a configured RichTextLabel for one chat
## line body (fit-content, word wrap, no input capture).
static func make_rich(text: String, font_size: int, color: Color) -> RichTextLabel:
	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.fit_content = true
	rtl.scroll_active = false
	rtl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rtl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rtl.add_theme_font_size_override("normal_font_size", font_size)
	rtl.add_theme_font_size_override("bold_font_size", font_size)
	rtl.add_theme_color_override("default_color", color)
	rtl.add_theme_constant_override("line_separation", 1)
	fill_rich(rtl, text)
	return rtl
