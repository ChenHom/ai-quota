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

# 面板要顯示這份 app 是哪個 commit 建出來的——版號本身不會每次改，
# 光看版號分不出兩次建置
revision="$(git -C "$root_dir" rev-parse --short HEAD 2>/dev/null || echo unknown)"
if [[ -n "$(git -C "$root_dir" status --porcelain 2>/dev/null)" ]]; then
    revision="${revision}+"   # 工作區有未提交的改動
fi

plist="$app_dir/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :AIQuotaGitRevision string ${revision}" "$plist"
/usr/libexec/PlistBuddy -c "Add :AIQuotaBuiltAt string $(date '+%Y-%m-%d %H:%M')" "$plist"

ditto -c -k --norsrc --keepParent "$app_dir" "$zip_path"
echo "Created $app_dir"
echo "Created $zip_path"
