#!/system/bin/sh
# ============================================================
#  DAVION09 ENGINE — Action Handler
#  Author: Jeric Aparicio
#  1. Opens WebUI in external browser
#  2. Fetches latest files from GitHub via manifest.txt
# ============================================================

MODID="GovThermal"
MODDIR="/data/adb/modules/$MODID"
TMP="/data/local/tmp/davion_ota"
LOG="$MODDIR/ota.log"
BB="$MODDIR/busybox"
WEBUI_URL="http://127.0.0.1:8080"

GITHUB_USER="Jeric2294"
GITHUB_REPO="DAVION-ENGINE-09"
BRANCH="main"

MANIFEST_URL="https://raw.githubusercontent.com/$GITHUB_USER/$GITHUB_REPO/$BRANCH/manifest.txt"

log() { echo "[$(date '+%H:%M:%S')] $1" | tee -a "$LOG"; }

# ── HEADER ───────────────────────────────────────────────────
ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ui_print "  DAVION09 ENGINE — Action"
ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "=== ACTION START ==="

# ── STEP 1: ENSURE WEBUI IS RUNNING ─────────────────────────
ui_print ""
ui_print "⚙ Starting WebUI..."

pkill -f "httpd.*8080" 2>/dev/null
sleep 1
"$BB" httpd \
    -p 8080 \
    -h "$MODDIR/webroot" \
    -c "$MODDIR/httpd.conf" \
    >>"$LOG" 2>&1 &
sleep 1

ui_print "✔ WebUI running → $WEBUI_URL"
log "WebUI started"

# ── STEP 2: CHECK NETWORK ────────────────────────────────────
ui_print ""
ui_print "⚙ Checking for updates..."
if ! ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
    ui_print "  (No internet — skipping update)"
    log "No network — skipped"
    ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    exit 0
fi

# ── STEP 3: DOWNLOAD MANIFEST ────────────────────────────────
mkdir -p "$TMP"
log "Fetching manifest: $MANIFEST_URL"

"$BB" wget -q --timeout=10 --tries=3 \
    -O "$TMP/manifest.txt" "$MANIFEST_URL" 2>/dev/null

if [ ! -s "$TMP/manifest.txt" ]; then
    ui_print "  (Cannot reach GitHub — skipping update)"
    log "ERROR: manifest download failed"
    rm -rf "$TMP"
    ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    exit 0
fi
log "Manifest downloaded"

# ── STEP 4: FETCH EACH FILE ──────────────────────────────────
ui_print "↓ Fetching latest files from GitHub..."
updated=0
failed=0

while IFS= read -r line; do
    # Skip empty lines and comments
    [ -z "$line" ] && continue
    case "$line" in \#*) continue ;; esac

    # Format: relative_path download_url
    rel_path=$(echo "$line" | cut -d' ' -f1)
    url=$(echo "$line"      | cut -d' ' -f2-)

    [ -z "$rel_path" ] || [ -z "$url" ] && continue

    target="$MODDIR/$rel_path"
    mkdir -p "$(dirname "$target")" 2>/dev/null

    if "$BB" wget -q --timeout=15 --tries=3 \
        -O "$TMP/tmpfile" "$url" 2>/dev/null \
        && [ -s "$TMP/tmpfile" ]; then
        cp "$TMP/tmpfile" "$target"
        chmod 755 "$target" 2>/dev/null
        log "✔ $rel_path"
        updated=$((updated + 1))
    else
        log "✗ FAILED: $rel_path"
        failed=$((failed + 1))
    fi

done < "$TMP/manifest.txt"

# ── STEP 5: FIX PERMISSIONS ──────────────────────────────────
find "$MODDIR" -name "*.sh"           -exec chmod +x {} \; 2>/dev/null
find "$MODDIR/script_runner"  -type f -exec chmod +x {} \; 2>/dev/null
find "$MODDIR/logcat_detection" -type f -exec chmod +x {} \; 2>/dev/null
find "$MODDIR/webroot/cgi-bin" -type f -exec chmod +x {} \; 2>/dev/null
chmod +x "$MODDIR/busybox" 2>/dev/null

# ── STEP 6: RESTART WEBUI ────────────────────────────────────
if [ "$updated" -gt 0 ]; then
    ui_print "⚙ Restarting WebUI..."
    pkill -f "httpd.*8080" 2>/dev/null
    pkill -f "busybox.*8080" 2>/dev/null
    sleep 1
    "$BB" httpd \
        -p 8080 \
        -h "$MODDIR/webroot" \
        -c "$MODDIR/httpd.conf" \
        >>"$LOG" 2>&1 &
    sleep 1
    ui_print "✔ WebUI restarted — refresh browser"
    log "httpd restarted"
fi

# ── CLEANUP ──────────────────────────────────────────────────
rm -rf "$TMP"
log "Cleanup done"

# ── DONE ─────────────────────────────────────────────────────
ui_print ""
ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ "$updated" -gt 0 ]; then
    ui_print "  ✔ Updated $updated file(s)!"
    [ "$failed" -gt 0 ] && ui_print "  ⚠ Failed: $failed file(s)"
else
    ui_print "  ✔ Already up to date!"
fi
ui_print "  No reboot needed."
ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "=== ACTION DONE (updated=$updated failed=$failed) ==="
exit 0
