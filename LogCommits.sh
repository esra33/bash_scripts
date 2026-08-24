#-----------HOW TO RUN EXAMPLE---------------
# $ . ~/Desktop/BashScripts/LogCommits.sh; ResetFilesToCommit ddbf0a35a1f094f0c5377b5488c020654f4b95bc~1 /Users/andresramirex/Desktop/JavaFilesToReset 
#--------------------------------------------

source $BASH_SCRIPTS/GitCommands.sh;

function LogValuesOnFile() {
	
	echo "Logging Values On File";
	local logValue;	

	while IFS= read -r line
	do
	  echo "----------";
	  logValue=$(git log --format=%B -n 1 "$line");
	  echo "$logValue --> $line";
	done < "$1"
}

function ApplyStash() {
	git stash apply "$1";
	git status;
}

# finds headles commits and copies (awk?) to the clipboard
function FindHeadlessCommits() {
	git fsck --no-reflog | awk '/dangling commit/ {print $3}';
}

# Iterate through the lines in a file and executes the git action
function ResetFilesToCommit() {
	
	echo "This is a test";

	while IFS= read -r line
	do
	  echo "$line";
	  echo "----------";
	  git checkout "$1" -- "$line";
	done < "$2"
}

# Finds all children for the specified commit
function FindChildrenForCommit() {
	# For the current (or specified) commit-ish, get the all children, print the first child 
	children = "!bash -c 'c=${1:-HEAD}; set -- $(git rev-list --all --not \"$c\"^@ --children | grep $(git rev-parse \"$c\") ); shift; echo $1' -"
}
