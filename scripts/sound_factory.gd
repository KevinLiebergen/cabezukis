class_name SoundFactory
## Sonidos generados por código (no hacen falta archivos de audio).

const MIX_RATE := 22050

static func _to_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = bytes
	return wav

## Golpe seco (patada / toque de balón por defecto).
static func kick_sound() -> AudioStreamWAV:
	var dur := 0.14
	var n := int(dur * MIX_RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / MIX_RATE
		var freq := lerpf(190.0, 55.0, t / dur)
		var env := exp(-t * 30.0)
		s[i] = sin(TAU * freq * t) * env * 0.9 + (randf() * 2.0 - 1.0) * env * 0.15
	return _to_wav(s)

## "Tic" seco de la cuenta atrás (3, 2, 1).
static func countdown_tick_sound() -> AudioStreamWAV:
	var dur := 0.12
	var n := int(dur * MIX_RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / MIX_RATE
		var env := exp(-t * 25.0)
		s[i] = sin(TAU * 880.0 * t) * env * 0.6
	return _to_wav(s)

## Ovación al marcar gol (ruido con envolvente + tono grave).
static func goal_sound() -> AudioStreamWAV:
	var dur := 1.0
	var n := int(dur * MIX_RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var noise := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		noise = noise * 0.92 + (randf() * 2.0 - 1.0) * 0.35
		var env := minf(t / 0.1, 1.0) * exp(-maxf(t - 0.35, 0.0) * 3.0)
		s[i] = noise * env * 0.8 + sin(TAU * 90.0 * t) * env * 0.15
	return _to_wav(s)

## Recogida de power-up (arpegio ascendente).
static func powerup_sound() -> AudioStreamWAV:
	var notes := [523.0, 659.0, 784.0, 1047.0]
	var note_dur := 0.07
	var n := int(notes.size() * note_dur * MIX_RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / MIX_RATE
		var idx := mini(int(t / note_dur), notes.size() - 1)
		var lt := t - idx * note_dur
		var env := exp(-lt * 18.0)
		s[i] = sin(TAU * notes[idx] * t) * env * 0.5
	return _to_wav(s)

## Salto (pequeño "boing").
static func jump_sound() -> AudioStreamWAV:
	var dur := 0.12
	var n := int(dur * MIX_RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / MIX_RATE
		var freq := lerpf(280.0, 560.0, t / dur)
		s[i] = sin(TAU * freq * t) * exp(-t * 20.0) * 0.35
	return _to_wav(s)
