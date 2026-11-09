#!/usr/bin/env node
// Verifies every text pair used by the shipped themes against WCAG AA.
// Exits non-zero when a pair drops below its threshold.

const THEMES = {
	night: {
		"surface.base": "#0F1114",
		"surface.raised": "#16191E",
		"surface.sunken": "#0A0C0E",
		"text.primary": "#E7E9EC",
		"text.secondary": "#A3AAB5",
		"text.muted": "#7E8794",
		"accent.base": "#D4AF37",
		"accent.on": "#17130A",
		"state.success": "#4CAF7D",
		"state.warn": "#D9A441",
		"state.danger": "#E05B5B",
	},
	day: {
		"surface.base": "#F4F4F2",
		"surface.raised": "#FFFFFF",
		"surface.sunken": "#EAEAE6",
		"text.primary": "#14161A",
		"text.secondary": "#4A505A",
		"text.muted": "#656D7B",
		"accent.base": "#8A6A00",
		"accent.on": "#FFFFFF",
		"state.success": "#1F7A4D",
		"state.warn": "#8A5A00",
		"state.danger": "#B3261E",
	},
	contrast: {
		"surface.base": "#000000",
		"surface.raised": "#0B0B0B",
		"surface.sunken": "#000000",
		"text.primary": "#FFFFFF",
		"text.secondary": "#F2F2F2",
		"text.muted": "#D6D6D6",
		"accent.base": "#FFD84D",
		"accent.on": "#000000",
		"state.success": "#6BE3A4",
		"state.warn": "#FFD84D",
		"state.danger": "#FF8A8A",
	},
};

// [foreground, background, minimum ratio]
const PAIRS = [
	["text.primary", "surface.base", 4.5],
	["text.primary", "surface.raised", 4.5],
	["text.primary", "surface.sunken", 4.5],
	["text.secondary", "surface.base", 4.5],
	["text.secondary", "surface.raised", 4.5],
	["text.muted", "surface.base", 4.5],
	["text.muted", "surface.raised", 4.5],
	["accent.on", "accent.base", 4.5],
	["accent.base", "surface.base", 3],
	["accent.base", "surface.raised", 3],
	["state.success", "surface.raised", 4.5],
	["state.warn", "surface.raised", 4.5],
	["state.danger", "surface.raised", 4.5],
];

const hex = (value) => {
	const raw = value.replace("#", "");
	return [0, 2, 4].map((i) => parseInt(raw.slice(i, i + 2), 16) / 255);
};
const linear = (c) => (c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4));
const luminance = (value) => {
	const [r, g, b] = hex(value).map(linear);
	return 0.2126 * r + 0.7152 * g + 0.0722 * b;
};
const contrast = (a, b) => {
	const l1 = luminance(a);
	const l2 = luminance(b);
	const hi = Math.max(l1, l2);
	const lo = Math.min(l1, l2);
	return (hi + 0.05) / (lo + 0.05);
};

let failures = 0;
for (const [name, theme] of Object.entries(THEMES)) {
	for (const [fg, bg, min] of PAIRS) {
		const ratio = contrast(theme[fg], theme[bg]);
		const ok = ratio >= min;
		if (!ok) failures++;
		const mark = ok ? "pass" : "FAIL";
		console.log(`${name.padEnd(8)} ${fg} / ${bg} = ${ratio.toFixed(2)}:1 (min ${min}) ${mark}`);
	}
}

if (failures > 0) {
	console.error(`contrast: ${failures} pair(s) below threshold`);
	process.exit(1);
}
console.log("contrast: all pairs pass");
