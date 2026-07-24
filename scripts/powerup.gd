class_name Powerup
extends RefCounted
## Datos de los power-ups: tipos, emoji y color de cada uno. Ya no son
## iconos flotantes en el campo; match.gd reparte 2 aleatorios por jugador
## al empezar cada tiempo (ver Head.held_powerups).

enum Type { BIG_BALL, BIG_GOAL, BOUNCY, LOW_GRAVITY, SPEED, FREEZE, SUPER_KICK }

const LABELS := {
	Type.BIG_BALL: "🎈",
	Type.BIG_GOAL: "🥅",
	Type.BOUNCY: "🏀",
	Type.LOW_GRAVITY: "🌙",
	Type.SPEED: "⚡",
	Type.FREEZE: "❄️",
	Type.SUPER_KICK: "💥",
}

const COLORS := {
	Type.BIG_BALL: Color(0.95, 0.55, 0.1),
	Type.BIG_GOAL: Color(0.6, 0.4, 0.9),
	Type.BOUNCY: Color(0.2, 0.75, 0.3),
	Type.LOW_GRAVITY: Color(0.3, 0.6, 0.95),
	Type.SPEED: Color(0.95, 0.85, 0.2),
	Type.FREEZE: Color(0.4, 0.85, 0.95),
	Type.SUPER_KICK: Color(0.9, 0.2, 0.25),
}
