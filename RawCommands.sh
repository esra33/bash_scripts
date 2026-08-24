alias bash_profile="vi ~/.bash_profile;source ~/.bash_profile"

export JAVA_HOME=`/usr/libexec/java_home`
#export JAVA_HOME=`/usr/libexec/java_home -v 1.8.0_151`
export PATH=$PATH:$JAVA_HOME

export USER_HOME=/Users/andresramirex/

export ANDROID_SDK=$USER_HOME/Library/Android/sdk
export ANDROID_SDK_ROOT=$ANDROID_SDK
export ANDROID_PLATAFORM_TOOLS=$ANDROID_SDK/platform-tools
export ANDROID_TOOLS=$ANDROID_SDK/tools
export ANDROID_NDK_ROOT=$ANDROID_SDK/ndk-bundle
export ANDROID_BUILD_TOOLS=$ANDROID_SDK/build-tools/28.0.3

export UNITY_HOME=/Applications/Unity/Hub/Editor/2018.3.14f1/Unity.app
export UNITY_CONTENTS_HOME=$UNITY_HOME/Contents/MacOS/Unity

export PATH=$PATH:$ANDROID_SDK:$ANDROID_PLATAFORM_TOOLS:$ANDROID_TOOLS

export EMOJI=$USER_HOME/Documents/Projects/Emoji-Blitz
export BLACK_FOREST=$USER_HOME/Documents/Projects/BlackForestGame/SnowmanGame
export BUILD_OUTPUT=$USER_HOME/Desktop/Builds

export CUSTOM_SCRIPTS=/Users/andresramirex/Desktop/BashScripts
export PATH=$PATH:$CUSTOM_SCRIPTS

export PS1="\u@\h \[\033[32m\]\w\[\033[33m\]\$(parse_git_branch)\[\033[00m\] $ "

export VAULT_ADDR=http://10.12.42.6

#-------------------------------------------------------
# Color Definitions
export NO_COLOR='\033[0m'
export RED_COLOR='\033[0;31m'
export YELLOW_COLOR='\033[0;33m'
export BLUE_COLOR='\033[0;34m'

# More color code on https://stackoverflow.com/questions/5947742/how-to-change-the-output-color-of-echo-in-linux

#-------------------------------------------------------
# Provides a quick list of implemented functions and parameters
function ARESHelp(){
echo "";
echo "bash_profile";
echo "ResetGitAccount";
echo "SwitchToBranch '$'1: Target branch";
echo "UpdateFromBranch '$'1: Target branch";
echo "ResetCommit '$'1': Number of commits to reset back, note they must not be pushed commits, leave empty for all"
echo "PushBranch"
echo "RunUnityMethod: '$'1: Class.MethodName '$'2: target platform <android, iOS>"
echo "ClearBranch"
echo "MakeBranch"
echo "";
}

#-------------------------------------------------------
function parse_git_branch(){
     git branch 2> /dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/ (\1)/'
}

#-------------------------------------------------------
function ResetGitAccount(){

git config --global credential.helper osxkeychain;
git pull;
}

#-------------------------------------------------------
function ClearBranch(){
local isClean=$(git status | grep clean);
if [ "$isClean" == "" ]; then
local date=$(date "%d/%m/%y +%H:%M:%S");
local branch=$(git branch | grep '*' | sed -e 's/^* //');
git add *;
git stash push -m "[ClearBranch] - [$branch] - [$date]";
git stash drop 0;
fi
}

#-------------------------------------------------------
# Pushes the current git branch to the origin
function PushBranch(){
git pull;
local branch_name=$(git branch | grep '*' | sed -e 's/^* //');
echo "Pushing to origin $branch_name";
git push origin "$branch_name";
echo "Push Completed"
}

#-------------------------------------------------------
# Switches to a new branch specified as a parameter
function SwitchToBranch(){

local branch_name=$(git symbolic-ref --short -q HEAD | sed -e 's,.*/\(.*\),\1,')
local isClean=$(git status | grep clean);
local branch=$(git branch | grep '*' | sed -e 's/^* //');
local date=$(date "%d/%m/%y +%H:%M:%S");

git status;
echo "";

if [ "$branch_name" != "$1" ]; then

if [ "$isClean" == "" ]; then
echo -e "$YELLOW_COLOR------------------------";
echo "Stashing changes";
echo -e "------------------------$NO_COLOR ";
git add *;
git stash push -m "[SwitchToBranch] - [$branch] --> [$1] - [$date]";
fi

echo -e "$YELLOW_COLOR------------------------";
echo "Resetting current branch";
echo -e "------------------------$NO_COLOR ";

git reset --hard HEAD;

echo -e "$YELLOW_COLOR------------------------";
echo "Changing branches";
echo -e "------------------------$NO_COLOR ";

git checkout "$1";
git pull origin "$1";

fi

}

#-------------------------------------------------------
# Updates the current branch from a base branch
# The base branch has to be specified as a parameter
function UpdateFromBranch(){

local branch_name=$(git branch | grep '*' | sed -e 's/^* //')
local isClean=$(git status | grep clean);

git status;
echo "";

if [ "$branch_name" == "$1" ];
then
echo -e "$RED_COLOR invalid branch $NO_COLOR ";
else

if [ "$isClean" == "" ]; then
echo -e "$YELLOW_COLOR ";
echo "------------------------";
echo "Stashing changes";
echo "------------------------";
echo -e "$NO_COLOR ";

git add *;
git stash save;
fi

git reset --hard HEAD;

echo -e "$YELLOW_COLOR ";
echo "------------------------";
echo "Pulling Current";
echo "------------------------";
echo -e "$NO_COLOR ";

git pull origin "$branch_name";

echo -e "$YELLOW_COLOR ";
echo "------------------------";
echo "Checking out $1"
echo "------------------------";
echo -e "$NO_COLOR ";

git checkout "$1";
git pull origin "$1";

echo -e "$YELLOW_COLOR ";
echo "------------------------";
echo "Returning to original branch";
echo "------------------------";
echo -e "$NO_COLOR ";

git checkout "$branch_name";

echo -e "$YELLOW_COLOR ";
echo "------------------------";
echo "Merging...";

echo "------------------------";
echo -e "$NO_COLOR ";

git merge "$1";

if [ "$isClean" == "" ]; then

echo -e "$YELLOW_COLOR ";
echo "------------------------";
echo "Applying stashed changes"
echo "------------------------";
echo -e "$NO_COLOR ";

git stash pop;
fi

echo -e "$YELLOW_COLOR ";
echo "------------------------";
echo "Checking for conflicts"
echo "------------------------";
echo -e "$NO_COLOR ";

local hasConflicts=$(git status | grep 'CONFLICT\|both modified\|conflict\|both merged');
if [ "$hasConflicts" == "" ]; then
echo -e "$BLUE_COLOR All Clear";

echo -e "$YELLOW_COLOR ";
echo "------------------------";
echo "Unstaging Stash"
echo "------------------------";
echo -e "$NO_COLOR ";

git reset;

else
echo -e "$RED_COLOR $hasConflicts";
fi

fi

echo -e "$NO_COLOR";

}

#------------------------------------------------------------------
# Rolls back a set number of unpushed commits in the current branch
function ResetCommit(){

echo "Resetting back $1 commits";
git reset --soft HEAD~"$1";

}

#------------------------------------------------------------------
# Makes a new branch
function MakeBranch(){
git checkout -b "$1";
PushBranch;
git branch --set-upstream-to=origin/"$1";
}

#------------------------------------------------------------------
# Runs a unity method in batch mode
function RunUnityMethod(){

local path=$(pwd);
#$UNITY_CONTENTS_HOME -quit -batchmode -nographics -projectPath "$path" -executeMethod "$1" -buildTarget "$2";
echo "Not Working";
}

function CopyCommit() {
git cherry-pick "$1";
}

# Setting PATH for Python 3.6
# The original version is saved in .bash_profile.pysave
PATH="/Library/Frameworks/Python.framework/Versions/3.6/bin:${PATH}"
export PATH

function PullBranch {
git add *;
git stash;
git pull;
git stash pop 0;
}


