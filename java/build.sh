#!/bin/bash
# Build + test + chụp tour cho bản Java (chạy từ thư mục java/)
set -e
cd "$(dirname "$0")"
export JAVA_HOME=~/workspace/tools/jdk17
export PATH=$JAVA_HOME/bin:$PATH
CP=$(ls libs/*.jar | tr '\n' ':')

mkdir -p build shots
python3 tools/make_signs.py >/dev/null
javac -encoding UTF-8 -cp "$CP" -d build $(find src -name '*.java')
echo "== compile OK =="
java -cp "build" com.giangho.game.WorldTest

if [ "$1" = "tour" ]; then
  xvfb-run -a -s "-screen 0 1280x800x24" java -cp "build:$CP" com.giangho.game.ScreenshotMain
  echo "== tour xong: shots/ =="
  ls -la shots/
fi
