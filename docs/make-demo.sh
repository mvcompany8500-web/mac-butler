#!/bin/zsh
# Rebuild docs/demo.gif from the app's real HUD (off-screen; nothing on your screen is captured).
#   ./docs/make-demo.sh [path/to/Sasarisa.app]
set -e
cd "${0:a:h}/.."
APP=${1:-build-local/Sasarisa.app}
D=$(mktemp -d)
"$APP/Contents/MacOS/${${APP:t}:r}" --demo-frames "$D"
# timing: title 1.6 s, then per scene: listening 0.7 s, result 1.7 s
LIST=$D/list.txt; : > $LIST
for f in $D/f*.png; do
  n=${${f:t:r}#f}; n=$((10#$n))
  d=1.7; (( n == 0 )) && d=1.6; (( n > 0 && n % 2 == 1 )) && d=0.7
  echo "file '$f'" >> $LIST; echo "duration $d" >> $LIST
done
echo "file '$f'" >> $LIST
ffmpeg -loglevel error -y -f concat -safe 0 -i $LIST -vf "fps=10,scale=960:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=96[p];[b][p]paletteuse=dither=bayer:bayer_scale=4" docs/demo.gif
ffmpeg -loglevel error -y -i $D/f002.png -vf "scale=1280:-1" docs/demo-still.png
rm -rf $D
ls -la docs/demo.gif docs/demo-still.png
