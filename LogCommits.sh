# Internal: ParseVerboseFlag <parameters...>
#   Reads the -v flag. Sets: verbose (true | false) and args (the remaining parameters).
function ParseVerboseFlag() {
	verbose=false;
	args=();

	local arg;
	for arg in "$@"; do
		if [ "$arg" == "-v" ]; then
			verbose=true;
		else
			args+=("$arg");
		fi
	done
}

# Internal: ShowCommits <verbose: true | false> [no-walk mode]
#   Prints the commits whose hashes are read from input, one line each or full messages.
function ShowCommits() {
	local format="%h  %ad  %s";
	if [ "$1" == true ]; then
		format="----------%n%H  %ad%n%n%B";
	fi

	git log --stdin --no-walk"${2:+=$2}" --date=format:'%Y-%m-%d %H:%M' --format="$format";
}

# Usage: LogValuesOnFile [-v] <hashes file>
#   Prints the commits listed in a file (one hash per line), in file order.
#   -v              Show the full commit messages
#   Example: LogValuesOnFile ~/Desktop/hashes.txt
function LogValuesOnFile() {
	local verbose args;
	ParseVerboseFlag "$@";

	if [ ! -f "${args[0]}" ]; then
		echo "Usage: LogValuesOnFile [-v] <hashes file>";
		return 1;
	fi

	grep -v '^[[:space:]]*$' "${args[0]}" | ShowCommits "$verbose" unsorted;
}

# Usage: ApplyStash <stash | commit>
#   Applies a stash, or a recovered stash commit, and shows the status.
#   Example: ApplyStash a1b2c3d
function ApplyStash() {
	git stash apply "$1";
	git status;
}

# Usage: FindHeadlessCommits [-v]
#   Finds commits no branch points to anymore (lost resets, dropped stashes).
#   Lists them newest first and saves the list to a file in the temp folder, then opens it.
#   -v              Show the full commit messages
#   Example: FindHeadlessCommits -v
function FindHeadlessCommits() {
	local verbose args;
	ParseVerboseFlag "$@";

	local repo;
	repo=$(git rev-parse --show-toplevel) || return 1;

	echo "Searching for headless commits...";
	local output="${TMPDIR:-/tmp}/HeadlessCommits_$(basename "$repo").txt";
	git fsck --no-reflog 2>/dev/null | awk '/dangling commit/ { print $3 }' | ShowCommits "$verbose" > "$output";

	if [ ! -s "$output" ]; then
		echo "No headless commits found";
		return 0;
	fi

	cat "$output";
	open -t "$output";
}

# Usage: ResetFilesToCommit <commit> <paths file>
#   Resets the files listed in a file (one path per line) to their version at a commit.
#   Example: ResetFilesToCommit a1b2c3d~1 ~/Desktop/FilesToReset.txt
function ResetFilesToCommit() {
	if [ -z "$1" ] || [ ! -f "$2" ]; then
		echo "Usage: ResetFilesToCommit <commit> <paths file>";
		return 1;
	fi

	grep -v '^[[:space:]]*$' "$2" | git restore --source="$1" --staged --worktree --pathspec-from-file=- && git status --short;
}

# Usage: FindChildrenForCommit [-v] [commit]
#   Lists the commits whose parent is the given commit (default: the current one).
#   -v              Show the full commit messages
#   Example: FindChildrenForCommit a1b2c3d
function FindChildrenForCommit() {
	local verbose args;
	ParseVerboseFlag "$@";

	local commit;
	commit=$(git rev-parse --verify --quiet "${args[0]:-HEAD}^{commit}");
	if [ -z "$commit" ]; then
		echo "Unknown commit: ${args[0]}";
		return 1;
	fi

	local children;
	children=$(git rev-list --all --children | awk -v c="$commit" '$1 == c { for (i = 2; i <= NF; i++) print $i }');
	if [ -z "$children" ]; then
		echo "No children found";
		return 0;
	fi

	echo "$children" | ShowCommits "$verbose";
}
