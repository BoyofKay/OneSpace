#!/usr/bin/env bash
# R80: runs the screenshot robot once per set (core/themes/together × en/ar) on
# the emulator started by .github/workflows/screenshots.yml.
set -uo pipefail
mkdir -p build/screenshots build/logs
adb shell settings put global window_animation_scale 1 || true
adb shell settings put global transition_animation_scale 1 || true
adb shell settings put global animator_duration_scale 1 || true
status=0
for spec in ${SHOT_SETS//,/ }; do
  set_name="${spec%-*}"; lang="${spec#*-}"
  echo "::group::Screens $set_name ($lang)"
  if [ "$set_name" = "video" ]; then
    mkdir -p build/videos
    : > "build/videos/segments_$lang.txt"
    ( for i in $(seq 1 12); do
        [ -f /tmp/stop_rec ] && break
        t=$(adb shell 'echo $EPOCHREALTIME' | tr -d '\r')
        echo "$i $t" >> "build/videos/segments_$lang.txt"
        adb shell screenrecord --bit-rate 8000000 --size 720x1600 --time-limit 175 "/sdcard/rec_${lang}_$i.mp4" || break
      done ) &
    rec_pid=$!
    rm -f /tmp/stop_rec
  fi
  if ! flutter drive -d emulator-5554 \
      --driver=test_driver/integration_test.dart \
      --target=integration_test/screenshots_test.dart \
      --dart-define=DEMO_PASSWORD="$DEMO_PASSWORD" \
      --dart-define=SHOT_SET="$set_name" --dart-define=SHOT_LANG="$lang" \
      2>&1 | tee "build/logs/$spec.log"; then
    echo "::warning::Screens $spec failed"; status=1
  fi
  if [ "$set_name" = "video" ]; then
    touch /tmp/stop_rec
    adb shell pkill -INT screenrecord || true
    sleep 4; kill "$rec_pid" 2>/dev/null || true
    for f in $(adb shell ls /sdcard/ | tr -d '\r' | grep "^rec_${lang}_"); do adb pull "/sdcard/$f" "build/videos/$f" >/dev/null; done
    cp "build/logs/$spec.log" "build/videos/markers_$lang.log"
    python3 tools/screenshots/cut_clips.py "$lang" || echo "::warning::clip cutting failed"
    rm -f build/videos/rec_*.mp4
  fi
  echo "::endgroup::"
done
ls -1 build/screenshots | wc -l
exit $status
