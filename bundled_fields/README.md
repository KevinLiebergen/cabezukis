# Escenarios empaquetados en el APK

Para incluir un escenario dentro del APK, crea una subcarpeta con el nombre
del escenario y mete dentro una foto:

```
bundled_fields/
  Mi_Pueblo/
    fondo.jpg    (cualquier imagen PNG/JPG/WebP)
```

El nombre de la carpeta es el nombre del escenario en el juego
(los guiones bajos se convierten en espacios).

La foto se usa como fondo completo y encima se dibujan el césped, las líneas
y las porterías.

Los escenarios añadidos desde la propia app NO necesitan esto: se guardan en
el almacenamiento del teléfono sin recompilar nada.
