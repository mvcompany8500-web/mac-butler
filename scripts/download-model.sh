#!/bin/zsh
# Downloads Whisper large-v3-turbo (q8, 874 MB) from the official whisper.cpp repo on Hugging Face
# and verifies its SHA-256 (published by Hugging Face for this file) before using it.
set -e
DIR=${MACBUTLER_HOME:-$HOME/.macbutler}/models
F=$DIR/ggml-large-v3-turbo-q8_0.bin
SHA=317eb69c11673c9de1e1f0d459b253999804ec71ac4c23c17ecf5fbe24e259a1
mkdir -p "$DIR"
check() { [[ "$(shasum -a 256 "$1" | cut -d' ' -f1)" == "$SHA" ]]; }
if [[ -s "$F" ]] && check "$F"; then echo "✓ model already at $F (checksum OK)"; exit 0; fi
echo "› downloading Whisper model (874 MB) → $F"
curl -L --fail --proto '=https' --tlsv1.2 --progress-bar -o "$F.part" "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q8_0.bin"
if ! check "$F.part"; then rm -f "$F.part"; echo "✗ checksum mismatch — download discarded"; exit 1; fi
mv "$F.part" "$F"
echo "✓ done (checksum OK)"
