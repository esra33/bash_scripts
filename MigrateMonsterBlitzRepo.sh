# Gets the full name of the current Branch
function GetFullBranchName(){
	git branch | grep '*' | sed -e 's/^* //';
}

function MigrateRepo() {
	local branch=$(GetFullBranchName);

	echo "Replacing origin";
	git remote rm origin;
	git remote add origin "$1";

	echo "Fetching new origin";
	git fetch;

	echo "Setting upstream and pushing"
	git push origin "$branch";
	git branch --set-upstream-to=origin/"$branch";
	
	echo "Syncing with remote"
	git pull;
}

MigrateRepo $1;