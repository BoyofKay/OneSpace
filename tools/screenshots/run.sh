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
  if ! flutter drive -d emulator-5554 \
      --driver=test_driver/integration_test.dart \
      --target=integration_test/screenshots_test.dart \
      --dart-define=DEMO_PASSWORD="$DEMO_PASSWORD" \
      --dart-define=SHOT_SET="$set_name" --dart-define=SHOT_LANG="$lang" \
      2>&1 | tee "build/logs/$spec.log"; then
    echo "::warning::Screens $spec failed"; status=1
  fi
  echo "::endgroup::"
done
ls -1 build/screenshots | wc -l
exit $status
