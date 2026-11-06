#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"
configuration="${CONFIGURATION:-Release}"
case "$configuration" in Debug|Release) ;; *) echo "Use Debug or Release for CONFIGURATION." >&2; exit 1 ;; esac

xcodegen generate --spec project.yml
xcodebuild -quiet -project AgentUsage.xcodeproj -scheme AgentUsage \
    -configuration "$configuration" -derivedDataPath .xcode-derived CODE_SIGNING_ALLOWED=NO build

products="$root/.xcode-derived/Build/Products/$configuration"
app="$root/dist/Agent Usage.app"
helper="$app/Contents/Helpers/agent-usage-claude-capture"

rm -rf "$app"
mkdir -p "$root/dist"
ditto "$products/Agent Usage.app" "$app"
mkdir -p "$app/Contents/Helpers"
ditto "$products/agent-usage-claude-capture" "$helper"
codesign --force --sign - "$helper"
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
printf '%s\n' "$app"
