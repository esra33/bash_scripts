#-------------------------------------------------------
# Usage: AddToPath <directory>
#   Adds a directory to the end of PATH, unless it is already there.
#   Example: AddToPath "$HOME/bin"
function AddToPath() {
	case ":$PATH:" in
		*":$1:"*) ;;
		*) export PATH="$PATH:$1" ;;
	esac
}

# Usage: DedupePath
#   Removes duplicate PATH entries, keeping the first occurrence of each.
#   Runs automatically at the end of bash_profile.
function DedupePath() {
	local dir newPath=""
	local IFS=":"
	for dir in $PATH; do
		case ":$newPath:" in
			*":$dir:"*) ;;
			*) newPath="${newPath:+$newPath:}$dir" ;;
		esac
	done
	export PATH="$newPath"
}

# Internal: LatestVersionIn <directory>
#   Prints the newest version folder inside a directory (e.g. build-tools -> 36.0.0).
function LatestVersionIn() {
	ls "$1" 2>/dev/null | sort -V | tail -n 1
}

#-------------------------------------------------------
# Android
export ANDROID_SDK="$HOME/Library/Android/sdk"
export ANDROID_SDK_ROOT="$ANDROID_SDK"
export ANDROID_HOME="$ANDROID_SDK"
export ANDROID_PLATFORM_TOOLS="$ANDROID_SDK/platform-tools"
export ANDROID_CMDLINE_TOOLS="$ANDROID_SDK/cmdline-tools/latest/bin"
export ANDROID_BUILD_TOOLS="$ANDROID_SDK/build-tools/$(LatestVersionIn "$ANDROID_SDK/build-tools")"
export ANDROID_NDK_ROOT="$ANDROID_SDK/ndk/$(LatestVersionIn "$ANDROID_SDK/ndk")"

AddToPath "$ANDROID_PLATFORM_TOOLS"
AddToPath "$ANDROID_CMDLINE_TOOLS"
AddToPath "$ANDROID_BUILD_TOOLS"

#-------------------------------------------------------
# Unity (newest editor installed through Unity Hub)
export UNITY_HOME="/Applications/Unity/Hub/Editor/$(LatestVersionIn /Applications/Unity/Hub/Editor)/Unity.app"
export UNITY_CONTENTS_HOME="$UNITY_HOME/Contents/MacOS/Unity"

#-------------------------------------------------------
# Color Definitions
export NO_COLOR='\033[0m'
export RED_COLOR='\033[0;31m'
export YELLOW_COLOR='\033[0;33m'
export BLUE_COLOR='\033[0;34m'

# More color code on https://stackoverflow.com/questions/5947742/how-to-change-the-output-color-of-echo-in-linux

# Internal: LogMessage <message>
#   Prints a message inside a yellow banner.
function LogMessage() {
	echo -e "$YELLOW_COLOR ";
	echo "------------------------";
	echo "$1";
	echo "------------------------";
	echo -e "$NO_COLOR ";
}

# Internal: LogError <message>
#   Prints a message inside a red banner.
function LogError() {
	echo -e "$RED_COLOR ";
	echo "------------------------";
	echo "$1";
	echo "------------------------";
	echo -e "$NO_COLOR ";
}

#-------------------------------------------------------
# Usage: ARESHelp [command | --all]
#   Lists the available commands, or shows the full help of one command.
#   The help is read from the "Usage:" comments above each function.
#   --all           Also list the internal helper functions
#   Example: ARESHelp InstallAndStartAPK
function ARESHelp() {
	local mode="overview" target="";
	case "$1" in
		"") ;;
		--all) mode="all" ;;
		-*) LogError "Unknown option: $1 (see: ARESHelp ARESHelp)"; return 1 ;;
		*) mode="detail"; target=$1 ;;
	esac

	local sections=("Git|GitCommands.sh" "Commit history|LogCommits.sh" "Android|AndroidUtilities.sh" "Window layouts|WindowLayouts.sh" "Shell|Constants.sh");

	if [ "$mode" != "detail" ]; then
		echo "";
		echo "ARES shell tools";
		echo "Run 'ARESHelp <command>' for details, or 'ARESHelp --all' to include internal helpers.";
	fi

	local section title file chunk output="";
	for section in "${sections[@]}"; do
		title=${section%%|*};
		file=${section#*|};
		chunk=$(awk -v mode="$mode" -v target="$target" -v title="$title" -v file="$file" -v width=40 -v blue="$BLUE_COLOR" -v none="$NO_COLOR" '
			# Prints the help of the function documented in block[start..n]
			function emit(name,    usage, desc, i, pos) {
				if (mode == "detail") {
					if (tolower(name) != tolower(target)) return;
					for (i = start; i <= n; i++) print block[i];
					print "  Defined in " file;
					return;
				}
				if (kind == "internal" && mode != "all") return;

				usage = block[start];
				sub(/^(Usage|Internal): /, "", usage);
				desc = block[start + 1];
				sub(/^ +/, "", desc);

				# Long usages hide their modifiers behind [...]
				if (length(usage) > width && index(usage, " [-") > 0) {
					while ((pos = index(usage, " [-")) > 0) {
						usage = substr(usage, 1, pos - 1) substr(usage, index(substr(usage, pos + 1), "]") + pos + 1);
					}
					usage = usage " [...]";
				}

				line = (length(usage) > width) ? sprintf("  %s\n  %-" width "s %s", usage, "", desc) : sprintf("  %-" width "s %s", usage, desc);
				if (kind == "internal") internal[++internalCount] = line;
				else public[++publicCount] = line;
			}

			/^function / { name = $2; sub(/\(.*/, "", name); if (kind != "") emit(name); n = 0; kind = ""; next }
			/^#-+$/ { n = 0; kind = ""; next }
			/^#/ {
				line = substr($0, 2); sub(/^ /, "", line);
				block[++n] = line;
				if (kind == "" && line ~ /^Usage: /) { kind = "public"; start = n }
				if (kind == "" && line ~ /^Internal: /) { kind = "internal"; start = n }
				next;
			}
			{ n = 0; kind = "" }

			END {
				if (mode == "detail" || publicCount + internalCount == 0) exit;
				printf "\n%s%s%s\n", blue, title, none;
				for (i = 1; i <= publicCount; i++) print public[i];
				if (internalCount > 0) print "  -- internal --";
				for (i = 1; i <= internalCount; i++) print internal[i];
			}
		' "$BASH_SCRIPTS/$file");
		if [ -n "$chunk" ]; then
			output+="$chunk"$'\n';
		fi
	done

	if [ -z "$output" ]; then
		LogError "Unknown command: $target (run ARESHelp to see all commands)";
		return 1;
	fi

	printf '%s' "$output";
}
