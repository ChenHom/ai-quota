#!/bin/zsh
set -euo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
app_dir="$root_dir/dist/AIQuota.app"
zip_path="$root_dir/dist/AIQuota-macos.zip"

cd "$root_dir"
swift build -c release

rm -rf "$app_dir" "$zip_path"
mkdir -p "$app_dir/Contents/MacOS"
cp .build/release/AIQuota "$app_dir/Contents/MacOS/AIQuota"
strip -S "$app_dir/Contents/MacOS/AIQuota"
cp Packaging/Info.plist "$app_dir/Contents/Info.plist"

ditto -c -k --norsrc --keepParent "$app_dir" "$zip_path"
echo "Created $app_dir"
echo "Created $zip_path"
