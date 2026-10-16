# Jolene's everyday commands. `just` lists them.

set shell := ["bash", "-euo", "pipefail", "-c"]

project := "Jolene.xcodeproj"
scheme := "Jolene"
derived := "build/DerivedData"
debug_app := derived / "Build/Products/Debug/Jolene.app"
bundle_id := "com.johncarmack.jolene"
probe_app := "build/BadgeProbe.app"
probe_id := "com.johncarmack.jolene.badgeprobe"
probe_control := "build/badgeprobe.txt"

default:
    @just --list

# Build the Debug app into build/
build:
    xcodebuild -project {{project}} -scheme {{scheme}} -configuration Debug -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath {{derived}} -quiet build

# Run the unit tests
test:
    xcodebuild -project {{project}} -scheme {{scheme}} -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath {{derived}} -quiet test

# Run the tests the way CI does, signed ad hoc, so no certificate is needed
test-ci:
    xcodebuild test -project {{project}} -scheme {{scheme}} -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath build/DerivedDataCI CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= ENABLE_HARDENED_RUNTIME=NO -quiet

# Build a Developer ID release into build/release; set NOTARY_PROFILE (a notarytool keychain profile) to notarize it
release:
    #!/usr/bin/env bash
    set -euo pipefail
    rm -rf build/release
    xcodebuild -project {{project}} -scheme {{scheme}} -configuration Release -destination 'generic/platform=macOS' -archivePath build/release/Jolene.xcarchive -quiet archive
    xcodebuild -exportArchive -archivePath build/release/Jolene.xcarchive -exportPath build/release -exportOptionsPlist Tools/ExportOptions.plist -quiet
    if [ -n "${NOTARY_PROFILE:-}" ]; then
        ditto -c -k --keepParent build/release/Jolene.app build/release/notarize.zip
        xcrun notarytool submit build/release/notarize.zip --keychain-profile "$NOTARY_PROFILE" --wait
        xcrun stapler staple build/release/Jolene.app
        rm build/release/notarize.zip
    else
        echo "Signed, not notarized. Set NOTARY_PROFILE to a notarytool keychain profile to notarize."
    fi
    version=$(plutil -extract CFBundleShortVersionString raw build/release/Jolene.app/Contents/Info.plist)
    ditto -c -k --sequesterRsrc --keepParent build/release/Jolene.app "build/release/Jolene-$version.zip"
    echo "build/release/Jolene-$version.zip"

# Build, quit the running Jolene, and open the new build
run: build quit
    open {{debug_app}}

# Quit Jolene if it's running, and wait until it has
quit:
    #!/usr/bin/env bash
    set -euo pipefail
    [ -n "$(lsappinfo find bundleid={{bundle_id}})" ] || exit 0
    osascript -e 'tell application id "{{bundle_id}}" to quit'
    # Opening the new build while the old one is still quitting fails with error -609.
    for _ in $(seq 50); do
        [ -z "$(lsappinfo find bundleid={{bundle_id}})" ] && exit 0
        sleep 0.1
    done
    echo "Jolene was still quitting after 5 seconds." >&2
    exit 1

# Build BadgeProbe, a small Dock app that shows whatever badge you give it
probe-build:
    mkdir -p {{probe_app}}/Contents/MacOS
    cp Tools/BadgeProbe/Info.plist {{probe_app}}/Contents/Info.plist
    swiftc -O -o {{probe_app}}/Contents/MacOS/BadgeProbe Tools/BadgeProbe/BadgeProbe.swift
    codesign --force --sign - {{probe_app}}

# Put a badge on BadgeProbe: `just badge 12`, `just badge •`, `just badge 99+`. No label clears it.
badge label="nil":
    [ -x {{probe_app}}/Contents/MacOS/BadgeProbe ] || just probe-build
    printf '%s\n' '{{label}}' > {{probe_control}}
    if [ -z "$(lsappinfo find bundleid={{probe_id}})" ]; then open -g {{probe_app}} --args "$PWD/{{probe_control}}"; fi

# Quit BadgeProbe
probe-quit:
    printf 'quit\n' > {{probe_control}}

# Remove build output
clean:
    rm -rf build
