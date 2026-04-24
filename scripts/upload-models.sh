#!/usr/bin/env bash
#
# Zips the two Moonshine ORT model bundles from the user's Application Support
# directory and uploads them as assets of a GitHub Release.
#
# Usage:
#   scripts/upload-models.sh [release-tag]
#
#     release-tag — defaults to "models-v1"
#
# Prerequisites:
#   - The `gh` CLI is installed and authenticated (`gh auth status`).
#   - Both model directories already exist at:
#       ~/Library/Application Support/SubFlow/MoonshineModels/small-streaming-en
#       ~/Library/Application Support/SubFlow/MoonshineModels/medium-streaming-en
#   - You have push access to Jinsong-Zhou/subflow.
#
# After running this script, paste the printed URLs and SHA-256 hashes into
# SubFlow/Services/ModelDownloader.swift → ModelSource.source(for:).

set -euo pipefail

TAG="${1:-models-v1}"
REPO="Jinsong-Zhou/subflow"
MODELS_ROOT="$HOME/Library/Application Support/SubFlow/MoonshineModels"
STAGING="$(mktemp -d -t subflow-model-upload)"
trap 'rm -rf "$STAGING"' EXIT

MODELS=("small-streaming-en" "medium-streaming-en")

echo "==> Verifying local model directories"
for m in "${MODELS[@]}"; do
  dir="$MODELS_ROOT/$m"
  if [[ ! -d "$dir" ]]; then
    echo "ERROR: missing model directory $dir" >&2
    echo "       Run SubFlow once with the models in place, then re-run this script." >&2
    exit 1
  fi
  for f in adapter.ort cross_kv.ort decoder_kv.ort decoder_kv_with_attention.ort encoder.ort frontend.ort streaming_config.json tokenizer.bin; do
    if [[ ! -s "$dir/$f" ]]; then
      echo "ERROR: $dir/$f is missing or empty" >&2
      exit 1
    fi
  done
  echo "    OK: $m"
done

echo
echo "==> Zipping models into $STAGING"
for m in "${MODELS[@]}"; do
  ( cd "$MODELS_ROOT" && zip -q -r "$STAGING/$m.zip" "$m" )
  size=$(du -h "$STAGING/$m.zip" | cut -f1)
  echo "    $m.zip  ($size)"
done

echo
echo "==> Creating / reusing release '$TAG' on $REPO"
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  echo "    Release '$TAG' already exists — will replace assets."
else
  gh release create "$TAG" \
    --repo "$REPO" \
    --title "Moonshine model assets ($TAG)" \
    --notes "Pre-packaged Moonshine ORT streaming model bundles consumed by SubFlow at runtime. Do not delete — SubFlow releases depend on these asset URLs." \
    >/dev/null
fi

echo
echo "==> Uploading assets (this can take a while — ~450 MB total)"
for m in "${MODELS[@]}"; do
  echo "    uploading $m.zip ..."
  gh release upload "$TAG" "$STAGING/$m.zip" --repo "$REPO" --clobber
done

echo
echo "==> SHA-256 hashes (paste into ModelSource.source(for:) in ModelDownloader.swift)"
for m in "${MODELS[@]}"; do
  hash=$(shasum -a 256 "$STAGING/$m.zip" | awk '{print $1}')
  url="https://github.com/$REPO/releases/download/$TAG/$m.zip"
  echo
  echo "    $m:"
  echo "      url:  $url"
  echo "      sha256: $hash"
done

echo
echo "Done. Update ModelDownloader.swift then commit the change."
