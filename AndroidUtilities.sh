source $BASH_SCRIPTS/Constants.sh;

# Takes in a file path and returns if it is an apk
function IsValidFile() {
	[ $(echo "$1" | grep ".apk") != "" ];
}

# Takes in a package path on the computer and returns the package id
function GetPackageId() {
	aapt dump badging "$1" | grep package:\ name | awk '{ print $2 }' | cut -d "'" -f 2;
}

# Takes a package id as input and uninstalls it
function PckgUninstall() {
	LogMessage "Uninstalling previous package $1";
	adb uninstall "$1";
}

# Takes a package path on the computer and installs it on device
function PckgInstall() {
	LogMessage "Installing build on $1";		
	adb install "$1";
}

# Takes an Activity path as input and starts it on device
function PckgStart() {
	LogMessage "Starting package $1";		
	adb shell am start -n "$1";
}

function PckgStop() {
	LogMessage "Stopping package $1";
	adb shell am force-stop "$1";
}

# Takes a package id as input and returns the path to the activity on device
function GetActivityPath() {
	adb shell pm dump "$1" | grep -A 1 MAIN | grep "filter" | awk '{ print $2 }'
}

# Takes a package path as input, Uninstalls it from device (if installed)
function UninstallAPK() {
	local path=$1;
	local IsValidFile=$(IsValidFile "$path");
	if [ isValidFile ]; then
		local packageId=$(GetPackageId "$path");
		PckgUninstall "$packageId";
	else
		LogError "Invalid target file";
	fi	
}

# Takes a package path as input, Uninstalls it from device (if installed) -> Installs it on device
function InstallAPK() {
	local path=$1;
	local IsValidFile=$(IsValidFile "$path");
	if [ isValidFile ]; then
		local packageId=$(GetPackageId "$path");

		PckgUninstall "$packageId";
		PckgInstall "$path";
	else
		LogError "Invalid target file";
	fi	
}

# Takes a package path as input, Starts it if installed
function StartAPK() {
	local path=$1;
	local IsValidFile=$(IsValidFile "$path");
	if [ isValidFile ]; then
		local packageId=$(GetPackageId "$path");
		local activityPath=$(GetActivityPath "$packageId");

		PckgStart "$activityPath";
	else
		LogError "Invalid target file";
	fi
}

# Takes a package path as input, Uninstalls it from device (if installed) -> Installs it on device -> Starts it
function InstallAndStartAPK() {
	local path=$1;
	local IsValidFile=$(IsValidFile "$path");
	if [ isValidFile ]; then
		local packageId=$(GetPackageId "$path");
		local activityPath=$(GetActivityPath "$packageId");

		PckgUninstall "$packageId";
		PckgInstall "$path";
		PckgStart "$activityPath";

		Say "Job's Done!";
	else
		LogError "Invalid target file";
	fi	
}

# Stops the application associated to an apk on device and starts it again
function RestartAPK() {
	local path=$1;
	local IsValidFile=$(IsValidFile "$path");
	if [ isValidFile ]; then
		local packageId=$(GetPackageId "$path");
		local activityPath=$(GetActivityPath "$packageId");

		PckgStop "$packageId";
		PckgStart "$activityPath";
	else
		LogError "Invalid target file";
	fi		
}
