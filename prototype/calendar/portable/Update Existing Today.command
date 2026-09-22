#!/bin/bash
set -euo pipefail
TODAY_RELEASE_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$TODAY_RELEASE_DIR/Today.app/Contents/MacOS/TodayUpdateHelper" --choose "$TODAY_RELEASE_DIR"
