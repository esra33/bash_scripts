source "$BASH_SCRIPTS/Constants.sh";

export PS1="\u@\h \[\033[32m\]\w\[\033[33m\]\$(ParseGitBranch)\[\033[00m\] $ "

#-------------------------------------------------------
# Internal: ParseGitBranch
#   Prints " (branch)" for the prompt, or nothing outside a git repo.
function ParseGitBranch(){
     git branch 2> /dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/ (\1)/';
}

# Internal: GetCurrentBranch
#   Prints the current branch name (empty when HEAD is detached).
function GetCurrentBranch(){
     git branch --show-current;
}

# Internal: HasUpstream
#   Succeeds if the current branch tracks a remote branch.
function HasUpstream(){
     git rev-parse --abbrev-ref --symbolic-full-name '@{u}' > /dev/null 2>&1;
}

#-------------------------------------------------------
# Internal: IsBranchClean
#   Succeeds if there are no uncommitted or untracked changes.
function IsBranchClean(){
     [ -z "$(git status --porcelain)" ];
}

# Internal: HasConflicts
#   Lists the files that have merge conflicts.
function HasConflicts(){
     git diff --name-only --diff-filter=U;
}

#-------------------------------------------------------
# Usage: StashChanges <label>
#   Stashes all changes, including untracked files.
#   The stash message is: [label] - [branch] - [date time]
#   Example: StashChanges "before rebase"
function StashChanges() {
     LogMessage "Stashing changes";
     git stash push -u -m "[$1] - [$(GetCurrentBranch)] - [$(date '+%d/%m/%y %H:%M:%S')]";
}

#-------------------------------------------------------
# Usage: ClearBranch
#   Discards ALL uncommitted changes in the current branch (asks first).
#   A cleared stash can still be recovered with FindHeadlessCommits.
function ClearBranch(){
     if IsBranchClean; then
          echo "Nothing to clear";
          return 0;
     fi

     git status --short;
     local answer;
     read -r -p "Discard ALL of the changes above on $(GetCurrentBranch)? [y/N] " answer;
     if [ "$answer" != "y" ] && [ "$answer" != "Y" ]; then
          echo "Cancelled";
          return 1;
     fi

     StashChanges "ClearBranch" && git stash drop;
}

#------------------------------------------------------------------
# Usage: ResetCommit <number of commits>
#   Undoes unpushed commits, keeping their changes.
#   Refuses if any of those commits were already pushed.
#   Example: ResetCommit 2
function ResetCommit(){
     if ! [[ "$1" =~ ^[1-9][0-9]*$ ]]; then
          LogError "Usage: ResetCommit <number of commits>";
          return 1;
     fi

     if HasUpstream; then
          local unpushed;
          unpushed=$(git rev-list --count '@{u}..HEAD');
          if [ "$1" -gt "$unpushed" ]; then
               LogError "Only $unpushed commit(s) are unpushed, refusing to reset $1";
               return 1;
          fi
     fi

     echo "Resetting back $1 commits";
     git reset --soft HEAD~"$1";
}

#-------------------------------------------------------
# Usage: PullBranch
#   Pulls the current branch, keeping local changes.
function PullBranch(){
     git pull --autostash;
}

#-------------------------------------------------------
# Usage: PushBranch
#   Pushes the current branch to origin, pulling first if it is already there.
#   New branches are pushed and set to track origin.
function PushBranch(){
     if HasUpstream; then
          PullBranch || return 1;
     fi

     local branch;
     branch=$(GetCurrentBranch);
     echo "Pushing to origin $branch";
     git push -u origin HEAD && echo "Push Completed";
}

#------------------------------------------------------------------
# Usage: MakeBranch <branch name>
#   Creates a branch from the current one and pushes it to origin.
#   Example: MakeBranch feature/login
function MakeBranch(){
     if [ -z "$1" ]; then
          LogError "Usage: MakeBranch <branch name>";
          return 1;
     fi

     git switch -c "$1" && git push -u origin "$1";
}

#-------------------------------------------------------
# Usage: SwitchToBranch <branch>
#   Switches branch; local changes stay stashed on the old branch.
#   Fetches and pulls the target branch. If the switch fails, the changes are restored.
#   Example: SwitchToBranch feature/login
function SwitchToBranch(){
     if [ -z "$1" ]; then
          LogError "Usage: SwitchToBranch <branch name>";
          return 1;
     fi

     local branch;
     branch=$(GetCurrentBranch);
     if [ "$branch" == "$1" ]; then
          echo "Already on $1";
          return 0;
     fi

     git status;
     echo "";

     local stashed=false;
     if ! IsBranchClean; then
          StashChanges "SwitchToBranch" || return 1;
          stashed=true;
     fi

     LogMessage "Changing branches";
     git fetch origin;
     if ! git switch "$1"; then
          LogError "Could not switch to $1";
          if [ "$stashed" == true ]; then
               git stash pop;
          fi
          return 1;
     fi

     if HasUpstream; then
          git pull;
     fi

     if [ "$stashed" == true ]; then
          LogMessage "Your changes from $branch are saved in: $(git stash list -1)";
     fi
}

#-------------------------------------------------------
# Usage: UpdateFromBranch <base branch> [--theirs] [--renormalize]
#   Merges an updated base branch into the current one.
#   Stashes local changes, pulls the current branch, updates the local base branch
#   (without switching to it), merges it, then restores the local changes.
#   Stops on conflicts, keeping the local changes in the stash.
#   --theirs        Resolve conflicts with the base branch version
#   --renormalize   Apply .gitattributes rules to both sides first (e.g. after an LFS conversion)
#   Example: UpdateFromBranch main
function UpdateFromBranch(){
     if [ -z "$1" ] || [[ "$1" == -* ]]; then
          LogError "Usage: UpdateFromBranch <base branch> [--theirs] [--renormalize]";
          return 1;
     fi

     local mergeOptions=() flag;
     for flag in "${@:2}"; do
          case "$flag" in
               --theirs) mergeOptions+=(-X theirs) ;;
               --renormalize) mergeOptions+=(-X renormalize) ;;
               *) LogError "Unknown option: $flag"; return 1 ;;
          esac
     done

     local branch;
     branch=$(GetCurrentBranch);
     if [ -z "$branch" ] || [ "$branch" == "$1" ]; then
          LogError "Invalid branch";
          return 1;
     fi

     git status;
     echo "";
     echo -e "${BLUE_COLOR}Starting Update Process!!${NO_COLOR}";

     local stashed=false;
     if ! IsBranchClean; then
          StashChanges "UpdateFromBranch" || return 1;
          stashed=true;
     fi

     LogMessage "Pulling $branch";
     if HasUpstream && ! git pull; then
          UpdateFromBranchFailed "Pulling $branch failed" "$stashed";
          return 1;
     fi

     LogMessage "Updating local $1 from origin";
     if ! git fetch origin "$1:$1"; then
          UpdateFromBranchFailed "Could not update local $1 (it may have unpushed commits)" "$stashed";
          return 1;
     fi

     LogMessage "Merging $1 into $branch";
     git merge "${mergeOptions[@]}" "$1";

     local hasConflicts;
     hasConflicts=$(HasConflicts);
     if [ -n "$hasConflicts" ]; then
          UpdateFromBranchFailed "Merge conflicts in:"$'\n'"$hasConflicts" "$stashed";
          return 1;
     fi

     if [ "$stashed" == true ]; then
          LogMessage "Applying stashed changes";
          git stash pop || LogError "Your changes conflicted when re-applied, they are still in the stash";
     fi

     echo -e "${BLUE_COLOR}All Clear${NO_COLOR}";
     Say "Job's Done!";
}

# Internal: UpdateFromBranchFailed <message> <stashed: true | false>
#   Reports why UpdateFromBranch stopped and where the stashed changes are.
function UpdateFromBranchFailed(){
     LogError "$1";
     if [ "$2" == true ]; then
          echo "Your changes are saved in: $(git stash list -1)";
          echo "Re-apply them with 'git stash pop' once the branch is ready";
     fi
}

#-------------------------------------------------------
# Internal: HasOnlyNormalizationChanges <repo root>
#   Succeeds if the only uncommitted changes are files that renormalizing would fix
#   (files git shows as modified only because the .gitattributes rules changed).
function HasOnlyNormalizationChanges(){
     (
          cd "$1" || exit 1;
          git diff --cached --quiet || exit 1;
          [ -z "$(git ls-files --others --exclude-standard)" ] || exit 1;

          # Each modified file must match its committed version once the current rules are applied to both
          local file;
          while IFS= read -r file; do
               [ -f "$file" ] || exit 1;
               [ "$(git hash-object --path="$file" "$file")" == "$(git cat-file blob ":$file" | git hash-object --path="$file" --stdin)" ] || exit 1;
          done < <(git -c core.quotePath=false diff --name-only);
          exit 0;
     )
}

#-------------------------------------------------------
# Usage: RenormalizeBranch <base branch>
#   Re-applies .gitattributes (e.g. LFS) to all files, then merges the base branch.
#   Commits the renormalized files, then runs: UpdateFromBranch <base branch> --renormalize --theirs
#   Needs a clean working tree (files changed only by new .gitattributes rules are allowed).
#   Example: RenormalizeBranch develop
function RenormalizeBranch(){
     if [ -z "$1" ]; then
          LogError "Usage: RenormalizeBranch <base branch>";
          return 1;
     fi

     if [ -z "$(GetCurrentBranch 2>/dev/null)" ]; then
          LogError "Not on a branch (or not in a git repo)";
          return 1;
     fi

     local root;
     root=$(git rev-parse --show-toplevel);

     if ! IsBranchClean && ! HasOnlyNormalizationChanges "$root"; then
          LogError "Commit or stash your changes first (including .gitattributes), so they don't end up in the renormalize commit";
          return 1;
     fi
     if grep -q "filter=lfs" "$root/.gitattributes" 2>/dev/null && [ -z "$(git config --get filter.lfs.clean)" ]; then
          LogError "This repo uses LFS but git lfs is not set up, run 'git lfs install' first";
          return 1;
     fi

     LogMessage "Renormalizing files";
     (cd "$root" && git add --renormalize .) || return 1;

     if git diff --cached --quiet; then
          echo "Files already match .gitattributes, nothing to commit";
     else
          git commit -m "Renormalize files after .gitattributes changes" || return 1;
     fi

     UpdateFromBranch "$1" --renormalize --theirs;
}

#-------------------------------------------------------
# Usage: CopyCommit <commit>
#   Applies a commit from another branch onto the current one (cherry-pick).
#   Example: CopyCommit a1b2c3d
function CopyCommit() {
     git cherry-pick "$1";
}

#-------------------------------------------------------
# Usage: BatchPush [--size N] [--remote NAME] [--dry-run] [--force]
#   Pushes the current branch in batches of commits, then its tags.
#   For pushes too large for the server in one go. Run it again to continue after a failure.
#   --size N        Commits per batch, higher than 1 (default 10)
#   --remote NAME   Remote to push to (default origin)
#   --dry-run       Only show the batches, push nothing
#   --force         Overwrite the remote branch if it has commits you don't have (asks first)
#   Example: BatchPush --size 50 --dry-run
function BatchPush(){
     local size=10 remote="origin" dryRun=false force="";
     while [ $# -gt 0 ]; do
          case "$1" in
               --size)
                    if ! [[ "$2" =~ ^[0-9]+$ ]] || [ "$2" -le 1 ]; then
                         LogError "--size must be a number higher than 1";
                         return 1;
                    fi
                    size=$2;
                    shift ;;
               --remote) remote=$2; shift ;;
               --dry-run) dryRun=true ;;
               --force) force="--force" ;;
               *) LogError "Unknown option: $1"; return 1 ;;
          esac
          shift;
     done

     local branch;
     branch=$(GetCurrentBranch 2>/dev/null);
     if [ -z "$branch" ]; then
          LogError "Not on a branch (or not in a git repo)";
          return 1;
     fi
     if ! git remote get-url "$remote" > /dev/null 2>&1; then
          LogError "Remote $remote does not exist";
          return 1;
     fi

     # Only push the commits the remote doesn't have yet
     git fetch "$remote" "$branch" > /dev/null 2>&1;
     local range="HEAD";
     if git show-ref --quiet --verify "refs/remotes/$remote/$branch"; then
          range="$remote/$branch..HEAD";

          local behind;
          behind=$(git rev-list --count "HEAD..$remote/$branch");
          if [ "$behind" -gt 0 ]; then
               if [ -z "$force" ]; then
                    LogError "$remote/$branch has $behind commit(s) you don't have. Pull first, or use --force to overwrite them";
                    return 1;
               fi
               LogError "WARNING: --force will delete $behind commit(s) from $remote/$branch";
               if [ "$dryRun" == false ]; then
                    local answer;
                    read -r -p "Overwrite $remote/$branch? [y/N] " answer;
                    if [ "$answer" != "y" ] && [ "$answer" != "Y" ]; then
                         echo "Cancelled";
                         return 1;
                    fi
               fi
          fi
     fi

     # Every Nth commit (oldest first) is the end of a batch, the last batch ends at HEAD
     local total head batches;
     total=$(git rev-list --count --first-parent "$range");
     head=$(git rev-parse HEAD);
     batches=$(git rev-list --first-parent --reverse "$range" | awk -v n="$size" 'NR % n == 0');
     if [ "$total" -gt 0 ] && [ "$(echo "$batches" | tail -n 1)" != "$head" ]; then
          batches=$(printf '%s\n%s' "$batches" "$head" | grep .);
     fi

     local count;
     count=$(echo "$batches" | grep -c .);
     LogMessage "Pushing $total commit(s) of $branch to $remote in $count batch(es) of $size";

     local sha number=0;
     for sha in $batches; do
          number=$((number + 1));
          echo "Batch $number/$count: pushing $(git rev-parse --short "$sha")";
          if [ "$dryRun" == true ]; then
               continue;
          fi
          if ! git push $force "$remote" "$sha:refs/heads/$branch"; then
               LogError "Batch $number/$count failed, run BatchPush again to continue from there";
               return 1;
          fi
     done

     if [ "$dryRun" == true ]; then
          echo "Would then push $(git tag | grep -c .) tag(s)";
          return 0;
     fi

     git branch --set-upstream-to="$remote/$branch" > /dev/null 2>&1;

     LogMessage "Pushing tags";
     git push "$remote" --tags || return 1;

     echo -e "${BLUE_COLOR}Batch Push Completed${NO_COLOR}";
}

#-------------------------------------------------------
# Usage: MigrateRepo <new remote url> [--size N] [--dry-run]
#   Moves all branches, tags and LFS files to a new remote.
#   The new remote becomes origin and the old one is kept as old-origin.
#   Stops if the new remote already has branches. Run it again with the same url to resume.
#   --size N        Commits per batch when pushing the current branch (see BatchPush)
#   --dry-run       Only show the steps, change nothing
#   Example: MigrateRepo git@github.com:org/new-repo.git --size 50
function MigrateRepo(){
     local url="" size="" dryRun=false;
     while [ $# -gt 0 ]; do
          case "$1" in
               --size) size=$2; shift ;;
               --dry-run) dryRun=true ;;
               -*) LogError "Unknown option: $1"; return 1 ;;
               *) url=$1 ;;
          esac
          shift;
     done

     if [ -z "$url" ]; then
          LogError "Usage: MigrateRepo <new remote url> [--size N] [--dry-run]";
          return 1;
     fi

     local branch;
     branch=$(GetCurrentBranch 2>/dev/null);
     if [ -z "$branch" ]; then
          LogError "Not on a branch (or not in a git repo)";
          return 1;
     fi

     # A previous run already swapped the remotes: only resume if it was to this same url
     local resuming=false oldRemote="origin";
     if git remote get-url old-origin > /dev/null 2>&1; then
          if [ "$(git remote get-url origin 2>/dev/null)" != "$url" ]; then
               LogError "A remote named old-origin already exists, rename or remove it first";
               return 1;
          fi
          resuming=true;
          oldRemote="old-origin";
          LogMessage "Resuming migration to $url";
     elif ! git remote get-url origin > /dev/null 2>&1; then
          LogError "This repo has no origin remote to migrate from";
          return 1;
     fi

     LogMessage "Checking $url";
     local existing;
     if ! existing=$(git ls-remote --heads "$url"); then
          LogError "Cannot reach $url (check the url and your access)";
          return 1;
     fi
     if [ "$resuming" == false ] && [ -n "$existing" ]; then
          LogError "$url already has branches, refusing to migrate into it";
          return 1;
     fi

     local usesLfs=false;
     if grep -q "filter=lfs" "$(git rev-parse --show-toplevel)/.gitattributes" 2>/dev/null; then
          usesLfs=true;
     fi

     LogMessage "Fetching everything from $oldRemote";
     git fetch "$oldRemote" --prune --tags || return 1;
     if [ "$usesLfs" == true ]; then
          git lfs fetch --all "$oldRemote" || return 1;
     fi

     local branches;
     branches=$(git for-each-ref --format='%(refname:strip=3)' "refs/remotes/$oldRemote/" | grep -vx HEAD);

     if [ "$dryRun" == true ]; then
          echo "Would rename origin to old-origin and add $url as origin";
          echo "Would push $branch with: BatchPush ${size:+--size $size}";
          echo "Would push $(echo "$branches" | grep -vxc "$branch") other branch(es) and $(git tag | grep -c .) tag(s)";
          if [ "$usesLfs" == true ]; then
               echo "Would push all LFS files";
          fi
          return 0;
     fi

     if [ "$resuming" == false ]; then
          LogMessage "Swapping remotes";
          git remote rename origin old-origin || return 1;
          git remote add origin "$url" || return 1;
     fi

     local resumeHint="Fix the problem and run MigrateRepo $url again to resume";

     BatchPush ${size:+--size "$size"} || { LogError "$resumeHint"; return 1; };

     LogMessage "Pushing the other branches";
     local other refspecs=();
     for other in $branches; do
          if [ "$other" != "$branch" ]; then
               refspecs+=("refs/remotes/old-origin/$other:refs/heads/$other");
          fi
     done
     if [ ${#refspecs[@]} -gt 0 ]; then
          git push origin "${refspecs[@]}" || { LogError "$resumeHint"; return 1; };
     fi

     if [ "$usesLfs" == true ]; then
          LogMessage "Pushing LFS files";
          local lfsRefs=();
          for other in $branches; do
               lfsRefs+=("refs/remotes/old-origin/$other");
          done
          git lfs push --all origin "$branch" "${lfsRefs[@]}" || { LogError "$resumeHint"; return 1; };
     fi

     LogMessage "Pointing local branches to the new origin";
     git fetch origin --prune > /dev/null 2>&1;
     local localBranch;
     for localBranch in $(git for-each-ref --format='%(refname:strip=2)' refs/heads/); do
          if [ "$(git config "branch.$localBranch.remote")" == "old-origin" ] && git show-ref --quiet --verify "refs/remotes/origin/$localBranch"; then
               git branch --set-upstream-to="origin/$localBranch" "$localBranch" > /dev/null;
          fi
     done
     if [ "$(git config remote.pushDefault)" == "old-origin" ]; then
          git config remote.pushDefault origin;
     fi

     echo -e "${BLUE_COLOR}Migration Completed. The old remote is still available as old-origin${NO_COLOR}";
     Say "Job's Done!";
}
