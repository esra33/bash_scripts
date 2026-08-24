source "$BASH_SCRIPTS/Constants.sh";

export PS1="\u@\h \[\033[32m\]\w\[\033[33m\]\$(ParseGitBranch)\[\033[00m\] $ "

#-------------------------------------------------------
# Parces the git branch name

# dunno what this does?
function ParseGitBranch(){
     git branch 2> /dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/ (\1)/';
}

# Gets the full name of the current Branch
function GetFullBranchName(){
     git branch | grep '*' | sed -e 's/^* //';
}

# Gets the short name of the current Branch
function GetShortBranchName(){
     git symbolic-ref --short -q HEAD | sed -e 's,.*/\(.*\),\1,';
}

#-------------------------------------------------------
# Resets git account
function ResetGitAccount(){
     git config --global credential.helper osxkeychain;
     git pull;
}

#-------------------------------------------------------
# Check if the branch has changes
function IsBranchClean(){
     git status | grep clean;
}

function HasConflicts(){
     git status | grep 'CONFLICT\|both modified\|conflict\|both merged'
}

#-------------------------------------------------------
# Adds and stashes all changes with message INPUT - BranchName - Date Time
function StashChanges() {
     echo -e "$YELLOW_COLOR------------------------";
     echo "Stashing changes";
     echo -e "------------------------$NO_COLOR ";

     local date=$(date);
     local branch=$(GetFullBranchName);
     git add *;
     git stash push -m "[$1] - [$branch] - [$date]";
}

#-------------------------------------------------------
# Clears the Branch
function ClearBranch(){
     local isClean=$(IsBranchClean);
     if [ "$isClean" == "" ]; then
          StashChanges "ClearBranch";
          git stash drop 0;
     fi
}

#------------------------------------------------------------------
# Rolls back a set number of unpushed commits in the current branch
function ResetCommit(){
     echo "Resetting back $1 commits";
     git reset --soft HEAD~"$1";
}

#-------------------------------------------------------
# Pulls all changes for current Branch
function PullBranch(){
     
     local isClean=$(IsBranchClean);
     
     if [ "$isClean" == "" ]; then
          StashChanges "PullBranch";
     fi

     git pull;
     
     if [ "$isClean" == "" ]; then
          git stash pop 0;
     fi
}

#-------------------------------------------------------
# Pushes the current git branch to the origin
function PushBranch(){
     PullBranch;
     local branch=$(GetFullBranchName);
     echo "Pushing to origin $branch";
     git push origin "$branch";
     echo "Push Completed"
}

#------------------------------------------------------------------
# Makes a new branch
function MakeBranch(){
     git checkout -b "$1";
     PushBranch;
     git branch --set-upstream-to=origin/"$1";
}

#-------------------------------------------------------
# Switches to a new branch specified as a parameter
function SwitchToBranch(){

     local branch_name=$(GetShortBranchName);
     local isClean=$(IsBranchClean);
     local branch=$(GetFullBranchName);

     git status;
     echo "";

     if [ "$branch_name" != "$1" ] && [ "$branch" != "$1" ]; then

          if [ "$isClean" == "" ]; then
               StashChanges "SwitchToBranch"
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

     local branch_name=$(GetShortBranchName);
     local isClean=$(IsBranchClean);
     local branch=$(GetFullBranchName);

     git status;
     echo "";

     if [ "$branch_name" == "$1" ] || [ "$branch" == "$1" ]; then
          echo -e "$RED_COLOR Invalid branch $NO_COLOR ";
     else
          echo -e "'$BLUE_COLOR'Starting Update Process!!'$NO_COLOR'";
          if [ "$isClean" == "" ]; then
               StashChanges "UpdateFromBranch";
          fi

          git reset --hard HEAD;

          echo -e "$YELLOW_COLOR ";
          echo "------------------------";
          echo "Pulling Current";
          echo "------------------------";
          echo -e "$NO_COLOR ";

          git pull origin "$branch";

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

          git checkout "$branch";

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

          local hasConflicts=$(HasConflicts);
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

          Say "Job's Done!";
     fi

     echo -e "$NO_COLOR";
}