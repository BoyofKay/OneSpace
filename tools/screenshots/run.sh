#!/usr/bin/env bash
# R80: runs the screenshot robot once per set (core/themes/together/video/tutorial × en/ar) on
# the emulator started by .github/workflows/screenshots.yml.
set -uo pipefail
mkdir -p build/screenshots build/logs
adb shell settings put global window_animation_scale 1 || true
adb shell settings put global transition_animation_scale 1 || true
adb shell settings put global animator_duration_scale 1 || true
# A lighter, phone-like screen (360×800 dp) and a tidy status bar (9:41, full battery).
prepare_device() {
  adb wait-for-device
  until [ "$(adb shell getprop sys.boot_completed | tr -d '\r')" = "1" ]; do sleep 2; done
  adb root >/dev/null 2>&1 || true
  sleep 3; adb wait-for-device
  until [ "$(adb shell getprop sys.boot_completed | tr -d '\r')" = "1" ]; do sleep 2; done
  adb shell setprop persist.sys.timezone America/Toronto || true  # Adam lives in Toronto
  adb shell cmd overlay enable com.android.internal.systemui.navbar.gestural || true   # thin gesture bar
  adb shell wm size 720x1600 || true
  adb shell wm density 300 || true                                # 384 × 853 dp, a typical phone
  adb shell settings put global window_animation_scale 1 || true
  adb shell settings put global sysui_demo_allowed 1 || true
  adb shell am broadcast -a com.android.systemui.demo -e command enter >/dev/null || true
  adb shell am broadcast -a com.android.systemui.demo -e command clock -e hhmm 0941 >/dev/null || true
  adb shell am broadcast -a com.android.systemui.demo -e command battery -e level 100 -e plugged false >/dev/null || true
  adb shell am broadcast -a com.android.systemui.demo -e command network -e wifi show -e level 4 -e mobile show -e datatype none -e level 4 >/dev/null || true
  adb shell am broadcast -a com.android.systemui.demo -e command notifications -e visible false >/dev/null || true
}
# If the emulator died during a set, start it again before the next one.
revive() {
  if [ "$(adb get-state 2>/dev/null)" != "device" ]; then
    echo "::warning::Emulator was lost — restarting it"
    adb emu kill >/dev/null 2>&1 || true; sleep 5
    nohup "$ANDROID_HOME/emulator/emulator" -avd test -no-window -gpu swiftshader_indirect -noaudio -no-boot-anim -camera-back none -no-snapshot >/dev/null 2>&1 &
    sleep 20
    prepare_device
  fi
}
prepare_device
adb shell settings put global sysui_demo_allowed 1 || true
adb shell am broadcast -a com.android.systemui.demo -e command enter >/dev/null || true
adb shell am broadcast -a com.android.systemui.demo -e command clock -e hhmm 0941 >/dev/null || true
adb shell am broadcast -a com.android.systemui.demo -e command battery -e level 100 -e plugged false >/dev/null || true
adb shell am broadcast -a com.android.systemui.demo -e command network -e wifi show -e level 4 -e mobile show -e datatype none -e level 4 >/dev/null || true
adb shell am broadcast -a com.android.systemui.demo -e command notifications -e visible false >/dev/null || true
status=0
for spec in ${SHOT_SETS//,/ }; do
  set_name="${spec%-*}"; lang="${spec#*-}"
  revive
  echo "::group::Screens $set_name ($lang)"
  if [ "$set_name" = "video" ] || [ "$set_name" = "tutorial" ]; then
    mkdir -p build/videos
    : > "build/videos/segments_$lang.txt"
    ( for i in $(seq 1 60); do
        [ -f /tmp/stop_rec ] && break
        t=$(adb shell 'echo $EPOCHREALTIME' | tr -d '\r')
        echo "$i $t" >> "build/videos/segments_$lang.txt"
        adb shell screenrecord --bit-rate 8000000 --size 720x1600 --time-limit 40 "/sdcard/rec_${lang}_$i.mp4" || break
      done ) &
    rec_pid=$!
    rm -f /tmp/stop_rec
  fi
  adb shell setprop debug.onespace.shots "$spec"
  adb shell setprop debug.onespace.pw "$DEMO_PASSWORD"
  if ! flutter drive -d emulator-5554 \
      --driver=test_driver/integration_test.dart \
      --target=integration_test/screenshots_test.dart \
      --flavor qa \
      --use-application-binary=build/app/outputs/flutter-apk/app-qa-debug.apk \
      2>&1 | python3 tools/screenshots/watch.py "build/logs/$spec.log"; then
    echo "::warning::Screens $spec failed"; status=1
  fi
  if [ "$set_name" = "video" ] || [ "$set_name" = "tutorial" ]; then
    touch /tmp/stop_rec
    adb shell pkill -INT screenrecord || true
    sleep 4; kill "$rec_pid" 2>/dev/null || true
    revive   # the finished segments survive an emulator crash on /sdcard
    for f in $(adb shell ls /sdcard/ | tr -d '\r' | grep "^rec_${lang}_"); do adb pull "/sdcard/$f" "build/videos/$f" >/dev/null; done
    cp "build/logs/$spec.log" "build/videos/markers_$lang.log"
    python3 tools/screenshots/cut_clips.py "$lang" || echo "::warning::clip cutting failed"
    rm -f build/videos/rec_*.mp4
  fi
  echo "::endgroup::"
done
ls -1 build/screenshots | wc -l
exit $status
