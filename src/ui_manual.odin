package main

import "core:c"
import "core:fmt"
import "core:math"
import rl "vendor:raylib"
import "vendor:raylib/rlgl"

MANUAL_MAX_W       :: 1200
MANUAL_MAX_H       :: 800
MANUAL_NAV_W       :: 300
MANUAL_NAV_GAP     :: 8
MANUAL_COL_GAP     :: 20
MANUAL_BODY_PAD    :: 28
MANUAL_HEAD_H      :: 88
MANUAL_TEXT_SIZE   :: 13
MANUAL_LINE_H      :: 24
MANUAL_BLOCK_GAP   :: 16
MANUAL_KEY_SIZE    :: 10
MANUAL_KEY_H       :: 20
MANUAL_KEY_COL_W   :: 210
MANUAL_SCROLL_STEP :: 72
MANUAL_CLOSE_W     :: 132
MANUAL_CLOSE_H     :: 34
MANUAL_TABLE_ROW_H :: 28

Manual_Section :: struct {
	title: cstring,
	tag:   cstring,
	body:  proc(m: ^Manual_Layout),
}

MANUAL_SECTIONS := [?]Manual_Section{
	{"MISSION BRIEFING", "OPERATIONS", manual_mission},
	{"CAMERA AND VIEW", "NAVIGATION", manual_camera},
	{"MINING AND MINERALS", "ECONOMY", manual_mining},
	{"EARTH PRODUCTION", "INDUSTRY", manual_production},
	{"DRONE CLASSES", "ASSETS", manual_drones},
	{"FLEET COMMAND", "ORDERS", manual_fleet},
	{"LIBERATING PLANETS", "COMBAT", manual_liberation},
	{"OUTPOSTS", "INFRASTRUCTURE", manual_outposts},
	{"ORBITAL DEFENSES", "FORTIFICATION", manual_defenses},
	{"ENEMY ATTACKS", "THREAT ASSESSMENT", manual_attacks},
	{"FOG OF WAR AND INTEL", "SENSORS", manual_fog},
	{"ENEMY CITADEL", "PRIMARY TARGET", manual_citadel},
	{"COMMAND REFERENCE", "QUICK REFERENCE", manual_reference},
}

MANUAL_HINTS := [?]Menu_Hint{{"UP/DN", "SECTION"}, {"WHEEL", "SCROLL"}, {"ESC", "CLOSE"}}

manual_open := false
manual_section := 0
manual_scroll: f32
manual_scroll_target: f32
manual_content_h: f32
manual_thumb_drag := false
manual_thumb_grab: f32
manual_next_rect: rl.Rectangle

Manual_Layout :: struct {
	x, y, w: f32,
	view:    rl.Rectangle,
}

Manual_Style :: enum {
	BODY,
	TERM,
	WARN,
	HOSTILE,
	KEY,
}

Manual_Key :: struct {
	keys: string,
	desc: string,
}

Manual_Stat :: struct {
	value: cstring,
	label: cstring,
	color: rl.Color,
}

open_manual :: proc() {
	manual_open = true
	game_paused = true
	manual_thumb_drag = false
}

close_manual :: proc() {
	manual_open = false
	game_paused = false
	manual_thumb_drag = false
}

set_manual_section :: proc(section: int) {
	n := len(MANUAL_SECTIONS)
	manual_section = (section % n + n) % n
	manual_scroll = 0
	manual_scroll_target = 0
	manual_content_h = 0
	manual_thumb_drag = false
	manual_next_rect = {}
}

manual_rects :: proc() -> (box, nav, panel, view, close_btn: rl.Rectangle) {
	sw := f32(ui_screen_w())
	sh := f32(ui_screen_h())
	w := min(sw - 64, MANUAL_MAX_W)
	h := min(sh - MENU_FOOTER_H - 48, MANUAL_MAX_H)
	box = {math.round((sw - w) / 2), math.round((sh - MENU_FOOTER_H - h) / 2), w, h}
	top := box.y + MENU_TITLE_H + 10
	bottom := box.y + box.height - 26
	nav = {box.x + MENU_PAD_X, top, MANUAL_NAV_W, bottom - top}
	panel_x := nav.x + nav.width + MANUAL_COL_GAP
	panel = {panel_x, top, box.x + box.width - MENU_PAD_X - panel_x, bottom - top}
	view = {panel.x + MANUAL_BODY_PAD, panel.y + MANUAL_HEAD_H, panel.width - 2 * MANUAL_BODY_PAD - 12, panel.height - MANUAL_HEAD_H - 18}
	close_btn = {box.x + box.width - MENU_PAD_X - MANUAL_CLOSE_W, box.y + (MENU_TITLE_H - 8 - MANUAL_CLOSE_H) / 2, MANUAL_CLOSE_W, MANUAL_CLOSE_H}
	return
}

manual_tab_rect :: proc(nav: rl.Rectangle, index: int) -> rl.Rectangle {
	n := f32(len(MANUAL_SECTIONS))
	gap: f32 = nav.height < n * 38 ? 4 : MANUAL_NAV_GAP
	row_h := math.floor(clamp((nav.height + gap) / n - gap, 22, 42))
	return {nav.x, nav.y + f32(index) * (row_h + gap), nav.width, row_h}
}

manual_scroll_rects :: proc(panel, view: rl.Rectangle) -> (up, down, track: rl.Rectangle) {
	x := panel.x + panel.width - 26
	up = {x, view.y, 16, 16}
	down = {x, view.y + view.height - 16, 16, 16}
	track = {x + 5, up.y + up.height + 8, 6, down.y - 8 - (up.y + up.height + 8)}
	return
}

manual_max_scroll :: proc(view: rl.Rectangle) -> f32 {
	return max(manual_content_h - view.height, 0)
}

manual_thumb_rect :: proc(track, view: rl.Rectangle) -> rl.Rectangle {
	max_scroll := manual_max_scroll(view)
	if max_scroll <= 0 { return track }
	th := max(track.height * view.height / manual_content_h, 32)
	ty := track.y + (track.height - th) * clamp(manual_scroll / max_scroll, 0, 1)
	return {track.x, ty, track.width, th}
}

update_manual :: proc(dt: f32) {
	if rl.IsKeyPressed(.ESCAPE) || pause_key_pressed() {
		close_manual()
		return
	}
	box, nav, panel, view, close_btn := manual_rects()
	up, down, track := manual_scroll_rects(panel, view)
	max_scroll := manual_max_scroll(view)
	mouse := ui_mouse()

	if rl.IsKeyPressed(.UP) { set_manual_section(manual_section - 1) }
	if rl.IsKeyPressed(.DOWN) || rl.IsKeyPressed(.TAB) { set_manual_section(manual_section + 1) }
	if rl.IsKeyPressed(.PAGE_DOWN) { manual_scroll_target += view.height * 0.85 }
	if rl.IsKeyPressed(.PAGE_UP) { manual_scroll_target -= view.height * 0.85 }
	if rl.IsKeyPressed(.HOME) { manual_scroll_target = 0 }
	if rl.IsKeyPressed(.END) { manual_scroll_target = max_scroll }
	if wheel := rl.GetMouseWheelMove(); wheel != 0 && rl.CheckCollisionPointRec(mouse, box) {
		manual_scroll_target -= wheel * MANUAL_SCROLL_STEP
	}

	if rl.IsMouseButtonPressed(.LEFT) {
		thumb := manual_thumb_rect(track, view)
		if rl.CheckCollisionPointRec(mouse, close_btn) {
			close_manual()
			return
		}
		for i in 0..<len(MANUAL_SECTIONS) {
			if rl.CheckCollisionPointRec(mouse, manual_tab_rect(nav, i)) {
				if i != manual_section { set_manual_section(i) }
				return
			}
		}
		if manual_next_rect.width > 0 && rl.CheckCollisionPointRec(mouse, manual_next_rect) && rl.CheckCollisionPointRec(mouse, view) {
			set_manual_section(manual_section + 1)
			return
		}
		if max_scroll > 0 {
			if rl.CheckCollisionPointRec(mouse, up) {
				manual_scroll_target -= MANUAL_SCROLL_STEP
			} else if rl.CheckCollisionPointRec(mouse, down) {
				manual_scroll_target += MANUAL_SCROLL_STEP
			} else if rl.CheckCollisionPointRec(mouse, {thumb.x - 6, thumb.y, thumb.width + 12, thumb.height}) {
				manual_thumb_drag = true
				manual_thumb_grab = mouse.y - thumb.y
			} else if rl.CheckCollisionPointRec(mouse, {track.x - 6, track.y, track.width + 12, track.height}) {
				manual_scroll_target += mouse.y < thumb.y ? -view.height * 0.85 : view.height * 0.85
			}
		}
	}
	if !rl.IsMouseButtonDown(.LEFT) { manual_thumb_drag = false }
	if manual_thumb_drag && max_scroll > 0 {
		thumb := manual_thumb_rect(track, view)
		span := track.height - thumb.height
		if span > 0 {
			manual_scroll_target = (mouse.y - manual_thumb_grab - track.y) / span * max_scroll
		}
	}

	manual_scroll_target = clamp(manual_scroll_target, 0, max_scroll)
	if manual_thumb_drag {
		manual_scroll = manual_scroll_target
	} else {
		manual_scroll += (manual_scroll_target - manual_scroll) * min(dt * 16, 1)
		if abs(manual_scroll_target - manual_scroll) < 0.5 { manual_scroll = manual_scroll_target }
	}
}

draw_manual :: proc() {
	draw_menu_backdrop(MANUAL_HINTS[:])
	box, nav, panel, view, close_btn := manual_rects()
	mouse := ui_mouse()
	section := MANUAL_SECTIONS[manual_section]

	rl.DrawRectangleRounded(box, menu_round(box, 18), 16, rl.Color{0, 6, 4, 225})
	draw_menu_frame(box, "TUTORIAL")
	title_size: f32 = 28
	title_y := box.y + (MENU_TITLE_H - 8 - title_size) / 2 + 1
	sub_x := box.x + MENU_PAD_X + measure_display_text("TUTORIAL", title_size) + 24
	sub_y := title_y + title_size - 10 - 4
	draw_display_text("FIELD MANUAL", {sub_x, sub_y}, 10, SCIFI_LABEL)
	count_x := sub_x + measure_display_text("FIELD MANUAL", 10) + 14
	rl.DrawRectangleRec({count_x, sub_y + 1, 1, 9}, rl.Fade(SCIFI_GREEN, 0.45))
	draw_display_text(fmt.ctprintf("SECTION %02d OF %02d", manual_section + 1, len(MANUAL_SECTIONS)), {count_x + 14, sub_y}, 10, SCIFI_MUTED)

	draw_manual_close_button(close_btn, rl.CheckCollisionPointRec(mouse, close_btn))

	for s, i in MANUAL_SECTIONS {
		r := manual_tab_rect(nav, i)
		draw_manual_tab(r, i, s.title, i == manual_section, rl.CheckCollisionPointRec(mouse, r))
	}

	round := menu_round(panel, 14)
	rl.DrawRectangleRounded(panel, round, 16, rl.Color{0, 10, 7, 170})
	rl.DrawRectangleRoundedLinesEx(panel, round, 16, 1.5, rl.Fade(SCIFI_GREEN, 0.35))

	head_x := panel.x + MANUAL_BODY_PAD
	draw_display_text(fmt.ctprintf("%02d", manual_section + 1), {head_x, panel.y + 22}, 10, SCIFI_GREEN)
	draw_display_text(section.tag, {head_x + 30, panel.y + 22}, 10, SCIFI_LABEL)
	draw_display_text(section.title, {head_x, panel.y + 40}, 22, SCIFI_MINT)
	sep_y := panel.y + MANUAL_HEAD_H - 14
	sep_right := panel.x + panel.width - MANUAL_BODY_PAD
	rl.DrawLineEx({head_x, sep_y}, {sep_right, sep_y}, 1, rl.Fade(SCIFI_GREEN, 0.35))
	rl.DrawRectangleRec({head_x, sep_y - 1.5, 44, 3}, SCIFI_FILL)
	rl.DrawRectangleRec({sep_right - 3, sep_y - 4, 3, 8}, rl.Fade(SCIFI_GREEN, 0.7))

	rl.BeginScissorMode(c.int(view.x * ui_scale), c.int((view.y - 4) * ui_scale), c.int(math.ceil(view.width * ui_scale)), c.int(math.ceil((view.height + 8) * ui_scale)))
	m := Manual_Layout{x = view.x, y = view.y - manual_scroll, w = view.width, view = view}
	start_y := m.y
	section.body(&m)
	manual_next_rect = {}
	if manual_section + 1 < len(MANUAL_SECTIONS) {
		m.y += 8
		r := rl.Rectangle{m.x, m.y, m.w, MENU_ITEM_H}
		label := fmt.ctprintf("NEXT  //  %s", MANUAL_SECTIONS[manual_section + 1].title)
		visible := r.y + r.height > view.y && r.y < view.y + view.height
		hovered := visible && rl.CheckCollisionPointRec(mouse, r) && rl.CheckCollisionPointRec(mouse, view)
		draw_menu_item(r, label, "DOWN", hovered)
		if visible { manual_next_rect = r }
		m.y += MENU_ITEM_H
	}
	manual_content_h = m.y - start_y
	rl.EndScissorMode()

	if manual_max_scroll(view) > 0 {
		draw_manual_scrollbar(panel, view, mouse)
	}
}

draw_manual_close_button :: proc(r: rl.Rectangle, hovered: bool) {
	round := menu_round(r, 10)
	fill := rl.Color{0, 10, 7, 110}
	border := rl.Fade(SCIFI_GREEN, 0.6)
	text_col := SCIFI_GREEN
	if hovered {
		fill = SCIFI_FILL
		fill.a = 235
		border = rl.Fade(SCIFI_GREEN, 0.9)
		text_col = SCIFI_INK
	}
	rl.DrawRectangleRounded(r, round, 12, fill)
	rl.DrawRectangleRoundedLinesEx(r, round, 12, 1.5, border)
	cy := r.y + r.height / 2
	cx := r.x + 22
	rl.DrawLineEx({cx - 5, cy - 5}, {cx + 5, cy + 5}, 2, text_col)
	rl.DrawLineEx({cx - 5, cy + 5}, {cx + 5, cy - 5}, 2, text_col)
	draw_display_text("CLOSE", {cx + 16, cy - 7}, 14, text_col)
	kw := measure_display_text("ESC", 9)
	draw_display_text("ESC", {r.x + r.width - 14 - kw, cy - 4.5}, 9, rl.Fade(text_col, 0.65))
}

draw_manual_tab :: proc(r: rl.Rectangle, index: int, title: cstring, selected, hovered: bool) {
	round := menu_round(r, 10)
	fill := rl.Color{0, 10, 7, 110}
	border := rl.Fade(SCIFI_GREEN, 0.4)
	text_col := SCIFI_GREEN
	num_col := SCIFI_MUTED
	if selected {
		fill = SCIFI_FILL
		fill.a = 235
		border = rl.Fade(SCIFI_GREEN, 0.9)
		text_col = SCIFI_INK
		num_col = rl.Fade(SCIFI_INK, 0.6)
	} else if hovered {
		fill = rl.Color{8, 44, 30, 200}
		border = rl.Fade(SCIFI_GREEN, 0.8)
		text_col = SCIFI_MINT
		num_col = SCIFI_LABEL
	}
	rl.DrawRectangleRounded(r, round, 12, fill)
	rl.DrawRectangleRoundedLinesEx(r, round, 12, 1.5, border)
	cy := r.y + r.height / 2
	draw_display_text(fmt.ctprintf("%02d", index + 1), {r.x + 16, cy - 5}, 10, num_col)
	draw_display_text(title, {r.x + 48, cy - 6.5}, 13, text_col)
	if selected {
		ax := r.x + r.width - 22
		rl.DrawTriangle({ax, cy - 5}, {ax, cy + 5}, {ax + 7, cy}, text_col)
		px := r.x - 16
		rl.DrawTriangle({px, cy - 6}, {px, cy + 6}, {px + 8, cy}, SCIFI_GREEN)
	}
}

draw_manual_scrollbar :: proc(panel, view: rl.Rectangle, mouse: rl.Vector2) {
	up, down, track := manual_scroll_rects(panel, view)
	thumb := manual_thumb_rect(track, view)
	max_scroll := manual_max_scroll(view)
	for arrow, i in ([2]rl.Rectangle{up, down}) {
		hovered := rl.CheckCollisionPointRec(mouse, arrow)
		at_end := i == 0 ? manual_scroll <= 0.5 : manual_scroll >= max_scroll - 0.5
		col := at_end ? rl.Fade(SCIFI_GREEN, 0.3) : (hovered ? SCIFI_MINT : SCIFI_GREEN)
		rl.DrawRectangleRoundedLinesEx(arrow, 1, 12, 1, rl.Fade(col, 0.7))
		cx := arrow.x + arrow.width / 2
		cy := arrow.y + arrow.height / 2
		if i == 0 {
			rl.DrawLineEx({cx - 4, cy + 2}, {cx, cy - 2}, 1.5, col)
			rl.DrawLineEx({cx, cy - 2}, {cx + 4, cy + 2}, 1.5, col)
		} else {
			rl.DrawLineEx({cx - 4, cy - 2}, {cx, cy + 2}, 1.5, col)
			rl.DrawLineEx({cx, cy + 2}, {cx + 4, cy - 2}, 1.5, col)
		}
	}
	rl.DrawRectangleRounded(track, 1, 8, rl.Color{0, 30, 18, 200})
	rl.DrawRectangleRoundedLinesEx(track, 1, 8, 1, rl.Fade(SCIFI_GREEN, 0.25))
	hot := manual_thumb_drag || rl.CheckCollisionPointRec(mouse, {thumb.x - 6, thumb.y, thumb.width + 12, thumb.height})
	rl.DrawRectangleRounded(thumb, 1, 8, hot ? SCIFI_GREEN : SCIFI_FILL)
	mid := thumb.y + thumb.height / 2
	for k in -1..=1 {
		rl.DrawLineEx({thumb.x + 1.5, mid + f32(k) * 3}, {thumb.x + thumb.width - 1.5, mid + f32(k) * 3}, 1, rl.Fade(SCIFI_INK, 0.7))
	}
}

manual_style_color :: proc(style: Manual_Style) -> rl.Color {
	switch style {
	case .BODY:    return rl.Color{188, 226, 208, 255}
	case .TERM:    return SCIFI_GREEN
	case .WARN:    return SCIFI_AMBER
	case .HOSTILE: return SCIFI_RED
	case .KEY:     return SCIFI_INK
	}
	return SCIFI_TEXT
}

Manual_Segment :: struct {
	text:  string,
	style: Manual_Style,
	w:     f32,
}

manual_cstr :: proc(buf: ^[256]u8, s: string) -> cstring {
	n := min(len(s), len(buf) - 1)
	copy(buf[:n], s[:n])
	buf[n] = 0
	return cstring(&buf[0])
}

manual_segment_width :: proc(seg: Manual_Segment) -> f32 {
	buf: [256]u8
	if seg.style == .KEY {
		return max(measure_display_text(manual_cstr(&buf, seg.text), MANUAL_KEY_SIZE) + 14, 22)
	}
	return measure_display_text(manual_cstr(&buf, seg.text), MANUAL_TEXT_SIZE)
}

draw_manual_keycap :: proc(text: cstring, x, cy, w: f32) {
	cap := rl.Rectangle{x, cy - MANUAL_KEY_H / 2, w, MANUAL_KEY_H}
	rl.DrawRectangleRounded(cap, 0.45, 8, SCIFI_FILL)
	rl.DrawRectangleRoundedLinesEx(cap, 0.45, 8, 1, SCIFI_GREEN)
	tw := measure_display_text(text, MANUAL_KEY_SIZE)
	draw_display_text(text, {x + (w - tw) / 2, cy - MANUAL_KEY_SIZE * 0.5}, MANUAL_KEY_SIZE, SCIFI_INK)
}

manual_rich_text :: proc(text: string, x, y, w: f32, view: rl.Rectangle) -> f32 {
	size: f32 = MANUAL_TEXT_SIZE
	spacing := display_spacing(size)
	space_w := measure_display_text(" ", size) + spacing
	style := Manual_Style.BODY
	line_y := y
	cx: f32 = 0
	i := 0
	buf: [256]u8
	for i < len(text) {
		ch := text[i]
		if ch == ' ' {
			i += 1
			continue
		}
		if ch == '\n' {
			line_y += MANUAL_LINE_H
			cx = 0
			i += 1
			continue
		}
		segs: [8]Manual_Segment
		nseg := 0
		word_w: f32 = 0
		for i < len(text) && text[i] != ' ' && text[i] != '\n' {
			ch = text[i]
			switch ch {
			case '{': style = .TERM; i += 1; continue
			case '<': style = .WARN; i += 1; continue
			case '}', '>': style = .BODY; i += 1; continue
			case '|':
				style = style == .HOSTILE ? .BODY : .HOSTILE
				i += 1
				continue
			}
			seg: Manual_Segment
			if ch == '[' {
				j := i + 1
				for j < len(text) && text[j] != ']' { j += 1 }
				seg = {text = text[i + 1:j], style = .KEY}
				i = min(j + 1, len(text))
			} else {
				start := i
				for i < len(text) {
					d := text[i]
					if d == ' ' || d == '\n' || d == '{' || d == '}' || d == '<' || d == '>' || d == '|' || d == '[' { break }
					i += 1
				}
				seg = {text = text[start:i], style = style}
			}
			seg.w = manual_segment_width(seg)
			if nseg < len(segs) {
				if nseg > 0 { word_w += seg.style == .KEY || segs[nseg - 1].style == .KEY ? 4 : spacing }
				segs[nseg] = seg
				nseg += 1
				word_w += seg.w
			}
		}
		if cx > 0 && cx + word_w > w {
			line_y += MANUAL_LINE_H
			cx = 0
		}
		if line_y + MANUAL_LINE_H >= view.y && line_y <= view.y + view.height {
			sx := x + cx
			cy := line_y + MANUAL_LINE_H / 2
			for s, k in segs[:nseg] {
				if k > 0 { sx += s.style == .KEY || segs[k - 1].style == .KEY ? 4 : spacing }
				if s.style == .KEY {
					draw_manual_keycap(manual_cstr(&buf, s.text), sx, cy, s.w)
				} else {
					draw_display_text(manual_cstr(&buf, s.text), {sx, cy - size * 0.5 - 1}, size, manual_style_color(s.style))
				}
				sx += s.w
			}
		}
		cx += word_w + space_w
	}
	return line_y + MANUAL_LINE_H - y
}

manual_visible :: proc(m: ^Manual_Layout, h: f32) -> bool {
	return m.y + h >= m.view.y - 8 && m.y <= m.view.y + m.view.height + 8
}

manual_text :: proc(m: ^Manual_Layout, text: string) {
	m.y += manual_rich_text(text, m.x, m.y, m.w, m.view) + MANUAL_BLOCK_GAP
}

manual_heading :: proc(m: ^Manual_Layout, title: cstring) {
	m.y += 4
	if manual_visible(m, 20) {
		size: f32 = 11
		draw_display_text(title, {m.x, m.y + 2}, size, SCIFI_GREEN)
		lx := m.x + measure_display_text(title, size) + 12
		ly := m.y + 2 + size * 0.5
		rl.DrawLineEx({lx, ly}, {m.x + m.w, ly}, 1, rl.Fade(SCIFI_GREEN, 0.3))
		rl.DrawRectangleRec({m.x + m.w - 3, ly - 3, 3, 6}, rl.Fade(SCIFI_GREEN, 0.7))
	}
	m.y += 26
}

manual_step :: proc(m: ^Manual_Layout, number: int, text: string) {
	indent: f32 = 44
	h := manual_rich_text(text, m.x + indent, m.y, m.w - indent, m.view)
	if manual_visible(m, MANUAL_LINE_H) {
		tag := rl.Rectangle{m.x, m.y + 2, 30, MANUAL_LINE_H - 4}
		draw_chamfered_panel(tag, 4, rl.Color{6, 40, 26, 255}, SCIFI_STEEL)
		label := fmt.ctprintf("%02d", number)
		lw := measure_display_text(label, 10)
		draw_display_text(label, {tag.x + (tag.width - lw) / 2, tag.y + tag.height / 2 - 5}, 10, SCIFI_GREEN)
	}
	m.y += h + 8
}

manual_keys :: proc(m: ^Manual_Layout, rows: []Manual_Key) {
	for row, i in rows {
		key_h := manual_rich_text(row.keys, m.x + 12, m.y + 6, MANUAL_KEY_COL_W - 20, m.view)
		desc_h := manual_rich_text(row.desc, m.x + MANUAL_KEY_COL_W, m.y + 6, m.w - MANUAL_KEY_COL_W - 12, m.view)
		h := max(key_h, desc_h) + 12
		if manual_visible(m, h) {
			if i % 2 == 0 {
				rl.DrawRectangleRec({m.x, m.y, m.w, h}, rl.Color{0, 40, 24, 40})
			}
			rl.DrawLineEx({m.x, m.y + h}, {m.x + m.w, m.y + h}, 1, rl.Fade(SCIFI_GREEN, 0.12))
		}
		m.y += h
	}
	m.y += MANUAL_BLOCK_GAP
}

manual_figure :: proc(m: ^Manual_Layout, h: f32, draw: proc(r: rl.Rectangle)) {
	r := rl.Rectangle{m.x, m.y, m.w, h}
	if manual_visible(m, h) {
		round := menu_round(r, 10)
		rl.DrawRectangleRounded(r, round, 12, rl.Color{0, 18, 12, 150})
		rl.DrawRectangleRoundedLinesEx(r, round, 12, 1, rl.Fade(SCIFI_GREEN, 0.3))
		rl.DrawRectangleRec({r.x + 18, r.y - 1, 40, 3}, SCIFI_FILL)
		draw(r)
	}
	m.y += h + MANUAL_BLOCK_GAP + 4
}

manual_table_h :: proc(rows: int) -> f32 {
	return f32(rows + 1) * MANUAL_TABLE_ROW_H + 24
}

draw_manual_table_row :: proc(r: rl.Rectangle, row: int, cols: []f32, cells: []cstring, colors: []rl.Color) {
	y := r.y + 12 + f32(row) * MANUAL_TABLE_ROW_H
	x := r.x + 20
	inner_w := r.width - 40
	if row == 0 {
		rl.DrawLineEx({x, y + MANUAL_TABLE_ROW_H - 2}, {x + inner_w, y + MANUAL_TABLE_ROW_H - 2}, 1, rl.Fade(SCIFI_GREEN, 0.4))
	} else if row % 2 == 0 {
		rl.DrawRectangleRec({x, y + 1, inner_w, MANUAL_TABLE_ROW_H - 2}, rl.Color{0, 50, 30, 46})
	}
	size: f32 = row == 0 ? 9 : 11
	cx := x + 8
	for cell, k in cells {
		col := colors[min(k, len(colors) - 1)]
		draw_display_text(cell, {cx, y + MANUAL_TABLE_ROW_H / 2 - size * 0.5 - 1}, size, row == 0 ? SCIFI_LABEL : col)
		cx += cols[k] * (inner_w - 16)
	}
}

draw_manual_card :: proc(r: rl.Rectangle, color: rl.Color) {
	round := menu_round(r, 10)
	rl.DrawRectangleRounded(r, round, 12, rl.Color{0, 12, 8, 220})
	rl.DrawRectangleRounded(r, round, 12, rl.Fade(color, 0.05))
	rl.DrawRectangleRoundedLinesEx(r, round, 12, 1.5, rl.Fade(color, 0.55))
	rl.DrawRectangleRec({r.x + 14, r.y - 1, 28, 3}, color)
}

draw_manual_stats :: proc(r: rl.Rectangle, stats: []Manual_Stat) {
	gap: f32 = 14
	n := f32(len(stats))
	tile_w := (r.width - 40 - gap * (n - 1)) / n
	for s, i in stats {
		t := rl.Rectangle{r.x + 20 + f32(i) * (tile_w + gap), r.y + 16, tile_w, r.height - 32}
		draw_manual_card(t, s.color)
		vw := measure_display_text(s.value, 24)
		fill := s.color == SCIFI_RED ? rl.Color{255, 200, 204, 255} : (s.color == SCIFI_AMBER ? rl.Color{255, 214, 176, 255} : SCIFI_MINT)
		draw_display_text_glow(s.value, {t.x + (t.width - vw) / 2, t.y + 14}, 24, fill, rl.Fade(s.color, 0.3), rl.Fade(s.color, 0.45))
		lw := measure_display_text(s.label, 9)
		draw_display_text(s.label, {t.x + (t.width - lw) / 2, t.y + t.height - 22}, 9, SCIFI_LABEL)
	}
}

manual_mission :: proc(m: ^Manual_Layout) {
	manual_text(m, "The solar system has fallen to a hostile drone armada. You hold only {Earth}. Every other planet is held by an |enemy garrison|, and the |Enemy HQ| waits in deep space beyond Neptune.")
	manual_figure(m, 250, draw_manual_system_map)
	manual_text(m, "{Victory}: liberate all eight planets and destroy the Enemy HQ. <Defeat>: lose every command base and every drone you own.")
	manual_heading(m, "YOUR FIRST MINUTES")
	manual_step(m, 1, fmt.tprintf("Queue {{mining drones}} with [M] until Earth's %d mining slots are full. More drones means more {{minerals}}.", planet_mining_cap(EARTH)))
	manual_step(m, 2, "Queue {combat drones} with [C], select them in the inspector, and right-click a weakly held planet such as |Venus|.")
	manual_step(m, 3, "When the planet is liberated, send miners there and build a {refinery} with [B] to start earning from it.")
	manual_step(m, 4, "Reinvest: more {command bases}, bigger fleets, and {orbital defenses} to hold what you take.")
	m.y += MANUAL_BLOCK_GAP - 8
	manual_text(m, "Opening this manual pauses the game. Work through the sections in order, or jump to any topic on the left.")
}

draw_manual_system_map :: proc(r: rl.Rectangle) {
	for gx := r.x + 40; gx < r.x + r.width - 20; gx += 40 {
		rl.DrawLineEx({gx, r.y + 12}, {gx, r.y + r.height - 12}, 1, rl.Color{71, 252, 175, 12})
	}
	for gy := r.y + 30; gy < r.y + r.height - 12; gy += 40 {
		rl.DrawLineEx({r.x + 12, gy}, {r.x + r.width - 12, gy}, 1, rl.Color{71, 252, 175, 12})
	}

	min_x, max_x := planets[0].position.x, planets[0].position.x
	min_z, max_z := planets[0].position.z, planets[0].position.z
	for p in 0..<PLANET_COUNT {
		pos := planets[p].position
		min_x = min(min_x, pos.x); max_x = max(max_x, pos.x)
		min_z = min(min_z, pos.z); max_z = max(max_z, pos.z)
	}
	hq_gap := (max_x - min_x) * 0.35
	legend_w: f32 = 170
	area := rl.Rectangle{r.x + 56, r.y + 40, r.width - 112 - legend_w, r.height - 92}
	sx := area.width / (max_x - min_x + hq_gap)
	sz := min(area.height / (max_z - min_z), sx * 0.75)
	oz := area.y + (area.height - (max_z - min_z) * sz) / 2
	to_map :: proc(x, z, min_x, min_z, sx, sz, ox, oz: f32) -> rl.Vector2 {
		return {ox + (x - min_x) * sx, oz + (z - min_z) * sz}
	}

	earth := to_map(planets[EARTH].position.x, planets[EARTH].position.z, min_x, min_z, sx, sz, area.x, oz)
	hq := to_map(max_x + hq_gap, ENEMY_HQ_POSITION.z, min_x, min_z, sx, sz, area.x, oz)
	steps := 48
	for k in 0..<steps {
		if k % 2 == 1 { continue }
		a := earth + (hq - earth) * (f32(k) / f32(steps))
		b := earth + (hq - earth) * (f32(k + 1) / f32(steps))
		rl.DrawLineEx(a, b, 1, rl.Fade(SCIFI_RED, 0.3))
	}
	brk := earth + (hq - earth) * 0.82
	for k in 0..<2 {
		o := rl.Vector2{f32(k) * 6 - 3, 0}
		rl.DrawLineEx(brk + o + {-3, 7}, brk + o + {3, -7}, 1.5, rl.Fade(SCIFI_RED, 0.75))
	}

	for p in 0..<PLANET_COUNT {
		c := to_map(planets[p].position.x, planets[p].position.z, min_x, min_z, sx, sz, area.x, oz)
		rad := clamp(planets[p].radius * sx * 0.5, 6, 18)
		ring := planet_liberated(p) ? SCIFI_GREEN : SCIFI_RED
		rl.DrawCircleV(c, rad + 7, rl.Fade(ring, 0.08))
		rl.DrawCircleV(c, rad, planets[p].color)
		rl.DrawCircleV(c + {rad * 0.3, rad * 0.25}, rad * 0.75, rl.Color{0, 0, 0, 70})
		rl.DrawRing(c, rad + 3, rad + 4.5, 0, 360, 36, ring)
		nw := measure_display_text(planets[p].name, 9)
		draw_display_text(planets[p].name, {c.x - nw / 2, c.y + rad + 9}, 9, p == EARTH ? SCIFI_GREEN : SCIFI_MINT)
	}

	hq_r: f32 = 13
	rl.DrawCircleV(hq, hq_r + 12, rl.Fade(SCIFI_RED, 0.1))
	rl.DrawPoly(hq, 6, hq_r, 0, rl.Color{70, 10, 16, 255})
	rl.DrawPolyLinesEx(hq, 6, hq_r, 0, 2, SCIFI_RED)
	rl.DrawPolyLinesEx(hq, 6, hq_r * 0.5, 30, 1.5, rl.Fade(SCIFI_RED, 0.7))
	hw := measure_display_text("ENEMY HQ", 9)
	draw_display_text("ENEMY HQ", {hq.x - hw / 2, hq.y + hq_r + 10}, 9, SCIFI_RED)

	lx := r.x + r.width - legend_w - 10
	ly := r.y + 28
	draw_display_text("SECTOR MAP", {lx, ly}, 9, SCIFI_LABEL)
	ly += 26
	rl.DrawRing({lx + 7, ly + 6}, 5, 6.5, 0, 360, 24, SCIFI_GREEN)
	draw_display_text("LIBERATED", {lx + 22, ly + 1}, 10, SCIFI_MINT)
	ly += 24
	rl.DrawRing({lx + 7, ly + 6}, 5, 6.5, 0, 360, 24, SCIFI_RED)
	draw_display_text("OCCUPIED", {lx + 22, ly + 1}, 10, SCIFI_MINT)
	ly += 24
	rl.DrawPolyLinesEx({lx + 7, ly + 6}, 6, 6.5, 0, 1.5, SCIFI_RED)
	draw_display_text("ENEMY HQ", {lx + 22, ly + 1}, 10, SCIFI_MINT)
	draw_display_text(fmt.ctprintf("%d OF %d PLANETS FREE", liberated_planet_count(), PLANET_COUNT), {lx, r.y + r.height - 34}, 9, SCIFI_GREEN)
}

manual_camera :: proc(m: ^Manual_Layout) {
	manual_text(m, "You command from orbit. The {inspector} on the right shows whatever is selected, the {resource readout} in the top left tracks your minerals, and the telemetry in the bottom right reports altitude, zoom, and frame rate.")
	manual_keys(m, {
		{"[W] [A] [S] [D] / [ARROWS]", "Pan the tactical view across the system."},
		{"[Q] [E] / [WHEEL]", "Zoom the altitude in and out. [-] and [=] work too."},
		{"[SPACE]", "Select {Earth}. Press again to center the camera on it."},
		{"[LEFT CLICK]", "Select a planet, or the |Enemy HQ|, and open it in the inspector."},
		{"[F11] / [ALT] + [ENTER]", "Toggle borderless fullscreen."},
		{"[P] / [F10]", "Pause and open the mission menu: save, load, new game, or quit."},
		{"[F5]", "Quick-save without pausing."},
	})
	manual_heading(m, "PLANET BADGES")
	manual_text(m, "Every liberated planet carries a {status badge} under its name: orbital defense ammo, mining drones against the planet's mining cap, and fighters on station. Badges stay dim until the planet is selected, and they double as shortcuts, covered in {Fleet Command}.")
	manual_heading(m, "SECTOR GLOWS")
	manual_text(m, "Space itself warns you. A |red glow| around a planet means battle or an incoming raid; an <amber glow> marks the enemy world launching it. The Enemy HQ always smolders red.")
}

manual_mining :: proc(m: ^Manual_Layout) {
	manual_text(m, "{Minerals} pay for everything. They flow in continuously from {mining drones} working a planet, so nothing has to be hauled home and the income starts the moment a drone is at work.")
	manual_figure(m, 132, draw_manual_resource_figure)
	manual_text(m, "Each planet has a {mining cap}. Drones beyond the cap wait idle in orbit as a reserve and step in when a working drone is lost or called away to a construction crew, so surplus drones never earn extra.")
	manual_text(m, "A planet only pays once it has a {refinery}. Earth starts with one; every liberated world needs its own. Distant worlds yield more per trip but each trip takes longer:")
	manual_figure(m, manual_table_h(PLANET_COUNT), draw_manual_yield_table)
	manual_text(m, "Send miners to a planet by selecting them and right-clicking it. <Only mine liberated planets>: drones parked at an enemy world are destroyed.")
}

draw_manual_resource_figure :: proc(r: rl.Rectangle) {
	rlgl.PushMatrix()
	rlgl.Translatef(r.x + 28 - HUD_PAD, r.y + 14 - HUD_PAD, 0)
	draw_resource_hud()
	rlgl.PopMatrix()

	lx := r.x + 400
	rows := [3][2]cstring{
		{"MINERAL STOCK", "Spend it on drones, bases, and structures."},
		{"INCOME / S", "Live yield from every working miner."},
		{"DRONE SPEED", "Build-speed upgrade level, up to 5."},
	}
	for row, i in rows {
		y := r.y + 24 + f32(i) * 32
		draw_display_text(fmt.ctprintf("%02d", i + 1), {lx, y + 1}, 9, SCIFI_GREEN)
		draw_display_text(row[0], {lx + 28, y}, 11, SCIFI_MINT)
		draw_display_text(row[1], {lx + 28, y + 15}, 9, SCIFI_MUTED)
	}
}

draw_manual_yield_table :: proc(r: rl.Rectangle) {
	cols := []f32{0.17, 0.14, 0.15, 0.17, 0.18, 0.19}
	colors := []rl.Color{SCIFI_MINT, SCIFI_TEXT}
	draw_manual_table_row(r, 0, cols, {"PLANET", "DRONE CAP", "PER TRIP", "ROUND TRIP", "MAX INCOME", "REFINERY"}, colors)
	for p in 0..<PLANET_COUNT {
		cap := planet_mining_cap(p)
		cycle := planet_cycle_time(p)
		refinery := p == EARTH ? cstring("BUILT") : fmt.ctprintf("%d", cap * 10)
		draw_manual_table_row(r, p + 1, cols, {
			planets[p].name,
			fmt.ctprintf("%d", cap),
			fmt.ctprintf("%d", mining_rate(p)),
			fmt.ctprintf("%.1f S", cycle),
			fmt.ctprintf("+%.1f / S", f32(cap * mining_rate(p)) / cycle),
			refinery,
		}, p == EARTH ? []rl.Color{SCIFI_GREEN} : colors)
	}
}

manual_production :: proc(m: ^Manual_Layout) {
	manual_text(m, fmt.tprintf("Earth is your only shipyard. Every {{command base}} adds one {{production line}}, and the lines build in parallel, one drone each. You start with 1 base and can grow to %d.", MAX_BASES))
	manual_keys(m, {
		{"[M]", fmt.tprintf("Queue a mining drone for {{%d}} minerals.", MINER_COST)},
		{"[C]", fmt.tprintf("Queue a combat drone for {{%d}} minerals.", COMBAT_COST)},
		{"[N] / [SHIFT] + [M]", fmt.tprintf("Queue 5 miners for {{%d}}. Needs all %d bases.", BATCH_MINER_COST, MAX_BASES)},
		{"[X] / [SHIFT] + [C]", fmt.tprintf("Queue 5 fighters for {{%d}}. Needs all %d bases.", BATCH_COMBAT_COST, MAX_BASES)},
		{"[U]", "Buy the next drone build-speed upgrade."},
		{"[T]", "Toggle the autobuilder. Needs all 5 bases."},
		{"[ESC]", "Cancel the newest queued build with a full refund."},
		{"[CLICK SLOT]", "Cancel that slot in the queue buffer, also refunded."},
	})
	manual_figure(m, manual_table_h(4), draw_manual_production_table)
	manual_text(m, fmt.tprintf("The {{queue buffer}} holds 5 orders per base. A new base needs a crew of {{%d mining drones}} for its %.0f second build, pulled from Earth's miners, so income dips while it is under construction.", BASE_CONSTRUCT_MINERS, BASE_CONSTRUCT_TIME))
	manual_heading(m, "AUTOBUILDER")
	manual_text(m, "With all 5 bases built, the radio in the queue header keeps ordering batches of 5 miners or 5 fighters whenever the queue runs dry and you can afford it. Press [T] to switch it on and off.")
	manual_heading(m, "RALLY POINT")
	manual_text(m, "With Earth selected and no drones selected, right-click another planet to set a {rally point}: new drones fly straight there when they launch. Right-click Earth to clear it.")
}

draw_manual_production_table :: proc(r: rl.Rectangle) {
	cols := []f32{0.27, 0.14, 0.17, 0.42}
	colors := []rl.Color{SCIFI_MINT, SCIFI_TEXT, SCIFI_TEXT, SCIFI_MUTED}
	draw_manual_table_row(r, 0, cols, {"ORDER", "COST", "BUILD TIME", "NOTES"}, colors)
	draw_manual_table_row(r, 1, cols, {"MINING DRONE", fmt.ctprintf("%d", MINER_COST), fmt.ctprintf("%.1f S", drone_build_time(.MINING)), "One per production line"}, colors)
	draw_manual_table_row(r, 2, cols, {"COMBAT DRONE", fmt.ctprintf("%d", COMBAT_COST), fmt.ctprintf("%.1f S", drone_build_time(.COMBAT)), "One per production line"}, colors)
	draw_manual_table_row(r, 3, cols, {"COMMAND BASE", fmt.ctprintf("%d", BASE_COST), fmt.ctprintf("%.0f S", BASE_CONSTRUCT_TIME), fmt.ctprintf("Crew of %d miners, max %d", BASE_CONSTRUCT_MINERS, MAX_BASES)}, colors)
	draw_manual_table_row(r, 4, cols, {"DRONE SPEED", fmt.ctprintf("%d", DRONE_SPEED_UPGRADE_COST), "INSTANT", fmt.ctprintf("-%.0f%% build time per level, %d levels", (1 - DRONE_SPEED_UPGRADE_FACTOR) * 100, DRONE_SPEED_UPGRADE_MAX)}, colors)
}

manual_drones :: proc(m: ^Manual_Layout) {
	manual_text(m, "Two drone classes do all the work. Both are built on Earth and both appear as tiles in the inspector rosters of the planet they belong to.")
	manual_figure(m, 176, draw_manual_drone_cards)
	manual_text(m, "Enemy drones use the same hulls drawn in |red|. They only show up where you have vision; see {Fog of War and Intel}.")
	manual_heading(m, "STATUS LIGHTS")
	manual_text(m, "The dot in the corner of each roster tile shows what that drone is doing right now:")
	manual_figure(m, 5 * 30 + 24, draw_manual_state_legend)
	manual_text(m, "Mining drones in transit are never targeted. Parked at a planet with no fighters to protect them, they are picked off one by one.")
}

draw_manual_drone_cards :: proc(r: rl.Rectangle) {
	gap: f32 = 16
	card_w := (r.width - 40 - gap) / 2
	cards := [2]struct {
		kind:  Unit_Type,
		title: cstring,
		stats: cstring,
		line1: cstring,
		line2: cstring,
		color: rl.Color,
	}{
		{.MINING, "MINING DRONE", fmt.ctprintf("COST %d  //  BUILD %.1f S", MINER_COST, drone_build_time(.MINING)), "Mines minerals and crews every", "construction project. Unarmed.", SCIFI_AMBER},
		{.COMBAT, "COMBAT DRONE", fmt.ctprintf("COST %d  //  BUILD %.1f S", COMBAT_COST, drone_build_time(.COMBAT)), "Guards orbit, fights garrisons,", "and besieges enemy structures.", SCIFI_BLUE},
	}
	for card, i in cards {
		t := rl.Rectangle{r.x + 20 + f32(i) * (card_w + gap), r.y + 16, card_w, r.height - 32}
		draw_manual_card(t, card.color)
		icon_c := rl.Vector2{t.x + 64, t.y + t.height / 2}
		rl.DrawCircleV(icon_c, 46, rl.Fade(card.color, 0.06))
		rl.DrawRing(icon_c, 44, 45.5, 0, 360, 48, rl.Fade(card.color, 0.35))
		draw_unit_icon(card.kind, icon_c, 84, card.color)
		tx := t.x + 128
		draw_display_text(card.title, {tx, t.y + 22}, 14, card.color)
		draw_display_text(card.stats, {tx, t.y + 46}, 9, SCIFI_LABEL)
		draw_display_text(card.line1, {tx, t.y + 74}, 10, SCIFI_TEXT)
		draw_display_text(card.line2, {tx, t.y + 92}, 10, SCIFI_TEXT)
		draw_unit_icon(card.kind, {tx + 12, t.y + t.height - 22}, 24, SCIFI_RED)
		draw_display_text("HOSTILE VARIANT", {tx + 30, t.y + t.height - 27}, 9, rl.Fade(SCIFI_RED, 0.85))
	}
}

draw_manual_state_legend :: proc(r: rl.Rectangle) {
	rows := [5]struct {
		state: Unit_State,
		label: cstring,
		desc:  cstring,
	}{
		{.MINING, "MINING", "Working a planet and earning minerals."},
		{.IDLE, "IDLE", "Reserve miner waiting in orbit for a free mining slot."},
		{.CONSTRUCTING, "CONSTRUCTING", "Crewing a base, refinery, battery, or ammo build."},
		{.TRANSIT, "TRANSIT", "Flying between planets."},
		{.GUARDING, "GUARDING", "Fighter on station in orbit, ready to engage."},
	}
	for row, i in rows {
		y := r.y + 12 + f32(i) * 30
		cy := y + 15
		tile := rl.Rectangle{r.x + 22, cy - 12, 24, 24}
		draw_unit_icon(row.state == .GUARDING ? .COMBAT : .MINING, {tile.x + 12, cy}, 24, row.state == .GUARDING ? SCIFI_BLUE : SCIFI_AMBER)
		rl.DrawCircleSector({tile.x + tile.width - 2, tile.y + 2}, 3.5, 0, 360, TILE_DOT_SEGMENTS, state_color(row.state))
		draw_display_text(row.label, {r.x + 70, cy - 6}, 11, SCIFI_MINT)
		draw_display_text(row.desc, {r.x + 230, cy - 5.5}, 10, SCIFI_TEXT)
	}
}

manual_fleet :: proc(m: ^Manual_Layout) {
	manual_text(m, "Drones are commanded through the {inspector rosters}. Select a planet to list the drones stationed there, pick their tiles, then right-click a destination in space.")
	manual_keys(m, {
		{"[CLICK TILE]", "Select one drone."},
		{"[DOUBLE CLICK]", "Select every drone of that class in the roster."},
		{"[CTRL] + [CLICK]", "Add a drone to the selection, or remove it."},
		{"[DRAG]", "Box-select tiles inside the inspector."},
		{"[RIGHT CLICK]", "Send the selection to a planet or the |Enemy HQ|."},
		{"[SHIFT] + [1-9]", "Save the selection as a squad."},
		{"[1-9]", "Recall that squad from anywhere on the map."},
	})
	manual_text(m, "Squads appear as small badges under the resource readout. A drone stays in its squad until it is saved into another one or destroyed.")
	manual_heading(m, "PLANET BADGE SHORTCUTS")
	manual_text(m, "Double-click the miner or fighter row of a planet badge to select those drones without opening the planet. The {+} beside a row queues one more of that drone on Earth.")
	manual_heading(m, "ORDERS TO KNOW")
	manual_text(m, "Fighters sent to an enemy world attack on arrival. Miners sent to a planet start mining or join its construction crews. <Mining drones cannot be sent to the Enemy HQ>; they are dropped from that order.")
}

manual_liberation :: proc(m: ^Manual_Layout) {
	manual_text(m, "Occupied planets are held by a |garrison| of fighters, mining drones, and a fortified |command base|. Fighters you send engage automatically as soon as they reach orbit.")
	manual_figure(m, 112, draw_manual_siege_steps)
	manual_text(m, "Combat resolves in rounds: every round one fighter falls on each side. Bring more fighters than the garrison and your survivors grind down the battery and then the base. When the base hits zero the planet is {liberated} and becomes yours.")
	manual_figure(m, manual_table_h(SECTOR_COUNT - 1), draw_manual_garrison_table)
	manual_text(m, "<Protect your miners>: once your fighters at a planet are gone, enemy fighters destroy one mining drone per round. An active orbital defense soaks that damage first.")
	manual_text(m, fmt.tprintf("If enemies hold {{Earth}} and none of your drones are left there, they demolish one command base every %.0f seconds.", BASE_SIEGE_TIME))
}

draw_manual_siege_steps :: proc(r: rl.Rectangle) {
	steps := [3][2]cstring{
		{"DEFENDERS", "Guarding fighters fall first"},
		{"BATTERY", "Then the orbital defense"},
		{"COMMAND BASE", "Zero HP liberates the planet"},
	}
	gap: f32 = 34
	w := (r.width - 40 - 2 * gap) / 3
	for s, i in steps {
		t := rl.Rectangle{r.x + 20 + f32(i) * (w + gap), r.y + 18, w, r.height - 36}
		col := i == 2 ? SCIFI_GREEN : SCIFI_RED
		draw_manual_card(t, col)
		tag := rl.Rectangle{t.x + 14, t.y + t.height / 2 - 16, 32, 32}
		draw_chamfered_panel(tag, 5, rl.Fade(col, 0.18), col)
		num := fmt.ctprintf("%d", i + 1)
		nw := measure_display_text(num, 16)
		draw_display_text(num, {tag.x + (tag.width - nw) / 2, tag.y + 7}, 16, col)
		draw_display_text(s[0], {t.x + 60, t.y + t.height / 2 - 16}, 12, SCIFI_MINT)
		draw_display_text(s[1], {t.x + 60, t.y + t.height / 2 + 4}, 10, SCIFI_MUTED)
		if i < 2 {
			ax := t.x + t.width + gap / 2
			ay := t.y + t.height / 2
			rl.DrawLineEx({ax - 9, ay - 8}, {ax, ay}, 2, SCIFI_GREEN)
			rl.DrawLineEx({ax, ay}, {ax - 9, ay + 8}, 2, SCIFI_GREEN)
			rl.DrawLineEx({ax - 1, ay - 8}, {ax + 8, ay}, 2, rl.Fade(SCIFI_GREEN, 0.45))
			rl.DrawLineEx({ax + 8, ay}, {ax - 1, ay + 8}, 2, rl.Fade(SCIFI_GREEN, 0.45))
		}
	}
}

draw_manual_garrison_table :: proc(r: rl.Rectangle) {
	cols := []f32{0.24, 0.2, 0.2, 0.18, 0.18}
	colors := []rl.Color{SCIFI_MINT, SCIFI_RED, SCIFI_AMBER, SCIFI_TEXT, SCIFI_MUTED}
	draw_manual_table_row(r, 0, cols, {"SECTOR", "FIGHTERS", "MINERS", "BASE HP", "STATUS"}, colors)
	row := 1
	for p in 0..<PLANET_COUNT {
		if p == EARTH { continue }
		status := planet_liberated(p) ? cstring("LIBERATED") : cstring("OCCUPIED")
		draw_manual_table_row(r, row, cols, {planets[p].name, fmt.ctprintf("%d", GARRISON_FIGHTERS[p]), fmt.ctprintf("%d", GARRISON_MINERS[p]), fmt.ctprintf("%d", GARRISON_BASE_HP[p]), status}, planet_liberated(p) ? []rl.Color{SCIFI_GREEN} : colors)
		row += 1
	}
	hq_status := enemy_hq_destroyed() ? cstring("DESTROYED") : cstring("ACTIVE")
	draw_manual_table_row(r, row, cols, {"ENEMY HQ", fmt.ctprintf("%d", GARRISON_FIGHTERS[ENEMY_HOME]), "-", fmt.ctprintf("%d", GARRISON_BASE_HP[ENEMY_HOME]), hq_status}, []rl.Color{SCIFI_RED, SCIFI_RED, SCIFI_MUTED, SCIFI_TEXT, SCIFI_MUTED})
}

manual_outposts :: proc(m: ^Manual_Layout) {
	manual_text(m, "Every liberated planet becomes an {outpost}. Select it to see its status, its structures, and the drones stationed there.")
	manual_figure(m, manual_table_h(3), draw_manual_structure_table)
	manual_keys(m, {
		{"[B]", "Build a refinery at the selected outpost."},
		{"[O]", "Build an orbital defense at the selected planet, Earth included."},
	})
	manual_text(m, "Construction needs a {crew} of mining drones on site. Miners at the planet join automatically, and the build clock only runs while the crew is complete. When the job is done the crew goes back to mining, or moves on to the next project if several are queued.")
	manual_text(m, "Once its refinery is up, the outpost is linked to Earth by a glowing {mineral beam} and starts paying out.")
	manual_text(m, "<Losing a planet's orbital defense also destroys its refinery>, so fortify the worlds that matter most.")
}

draw_manual_structure_table :: proc(r: rl.Rectangle) {
	cols := []f32{0.25, 0.14, 0.12, 0.16, 0.33}
	colors := []rl.Color{SCIFI_MINT, SCIFI_TEXT, SCIFI_TEXT, SCIFI_AMBER, SCIFI_MUTED}
	draw_manual_table_row(r, 0, cols, {"STRUCTURE", "COST", "TIME", "CREW", "EFFECT"}, colors)
	draw_manual_table_row(r, 1, cols, {"REFINERY", "CAP x 10", fmt.ctprintf("%.0f S", REFINERY_BUILD_TIME), fmt.ctprintf("%d MINERS", REFINERY_CONSTRUCT_MINERS), "Unlocks mining income"}, colors)
	draw_manual_table_row(r, 2, cols, {"ORBITAL DEFENSE", fmt.ctprintf("%d", ORBITAL_DEFENSE_COST), fmt.ctprintf("%.0f S", ORBITAL_DEFENSE_BUILD_TIME), fmt.ctprintf("%d MINERS", ORBITAL_DEFENSE_CONSTRUCT_MINERS), "Shoots incoming fighters"}, colors)
	draw_manual_table_row(r, 3, cols, {"AMMO ROUND", fmt.ctprintf("%d", ORBITAL_DEFENSE_AMMO_COST), fmt.ctprintf("%.0f S", ORBITAL_DEFENSE_AMMO_BUILD_TIME), fmt.ctprintf("%d MINER", ORBITAL_DEFENSE_AMMO_CONSTRUCT_MINERS), "Reloads one battery shot"}, colors)
}

manual_defenses :: proc(m: ^Manual_Layout) {
	manual_text(m, fmt.tprintf("An {{orbital defense}} battery guards the planet it is built on, one per planet. Earth starts with a battery loaded with %d rounds.", ORBITAL_DEFENSE_START_AMMO))
	manual_figure(m, 112, draw_manual_battery_stats)
	manual_text(m, fmt.tprintf("The battery only fires at enemy fighters {{approaching}} the planet. Each round destroys up to %d of them; fighters already in orbit are below its arc. Buy rounds with the {{+}} on the planet badge or from the inspector ammo row.", ORBITAL_DEFENSE_KILLS_PER_SHOT))
	manual_text(m, "<An empty battery holds fire> and its badge shows the ammo count in red. While under construction the gun is lowered into its cradle and cannot fire.")
	manual_text(m, "Once your fighters at a planet are gone, |besiegers| turn on the battery. It absorbs their fire to protect your miners, and when it falls the refinery falls with it.")
}

draw_manual_battery_stats :: proc(r: rl.Rectangle) {
	draw_manual_stats(r, {
		{fmt.ctprintf("%d", ORBITAL_DEFENSE_AMMO_MAX), "MAX ROUNDS", SCIFI_GREEN},
		{fmt.ctprintf("%d", ORBITAL_DEFENSE_KILLS_PER_SHOT), "KILLS PER ROUND", SCIFI_GREEN},
		{fmt.ctprintf("%d", ORBITAL_DEFENSE_HP_PER_LEVEL), "HULL POINTS", SCIFI_GREEN},
		{fmt.ctprintf("%d", ORBITAL_DEFENSE_AMMO_COST), "COST PER ROUND", SCIFI_AMBER},
	})
}

manual_attacks :: proc(m: ^Manual_Layout) {
	manual_text(m, "The armada strikes back on two clocks: frequent {raids} from occupied planets and heavy |waves| from the Enemy HQ.")
	manual_figure(m, 176, draw_manual_attack_timeline)
	manual_heading(m, "RAIDS")
	manual_text(m, fmt.tprintf("Every {{%.0f seconds}} each occupied planet can raid its nearest liberated planet with %d fighters. Each of your worlds is targeted by at most one raider at a time, so freeing more planets means more raids at once, until no occupied planets remain.", MINOR_WAVE_INTERVAL, MINOR_WAVE_SIZE))
	manual_heading(m, "WAVES")
	manual_text(m, fmt.tprintf("From the %d minute mark, every %d minutes, the |Enemy HQ| sends a wave at your planet closest to it, once you hold Earth plus at least one other world. Each liberated planet beyond Earth adds {{%d fighters}} to the wave.", WAVE_FIRST_DELAY / 60, WAVE_INTERVAL / 60, WAVE_FIGHTERS_PER_LIBERATED))
	manual_heading(m, "EARLY WARNING")
	manual_text(m, "<Three seconds> before a raid launches, the target planet glows |red| and the source glows <amber>. The red glare stays on while the raiders are in flight and becomes the full battle glow when they arrive.")
}

draw_manual_attack_timeline :: proc(r: rl.Rectangle) {
	span: f32 = 600
	x0 := r.x + 40
	x1 := r.x + r.width - 40
	axis_y := r.y + r.height - 40
	rl.DrawLineEx({x0, axis_y}, {x1, axis_y}, 1.5, rl.Fade(SCIFI_GREEN, 0.6))
	for t: f32 = 0; t <= span; t += 60 {
		x := x0 + (x1 - x0) * t / span
		rl.DrawLineEx({x, axis_y}, {x, axis_y + 6}, 1, rl.Fade(SCIFI_GREEN, 0.6))
		label := fmt.ctprintf("%d:00", int(t) / 60)
		lw := measure_display_text(label, 9)
		draw_display_text(label, {x - lw / 2, axis_y + 12}, 9, SCIFI_MUTED)
	}
	for t: f32 = MINOR_WAVE_INTERVAL; t <= span; t += MINOR_WAVE_INTERVAL {
		x := x0 + (x1 - x0) * t / span
		rl.DrawLineEx({x, axis_y - 30}, {x, axis_y}, 1, rl.Fade(SCIFI_AMBER, 0.5))
		rl.DrawPoly({x, axis_y - 34}, 4, 6, 0, SCIFI_AMBER)
	}
	for t: f32 = WAVE_FIRST_DELAY; t <= span; t += WAVE_INTERVAL {
		x := x0 + (x1 - x0) * t / span
		rl.DrawLineEx({x, axis_y - 62}, {x, axis_y}, 2, rl.Fade(SCIFI_RED, 0.6))
		rl.DrawCircleV({x, axis_y - 68}, 14, rl.Fade(SCIFI_RED, 0.12))
		rl.DrawPoly({x, axis_y - 68}, 3, 9, 90, SCIFI_RED)
	}
	lx := r.x + 24
	ly := r.y + 18
	rl.DrawPoly({lx + 6, ly + 6}, 4, 6, 0, SCIFI_AMBER)
	draw_display_text(fmt.ctprintf("RAID  //  EVERY %.0f S", MINOR_WAVE_INTERVAL), {lx + 20, ly}, 10, SCIFI_AMBER)
	rl.DrawPoly({lx + 236, ly + 6}, 3, 7, 90, SCIFI_RED)
	draw_display_text(fmt.ctprintf("HQ WAVE  //  FROM %d:00, EVERY %d:00", WAVE_FIRST_DELAY / 60, WAVE_INTERVAL / 60), {lx + 252, ly}, 10, SCIFI_RED)
}

manual_fog :: proc(m: ^Manual_Layout) {
	manual_text(m, fmt.tprintf("You only see enemy forces where you have a presence. A sector is lit while any of your drones are near it, while you own a structure there, and for %.0f seconds after your last fighter there falls. Earth is always lit.", COMBAT_VISION_LINGER))
	manual_figure(m, 132, draw_manual_intel_cards)
	manual_text(m, "When a scouted sector goes dark, the inspector keeps a {ghost view} of the last known garrison, marked <STALE>. Treat it as a memory, not a live feed: the enemy may have moved. Sectors you have never seen stay UNSCOUTED.")
	manual_text(m, fmt.tprintf("<Scouting>: a lone fighter that arrives at an enemy world survives %.1f seconds before the garrison can target it, enough to reveal what you are up against.", SCOUT_SURVIVAL))
}

draw_manual_intel_cards :: proc(r: rl.Rectangle) {
	cards := [3]struct {
		title: cstring,
		line1: cstring,
		line2: cstring,
		color: rl.Color,
	}{
		{"LIVE FEED", "Drones or structures on site.", "Exact enemy counts.", SCIFI_GREEN},
		{"STALE INTEL", "Seen before, now dark.", "Frozen last snapshot.", SCIFI_AMBER},
		{"UNSCOUTED", "Never visited.", "Nothing is known.", SCIFI_MUTED},
	}
	gap: f32 = 14
	w := (r.width - 40 - 2 * gap) / 3
	for card, i in cards {
		t := rl.Rectangle{r.x + 20 + f32(i) * (w + gap), r.y + 16, w, r.height - 32}
		draw_manual_card(t, card.color)
		rl.DrawCircleV({t.x + 20, t.y + 25}, 4, card.color)
		if i == 0 { rl.DrawCircleV({t.x + 20, t.y + 25}, 8, rl.Fade(card.color, 0.2)) }
		draw_display_text(card.title, {t.x + 34, t.y + 18}, 12, card.color)
		draw_display_text(card.line1, {t.x + 16, t.y + 50}, 10, SCIFI_TEXT)
		draw_display_text(card.line2, {t.x + 16, t.y + 68}, 10, SCIFI_MUTED)
	}
}

manual_citadel :: proc(m: ^Manual_Layout) {
	manual_text(m, "The |Enemy HQ| is the heart of the armada: a fortress in deep space, far beyond Neptune. It is not a planet and cannot be mined, but it must fall for you to win. Click it to inspect its garrison, battery, and hull.")
	manual_figure(m, 112, draw_manual_citadel_stats)
	manual_text(m, fmt.tprintf("Its battery is Level 10: it needs no ammo and destroys up to %d fighters per wave. Combat at the citadel runs five times faster than at a planet. Break the garrison, breach the battery, then the core.", 10 * ORBITAL_DEFENSE_KILLS_PER_LEVEL))
	manual_text(m, fmt.tprintf("<While you press the assault> and its garrison is below %d, the HQ spends its waves rebuilding defenders instead of attacking your planets. Keep the pressure on.", ENEMY_HQ_GARRISON))
	manual_text(m, "Only fighters can be sent to the citadel. Mass them first: reinforcements arriving one squad at a time are cut down by the battery.")
}

draw_manual_citadel_stats :: proc(r: rl.Rectangle) {
	draw_manual_stats(r, {
		{fmt.ctprintf("%d", ENEMY_HQ_GARRISON), "GARRISON FIGHTERS", SCIFI_RED},
		{"LVL 10", "ORBITAL BATTERY", SCIFI_RED},
		{fmt.ctprintf("%d", 10 * ORBITAL_DEFENSE_HP_PER_LEVEL), "BATTERY HP", SCIFI_RED},
		{fmt.ctprintf("%d", ENEMY_HQ_BASE_HP), "CORE HP", SCIFI_RED},
	})
}

manual_reference :: proc(m: ^Manual_Layout) {
	manual_heading(m, "CAMERA")
	manual_keys(m, {
		{"[W] [A] [S] [D] / [ARROWS]", "Pan the view"},
		{"[Q] [E] / [WHEEL]", "Zoom in and out"},
		{"[SPACE]", "Select Earth, again to center on it"},
		{"[F11]", "Toggle fullscreen"},
	})
	manual_heading(m, "SELECTION AND ORDERS")
	manual_keys(m, {
		{"[CLICK]", "Select a planet, the HQ, or a drone tile"},
		{"[DOUBLE CLICK]", "Select every drone of that class"},
		{"[CTRL] + [CLICK]", "Toggle a drone in the selection"},
		{"[DRAG]", "Box-select inspector tiles"},
		{"[RIGHT CLICK]", "Send the selection, or set the rally point"},
		{"[SHIFT] + [1-9]", "Save squad"},
		{"[1-9]", "Recall squad"},
	})
	manual_heading(m, "EARTH PRODUCTION")
	manual_keys(m, {
		{"[M] / [C]", "Queue a miner or a fighter"},
		{"[N] / [X]", "Queue 5 miners or 5 fighters"},
		{"[U]", "Drone build-speed upgrade"},
		{"[T]", "Toggle the autobuilder"},
		{"[ESC]", "Cancel the newest build"},
	})
	manual_heading(m, "OUTPOSTS")
	manual_keys(m, {
		{"[B]", "Build a refinery"},
		{"[O]", "Build an orbital defense"},
	})
	manual_heading(m, "SYSTEM")
	manual_keys(m, {
		{"[P] / [F10]", "Pause menu"},
		{"[F5]", "Quick-save"},
		{"[CTRL] + [N]", "Debug: launch an enemy wave now"},
	})
}
