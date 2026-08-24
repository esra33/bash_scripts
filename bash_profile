alias bash_profile="vi ~/.bash_profile;source ~/.bash_profile;RefreshScripts;"

export BASH_SCRIPTS='/Users/andresramirex/Desktop/BashScripts'
export BREW='/opt/homebrew/bin'

# Setup Python
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init --path)"
eval "$(pyenv init -)"
eval "$(pyenv virtualenv-init -)"
#-------------

export PATH=$PATH:$BASH_SCRIPTS:$BREW

function RefreshScripts(){
source $BASH_SCRIPTS/GitCommands.sh
source $BASH_SCRIPTS/LogCommits.sh
source $BASH_SCRIPTS/AndroidUtilities.sh
}
eval "$(/opt/homebrew/bin/brew shellenv)"
