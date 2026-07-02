// 배경 다이내믹 셰이더 — 보라/남색/짙은 청색 그라데이션 + TIME 기반 색상 변이
// 모바일 성능: sin 연산 2~3회 수준의 가벼운 절차적 셰이더 (외부 텍스처 불필요)
shader_type canvas_item;
render_mode unshaded;

// 기본 색상 — 어두운 보라 / 짙은 청 (보석빛 판타지 테마)
uniform vec3 color_a : source_color = vec3(0.18, 0.08, 0.32); // 어두운 보라
uniform vec3 color_b : source_color = vec3(0.05, 0.07, 0.22); // 짙은 청색
uniform float speed : hint_range(0.0, 2.0) = 0.3;              // 색상 변이 속도

void fragment() {
	// 세로 방향 기본 그라데이션 (위 color_a → 아래 color_b)
	float gradient = clamp(UV.y, 0.0, 1.0);

	// TIME 기반 색상 변이 — sin 파형으로 천천히 흐르는 색상 밀림
	float wave = sin(TIME * speed + UV.y * 3.0) * 0.5 + 0.5;

	// 부유하는 보석빛 느낌 — UV 좌표에 sin/TIME 더해 색상이 미세하게 밀림
	float drift = sin(TIME * speed * 0.7 + UV.x * 2.5) * 0.1;

	// 두 색상 보간 + 시간 변이 적용
	vec3 col = mix(color_a, color_b, gradient);
	col = mix(col, color_a * 1.3, wave * 0.25 + drift);

	// 약간의 보석빛 광채 (세로 위치에 따른 미세 밝기 변화)
	col += vec3(0.04, 0.02, 0.08) * sin(TIME * speed * 0.5 + UV.y * 6.0) * 0.5;

	COLOR = vec4(col, 1.0);
}
