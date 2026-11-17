source "$BASH_SCRIPTS/Constants.sh";

function ClaudeResumeWork(){
	local model="sonnet" feature="";
	while [ $# -gt 0 ]; do
          case "$1" in
               -m|--model) model=$2; shift ;;
               -f|--feature) feature=$2; shift ;;
               *) LogError "Unknown option: $1"; return 1 ;;
          esac
          shift;
    done

    if [ -z "$model" ]; then
    	model="sonnet";
    fi

    if [ -z "$feature" ]; then
    	LogError "Invalid feature";
    	return 1;
    fi

    claude --model "$model" "\"/resume-work $GameProgressSaveSlim\""
}
