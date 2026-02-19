#!/usr/bin/env bash
# ==============================================================================
# Bulk compress + encrypt all plaintext cloud backup files (PARALLEL)
# ==============================================================================
# Finds every non-.age file in the cloud backup folder.
# For each: compress (if compressible) → encrypt → verify → remove plaintext.
# Uses xargs -P for parallel processing across multiple CPU cores.
#
# Usage: bash encrypt-cloud-bulk.sh [--dry-run] [--project NAME] [--jobs N]
# ==============================================================================

set -euo pipefail

CLOUD_ROOT="/Volumes/TMS WORK DRIVE - 4 TB/Dropbox/Backups/Checkpoint"
KEY_PATH="${ENCRYPTION_KEY_PATH:-$HOME/.config/checkpoint/age-key.txt}"
DRY_RUN=false
TARGET_PROJECT=""
JOBS=$(( $(sysctl -n hw.ncpu 2>/dev/null || echo 4) / 2 ))
[[ $JOBS -lt 2 ]] && JOBS=2
LOG_FILE="/tmp/checkpoint-bulk-encrypt-$(date +%Y%m%d_%H%M%S).log"

# Parse args
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=true; shift ;;
        --project) TARGET_PROJECT="$2"; shift 2 ;;
        --jobs) JOBS="$2"; shift 2 ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done

# Verify prerequisites
if ! command -v age &>/dev/null; then
    echo "ERROR: age is not installed" >&2
    exit 1
fi

if [[ ! -f "$KEY_PATH" ]]; then
    echo "ERROR: age key not found at $KEY_PATH" >&2
    exit 1
fi

if [[ ! -d "$CLOUD_ROOT" ]]; then
    echo "ERROR: Cloud root not found: $CLOUD_ROOT" >&2
    exit 1
fi

# Get recipient from key
RECIPIENT=$(age-keygen -y "$KEY_PATH" 2>/dev/null)
if [[ -z "$RECIPIENT" ]]; then
    echo "ERROR: Could not extract public key from $KEY_PATH" >&2
    exit 1
fi

# Progress tracking
PROGRESS_DIR=$(mktemp -d)
trap "rm -rf '$PROGRESS_DIR'" EXIT
echo -n > "$PROGRESS_DIR/encrypted"
echo -n > "$PROGRESS_DIR/skipped"
echo -n > "$PROGRESS_DIR/failed"

echo "=============================================="
echo "Checkpoint Cloud Bulk Encrypt + Compress"
echo "Started: $(date)"
echo "Cloud root: $CLOUD_ROOT"
echo "Parallel jobs: $JOBS"
echo "Dry run: $DRY_RUN"
echo "Target: ${TARGET_PROJECT:-all projects}"
echo "Log: $LOG_FILE"
echo "=============================================="
echo ""

# Write worker script
WORKER_SCRIPT="$PROGRESS_DIR/worker.sh"
cat > "$WORKER_SCRIPT" <<'WORKER'
#!/usr/bin/env bash
set -uo pipefail

KEY_PATH="$1"
RECIPIENT="$2"
DRY_RUN="$3"
PROGRESS_DIR="$4"
LOG_FILE="$5"
src_file="$6"

# Skip if .age or .gz.age counterpart already exists
if [[ -f "${src_file}.age" ]]; then
    rm -f "$src_file"
    echo "1" >> "$PROGRESS_DIR/skipped"
    exit 0
fi
if [[ -f "${src_file}.gz.age" ]]; then
    rm -f "$src_file"
    echo "1" >> "$PROGRESS_DIR/skipped"
    exit 0
fi

if [[ "$DRY_RUN" == "true" ]]; then
    echo "1" >> "$PROGRESS_DIR/encrypted"
    exit 0
fi

# Check if compressible
_skip_gz=false
case "${src_file,,}" in
    *.gz|*.tgz|*.zip|*.7z|*.rar|*.bz2|*.xz|*.zst|*.lz4|*.lzma) _skip_gz=true ;;
    *.jpg|*.jpeg|*.png|*.gif|*.webp|*.avif|*.ico|*.svg) _skip_gz=true ;;
    *.mp4|*.mp3|*.mov|*.avi|*.mkv|*.webm|*.flac|*.aac|*.ogg) _skip_gz=true ;;
    *.woff|*.woff2|*.ttf|*.otf) _skip_gz=true ;;
    *.pdf|*.doc|*.docx|*.xlsx|*.pptx) _skip_gz=true ;;
    *.jar|*.war|*.ear|*.whl|*.egg) _skip_gz=true ;;
    *.pxm|*.psd|*.ai|*.indd) _skip_gz=true ;;
    *.db.gz) _skip_gz=true ;;
esac

if [[ "$_skip_gz" == "true" ]]; then
    # Encrypt only
    if age -r "$RECIPIENT" -o "${src_file}.age" "$src_file" 2>>"$LOG_FILE"; then
        if [[ -s "${src_file}.age" ]]; then
            rm -f "$src_file"
            echo "1" >> "$PROGRESS_DIR/encrypted"
            exit 0
        else
            rm -f "${src_file}.age"
        fi
    fi
    echo "FAILED encrypt: $src_file" >> "$LOG_FILE"
    echo "1" >> "$PROGRESS_DIR/failed"
    exit 1
else
    # Compress then encrypt
    if gzip -f "$src_file" 2>>"$LOG_FILE"; then
        if age -r "$RECIPIENT" -o "${src_file}.gz.age" "${src_file}.gz" 2>>"$LOG_FILE"; then
            if [[ -s "${src_file}.gz.age" ]]; then
                rm -f "${src_file}.gz"
                echo "1" >> "$PROGRESS_DIR/encrypted"
                exit 0
            else
                rm -f "${src_file}.gz.age"
            fi
        fi
        # Encryption failed — restore from .gz
        gunzip -f "${src_file}.gz" 2>/dev/null
    else
        # gzip failed — encrypt without compression
        if age -r "$RECIPIENT" -o "${src_file}.age" "$src_file" 2>>"$LOG_FILE"; then
            if [[ -s "${src_file}.age" ]]; then
                rm -f "$src_file"
                echo "1" >> "$PROGRESS_DIR/encrypted"
                exit 0
            else
                rm -f "${src_file}.age"
            fi
        fi
    fi
    echo "FAILED: $src_file" >> "$LOG_FILE"
    echo "1" >> "$PROGRESS_DIR/failed"
    exit 1
fi
WORKER
chmod +x "$WORKER_SCRIPT"

# Build file list (null-delimited for safe filenames)
FILE_LIST="$PROGRESS_DIR/file_list.txt"
for project_dir in "$CLOUD_ROOT"/*/; do
    [[ -d "$project_dir" ]] || continue
    pname=$(basename "$project_dir")

    if [[ -n "$TARGET_PROJECT" ]] && [[ "$pname" != "$TARGET_PROJECT" ]]; then
        continue
    fi

    find "$project_dir" -type f \
        ! -name "*.age" \
        ! -name ".checkpoint-cloud-index.json" \
        ! -name ".checkpoint-state.json" \
        ! -name ".DS_Store" \
        ! -path "*/.checkpoint-manifests/*" \
        -print0 2>/dev/null >> "$FILE_LIST" || true
done

TOTAL=$(tr -cd '\0' < "$FILE_LIST" | wc -c | tr -d ' ')
echo "Total plaintext files to process: $TOTAL"
echo "Processing with $JOBS parallel workers..."
echo ""

# Progress monitor in background
(
    while true; do
        sleep 10
        _enc=$(wc -l < "$PROGRESS_DIR/encrypted" 2>/dev/null | tr -d ' ')
        _skip=$(wc -l < "$PROGRESS_DIR/skipped" 2>/dev/null | tr -d ' ')
        _fail=$(wc -l < "$PROGRESS_DIR/failed" 2>/dev/null | tr -d ' ')
        _done=$((_enc + _skip + _fail))
        if [[ $TOTAL -gt 0 ]]; then
            _pct=$((_done * 100 / TOTAL))
        else
            _pct=100
        fi
        echo "  Progress: $_done / $TOTAL ($_pct%) — $_enc encrypted, $_skip skipped, $_fail failed"
        if [[ $_done -ge $TOTAL ]]; then
            break
        fi
    done
) &
MONITOR_PID=$!

# Run parallel workers
xargs -0 -P "$JOBS" -n1 bash "$WORKER_SCRIPT" "$KEY_PATH" "$RECIPIENT" "$DRY_RUN" "$PROGRESS_DIR" "$LOG_FILE" < "$FILE_LIST"

# Stop monitor
kill $MONITOR_PID 2>/dev/null || true
wait $MONITOR_PID 2>/dev/null || true

# Final counts
_enc=$(wc -l < "$PROGRESS_DIR/encrypted" | tr -d ' ')
_skip=$(wc -l < "$PROGRESS_DIR/skipped" | tr -d ' ')
_fail=$(wc -l < "$PROGRESS_DIR/failed" | tr -d ' ')

echo ""
echo "=============================================="
echo "COMPLETE"
echo "Total plaintext files: $TOTAL"
echo "Encrypted (compressed+encrypted): $_enc"
echo "Skipped (already had .age counterpart): $_skip"
echo "Failed: $_fail"
echo "Finished: $(date)"
echo "=============================================="
