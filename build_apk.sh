#!/bin/bash
set -e

export ANDROID_HOME=/home/runner/android-sdk
export PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools
export JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java))))

# Фикс для песочницы Replit: отключаем JVM shared-memory и daemon
export GRADLE_OPTS="-XX:+PerfDisableSharedMem -Xmx1g -Xms256m -Dorg.gradle.daemon=false"
export _JAVA_OPTIONS="-XX:+PerfDisableSharedMem -Dfile.encoding=UTF-8"
export GRADLE_USER_HOME=/home/runner/.gradle

LOG=/home/runner/workspace/build.log
echo "=== Сборка APK начата: $(date) ===" | tee $LOG
echo "ANDROID_HOME=$ANDROID_HOME" | tee -a $LOG
echo "JAVA_HOME=$JAVA_HOME" | tee -a $LOG
echo "Свободно: $(df -h /home/runner/ | tail -1 | awk '{print $4}')" | tee -a $LOG

echo "[1/2] flutter pub get..." | tee -a $LOG
flutter pub get 2>&1 | tee -a $LOG

echo "" | tee -a $LOG
echo "[2/2] flutter build apk --debug (no-daemon)..." | tee -a $LOG

# Добавляем --no-daemon в gradle.properties
mkdir -p android
cat > android/gradle.properties << 'GRADLE_PROPS'
org.gradle.jvmargs=-Xmx1g -XX:+PerfDisableSharedMem -Dfile.encoding=UTF-8
org.gradle.daemon=false
org.gradle.parallel=false
org.gradle.caching=false
android.useAndroidX=true
android.enableJetifier=true
GRADLE_PROPS

flutter build apk --debug 2>&1 | tee -a $LOG

APK_DEBUG=build/app/outputs/flutter-apk/app-debug.apk
APK_RELEASE=build/app/outputs/flutter-apk/app-release.apk

if [ -f "$APK_DEBUG" ]; then
  SIZE=$(du -sh $APK_DEBUG | cut -f1)
  echo "" | tee -a $LOG
  echo "=====================================" | tee -a $LOG
  echo "✅ DEBUG APK СОБРАН! Размер: $SIZE" | tee -a $LOG
  echo "📁 Путь: $APK_DEBUG" | tee -a $LOG
  echo "=====================================" | tee -a $LOG
elif [ -f "$APK_RELEASE" ]; then
  SIZE=$(du -sh $APK_RELEASE | cut -f1)
  echo "✅ RELEASE APK СОБРАН! Размер: $SIZE" | tee -a $LOG
  echo "📁 Путь: $APK_RELEASE" | tee -a $LOG
else
  echo "❌ APK не найден — смотри лог выше" | tee -a $LOG
  exit 1
fi
