#!/bin/zsh
# Downloads Whisper large-v3-turbo (q8, 874 MB) from the official whisper.cpp repo on Hugging Face.
set -e
DIR=${MACBUTLER_HOME:-$HOME/.macbutler}/models
F=$DIR/ggml-large-v3-turbo-q8_0.bin
mkdir -p "$DIR"
if [[ -s "$F" ]]; then echo "✓ model already at $F"; exit 0; fi
echo "› downloading Whisper model (874 MB) → $F"
curl -L --fail --progress-bar -o "$F.part" "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q8_0.bin"
mv "$F.part" "$F"
echo "✓ done"
