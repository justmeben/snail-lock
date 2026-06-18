#!/bin/bash
# Snail Lock installer — clone the repo and run this:
#
#   git clone https://github.com/justmeben/snail-lock.git
#   cd snail-lock
#   ./install.sh
#
# Builds the app from source (needs Xcode Command Line Tools), installs it to
# /Applications, writes ~/.snail_lock.conf, and launches it.

set -e
cd "$(dirname "$0")"

DEFAULT_PASSWORD="slug"
DEFAULT_MESSAGE="BRB — DO NOT TOUCH"

B="\033[1m"; R="\033[0m"; D="\033[2m"; G="\033[32m"; Y="\033[33m"
ok()   { printf "  ${G}✓${R} %s\n" "$1"; }
warn() { printf "  ${Y}!${R} %s\n" "$1"; }
fail() { printf "  ${Y}✗${R} %s\n" "$1"; exit 1; }

printf "\n${B}🐌  Snail Lock — installer${R}\n"
printf "${D}Fake-lock screen for macOS. Stops snoopers, doesn't actually lock the session.${R}\n\n"

# Reads from the controlling terminal directly so the script works even when
# itself is being piped from stdin (curl ... | bash).
ask() {
    local default=$1
    local val=""
    if [ -r /dev/tty ]; then
        IFS= read -r val </dev/tty || val=""
    fi
    printf "%s" "${val:-$default}"
}

# --- Read any existing config so re-installs reuse all user values ---
CFG="$HOME/.snail_lock.conf"
read_conf() {
    local key=$1
    [ -f "$CFG" ] || return
    grep -E "^[[:space:]]*${key}[[:space:]]*=" "$CFG" | head -1 | sed -E 's/^[^=]*=[[:space:]]*//'
}

EXISTING_PASSWORD="$(read_conf password)"
EXISTING_MESSAGE="$(read_conf message)"

if [ -n "$EXISTING_PASSWORD" ] && [ -n "$EXISTING_MESSAGE" ]; then
    PASSWORD="$EXISTING_PASSWORD"
    MESSAGE="$EXISTING_MESSAGE"
    printf "${D}Using existing config at %s — skipping prompts.${R}\n" "$CFG"
else
    # --- Prompt: password ---
    printf "${B}Password${R} ${D}(press Enter to use \"%s\"):${R}\n" "${EXISTING_PASSWORD:-$DEFAULT_PASSWORD}"
    printf "> "
    PASSWORD="$(ask "${EXISTING_PASSWORD:-$DEFAULT_PASSWORD}")"

    # --- Prompt: message ---
    printf "\n${B}On-screen message${R} for bystanders ${D}(Enter for \"%s\"):${R}\n" "${EXISTING_MESSAGE:-$DEFAULT_MESSAGE}"
    printf "> "
    MESSAGE="$(ask "${EXISTING_MESSAGE:-$DEFAULT_MESSAGE}")"
fi

printf "\n${B}Building…${R}\n"

# --- Build the app from source ---
if ! command -v swiftc >/dev/null 2>&1; then
    fail "swiftc not found. Install Xcode Command Line Tools (xcode-select --install) and retry."
fi
./build-app.sh >/dev/null
APP_SRC="Snail Lock.app"
if [ ! -x "$APP_SRC/Contents/MacOS/snail-lock" ]; then
    fail "Build produced no executable at $APP_SRC — check the swiftc output above."
fi
ok "Built $APP_SRC"

printf "\n${B}Installing…${R}\n"

# --- Strip quarantine + (re-)sign ad-hoc ---
xattr -cr "$APP_SRC" 2>/dev/null || true
codesign --force --deep --sign - "$APP_SRC" >/dev/null 2>&1 || true
ok "Cleared quarantine + ad-hoc signed"

# --- Install (ditto preserves bundle metadata; cp -R can drop attrs) ---
DEST="/Applications/Snail Lock.app"
rm -rf "$DEST" 2>/dev/null || true
if ditto "$APP_SRC" "$DEST" 2>/dev/null; then
    ok "Installed to /Applications"
else
    mkdir -p "$HOME/Applications"
    DEST="$HOME/Applications/Snail Lock.app"
    rm -rf "$DEST"
    ditto "$APP_SRC" "$DEST"
    ok "Installed to ~/Applications (no admin rights on /Applications)"
fi

# Quarantine can be re-applied by the file system at copy time; strip again on the installed copy.
xattr -cr "$DEST" 2>/dev/null || true

# --- Write config (all keys populated so they're easy to discover & edit) ---

# Preserve any existing customizations on re-install for keys we don't prompt for.
DEFAULT_UNLOCK_ICON="🐌"
DEFAULT_ICON_SET="🐌, 🐌, 🐌, 🐚, 🐛, 🌿, 🍃, 🌱, 🍄, 🪱"
DEFAULT_LOCK_HOTKEY="option+l"
DEFAULT_IMAGE_COUNT="5"
DEFAULT_IMAGE_SPIN="false"
UNLOCK_ICON="$(read_conf unlock_icon)"
ICON_SET="$(read_conf icon_set)"
LOCK_HOTKEY="$(read_conf lock_hotkey)"
IMAGE_PATH="$(read_conf image_path)"
IMAGE_COUNT="$(read_conf image_count)"
IMAGE_SPIN="$(read_conf image_spin)"
UNLOCK_ICON="${UNLOCK_ICON:-$DEFAULT_UNLOCK_ICON}"
ICON_SET="${ICON_SET:-$DEFAULT_ICON_SET}"
LOCK_HOTKEY="${LOCK_HOTKEY:-$DEFAULT_LOCK_HOTKEY}"
IMAGE_COUNT="${IMAGE_COUNT:-$DEFAULT_IMAGE_COUNT}"
IMAGE_SPIN="${IMAGE_SPIN:-$DEFAULT_IMAGE_SPIN}"

cat > "$CFG" <<EOF
# ~/.snail_lock.conf — Snail Lock settings.
# Edit any value below (or use the settings UI in the app).
# Lines starting with # are comments.

# Password the user has to type to unlock.
password=$PASSWORD

# Huge text shown on the lock screen for bystanders.
message=$MESSAGE

# Big clickable icon at the bottom of the screen that reveals the password
# prompt when tapped. Any single emoji or short text works.
unlock_icon=$UNLOCK_ICON

# Comma- or whitespace-separated list of emojis that fly around in the
# background. Repeats act as weights — listing an emoji multiple times makes
# it that much more likely to spawn.
icon_set=$ICON_SET

# Global hotkey that triggers the lock from anywhere.
# Format: cmd/shift/option/control + one key, joined by '+'. Example: option+l
lock_hotkey=$LOCK_HOTKEY

# Custom image (PNG / JPG / animated GIF) shown bouncing around alongside the
# emoji background. Leave image_path empty to disable.
image_path=$IMAGE_PATH
image_count=$IMAGE_COUNT
image_spin=$IMAGE_SPIN
EOF
chmod 600 "$CFG"
ok "Config written to $CFG"

# --- Launch (kill any previous instance first so the new binary actually runs) ---
pkill -x snail-lock 2>/dev/null && sleep 0.4
open "$DEST"
ok "Launched"

printf "\n${B}Done.${R}  Edit ${CFG} anytime; restart Snail Lock to apply message changes.\n"
printf "${D}If you ever get stuck behind it: ssh in (or open a remote shell) and run ${B}pkill -x snail-lock${R}.\n\n"
