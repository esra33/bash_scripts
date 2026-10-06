source "$BASH_SCRIPTS/Constants.sh";

# Saved layouts live here, one JSON file per profile.
WINDOW_LAYOUTS_DIR="${WINDOW_LAYOUTS_DIR:-$HOME/.window_layouts}";
WINDOW_LAYOUT_HELPER_SRC="$BASH_SCRIPTS/WindowLayoutHelper.swift";
WINDOW_LAYOUT_HELPER_BIN="$HOME/.cache/window_layouts/WindowLayoutHelper";

#-------------------------------------------------------
# Internal helpers

# Internal: WindowLayoutHelper <args...>
#   Runs the Swift helper, compiling it first if the source is newer than the binary.
function WindowLayoutHelper() {
	if [ ! -x "$WINDOW_LAYOUT_HELPER_BIN" ] || [ "$WINDOW_LAYOUT_HELPER_SRC" -nt "$WINDOW_LAYOUT_HELPER_BIN" ]; then
		echo "Compiling window layout helper..." >&2;
		mkdir -p "$(dirname "$WINDOW_LAYOUT_HELPER_BIN")";
		# The default SDK can be newer than the installed compiler, so fall back to older SDKs.
		local sdk compiled="";
		for sdk in "" $(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX[0-9]*.sdk 2>/dev/null | sort -rV); do
			if swiftc -O -swift-version 5 ${sdk:+-sdk "$sdk"} "$WINDOW_LAYOUT_HELPER_SRC" -o "$WINDOW_LAYOUT_HELPER_BIN" 2>/dev/null; then
				compiled=1;
				break;
			fi
		done
		if [ -z "$compiled" ]; then
			swiftc -O -swift-version 5 "$WINDOW_LAYOUT_HELPER_SRC" -o "$WINDOW_LAYOUT_HELPER_BIN" >&2;
			LogError "Failed to compile $WINDOW_LAYOUT_HELPER_SRC" >&2;
			return 1;
		fi
	fi
	"$WINDOW_LAYOUT_HELPER_BIN" "$@";
}

# Internal: WindowLayoutUsage <function name>
#   Prints the "# Usage:" comment block written above a function in this file.
function WindowLayoutUsage() {
	awk -v name="$1" '
		$0 ~ "^# Usage: " name "( |$)" { printing = 1 }
		printing && /^function/ { exit }
		printing { sub(/^# ?/, ""); print }
	' "$BASH_SCRIPTS/WindowLayouts.sh";
}

# Internal: IsHelpFlag <arg>
#   Succeeds when the argument is -h or --help.
function IsHelpFlag() {
	[ "$1" = "-h" ] || [ "$1" = "--help" ];
}

# Internal: WindowLayoutPath <name>
#   Prints the JSON path for a profile name, failing if the name is empty.
function WindowLayoutPath() {
	if [ -z "$1" ]; then
		LogError "Missing layout name" >&2;
		return 1;
	fi
	echo "$WINDOW_LAYOUTS_DIR/${1%.json}.json";
}

#-------------------------------------------------------
# Layout commands

# Usage: SaveWindowLayout <name>
#   Saves every app window's display, desktop, position and size to a JSON profile,
#   including windows on desktops you are not currently looking at.
#   Saving with an existing name overwrites that profile.
#
#   Profiles are stored in $WINDOW_LAYOUTS_DIR (default ~/.window_layouts).
#
#   Examples:
#     SaveWindowLayout work
#     SaveWindowLayout "deep focus"
function SaveWindowLayout() {
	if IsHelpFlag "$1"; then WindowLayoutUsage "${FUNCNAME[0]}"; return 0; fi
	local file tmp;
	file=$(WindowLayoutPath "$1") || return 1;
	mkdir -p "$WINDOW_LAYOUTS_DIR";

	tmp=$(mktemp);
	if ! WindowLayoutHelper save > "$tmp"; then
		rm -f "$tmp";
		LogError "Could not capture the window layout";
		return 1;
	fi
	jq --arg name "${1%.json}" '. + {name: $name}' "$tmp" > "$file";
	rm -f "$tmp";

	echo "Saved $(jq '.windows | length' "$file") windows on $(jq '.displays | length' "$file") display(s) to $file";
}

# Usage: LoadWindowLayout <name> [--dry-run] [--launch]
#   Moves and resizes windows to match a saved profile.
#
#   Options:
#     --dry-run   Print where each window would go without moving anything
#     --launch    Open apps from the profile that are not running, then place them
#
#   Windows on the wrong desktop are moved with yabai when it is installed with its
#   scripting addition; otherwise they are listed so you can drag them over.
#
#   Examples:
#     LoadWindowLayout work
#     LoadWindowLayout work --launch
#     LoadWindowLayout work --dry-run
function LoadWindowLayout() {
	if IsHelpFlag "$1"; then WindowLayoutUsage "${FUNCNAME[0]}"; return 0; fi
	local file;
	file=$(WindowLayoutPath "$1") || return 1;
	if [ ! -f "$file" ]; then
		LogError "No layout named $1 (see ListWindowLayouts)";
		return 1;
	fi
	shift;
	WindowLayoutHelper apply "$file" "$@";
}

# Usage: ListWindowLayouts
#   Lists saved profiles with their window count, displays and save date.
#
#   Example:
#     ListWindowLayouts
function ListWindowLayouts() {
	if IsHelpFlag "$1"; then WindowLayoutUsage "${FUNCNAME[0]}"; return 0; fi
	local file;
	shopt -s nullglob;
	local files=("$WINDOW_LAYOUTS_DIR"/*.json);
	shopt -u nullglob;

	if [ ${#files[@]} -eq 0 ]; then
		echo "No saved layouts in $WINDOW_LAYOUTS_DIR";
		return 0;
	fi
	for file in "${files[@]}"; do
		jq -r --arg name "$(basename "$file" .json)" \
			'"\($name)\t\(.windows | length) windows\t\([.displays[].name] | join(", "))\t\(.savedAt)"' "$file";
	done | column -t -s $'\t';
}

# Usage: ShowWindowLayout <name>
#   Prints the windows in a profile grouped by display and desktop, with each
#   window's position and size relative to its display.
#
#   Example:
#     ShowWindowLayout work
function ShowWindowLayout() {
	if IsHelpFlag "$1"; then WindowLayoutUsage "${FUNCNAME[0]}"; return 0; fi
	local file;
	file=$(WindowLayoutPath "$1") || return 1;
	if [ ! -f "$file" ]; then
		LogError "No layout named $1";
		return 1;
	fi
	jq -r '
		(.displays | map({key: .uuid, value: .name}) | from_entries) as $names
		| .windows
		| group_by([.display, (.desktop // 0)])[]
		| "\n\($names[.[0].display] // "Unknown display") - " + (if .[0].desktop then "desktop \(.[0].desktop)" else "all desktops" end),
		  (.[] | "  \(.app): \(if .title == "" then "(untitled)" else .title end)  [\(.relativeFrame.x|floor),\(.relativeFrame.y|floor) \(.relativeFrame.w|floor)x\(.relativeFrame.h|floor)]\(if .fullscreen then " fullscreen" else "" end)\(if .minimized then " minimized" else "" end)")
	' "$file";
}

# Usage: DeleteWindowLayout <name>
#   Permanently deletes a saved profile.
#
#   Example:
#     DeleteWindowLayout work
function DeleteWindowLayout() {
	if IsHelpFlag "$1"; then WindowLayoutUsage "${FUNCNAME[0]}"; return 0; fi
	local file;
	file=$(WindowLayoutPath "$1") || return 1;
	if [ ! -f "$file" ]; then
		LogError "No layout named $1";
		return 1;
	fi
	rm "$file" && echo "Deleted $file";
}
