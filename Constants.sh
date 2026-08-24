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

export PATH=$PATH:$ANDROID_SDK:$ANDROID_PLATAFORM_TOOLS:$ANDROID_TOOLS:$ANDROID_BUILD_TOOLS

export EMOJI=$USER_HOME/Documents/Projects/Emoji-Blitz
export BLACK_FOREST=$USER_HOME/Documents/Projects/BlackForestGame/SnowmanGame
export BUILD_OUTPUT=$USER_HOME/Desktop/Builds

export CUSTOM_SCRIPTS=/Users/andresramirex/Desktop/BashScripts
export PATH=$PATH:$CUSTOM_SCRIPTS

export VAULT_ADDR=http://10.12.42.6

#-------------------------------------------------------
# Color Definitions
export NO_COLOR='\033[0m'
export RED_COLOR='\033[0;31m'
export YELLOW_COLOR='\033[0;33m'
export BLUE_COLOR='\033[0;34m'

# More color code on https://stackoverflow.com/questions/5947742/how-to-change-the-output-color-of-echo-in-linux

function LogMessage() {
	echo -e "$YELLOW_COLOR ";
	echo "------------------------";
	echo "$1";
	echo "------------------------";
	echo -e "$NO_COLOR ";
}

function LogError() {
	echo -e "$RED_COLOR ";
	echo "------------------------";
	echo "$1";
	echo "------------------------";
	echo -e "$NO_COLOR ";
}