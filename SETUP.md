# Poll Call setup

Every value you must change contains `CHANGEME`. To find any you missed:

    grep -rn CHANGEME .

## 1. Values to replace

| File | Find | Replace with | Needed for |
|---|---|---|---|
| project.yml | `CHANGEME_GOOGLE_CIVIC_API_KEY` | Your Google Civic Information API key | Polling places on the map |
| project.yml | `com.CHANGEME` (2 places) | Your reverse domain, e.g. `com.elliottdavid` | Real iPhone, App Store |
| project.yml | `CHANGEME_TEAM_ID` | Your 10-character Apple Team ID | Real iPhone, App Store |
| ExportOptions.plist | `CHANGEME_TEAM_ID` | Same Team ID | App Store upload |
| project-noassets.yml | `CHANGEME_GOOGLE_CIVIC_API_KEY`, `com.CHANGEME` | Same as above | Only if you use the fallback |

- API key: console.cloud.google.com > enable "Google Civic Information API" > Credentials > Create API key.
  Restrict it to iOS apps with your bundle ID.
- Team ID: developer.apple.com/account > Membership details.

## 2. Build for the Simulator

    cd ~/Coding/PollCall
    xcodegen
    rm -rf build
    xcodebuild -project PollCall.xcodeproj -scheme PollCall -destination "generic/platform=iOS Simulator" -derivedDataPath build CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|BUILD"
    xcrun simctl boot "iPhone 16"
    open -a Simulator
    xcrun simctl install "iPhone 16" build/Build/Products/Debug-iphonesimulator/PollCall.app
    xcrun simctl launch "iPhone 16" com.YOURDOMAIN.PollCall

If the build fails on Assets.xcassets, use `xcodegen --spec project-noassets.yml` instead of `xcodegen`.

## 3. Upload to the App Store (needs Xcode 26+ and a paid developer account)

    xcodegen
    xcodebuild -project PollCall.xcodeproj -scheme PollCall -configuration Release -destination "generic/platform=iOS" -archivePath build/PollCall.xcarchive -allowProvisioningUpdates archive
    xcodebuild -exportArchive -archivePath build/PollCall.xcarchive -exportPath build/export -exportOptionsPlist ExportOptions.plist -allowProvisioningUpdates

Drag `build/export/PollCall.ipa` into Transporter > Verify > Deliver.
Before each new upload, raise `CFBundleVersion` and `CURRENT_PROJECT_VERSION` in project.yml (1, 2, 3...).

## 4. Optional defaults

- `PollCall/ReminderScheduler.swift`: `dailyHour = 9` is the early-voting reminder time.
- `PollCall/Midterms2026.swift`: dates are for Nov 3, 2026 only. Update for future elections.
