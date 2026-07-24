# Jugadores empaquetados en el APK

Para añadir un jugador que venga incluido dentro del APK, crea una subcarpeta
con el nombre del jugador y mete dentro su foto y (opcionalmente) su audio:

```
bundled_players/
  Kevin/
    face.png      (o .jpg / .webp — la foto de la cara)
    sound.ogg     (o .mp3 / .wav — suena al golpear el balón; opcional)
    gol.ogg       (suena cuando marca gol; opcional; también vale goal.ogg)
  Maria/
    face.jpg
```

Cualquier audio cuyo nombre empiece por "gol" se usa como sonido de gol;
el resto de audios, como sonido de golpeo.

El nombre de la carpeta es el nombre del jugador en el juego
(los guiones bajos se convierten en espacios).

Después de añadir carpetas, vuelve a generar el APK.

Los jugadores añadidos desde la propia app NO necesitan esto: se guardan en el
almacenamiento del teléfono sin recompilar nada.
