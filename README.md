# ⚽ Cabezukis

Juego estilo *Soccer Heads*: fútbol 1 contra la máquina con cabezudos cuyas
caras son fotos que tú subes, y con un audio propio que suena cuando golpean
el balón. Hecho con Godot 4.7.

## Jugar

- **Móvil:** instala `build/cabezukis.apk` y usa los botones táctiles
  (◀ ▶ mover, ▲ saltar, ● chutar).
- **PC (para probar):**
  ```bash
  ~/tools/godot/Godot_v4.7.1-stable_linux.x86_64 --path .
  ```
  Teclas: A/D o flechas para moverse, W/↑ salta, Espacio/S/X chuta.

El partido dura 90 segundos en dos partes de 45. En el **descanso** el juego
se pausa, suena la música del descanso (piti time de serie; puedes cambiarla
en la pantalla de *Escenarios*) y al pulsar *Segunda parte* los equipos
**cambian de campo**.
Si acaba en empate hay muerte súbita.

## Balones y campos

Antes de cada partido eliges balón y campo (se recuerda tu última elección):

- **Balones** (dibujados por código): Trionda '26 (el del Mundial, por
  defecto), Clásico hexagonal B/N, Brazuca '14, Jabulani '10, Tango '82 y
  Roteiro '04.
- **Campos**: los escenarios de foto que añadas. Si no hay ninguno, se usa
  un estadio dibujado por código como último recurso.

### Añadir escenarios con tus fotos

Menú → *Escenarios* → nombre + foto. La foto llena el fondo y encima se
dibujan el césped y las porterías. También hay carpeta de importación (en
Android: `Android/data/com.cabezukis.game/files/import_fields/`) y carpeta
`bundled_fields/` para empaquetarlos en el APK (ver su README).

## Power-ups (aparecen flotando en el campo; se activan al tocarlos con el balón)

| Icono | Efecto |
|-------|--------|
| 🎈 | Pelota gigante |
| 🤏 | Pelota mini |
| 🏀 | Súper rebote |
| 🌙 | Gravedad lunar |
| ⚡ | Turbo para el último que tocó el balón |
| ❄️ | Congela al rival del último que tocó |
| 💥 | Chut mucho más potente |

## Añadir jugadores (caras y sonidos)

Cada jugador puede tener dos audios: **golpeo** (suena al tocar el balón) y
**gol** (suena cuando marca). ⚠️ Los `.ogg` de notas de voz de WhatsApp son
Opus y Godot no los decodifica: conviértelos antes con
`ffmpeg -i nota.ogg -c:a libvorbis -q:a 4 salida.ogg` (la app avisa si el
audio no vale).

**Desde la app** (sin recompilar): Menú → *Gestionar jugadores* → nombre +
foto + audio de golpeo + audio de gol (ambos opcionales).

**Por carpeta de importación**: copia archivos con la convención
`nombre.png/jpg` + `nombre_golpe.ogg` + `nombre_gol.ogg` (el golpeo también
vale como `nombre.ogg` a secas) a la carpeta que muestra la pantalla de
gestión y pulsa *Importar desde la carpeta*. En Android esa carpeta es
`Android/data/com.cabezukis.game/files/import/` (accesible por USB).

**Empaquetados en el APK**: mete carpetas en `bundled_players/` (ver su
README) y regenera el APK.

## Assets propios

En `cabezuki_assets/` (ignorada por Godot, no va dentro del APK) están tus
materiales: `caras/`, `audios/` (ya convertidos a Vorbis; los Opus originales
en `audios/originales_opus/`) y `escenarios/`. Desde ahí se suben por la app
o se copian a las carpetas de importación.

## Regenerar el APK

```bash
~/tools/godot/Godot_v4.7.1-stable_linux.x86_64 --headless --export-debug "Android" build/cabezukis.apk
```

Requiere (ya instalado en esta máquina):
- Godot 4.7.1 en `~/tools/godot/`
- Plantillas de exportación en `~/.local/share/godot/export_templates/4.7.1.stable/`
- Android SDK en `~/tools/android-sdk/` (build-tools 35, platform android-35)
- Keystore de debug en `~/tools/keys/debug.keystore` (configurada en los
  ajustes del editor de Godot)

Para instalar en el móvil: `adb install build/cabezukis.apk`, o copia el APK
al teléfono y ábrelo (hay que permitir "instalar apps desconocidas").

## Estructura

- `scripts/match.gd` — partido: campo, marcador, power-ups, HUD, controles táctiles
- `scripts/head.gd` — el cabezudo (movimiento, chut, y la IA de la máquina)
- `scripts/ball.gd` — balón (física, tamaño/rebote variables)
- `scripts/powerup.gd` — power-ups del campo
- `scripts/player_db.gd` — jugadores: integrados, del APK y creados por el usuario
- `scripts/field_art.gd` — decorado del estadio dibujado por código
- `shot.gd` / `shot_scene.tscn` — herramienta de desarrollo para capturas
  automatizadas (excluida del APK)
