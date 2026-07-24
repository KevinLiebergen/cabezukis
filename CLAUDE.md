# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Juego estilo *Soccer Heads* (fútbol 1 vs máquina) hecho con **Godot 4.7.1** en GDScript, exportado a Android. No es un repositorio git. Código y comentarios en español.

## Comandos

Godot está en `~/tools/godot/Godot_v4.7.1-stable_linux.x86_64` (no en el PATH).

```bash
# Ejecutar el juego en PC
~/tools/godot/Godot_v4.7.1-stable_linux.x86_64 --path .

# Comprobar sintaxis de un script
~/tools/godot/Godot_v4.7.1-stable_linux.x86_64 --headless --check-only -s res://scripts/match.gd

# Reimportar recursos (necesario tras añadir assets nuevos)
~/tools/godot/Godot_v4.7.1-stable_linux.x86_64 --headless --import

# Exportar el APK (requiere SDK en ~/tools/android-sdk, plantillas 4.7.1 y keystore en ~/tools/keys/debug.keystore, ya instalados)
~/tools/godot/Godot_v4.7.1-stable_linux.x86_64 --headless --export-debug "Android" build/cabezukis.apk

# Instalar en el móvil
adb install build/cabezukis.apk
```

### Pruebas y capturas (shot.gd)

No hay tests unitarios; la verificación se hace con `shot_scene.tscn` + `shot.gd`, una herramienta que carga una escena, opcionalmente la "conduce", imprime estado (`SHOT_STATE`, marcador, posiciones) y guarda una captura PNG. Se controla por variables de entorno:

```bash
# Captura de una escena (headless vale para menús; para el partido usar xvfb-run)
timeout 30 env SHOT_SCENE=main_menu SHOT_OUT=/ruta/salida.png SHOT_WAIT=2.0 \
  ~/tools/godot/Godot_v4.7.1-stable_linux.x86_64 --headless --path . res://shot_scene.tscn

# Partido con simulación de input (SHOT_DRIVE) y render real
timeout 120 env SHOT_SCENE=match SHOT_DRIVE=1 SHOT_WAIT=25 SHOT_OUT=/ruta/salida.png \
  xvfb-run -a -s '-screen 0 1280x720x24' \
  ~/tools/godot/Godot_v4.7.1-stable_linux.x86_64 --resolution 1280x720 --path . res://shot_scene.tscn
```

Otras variables: `SHOT_BALL`, `SHOT_FIELD`, `SHOT_P1_NAME`, `SHOT_DURATION`, `SHOT_FORCE_GOAL=1` (fuerza un gol y comprueba el audio de gol), `SHOT_HALFTIME=1` + `SHOT_OUT2` (descanso y segunda parte), `SHOT_TEST_IMPORT=1` (prueba la importación de jugadores), `SHOT_IMPORT_FIELDS=1`. `shot.gd` y `shot_scene.tscn` están excluidos del APK vía `exclude_filter` en `export_presets.cfg`.

## Arquitectura

Tres autoloads (singletons) definidos en `project.godot`, que son la columna vertebral:

- **`GameState`** (`scripts/game_state.gd`) — estado global entre escenas: jugadores elegidos (`p1`/`p2` como Dictionary), balón, campo, duración; registra los InputMap; persiste ajustes en `user://settings.json` y la música del descanso en `user://halftime.*`.
- **`PlayerDB`** (`scripts/player_db.gd`) — jugadores de tres orígenes fusionados: integrados (caras dibujadas por código con `FaceUtil`), empaquetados (`res://bundled_players/<Nombre>/face.png + sound.ogg + gol.ogg`) y del usuario (`user://players`, con importación desde `user://import`). Cada jugador es un Dictionary con `face: Texture2D`, `audio` (golpeo) y `goal_audio` (gol).
- **`FieldDB`** (`scripts/field_db.gd`) — campos: empaquetados (`res://bundled_fields`) y fotos del usuario (`user://fields`, importación desde `user://import_fields`); si no hay ninguno, cae a un estadio dibujado por código (`field_art.gd`).

Flujo de escenas (`scenes/`): `main_menu` → `player_select` (elige jugador, balón y campo) → `match`. Las pantallas `manage_players` y `manage_fields` alimentan las DBs. Toda la UI se construye en gran parte por código en los scripts homónimos.

El partido (`scripts/match.gd`, el script más grande) monta el campo, marcador, HUD, controles táctiles y power-ups, y orquesta `head.gd` (cabezudo: movimiento, chut e IA de la máquina), `ball.gd` (física con tamaño/rebote variables) y `powerup.gd`. Estructura del partido: 2 partes de 45 s con descanso (pausa + cambio de campo) y muerte súbita si hay empate.

Convención clave del proyecto: **casi todo el arte y el sonido se genera por código** — balones (`ball_styles.gd`), caras por defecto (`face_util.gd`), estadios (`field_art.gd`), botas (`boot.gd`) y efectos de sonido (`sound_factory.gd`, WAV sintetizados). Los únicos assets binarios son los aportados por el usuario.

## Assets y audio

- `cabezuki_assets/` son materiales fuente del usuario (caras, audios, escenarios); **no entra en el APK** y no se referencia desde el código. Desde ahí se copian a `bundled_*/` o se suben por la app.
- ⚠️ Los `.ogg` de WhatsApp son Opus y Godot no los decodifica. Convertir siempre a Vorbis: `ffmpeg -i nota.ogg -c:a libvorbis -q:a 4 salida.ogg`. Convención de nombres para importar: `<nombre>_golpe.ogg` y `<nombre>_gol.ogg`.
- En Android las carpetas de importación son `Android/data/com.cabezukis.game/files/import/` (jugadores) e `import_fields/` (escenarios); en PC, `~/.local/share/godot/app_userdata/Cabezukis/`.
