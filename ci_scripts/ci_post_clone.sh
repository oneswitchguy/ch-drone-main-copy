#!/bin/zsh

# Writing Custom Build Scripts
# https://developer.apple.com/documentation/xcode/writing-custom-build-scripts

set -e

brew install cocoapods getsentry/tools/sentry-cli

# We don't run pod install because it would overwrite local customizations to DJI's source code
# pod install

./ch_clean_ffmpeg.sh
