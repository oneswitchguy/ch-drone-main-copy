# HandsOptional Flight Lab

Accessible DJI drone control for pilots using switch control, head tracking and other
assistive input.

## Building and Running

1. Install [CocoaPods](https://cocoapods.org).
2. **Do not run `pod install`.** `Pods/` contains local modifications to DJI's source, and
   reinstalling would overwrite them. See `ci_scripts/ci_post_clone.sh`.
3. Open `CH Drone 2.xcworkspace` in Xcode.
4. Change the code signing to your own organisation.
5. Copy `Debug-Local-Template.xcconfig` to `Debug-Local.xcconfig`.
6. In `Debug-Local.xcconfig`, replace the placeholder bundle ID with a new unique one.
7. Register an app at https://developer.dji.com/user/apps with your chosen bundle ID.
8. Copy the DJI API Key in to `Debug-Local.xcconfig`.
9. Build and Run.
