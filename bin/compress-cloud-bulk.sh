#!/usr/bin/env bash
# ==============================================================================
# Bulk compress existing .age cloud files to .gz.age (PARALLEL)
# ==============================================================================
# Converts .age files to .gz.age for compressible formats:
#   decrypt .age → gzip → re-encrypt as .gz.age → remove old .age
#
# Skips already-compressed formats (images, video, archives, etc.)
# Skips files that already have a .gz.age counterpart.
# Uses xargs -P for parallel processing across multiple CPU cores.
#
# Usage: bash compress-cloud-bulk.sh [--dry-run] [--project NAME] [--jobs N]
# ==============================================================================

set -euo pipefail

CLOUD_ROOT="/Volumes/TMS WORK DRIVE - 4 TB/Dropbox/Backups/Checkpoint"
KEY_PATH="${ENCRYPTION_KEY_PATH:-$HOME/.config/checkpoint/age-key.txt}"
DRY_RUN=false
TARGET_PROJECT=""
JOBS=12
LOG_FILE="/tmp/checkpoint-bulk-compress-$(date +%Y%m%d_%H%M%S).log"

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

RECIPIENT=$(age-keygen -y "$KEY_PATH" 2>/dev/null)
if [[ -z "$RECIPIENT" ]]; then
    echo "ERROR: Could not extract public key from $KEY_PATH" >&2
    exit 1
fi

# Progress tracking files (atomic counters via temp files)
PROGRESS_DIR=$(mktemp -d)
trap "rm -rf '$PROGRESS_DIR'" EXIT
echo "0" > "$PROGRESS_DIR/converted"
echo "0" > "$PROGRESS_DIR/skipped"
echo "0" > "$PROGRESS_DIR/failed"

echo "=============================================="
echo "Checkpoint Cloud Bulk Compress (.age → .gz.age)"
echo "Started: $(date)"
echo "Cloud root: $CLOUD_ROOT"
echo "Parallel jobs: $JOBS"
echo "Dry run: $DRY_RUN"
echo "Target: ${TARGET_PROJECT:-all projects}"
echo "Log: $LOG_FILE"
echo "=============================================="
echo ""

# Export worker function as a standalone script
WORKER_SCRIPT="$PROGRESS_DIR/worker.sh"
cat > "$WORKER_SCRIPT" <<'WORKER'
#!/usr/bin/env bash
set -uo pipefail

KEY_PATH="$1"
RECIPIENT="$2"
DRY_RUN="$3"
PROGRESS_DIR="$4"
LOG_FILE="$5"
age_file="$6"

# Get original name (strip .age)
original_name="${age_file%.age}"
basename_original=$(basename "$original_name")
gz_age_file="${original_name}.gz.age"

# Check if already-compressed format → skip
is_skip=false
case "${basename_original,,}" in
    *.gz|*.tgz|*.zip|*.7z|*.rar|*.bz2|*.xz|*.zst|*.lz4|*.lzma) is_skip=true ;;
    *.jpg|*.jpeg|*.png|*.gif|*.webp|*.avif|*.ico|*.svg) is_skip=true ;;
    *.mp4|*.mp3|*.mov|*.avi|*.mkv|*.webm|*.flac|*.aac|*.ogg) is_skip=true ;;
    *.woff|*.woff2|*.ttf|*.otf) is_skip=true ;;
    *.pdf|*.doc|*.docx|*.xlsx|*.pptx) is_skip=true ;;
    *.jar|*.war|*.ear|*.whl|*.egg) is_skip=true ;;
    *.pxm|*.psd|*.ai|*.indd) is_skip=true ;;
esac

if [[ "$is_skip" == "true" ]]; then
    # Atomic increment skip counter
    echo "1" >> "$PROGRESS_DIR/skipped"
    exit 0
fi

# Already has .gz.age → just remove old .age
if [[ -f "$gz_age_file" ]]; then
    rm -f "$age_file"
    echo "1" >> "$PROGRESS_DIR/converted"
    exit 0
fi

if [[ "$DRY_RUN" == "true" ]]; then
    echo "1" >> "$PROGRESS_DIR/converted"
    exit 0
fi

# Create secure temp dir
tmp_dir=$(mktemp -d)
base=$(basename "$original_name")
tmp_decrypted="$tmp_dir/$base"

# Decrypt → gzip → re-encrypt
if ! age -d -i "$KEY_PATH" -o "$tmp_decrypted" "$age_file" 2>/dev/null; then
    echo "FAILED decrypt: $age_file" >> "$LOG_FILE"
    echo "1" >> "$PROGRESS_DIR/failed"
    rm -rf "$tmp_dir"
    exit 1
fi

if ! gzip -f "$tmp_decrypted" 2>/dev/null; then
    echo "FAILED gzip: $age_file" >> "$LOG_FILE"
    echo "1" >> "$PROGRESS_DIR/failed"
    rm -rf "$tmp_dir"
    exit 1
fi

if ! age -r "$RECIPIENT" -o "$gz_age_file" "$tmp_dir/${base}.gz" 2>/dev/null; then
    echo "FAILED re-encrypt: $age_file" >> "$LOG_FILE"
    echo "1" >> "$PROGRESS_DIR/failed"
    rm -rf "$tmp_dir"
    rm -f "$gz_age_file"
    exit 1
fi

if [[ ! -s "$gz_age_file" ]]; then
    echo "FAILED verification: $age_file" >> "$LOG_FILE"
    echo "1" >> "$PROGRESS_DIR/failed"
    rm -f "$gz_age_file"
    rm -rf "$tmp_dir"
    exit 1
fi

# Success
rm -f "$age_file"
rm -rf "$tmp_dir"
echo "1" >> "$PROGRESS_DIR/converted"
exit 0
WORKER
chmod +x "$WORKER_SCRIPT"

# Build file list
FILE_LIST="$PROGRESS_DIR/file_list.txt"
for project_dir in "$CLOUD_ROOT"/*/; do
    [[ -d "$project_dir" ]] || continue
    pname=$(basename "$project_dir")

    if [[ -n "$TARGET_PROJECT" ]] && [[ "$pname" != "$TARGET_PROJECT" ]]; then
        continue
    fi

    find "$project_dir" -type f \
        -name "*.age" \
        ! -name "*.gz.age" \
        ! -path "*/.checkpoint-manifests/*" \
        -print0 2>/dev/null >> "$FILE_LIST" || true
done

TOTAL=$(tr -cd '\0' < "$FILE_LIST" | wc -c | tr -d ' ')
echo "Total .age files to process: $TOTAL"
echo "Processing with $JOBS parallel workers..."
echo ""

# Progress monitor in background
(
    while true; do
        sleep 10
        converted=$(wc -l < "$PROGRESS_DIR/converted" 2>/dev/null | tr -d ' ' || echo "0")
        skipped=$(wc -l < "$PROGRESS_DIR/skipped" 2>/dev/null | tr -d ' ' || echo "0")
        failed=$(wc -l < "$PROGRESS_DIR/failed" 2>/dev/null | tr -d ' ' || echo "0")
        done_count=$((converted + skipped + failed))
        if [[ $TOTAL -gt 0 ]]; then
            pct=$((done_count * 100 / TOTAL))
        else
            pct=100
        fi
        echo "  Progress: $done_count / $TOTAL ($pct%) — $converted converted, $skipped skipped, $failed failed"
        if [[ $done_count -ge $TOTAL ]]; then
            break
        fi
    done
) &
MONITOR_PID=$!

# Run parallel workers
# Note: -n1 passes filename as last positional arg (safe with quotes/special chars)
# Worker receives: $1=KEY_PATH $2=RECIPIENT $3=DRY_RUN $4=PROGRESS_DIR $5=LOG_FILE $6=age_file
xargs -0 -P "$JOBS" -n1 bash "$WORKER_SCRIPT" "$KEY_PATH" "$RECIPIENT" "$DRY_RUN" "$PROGRESS_DIR" "$LOG_FILE" < "$FILE_LIST"

# Stop monitor
kill $MONITOR_PID 2>/dev/null || true
wait $MONITOR_PID 2>/dev/null || true

# Final counts
converted=$(wc -l < "$PROGRESS_DIR/converted" 2>/dev/null | tr -d ' ' || echo "0")
skipped=$(wc -l < "$PROGRESS_DIR/skipped" 2>/dev/null | tr -d ' ' || echo "0")
failed=$(wc -l < "$PROGRESS_DIR/failed" 2>/dev/null | tr -d ' ' || echo "0")

echo ""
echo "=============================================="
echo "COMPLETE"
echo "Total .age files checked: $TOTAL"
echo "Converted to .gz.age: $converted"
echo "Skipped (already-compressed formats): $skipped"
echo "Failed: $failed"
echo "Finished: $(date)"
echo "=============================================="
