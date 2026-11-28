#!/bin/bash
# Renders every screen and every widget fixture of the DEBUG app (docs/RENDER-HARNESS.md).
#
#   scripts/render/run_all.sh <simulator-udid> <derived-data-dir>
#
# Builds the HearthRender scheme for testing once, then runs the walker one batch (one test method)
# at a time. The simulator's renderer goes black after roughly 20 app launches, so before every
# batch the simulator is shut down and booted again. After each batch the new PNGs are copied out of
# the test runner's Documents/renders, and at the end build_gallery.py builds the gallery.
#
# Use a simulator kept for this: the demo house replaces the app's stored accounts on it.
#
# Environment:
#   RENDER_OUT               output folder (default: <derived-data-dir>/render-output)
#   RENDER_ONLY              only batches whose "Class/method" matches this regex,
#                            e.g. RENDER_ONLY='HearthRenderTests/test0[1-3]' or 'WidgetRenderTests'
#   RENDER_WATCHDOG_SECONDS  kill a batch that runs longer than this (default: 600)
#   RENDER_RETRIES           run a failed batch again this many times (default: 1)
#   RENDER_XCODEBUILD_ARGS   extra xcodebuild arguments, e.g. 'CODE_SIGNING_ALLOWED=NO'
set -u -o pipefail

readonly TEST_TARGET="HearthRenderTests"
readonly SCHEME="HearthRender"
readonly APP_BUNDLE="com.rohit.hearth"
readonly RUNNER_BUNDLE="com.rohit.hearth.rendertests.xctrunner"
readonly WIDGET_CLASS="WidgetRenderTests"
readonly WIDGET_INDEX="test00Index"
# Home Screen automation, not a render: run it by hand when the real WidgetKit drawing is wanted.
readonly SKIPPED_CLASSES="WidgetPlacementTests"
readonly BOOT_TIMEOUT_SECONDS=180
readonly BOOT_SETTLE_SECONDS=5
readonly POLL_SECONDS=2

usage() {
    sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'
    exit 64
}

fail() {
    echo "run_all.sh: $*" >&2
    exit 1
}

[ $# -eq 2 ] || usage
readonly UDID="$1"
mkdir -p "$2" || fail "cannot create the derived-data directory $2"
DERIVED_DATA="$(cd "$2" && pwd)" || fail "cannot resolve $2"
readonly DERIVED_DATA
ROOT="$(cd "$(dirname "$0")/../.." && pwd)" || fail "cannot resolve the repository root"
readonly ROOT
readonly OUT="${RENDER_OUT:-$DERIVED_DATA/render-output}"
readonly RAW="$OUT/raw"
readonly LOGS="$OUT/logs"
readonly GALLERY="$OUT/gallery"
readonly ONLY="${RENDER_ONLY:-}"
readonly WATCHDOG_SECONDS="${RENDER_WATCHDOG_SECONDS:-600}"
readonly RETRIES="${RENDER_RETRIES:-1}"
# Deliberately word-split: several xcodebuild arguments in one variable.
read -r -a EXTRA_ARGS <<< "${RENDER_XCODEBUILD_ARGS:-}"

case "$WATCHDOG_SECONDS$RETRIES" in
    *[!0-9]*) fail "RENDER_WATCHDOG_SECONDS and RENDER_RETRIES must be whole numbers" ;;
esac
xcrun simctl list devices | grep -q "$UDID" || fail "no simulator with UDID $UDID (xcrun simctl list devices)"
command -v xcodegen >/dev/null || fail "xcodegen is not installed (brew install xcodegen)"
command -v python3 >/dev/null || fail "python3 is not installed"
mkdir -p "$RAW" "$LOGS" || fail "cannot create $OUT"

CHILD_PID=""
trap 'echo; echo "run_all.sh: interrupted"; [ -n "$CHILD_PID" ] && kill -TERM "$CHILD_PID" 2>/dev/null; exit 130' INT TERM

# macOS has no `timeout`: run the command in the background and kill it when it overruns.
# Returns the command's exit status, or 124 when the watchdog fired.
run_with_watchdog() {
    local limit="$1" log="$2"
    shift 2
    "$@" >"$log" 2>&1 &
    CHILD_PID=$!
    local waited=0
    while kill -0 "$CHILD_PID" 2>/dev/null; do
        if [ "$waited" -ge "$limit" ]; then
            echo "    watchdog: still running after ${limit}s, killing it"
            pkill -TERM -P "$CHILD_PID" 2>/dev/null
            kill -TERM "$CHILD_PID" 2>/dev/null
            sleep "$POLL_SECONDS"
            pkill -KILL -P "$CHILD_PID" 2>/dev/null
            kill -KILL "$CHILD_PID" 2>/dev/null
            wait "$CHILD_PID" 2>/dev/null
            CHILD_PID=""
            return 124
        fi
        sleep "$POLL_SECONDS"
        waited=$((waited + POLL_SECONDS))
    done
    wait "$CHILD_PID"
    local status=$?
    CHILD_PID=""
    return "$status"
}

# A fresh renderer: shut the simulator down and boot it again.
reboot_simulator() {
    xcrun simctl shutdown "$UDID" >/dev/null 2>&1   # "already shut down" is fine
    run_with_watchdog "$BOOT_TIMEOUT_SECONDS" "$LOGS/boot.log" xcrun simctl bootstatus "$UDID" -b \
        || { echo "    the simulator did not boot (see $LOGS/boot.log)"; return 1; }
    xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 \
        --cellularBars 4 --wifiBars 3 >/dev/null 2>&1 \
        || echo "    note: could not override the status bar"
    sleep "$BOOT_SETTLE_SECONDS"
}

runner_renders_dir() {
    local container
    container="$(xcrun simctl get_app_container "$UDID" "$RUNNER_BUNDLE" data 2>/dev/null)" || return 1
    echo "$container/Documents/renders"
}

# Copies what the batch wrote out of the runner's container. The catalog is merged rather than
# copied, so it is complete whether or not the container survives between batches.
collect_renders() {
    local renders before after
    renders="$(runner_renders_dir)" || { echo "    no test runner container to collect from"; return 1; }
    [ -d "$renders" ] || { echo "    the batch wrote no renders"; return 1; }
    before=$(find "$RAW" -name '*.png' | wc -l | tr -d ' ')
    rsync -a --exclude catalog.tsv "$renders/" "$RAW/" || { echo "    copying the renders failed"; return 1; }
    if [ -f "$renders/catalog.tsv" ]; then
        cat "$renders/catalog.tsv" >> "$RAW/catalog.tsv"
        awk '!seen[$0]++' "$RAW/catalog.tsv" > "$RAW/catalog.tsv.tmp" && mv "$RAW/catalog.tsv.tmp" "$RAW/catalog.tsv"
    fi
    after=$(find "$RAW" -name '*.png' | wc -l | tr -d ' ')
    echo "    collected: $((after - before)) new, $after in total"
}

xcodebuild_for() {
    local action="$1"
    shift
    xcodebuild "$action" -project "$ROOT/Hearth.xcodeproj" -scheme "$SCHEME" -destination "id=$UDID" \
        -derivedDataPath "$DERIVED_DATA" -skipMacroValidation ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"} "$@"
}

FAILED=()
RAN=0

# One batch = one test method, on a freshly booted simulator, under the watchdog.
execute_batch() {
    local class="$1" method="$2"
    local name="$class/$method" attempt=0 status=1 log
    RAN=$((RAN + 1))
    while [ "$attempt" -le "$RETRIES" ]; do
        log="$LOGS/$class-$method-$attempt.log"
        echo "==> $name (attempt $((attempt + 1)))"
        if reboot_simulator; then
            case "$method" in *CalendarDenied*) calendar_access revoke ;; esac
            run_with_watchdog "$WATCHDOG_SECONDS" "$log" \
                xcodebuild_for test-without-building "-only-testing:$TEST_TARGET/$name"
            status=$?
            collect_renders
            case "$method" in *CalendarDenied*) calendar_access reset ;; esac
        else
            status=1
        fi
        [ "$status" -eq 0 ] && { echo "    passed"; return 0; }
        echo "    failed with status $status (log: $log)"
        attempt=$((attempt + 1))
    done
    FAILED+=("$name")
    return 1
}

wanted() {
    [ -z "$ONLY" ] || [[ "$1" =~ $ONLY ]]
}

run_batch() {
    wanted "$1/$2" || return 0
    execute_batch "$1" "$2"
}

# Leave-by's "Needs calendar access" state: the app must be installed for the privacy setting.
calendar_access() {
    local app="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/Hearth.app"
    xcrun simctl install "$UDID" "$app" >/dev/null 2>&1 || echo "    note: could not install $app"
    xcrun simctl privacy "$UDID" "$1" calendar "$APP_BUNDLE" >/dev/null 2>&1 \
        || echo "    note: could not $1 calendar access"
}

test_classes() {
    sed -nE 's/^(final )?class ([A-Za-z0-9_]+): XCTestCase.*/\2/p' "$ROOT/$TEST_TARGET"/*.swift | sort
}

test_methods() {
    local file
    file="$(grep -lE "class $1: XCTestCase" "$ROOT/$TEST_TARGET"/*.swift | head -1)"
    [ -n "$file" ] || return 0
    sed -nE 's/^ +func (test[A-Za-z0-9_]+)\(\).*/\1/p' "$file" | sort
}

# How many widget batches the catalog needs: the ids the index saved over the ids per batch.
widget_batch_count() {
    local per ids
    per="$(sed -nE 's/^ +static let idsPerBatch = ([0-9]+).*/\1/p' "$ROOT/$TEST_TARGET/$WIDGET_CLASS.swift")"
    [ -n "$per" ] && [ "$per" -gt 0 ] && [ -s "$RAW/parity-ids.txt" ] || return 1
    ids=$(grep -c . "$RAW/parity-ids.txt")
    echo $(((ids + per - 1) / per))
}

# True when RENDER_ONLY leaves any widget batch to run.
wants_widgets() {
    local method
    for method in $(test_methods "$WIDGET_CLASS"); do
        wanted "$WIDGET_CLASS/$method" && return 0
    done
    return 1
}

echo "Hearth render: simulator $UDID, output $OUT"
(cd "$ROOT" && xcodegen generate >"$LOGS/xcodegen.log" 2>&1) || fail "xcodegen generate failed (see $LOGS/xcodegen.log)"
echo "==> build-for-testing"
xcodebuild_for build-for-testing >"$LOGS/build.log" 2>&1 || fail "the test build failed (see $LOGS/build.log)"

# Renders left in the runner by an earlier run would be collected as if they were new.
if reboot_simulator && stale="$(runner_renders_dir)" && [ -d "$stale" ]; then
    rm -rf "$stale" || fail "cannot clear the stale renders in $stale"
fi

for class in $(test_classes); do
    case " $SKIPPED_CLASSES $WIDGET_CLASS " in *" $class "*) continue ;; esac
    for method in $(test_methods "$class"); do run_batch "$class" "$method"; done
done

# Widgets: the index asks the app for its catalog, which decides how many batches there are. It
# runs whenever a widget batch is wanted, so the batches always follow the current catalog.
if wants_widgets; then
    rm -f "$RAW/parity-ids.txt"
    execute_batch "$WIDGET_CLASS" "$WIDGET_INDEX"
    if batches="$(widget_batch_count)"; then
        echo "    $(grep -c . "$RAW/parity-ids.txt") widget fixtures, $batches batches"
        index=0
        while [ "$index" -lt "$batches" ]; do
            run_batch "$WIDGET_CLASS" "$(printf 'testBatch%02d' "$index")"
            index=$((index + 1))
        done
    else
        echo "    the app's widget catalog could not be read, so no widget batch ran"
    fi
fi

xcrun simctl shutdown "$UDID" >/dev/null 2>&1

echo "==> gallery"
python3 -I "$ROOT/scripts/render/build_gallery.py" --src "$RAW" --out "$GALLERY" \
    || fail "build_gallery.py failed"

echo
echo "Ran $RAN batches. Gallery: $GALLERY/index.html (manifest: $GALLERY/manifest.md)"
if [ "${#FAILED[@]}" -gt 0 ]; then
    echo "Failed batches (run again with RENDER_ONLY='<Class/method>'):"
    printf '  %s\n' "${FAILED[@]}"
    exit 1
fi
