#!/usr/bin/env bash
# Force-stop the probe while it commits, then verify recovery on the device.
# Usage: tool/crash_check.sh <device-id> [delay-seconds]
set -euo pipefail
cd "$(dirname "$0")/.."
device=${1:?device id, e.g. emulator-5554}
delay=${2:-5}
package=org.bodytmi.bodytmi_android_probe
log=$(mktemp)
"${FLUTTER:-flutter}" --suppress-analytics test integration_test/crash_writer_test.dart \
  -d "$device" >"$log" 2>&1 &
writer=$!
for _ in $(seq 600); do
  grep -q BODYTMI_WRITER_READY "$log" && break
  kill -0 "$writer" 2>/dev/null || { cat "$log"; exit 1; }
  sleep 1
done
grep -q BODYTMI_WRITER_READY "$log" || { cat "$log"; exit 1; }
sleep "$delay"
adb -s "$device" shell am force-stop "$package"
echo "force-stopped $package after ${delay}s of committed writes"
wait "$writer" || true
rm -f "$log"
"${FLUTTER:-flutter}" --suppress-analytics test integration_test/crash_recovery_test.dart \
  -d "$device"
