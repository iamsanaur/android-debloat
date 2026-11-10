#!/bin/sh
# debloat.sh - safe, reversible Android debloating without root or a PC.
#
# Runs anywhere a POSIX shell exists: Termux on the same phone, Termux on a
# second Android device, Linux, macOS, WSL. Packages are removed only for the
# current user (`pm uninstall --user 0`), so the APKs stay on the system
# partition and everything can be restored with `restore` or a factory reset.
#
# Usage: sh scripts/debloat.sh [options] <command> [args]
# Run `sh scripts/debloat.sh help` for details.

set -u

VERSION=1.0.0
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_DIR=$(dirname "$SCRIPT_DIR")
DENYLIST=${DENYLIST:-$REPO_DIR/lists/never-remove.txt}
OUT_DIR=${DEBLOAT_OUT:-$REPO_DIR/backups}
MODE=adb          # adb | rish | local
SERIAL=${ANDROID_SERIAL:-}
USER_ID=0
ASSUME_YES=0
KEEP_DATA=1
TMP=""

usage() {
	cat <<'EOF'
debloat.sh - safe, reversible Android debloater (no root needed)

USAGE
  sh scripts/debloat.sh [options] <command> [args]

OPTIONS
  -s SERIAL     target a specific adb device (see `adb devices`)
  --rish        send device commands through Shizuku's `rish` (no adb needed)
  --local       run `pm` directly (only when already inside a shell/root shell)
  -u USER       Android user id (default 0 = main user)
  -y            don't ask for confirmation
  --no-keep-data  wipe app data on uninstall (default keeps it, for easy restore)

COMMANDS
  check                    verify connection, show device info and suggested lists
  backup [DIR]             save full package inventory (do this FIRST)
  list [FILTER]            list installed packages (S=system, U=user app)
  plan LIST...             dry run: show what `apply` would do
  apply LIST...            uninstall packages for the user (reversible)
  disable LIST...          disable packages instead of uninstalling (reversible)
  restore PKG|FILE...      bring back packages (accepts names, lists or log files)
  restore-backup DIR       restore every package present when DIR was taken
  commands LIST...         print plain `pm` commands to paste in any adb shell app
  help                     show this help

A LIST is a text file with one package per line; `#` starts a comment.
Every change is logged to backups/actions-<device>.log, which is itself a
valid input for `restore`.
EOF
}

die()  { printf 'error: %s\n' "$*" >&2; exit 1; }
info() { printf '%s\n' "$*" >&2; }

cleanup() { [ -n "$TMP" ] && rm -rf "$TMP"; }
trap cleanup EXIT INT TERM

# Run a shell command on the target device, stripping CRs from old adb.
dev() {
	case $MODE in
	adb)
		if [ -n "$SERIAL" ]; then adb -s "$SERIAL" shell "$1"
		else adb shell "$1"; fi ;;
	rish)  "${RISH:-rish}" -c "$1" ;;
	local) sh -c "$1" ;;
	esac </dev/null | tr -d '\r'
}

valid_pkg() {
	case $1 in
	'' | *[!A-Za-z0-9_.]* | .* | *..*) return 1 ;;
	esac
	return 0
}

# Print package names from list files: strip comments/whitespace, dedupe.
read_list() {
	for f in "$@"; do
		[ -f "$f" ] || die "file not found: $f"
		sed -e 's/#.*//' -e 's/[[:space:]]//g' "$f"
	done | grep -v '^$' | sort -u
}

DENY=""
load_denylist() {
	[ -f "$DENYLIST" ] || die "safety denylist missing: $DENYLIST (refusing to continue)"
	DENY=$(read_list "$DENYLIST")
}

is_denied() {
	set -f
	for pat in $DENY; do
		# shellcheck disable=SC2254
		case $1 in $pat) set +f; return 0 ;; esac
	done
	set +f
	return 1
}

need_tmp() { [ -n "$TMP" ] || TMP=$(mktemp -d "${TMPDIR:-/tmp}/debloat.XXXXXX") || die "mktemp failed"; }

preflight() {
	if [ "$MODE" = adb ]; then
		command -v adb >/dev/null 2>&1 ||
			die "adb not found. Termux: pkg install android-tools | Linux: install android-platform-tools"
	elif [ "$MODE" = rish ]; then
		command -v "${RISH:-rish}" >/dev/null 2>&1 ||
			die "rish not found. Export it from Shizuku (\"Use Shizuku in terminal apps\") and add it to PATH"
	fi
	out=$(dev 'echo debloat-ok' 2>&1)
	case $out in
	*debloat-ok*) ;;
	*) die "cannot reach device: $out" ;;
	esac
}

device_tag() {
	dev 'echo "$(getprop ro.product.manufacturer)-$(getprop ro.product.model)"' |
		tr ' /' '__' | tr -cd 'A-Za-z0-9_.-'
}

refresh_installed() {
	need_tmp
	dev "pm list packages --user $USER_ID" | sed -n 's/^package://p' | sort -u >"$TMP/installed"
	[ -s "$TMP/installed" ] || die "could not read package list from device"
}

is_installed() { grep -Fxq "$1" "$TMP/installed"; }

log_file() { mkdir -p "$OUT_DIR" && printf '%s/actions-%s.log' "$OUT_DIR" "$(device_tag)"; }

log_action() { # pkg action
	printf '%s  # %s %s user=%s\n' "$1" "$2" "$(date '+%Y-%m-%dT%H:%M:%S')" "$USER_ID" >>"$LOG"
}

confirm() {
	[ "$ASSUME_YES" -eq 1 ] && return 0
	printf '%s [y/N] ' "$1" >&2
	read -r ans || return 1
	case $ans in y | Y | yes | YES) return 0 ;; esac
	return 1
}

# Classify packages from lists. Writes $TMP/todo; prints a report.
build_plan() {
	load_denylist
	refresh_installed
	: >"$TMP/todo"
	n_do=0 n_skip=0 n_block=0 n_bad=0
	for pkg in $(read_list "$@"); do
		if ! valid_pkg "$pkg"; then
			printf '  INVALID   %s\n' "$pkg"; n_bad=$((n_bad + 1))
		elif is_denied "$pkg"; then
			printf '  BLOCKED   %s  (in never-remove list)\n' "$pkg"; n_block=$((n_block + 1))
		elif ! is_installed "$pkg"; then
			n_skip=$((n_skip + 1))
		else
			printf '  TARGET    %s\n' "$pkg"; echo "$pkg" >>"$TMP/todo"; n_do=$((n_do + 1))
		fi
	done
	printf '\n%s to act on, %s not installed (skipped), %s blocked, %s invalid\n' \
		"$n_do" "$n_skip" "$n_block" "$n_bad"
}

cmd_check() {
	preflight
	[ "$MODE" = adb ] && adb devices -l
	dev 'echo "Manufacturer : $(getprop ro.product.manufacturer)"
echo "Model        : $(getprop ro.product.model)"
echo "Android      : $(getprop ro.build.version.release) (SDK $(getprop ro.build.version.sdk))"
echo "Build        : $(getprop ro.build.display.id)"'
	sdk=$(dev 'getprop ro.build.version.sdk')
	case $sdk in
	'' | *[!0-9]*) ;;
	*) [ "$sdk" -lt 26 ] && info "warning: Android < 8 - restore may require a factory reset on this version" ;;
	esac
	refresh_installed
	printf 'Packages for user %s: %s installed\n' "$USER_ID" "$(wc -l <"$TMP/installed" | tr -d ' ')"
	mfr=$(dev 'getprop ro.product.manufacturer' | tr 'A-Z' 'a-z')
	printf '\nSuggested lists:\n  lists/google.txt\n  lists/third-party-preloads.txt\n'
	case $mfr in
	*samsung*) echo "  lists/samsung.txt" ;;
	*xiaomi* | *redmi* | *poco*) echo "  lists/xiaomi.txt" ;;
	*oneplus* | *oppo* | *realme*) echo "  lists/oneplus-oppo-realme.txt" ;;
	esac
}

cmd_backup() {
	preflight
	dir=${1:-$OUT_DIR/$(device_tag)-$(date +%Y%m%d-%H%M%S)}
	mkdir -p "$dir" || die "cannot create $dir"
	u=$USER_ID
	dev "pm list packages --user $u" | sed -n 's/^package://p' | sort >"$dir/installed.txt"
	dev "pm list packages -s --user $u" | sed -n 's/^package://p' | sort >"$dir/system.txt"
	dev "pm list packages -3 --user $u" | sed -n 's/^package://p' | sort >"$dir/user-apps.txt"
	dev "pm list packages -d --user $u" | sed -n 's/^package://p' | sort >"$dir/disabled.txt"
	dev "pm list packages -u --user $u" | sed -n 's/^package://p' | sort >"$dir/all-including-uninstalled.txt"
	dev "pm list packages -f --user $u" | sed 's/^package://' | sort >"$dir/apk-paths.txt"
	dev 'for p in ro.product.manufacturer ro.product.model ro.product.device ro.build.version.release ro.build.version.sdk ro.build.display.id ro.build.fingerprint; do echo "$p=$(getprop $p)"; done' >"$dir/device-info.txt"
	[ -s "$dir/installed.txt" ] || die "backup is empty - is the device connected and authorised?"
	info "Backup saved to $dir ($(wc -l <"$dir/installed.txt" | tr -d ' ') packages)"
	info "Undo everything later with: sh scripts/debloat.sh restore-backup \"$dir\""
}

cmd_list() {
	preflight
	need_tmp
	dev "pm list packages -s --user $USER_ID" | sed -n 's/^package://p' | sort -u >"$TMP/system"
	refresh_installed
	while read -r p; do
		if grep -Fxq "$p" "$TMP/system"; then t=S; else t=U; fi
		printf '%s %s\n' "$t" "$p"
	done <"$TMP/installed" | if [ $# -gt 0 ]; then grep -i -- "$1"; else cat; fi
}

cmd_plan() {
	[ $# -gt 0 ] || die "plan needs at least one list file"
	preflight
	build_plan "$@"
}

remove_pkgs() { # action: uninstall | disable
	action=$1; shift
	[ $# -gt 0 ] || die "$action needs at least one list file"
	preflight
	build_plan "$@"
	[ -s "$TMP/todo" ] || { info "Nothing to do."; return 0; }
	ls "$OUT_DIR"/*/installed.txt >/dev/null 2>&1 ||
		info "WARNING: no backup found in $OUT_DIR - run 'backup' first!"
	confirm "Proceed to $action $(wc -l <"$TMP/todo" | tr -d ' ') package(s)?" || { info "Aborted."; return 1; }
	LOG=$(log_file)
	ok=0 fail=0
	while read -r pkg; do
		if [ "$action" = uninstall ]; then
			k=""; [ "$KEEP_DATA" -eq 1 ] && k="-k"
			res=$(dev "pm uninstall $k --user $USER_ID $pkg" 2>&1)
			case $res in *Success*) good=1 ;; *) good=0 ;; esac
		else
			res=$(dev "pm disable-user --user $USER_ID $pkg" 2>&1)
			case $res in *disabled-user*) good=1 ;; *) good=0 ;; esac
		fi
		if [ $good -eq 1 ]; then
			printf '  OK    %s\n' "$pkg"; log_action "$pkg" "$action"; ok=$((ok + 1))
		else
			printf '  FAIL  %s: %s\n' "$pkg" "$(echo "$res" | tr '\n' ' ')"; fail=$((fail + 1))
		fi
	done <"$TMP/todo"
	printf '\nDone: %s succeeded, %s failed. Log: %s\n' "$ok" "$fail" "$LOG"
	echo "Reboot the phone now and run through the test checklist (docs/PROCEDURE.md, step 8)."
}

restore_pkgs() { # file with one package per line
	refresh_installed
	dev "pm list packages -d --user $USER_ID" | sed -n 's/^package://p' | sort -u >"$TMP/disabled"
	LOG=$(log_file)
	ok=0 fail=0
	while read -r pkg; do
		valid_pkg "$pkg" || { printf '  INVALID  %s\n' "$pkg"; continue; }
		if ! is_installed "$pkg"; then
			res=$(dev "cmd package install-existing --user $USER_ID $pkg 2>&1 || pm install-existing --user $USER_ID $pkg" 2>&1)
			case $res in
			*"installed for user"*) ;;
			*) printf '  FAIL     %s: %s\n' "$pkg" "$(echo "$res" | tr '\n' ' ')"; fail=$((fail + 1)); continue ;;
			esac
		fi
		if grep -Fxq "$pkg" "$TMP/disabled"; then
			dev "pm enable --user $USER_ID $pkg"  >/dev/null 2>&1
		fi
		printf '  RESTORED %s\n' "$pkg"; log_action "$pkg" restore; ok=$((ok + 1))
	done <"$1"
	printf '\nRestored %s, failed %s.\n' "$ok" "$fail"
}

cmd_restore() {
	[ $# -gt 0 ] || die "restore needs package names or files"
	preflight
	need_tmp
	: >"$TMP/restore"
	for a in "$@"; do
		if [ -f "$a" ]; then read_list "$a" >>"$TMP/restore"; else echo "$a" >>"$TMP/restore"; fi
	done
	sort -u "$TMP/restore" -o "$TMP/restore"
	restore_pkgs "$TMP/restore"
}

cmd_restore_backup() {
	[ $# -eq 1 ] && [ -f "$1/installed.txt" ] || die "usage: restore-backup BACKUP_DIR (must contain installed.txt)"
	preflight
	refresh_installed
	grep -Fxvf "$TMP/installed" "$1/installed.txt" >"$TMP/missing" || true
	if [ ! -s "$TMP/missing" ]; then info "Nothing missing compared to the backup."; return 0; fi
	sed 's/^/  /' "$TMP/missing"
	confirm "Restore these $(wc -l <"$TMP/missing" | tr -d ' ') package(s)?" || return 1
	restore_pkgs "$TMP/missing"
}

cmd_commands() {
	[ $# -gt 0 ] || die "commands needs at least one list file"
	load_denylist
	k=""; [ "$KEEP_DATA" -eq 1 ] && k="-k "
	echo "# Generated by debloat.sh - paste into any adb shell (Bugjaeger, LADB, adb shell)."
	echo "# Undo one package with: cmd package install-existing <package>"
	for pkg in $(read_list "$@"); do
		if ! valid_pkg "$pkg"; then echo "# INVALID: $pkg"
		elif is_denied "$pkg"; then echo "# BLOCKED (never-remove): $pkg"
		else echo "pm uninstall ${k}--user $USER_ID $pkg"
		fi
	done
}

# ---- argument parsing ----
while [ $# -gt 0 ]; do
	case $1 in
	-s) [ $# -ge 2 ] || die "-s needs a serial"; SERIAL=$2; shift 2 ;;
	-u) [ $# -ge 2 ] || die "-u needs a user id"; USER_ID=$2; shift 2
	    case $USER_ID in '' | *[!0-9]*) die "user id must be a number" ;; esac ;;
	-y) ASSUME_YES=1; shift ;;
	--rish) MODE=rish; shift ;;
	--local) MODE=local; shift ;;
	--no-keep-data) KEEP_DATA=0; shift ;;
	-V | --version) echo "debloat.sh $VERSION"; exit 0 ;;
	-h | --help) usage; exit 0 ;;
	-*) die "unknown option: $1 (see help)" ;;
	*) break ;;
	esac
done

[ $# -gt 0 ] || { usage; exit 1; }
command=$1; shift
case $command in
check)          cmd_check "$@" ;;
backup)         cmd_backup "$@" ;;
list)           cmd_list "$@" ;;
plan)           cmd_plan "$@" ;;
apply)          remove_pkgs uninstall "$@" ;;
disable)        remove_pkgs disable "$@" ;;
restore)        cmd_restore "$@" ;;
restore-backup) cmd_restore_backup "$@" ;;
commands)       cmd_commands "$@" ;;
help)           usage ;;
*)              die "unknown command: $command (see help)" ;;
esac
