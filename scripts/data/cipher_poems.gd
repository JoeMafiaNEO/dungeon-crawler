class_name CipherPoems
## The Mason's Cipher: 8 cryptic poems hidden on parchment notes.
## Each poem ends with a Caesar-shifted word (word shifted FORWARD by shift;
## the verse hints the shift — count BACK to decode).
## Decoding all eight in order yields the passphrase for the lockbox.

const POEMS := [
	{"word": "THE", "shift": 3, "cipher": "WKH",
		"verse": [
			"Three turns the key in the mason's hand,",
			"Three stones to mark the buried gate,",
			"Three knocks before you understand —",
		]},
	{"word": "QUIET", "shift": 5, "cipher": "VZNJY",
		"verse": [
			"Five fingers close on the chisel's haft,",
			"Five winters weather the carven face,",
			"What speaks in stone needs no draft —",
		]},
	{"word": "STONE", "shift": 7, "cipher": "ZAVUL",
		"verse": [
			"Seven courses climb the tower wall,",
			"Seven arches hold the dome,",
			"The loudest empires fade and fall —",
		]},
	{"word": "REMEMBERS", "shift": 4, "cipher": "VIQIQFIVW",
		"verse": [
			"Four corners square the foundation's art,",
			"Four winds have worn the temple stair,",
			"What hands have shaped, the walls by heart —",
		]},
	{"word": "EVERY", "shift": 6, "cipher": "KBKXE",
		"verse": [
			"Six sides the mason's hammer knows,",
			"Six seams where the ashlars meet,",
			"No eye has seen where the old road goes —",
		]},
	{"word": "HAND", "shift": 8, "cipher": "PIVL",
		"verse": [
			"Eight bells have rung the quarry's song,",
			"Eight shadows cross the drafting floor,",
			"The work outlives the worker long —",
		]},
	{"word": "THAT", "shift": 3, "cipher": "WKDW",
		"verse": [
			"Three lines converge on the master plan,",
			"Three plumbs align the rising spire,",
			"The blueprint burns in the mind of man —",
		]},
	{"word": "BUILDS", "shift": 5, "cipher": "GZNQIX",
		"verse": [
			"Five pillars bear the vaulted deep,",
			"Five lanterns light the under-hall,",
			"What wakes the stone from ancient sleep —",
		]},
]


## Caesar-shift a word FORWARD by shift (A->D for 3, wraps Z->A).
## Uppercase; non-letters pass through unchanged.
static func cipher_word(word: String, shift: int) -> String:
	var w := word.to_upper()
	var out := ""
	for i in w.length():
		var c := w.unicode_at(i)
		if c >= 65 and c <= 90:
			out += char(65 + (c - 65 + shift) % 26)
		else:
			out += w[i]
	return out


## The decoded passphrase: all eight words in order.
static func passphrase() -> String:
	var words: Array = []
	for p in POEMS:
		words.append(str(p["word"]))
	return " ".join(words)


## Normalize player lockbox input: uppercase, collapse whitespace, trim.
static func normalize_key(s: String) -> String:
	var t := s.to_upper().strip_edges()
	for ws in ["\t", "\n", "\r"]:
		t = t.replace(ws, " ")
	return " ".join(t.split(" ", false))


## Lowest fragment index 0..7 not in collected, or -1 when complete.
static func next_fragment(collected: Array) -> int:
	for i in POEMS.size():
		if i not in collected:
			return i
	return -1


## English word for a shift, for the journal hint.
static func shift_word(shift: int) -> String:
	match shift:
		3:
			return "three"
		4:
			return "four"
		5:
			return "five"
		6:
			return "six"
		7:
			return "seven"
		8:
			return "eight"
	return str(shift)


## Roman numeral for the journal (I..VIII).
static func roman(idx: int) -> String:
	return ["I", "II", "III", "IV", "V", "VI", "VII", "VIII"][clampi(idx, 0, 7)]
