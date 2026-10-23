#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 1 ]; then
	echo "usage: capture.sh <scenario.odin> [out_dir]" >&2
	exit 2
fi

scenario="$1"
skill_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(git -C "$skill_dir" rev-parse --show-toplevel)"
out="${2:-${TMPDIR:-${TMP:-/tmp}}/ui-capture}"

native() {
	if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi
}

[ -f "$scenario" ] || { echo "scenario not found: $scenario" >&2; exit 2; }
grep -q '^capture_scenario :: proc' "$scenario" || { echo "scenario must define capture_scenario :: proc(step: int) -> (done: bool)" >&2; exit 2; }

main_src="$repo/src/main.odin"
scale_src="$repo/src/ui_scale.odin"
engine_dst="$repo/src/zz_capture.odin"
scenario_dst="$repo/src/zz_capture_scenario.odin"
backup="$(mktemp -d)"
exe_dir="$repo/bin/capture"
exe="$exe_dir/ui-capture"
if [ "${OS:-}" = "Windows_NT" ]; then exe="$exe.exe"; fi

cp "$main_src" "$backup/main.odin"
cp "$scale_src" "$backup/ui_scale.odin"

restore() {
	cp "$backup/main.odin" "$main_src"
	cp "$backup/ui_scale.odin" "$scale_src"
	rm -f "$engine_dst" "$scenario_dst"
	rm -rf "$backup"
}
trap restore EXIT

cp "$skill_dir/capture.odin" "$engine_dst"
cp "$scenario" "$scenario_dst"

sed -i 's/^\(\t*\)rl\.EndDrawing()\(\r\?\)$/\1capture_tick()\2\n&/' "$main_src"
sed -i 's/^ui_mouse :: proc() -> rl\.Vector2 {\(\r\?\)$/&\n\tif capture_mouse_override { return capture_mouse_pos }\1/' "$scale_src"
sed -i 's/^ui_mouse_delta :: proc() -> rl\.Vector2 {\(\r\?\)$/&\n\tif capture_mouse_override { return capture_mouse_delta }\1/' "$scale_src"

check_hook() {
	local n
	n="$(grep -c "$1" "$2" || true)"
	if [ "$n" != "1" ]; then
		echo "hook '$1' matched $n times in $2; the anchor line changed, update capture.sh" >&2
		exit 3
	fi
}
check_hook 'capture_tick()' "$main_src"
check_hook 'return capture_mouse_pos' "$scale_src"
check_hook 'return capture_mouse_delta' "$scale_src"

mkdir -p "$exe_dir" "$out"
rm -f "$out"/*.png "$out/run.log"
odin build "$repo/src" -out:"$exe" -debug

set +e
(cd "$repo" && CAPTURE_DIR="$(native "$out")" timeout 300 "$exe" >"$out/run.log" 2>&1)
status=$?
set -e

grep -E '^(CAPTURE_|ERROR|WARNING)' "$out/run.log" || true
if ! grep -q '^CAPTURE_DONE' "$out/run.log"; then
	echo "capture run did not finish (exit $status); last log lines:" >&2
	tail -n 15 "$out/run.log" >&2
	exit 4
fi
echo "OUT_DIR $(native "$out")"
