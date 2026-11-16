#!/usr/bin/env bash
# R80: runs the screenshot robot once per set (core/themes/together × en/ar) on
# the emulator started by .github/workflows/screenshots.yml.
set -uo pipefail
mkdir -p build/screenshots build/logs
adb shell settings put global window_animation_scale 1 || true
adb shell settings put global transition_animation_scale 1 || true
adb shell settings put global animator_duration_scale 1 || true
# A lighter, phone-like screen (360×800 dp) and a tidy status bar (9:41, full battery).
adb root >/dev/null 2>&1 || true; sleep 2
adb shell setprop persist.sys.timezone Asia/Riyadh || true      # Omar lives in Riyadh
adb shell cmd overlay enable com.android.internal.systemui.navbar.gestural || true   # thin gesture bar
adb shell wm size 720x1600 || true
adb shell wm density 300 || true                                # 384 × 853 dp, a typical phone
adb shell settings put global sysui_demo_allowed 1 || true
adb shell am broadcast -a com.android.systemui.demo -e command enter >/dev/null || true
adb shell am broadcast -a com.android.systemui.demo -e command clock -e hhmm 0941 >/dev/null || true
adb shell am broadcast -a com.android.systemui.demo -e command battery -e level 100 -e plugged false >/dev/null || true
adb shell am broadcast -a com.android.systemui.demo -e command network -e wifi show -e level 4 -e mobile show -e datatype none -e level 4 >/dev/null || true
adb shell am broadcast -a com.android.systemui.demo -e command notifications -e visible false >/dev/null || true
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
  adb shell setprop debug.onespace.shots "$spec"
  adb shell setprop debug.onespace.pw "$DEMO_PASSWORD"
  if ! flutter drive -d emulator-5554 \
      --driver=test_driver/integration_test.dart \
      --target=integration_test/screenshots_test.dart \
      --use-application-binary=build/app/outputs/flutter-apk/app-debug.apk \
      2>&1 | python3 tools/screenshots/watch.py "build/logs/$spec.log"; then
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
