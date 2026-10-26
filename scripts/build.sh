#!/bin/bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd -- "$script_dir/.." && pwd)"
source_path="$project_dir/date_weekday_quiz_stayopen.applescript"
output_path="$project_dir/build/Date Weekday Quiz.app"
replace_existing=false

usage() {
    cat <<'USAGE'
Usage: scripts/build.sh [--source PATH] [--output PATH.app] [--force]

Compile the stay-open AppleScript into a background macOS app.
--force replaces only the specified existing build output.
This command does not install or launch the app.
USAGE
}

while (($#)); do
    case "$1" in
        --source|--output)
            if (($# < 2)); then usage >&2; exit 2; fi
            if [[ "$1" == --source ]]; then source_path="$2"; else output_path="$2"; fi
            shift 2
            ;;
        --force) replace_existing=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done

[[ -f "$source_path" ]] || { echo "Source not found: $source_path" >&2; exit 1; }
[[ "$output_path" == *.app ]] || { echo "Output must end in .app" >&2; exit 2; }
if [[ -e "$output_path" && "$replace_existing" != true ]]; then
    echo "Output already exists; pass --force to replace it: $output_path" >&2
    exit 1
fi

output_parent="$(dirname -- "$output_path")"
mkdir -p "$output_parent"
staging_dir="$(mktemp -d "$output_parent/.date-weekday-quiz-build.XXXXXX")"
trap 'rm -rf -- "$staging_dir"' EXIT
staged_app="$staging_dir/Date Weekday Quiz.app"

/usr/bin/osacompile -s -o "$staged_app" "$source_path"
info_plist="$staged_app/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleIdentifier -string com.vincentgoverse.dateweekdayquiz "$info_plist"
/usr/bin/plutil -replace CFBundleName -string 'Date Weekday Quiz' "$info_plist"
/usr/bin/plutil -replace CFBundleDisplayName -string 'Date Weekday Quiz' "$info_plist"
/usr/bin/plutil -replace CFBundleShortVersionString -string 2.0 "$info_plist"
/usr/bin/plutil -replace CFBundleVersion -string 2.0.0 "$info_plist"
/usr/bin/plutil -replace LSUIElement -bool true "$info_plist"
/usr/bin/plutil -replace OSAAppletStayOpen -bool true "$info_plist"
/usr/bin/plutil -replace NSAppleEventsUsageDescription -string 'Date Weekday Quiz displays scheduled practice prompts and weekday quiz dialogs.' "$info_plist"
/usr/bin/plutil -lint "$info_plist"
# osacompile can copy Finder metadata from its applet template. Strip only the
# newly generated bundle's extended attributes before creating its signature.
/usr/bin/xattr -cr "$staged_app"
/usr/bin/codesign --force --sign - "$staged_app"
/usr/bin/codesign --verify --strict "$staged_app"

if [[ -e "$output_path" ]]; then
    mv -- "$output_path" "$staging_dir/previous-build.app"
fi
if ! mv -- "$staged_app" "$output_path"; then
    if [[ -e "$staging_dir/previous-build.app" ]]; then
        mv -- "$staging_dir/previous-build.app" "$output_path"
    fi
    exit 1
fi
echo "Built: $output_path"
