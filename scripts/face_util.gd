class_name FaceUtil
## Utilidades para caras: máscara circular y caras por defecto generadas.

const CIRCLE_SHADER := "
shader_type canvas_item;
void fragment() {
	vec2 c = UV - vec2(0.5);
	if (length(c) > 0.5) {
		COLOR.a = 0.0;
	}
}
"

static var _circle_shader: Shader = null

static func circle_material() -> ShaderMaterial:
	if _circle_shader == null:
		_circle_shader = Shader.new()
		_circle_shader.code = CIRCLE_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = _circle_shader
	return mat

## Genera una cara sonriente simple de 256x256 para los cabezukis por defecto.
static func make_default_face(skin: Color, hair: Color, variant: int) -> ImageTexture:
	var size := 256
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size / 2.0, size / 2.0)
	var r := size / 2.0
	var eye_l := Vector2(size * 0.34, size * 0.42)
	var eye_r := Vector2(size * 0.66, size * 0.42)
	var mouth_c := Vector2(size * 0.5, size * 0.58)
	var dark := Color(0.15, 0.12, 0.1)
	for y in size:
		for x in size:
			var p := Vector2(x, y)
			var d := p.distance_to(center)
			if d > r:
				continue
			var col := skin
			# Pelo: casquete superior
			if variant % 2 == 0:
				if p.y < size * 0.28 or (d > r - 22.0 and p.y < center.y):
					col = hair
			else:
				if p.y < size * 0.2:
					col = hair
			# Ojos
			if p.distance_to(eye_l) < 15.0 or p.distance_to(eye_r) < 15.0:
				col = dark
			elif p.distance_to(eye_l) < 24.0 or p.distance_to(eye_r) < 24.0:
				col = Color.WHITE
			# Boca sonriente (arco)
			var md := p.distance_to(mouth_c)
			if md > 42.0 and md < 54.0 and p.y > mouth_c.y + 18.0:
				col = dark
			# Mejillas
			if p.distance_to(Vector2(size * 0.22, size * 0.6)) < 14.0 \
					or p.distance_to(Vector2(size * 0.78, size * 0.6)) < 14.0:
				col = col.lerp(Color(0.9, 0.4, 0.35), 0.45)
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)

