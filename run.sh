#!/bin/bash
set -e

echo "==> Building NexWave Network Workbench..."
swift build -c release

APP_DIR="NexWave Network Workbench.app"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
cp .build/release/NexWaveApp "$APP_DIR/Contents/MacOS/NexWaveApp"
if [ -f "AppIcon.icns" ]; then
    cp AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

echo "==> Launching NexWave Network Workbench..."
open "$APP_DIR"
echo "==> Application active!"
