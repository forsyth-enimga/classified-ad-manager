#!/usr/bin/env bash
# Generates the android/, windows/ and linux/ runner folders (they are not
# stored in the repo), sets Android minSdk to 26 (Android 8.0) and fetches
# packages. Run once after cloning:  bash tool/setup_platforms.sh
set -euo pipefail
cd "$(dirname "$0")/.."

# flutter create must not clobber our own files.
mkdir -p .setup_backup
cp lib/main.dart pubspec.yaml analysis_options.yaml .setup_backup/

flutter create --platforms=android,windows,linux \
  --project-name classified_ad_manager --org ca.classifiedadmanager .

cp .setup_backup/main.dart lib/main.dart
cp .setup_backup/pubspec.yaml pubspec.yaml
cp .setup_backup/analysis_options.yaml analysis_options.yaml
rm -rf .setup_backup test/widget_test.dart

# Android 8.0 (API 26) minimum. Handles both Groovy and Kotlin DSL templates.
for f in android/app/build.gradle android/app/build.gradle.kts; do
  if [ -f "$f" ]; then
    sed -i -E 's/(minSdk(Version)?[ =]+)flutter\.minSdkVersion/\1 26/' "$f"
    echo "--- $f"; grep -n "minSdk" "$f"
  fi
done

flutter pub get
