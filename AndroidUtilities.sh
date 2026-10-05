source "$BASH_SCRIPTS/Constants.sh";

#-------------------------------------------------------
# Device selection

# Usage: UseDevice [serial]
#   Lists connected devices, or picks the one all commands target.
#   Without a serial it shows the devices and the current target.
#   Example: UseDevice emulator-5554
function UseDevice() {
	if [ -z "$1" ]; then
		adb devices -l;
		echo "Current target: ${ANDROID_SERIAL:-none (single device mode)}";
		return 0;
	fi

	if ! adb devices | grep -q "^$1[[:space:]]*device$"; then
		LogError "Device $1 is not connected";
		return 1;
	fi
	export ANDROID_SERIAL="$1";
	echo "Using device $1";
}

# Internal: RequireDevice
#   Fails with a message unless exactly one target device is available.
function RequireDevice() {
	local devices;
	devices=$(adb devices | awk 'NR > 1 && $2 == "device" { print $1 }');

	if [ -n "$ANDROID_SERIAL" ]; then
		if ! echo "$devices" | grep -qx "$ANDROID_SERIAL"; then
			LogError "Selected device $ANDROID_SERIAL is not connected (run UseDevice to pick another)";
			return 1;
		fi
		return 0;
	fi

	local count;
	count=$(echo "$devices" | grep -c .);
	if [ "$count" -eq 0 ]; then
		LogError "No Android device connected";
		return 1;
	elif [ "$count" -gt 1 ]; then
		LogError "More than one device connected, pick one with: UseDevice <serial>";
		echo "$devices";
		return 1;
	fi
}

#-------------------------------------------------------
# Package helpers

# Internal: ResolvePackageId <apk path>
#   Validates an apk path and prints its package id.
function ResolvePackageId() {
	if [ ! -f "$1" ] || [[ "$1" != *.apk ]]; then
		LogError "Invalid target file: $1" >&2;
		return 1;
	fi

	local packageId;
	packageId=$(aapt dump badging "$1" 2>/dev/null | awk -F"'" '/^package: name=/ { print $2 }');
	if [ -z "$packageId" ]; then
		LogError "Could not read the package id from $1" >&2;
		return 1;
	fi
	echo "$packageId";
}

# Internal: IsPckgInstalled <package id>
#   Succeeds if the package is installed on the device.
function IsPckgInstalled() {
	adb shell pm list packages "$1" | tr -d '\r' | grep -qx "package:$1";
}

# Internal: PckgUninstall <package id>
#   Uninstalls a package from the device, if installed.
function PckgUninstall() {
	if IsPckgInstalled "$1"; then
		LogMessage "Uninstalling previous package $1";
		adb uninstall "$1";
	fi
}

# Internal: PckgInstall <apk path> [-r]
#   Installs an apk on the device (-r updates in place, keeping app data).
function PckgInstall() {
	LogMessage "Installing build $1";
	adb install $2 "$1";
}

# Internal: PckgStart <package id>
#   Launches an app like tapping its icon.
function PckgStart() {
	LogMessage "Starting package $1";
	adb shell monkey -p "$1" -c android.intent.category.LAUNCHER 1 > /dev/null;
}

# Internal: PckgStop <package id>
#   Force stops an app.
function PckgStop() {
	LogMessage "Stopping package $1";
	adb shell am force-stop "$1";
}

#-------------------------------------------------------
# APK commands

# Internal: ParseInstallFlags [--fresh | --keep] [--logcat]
#   Reads the install modifiers. Sets: installMode (fresh | keep, default fresh) and logcat (true | false).
function ParseInstallFlags() {
	installMode="fresh";
	logcat=false;

	local flag;
	for flag in "$@"; do
		case "$flag" in
			--fresh) installMode="fresh" ;;
			--keep) installMode="keep" ;;
			--logcat) logcat=true ;;
			*) LogError "Unknown option: $flag"; return 1 ;;
		esac
	done
}

# Internal: InstallWithMode <package id> <apk path> <fresh | keep>
#   Installs an apk using the given install mode.
function InstallWithMode() {
	local packageId=$1;
	local path=$2;
	local mode=$3;

	if [ "$mode" == "keep" ]; then
		if ! PckgInstall "$path" -r; then
			LogError "Update failed. If the build is signed with a different key, use --fresh";
			return 1;
		fi
	else
		PckgUninstall "$packageId";
		PckgInstall "$path";
	fi
}

# Usage: UninstallAPK <apk path>
#   Uninstalls the app of an apk from the device, if installed.
#   Example: UninstallAPK ~/Desktop/Builds/game.apk
function UninstallAPK() {
	local packageId;
	packageId=$(ResolvePackageId "$1") || return 1;
	RequireDevice || return 1;
	PckgUninstall "$packageId";
}

# Usage: InstallAPK <apk path> [--fresh | --keep]
#   Installs an apk on the device.
#   --fresh         Uninstall first, wiping app data (default)
#   --keep          Update in place, keeping app data
#   Example: InstallAPK ~/Desktop/Builds/game.apk --keep
function InstallAPK() {
	local installMode logcat;
	ParseInstallFlags "${@:2}" || return 1;

	local packageId;
	packageId=$(ResolvePackageId "$1") || return 1;
	RequireDevice || return 1;
	InstallWithMode "$packageId" "$1" "$installMode";
}

# Usage: StartAPK <apk path>
#   Launches the app of an apk on the device.
#   Example: StartAPK ~/Desktop/Builds/game.apk
function StartAPK() {
	local packageId;
	packageId=$(ResolvePackageId "$1") || return 1;
	RequireDevice || return 1;
	PckgStart "$packageId";
}

# Usage: InstallAndStartAPK <apk path> [--fresh | --keep] [--logcat]
#   Installs an apk on the device and launches it.
#   --fresh         Uninstall first, wiping app data (default)
#   --keep          Update in place, keeping app data
#   --logcat        Show the app's logs once it starts (Ctrl+C to stop)
#   Example: InstallAndStartAPK ~/Desktop/Builds/game.apk --keep --logcat
function InstallAndStartAPK() {
	local installMode logcat;
	ParseInstallFlags "${@:2}" || return 1;

	local packageId;
	packageId=$(ResolvePackageId "$1") || return 1;
	RequireDevice || return 1;

	InstallWithMode "$packageId" "$1" "$installMode" || return 1;
	PckgStart "$packageId" || return 1;

	Say "Job's Done!";

	if [ "$logcat" == true ]; then
		LogcatAPK "$1";
	fi
}

# Usage: RestartAPK <apk path>
#   Force stops the app of an apk and launches it again.
#   Example: RestartAPK ~/Desktop/Builds/game.apk
function RestartAPK() {
	local packageId;
	packageId=$(ResolvePackageId "$1") || return 1;
	RequireDevice || return 1;
	PckgStop "$packageId";
	PckgStart "$packageId";
}

# Usage: LogcatAPK <apk path>
#   Shows the logs of the running app of an apk (Ctrl+C to stop).
#   Waits up to 15 seconds for the app to start. Run it again if the app restarts.
#   Example: LogcatAPK ~/Desktop/Builds/game.apk
function LogcatAPK() {
	local packageId;
	packageId=$(ResolvePackageId "$1") || return 1;
	RequireDevice || return 1;

	local pid attempt;
	for attempt in $(seq 1 15); do
		pid=$(adb shell pidof "$packageId" | tr -d '\r' | awk '{ print $1 }');
		[ -n "$pid" ] && break;
		sleep 1;
	done

	if [ -z "$pid" ]; then
		LogError "$packageId is not running";
		return 1;
	fi

	LogMessage "Showing logs for $packageId (pid $pid), Ctrl+C to stop";
	adb logcat --pid="$pid";
}
