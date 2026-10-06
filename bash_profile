alias bash_profile="vi ~/.bash_profile; source ~/.bash_profile"

export BASH_SCRIPTS="$HOME/Documents/Projects/bash_scripts"

# Homebrew first, so tools it installs (pyenv) are on PATH
eval "$(/opt/homebrew/bin/brew shellenv)"

# Setup Python
if command -v pyenv >/dev/null; then
     export PYENV_ROOT="$HOME/.pyenv"
     eval "$(pyenv init --path)"
     eval "$(pyenv init -)"
     eval "$(pyenv virtualenv-init -)"
fi
#-------------

# Unity CLI
[ -f "$HOME/.unity/env" ] && . "$HOME/.unity/env"

function RefreshScripts(){
     source "$BASH_SCRIPTS/GitCommands.sh"
     source "$BASH_SCRIPTS/LogCommits.sh"
     source "$BASH_SCRIPTS/AndroidUtilities.sh"
     source "$BASH_SCRIPTS/WindowLayouts.sh"
}
RefreshScripts

AddToPath "$BASH_SCRIPTS"
DedupePath
