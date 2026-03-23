#!/bin/zsh

# Writing Custom Build Scripts
# https://developer.apple.com/documentation/xcode/writing-custom-build-scripts

set -e

# Remove the `CFBundleSupportedPlatforms` key from the FFmpeg framework's Info.plist.
ffmpeg_infoplist="$CI_PRIMARY_REPOSITORY_PATH/Pods/DJIWidget/FFmpeg/FFmpeg.framework/Info.plist"
/usr/libexec/PlistBuddy -c "Delete :CFBundleSupportedPlatforms" "$ffmpeg_infoplist"
