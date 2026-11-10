#!/bin/sh
# run-tests.sh - exercises debloat.sh against a simulated device (fake adb + pm).
# Usage: sh tests/run-tests.sh
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/debloat-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
FAKEBIN=$WORK/bin
mkdir -p "$FAKEBIN" "$WORK/state"
export FAKE_STATE=$WORK/state DEBLOAT_OUT=$WORK/backups

# Initial simulated device: system apps + one user app.
printf '%s\n' android com.android.systemui com.android.settings com.google.android.gms \
	com.google.android.apps.tachyon com.google.android.videos com.facebook.system \
	com.samsung.android.bixby.agent com.samsung.android.knox.attestation >"$FAKE_STATE/system"
echo com.termux >"$FAKE_STATE/user"
cat "$FAKE_STATE/system" "$FAKE_STATE/user" | sort >"$FAKE_STATE/installed"
: >"$FAKE_STATE/disabled"

cat >"$FAKEBIN/adb" <<'EOF'
#!/bin/sh
[ "$1" = -s ] && shift 2
case $1 in
devices) printf 'List of devices attached\nFAKE123 device model:Fake\n' ;;
shell) shift; PATH="$(dirname "$0")/dev:$PATH" sh -c "$*" | sed 's/$/\r/' ;;
esac
EOF
mkdir -p "$FAKEBIN/dev"
cat >"$FAKEBIN/dev/getprop" <<'EOF'
#!/bin/sh
case $1 in
ro.product.manufacturer) echo samsung ;; ro.product.model) echo SM-TEST ;;
ro.build.version.sdk) echo 34 ;; ro.build.version.release) echo 14 ;; *) echo x ;;
esac
EOF
cat >"$FAKEBIN/dev/cmd" <<'EOF'
#!/bin/sh
shift; exec pm "$@"
EOF
cat >"$FAKEBIN/dev/pm" <<'EOF'
#!/bin/sh
S=$FAKE_STATE
sub=$1; shift
pkg=""; flag=""
for a; do case $a in --user) ;; -*) flag="$flag $a" ;; [0-9]*) ;; *) pkg=$a ;; esac; done
case $sub in
list)
	case $flag in
	*-s*) f=$S/system ;; *-3*) f=$S/user ;; *-d*) f=$S/disabled ;;
	*-u*) f=$S/all ; cat $S/system $S/user | sort >$f ;; *) f=$S/installed ;;
	esac
	sed 's/^/package:/' "$f" ;;
uninstall)
	if grep -Fxq "$pkg" $S/installed; then grep -Fxv "$pkg" $S/installed >$S/t; mv $S/t $S/installed; echo Success
	else echo "Failure [not installed for 0]"; fi ;;
disable-user) echo "$pkg" >>$S/disabled; echo "Package $pkg new state: disabled-user" ;;
enable) grep -Fxv "$pkg" $S/disabled >$S/t; mv $S/t $S/disabled; echo "Package $pkg new state: enabled" ;;
install-existing)
	if grep -Fxq "$pkg" $S/system; then echo "$pkg" >>$S/installed; sort -u $S/installed -o $S/installed
		echo "Package $pkg installed for user: 0"
	else echo "Failure [package not found]"; exit 1; fi ;;
esac
EOF
chmod +x "$FAKEBIN/adb" "$FAKEBIN/dev/"*
export PATH="$FAKEBIN:$PATH"

D="sh $ROOT/scripts/debloat.sh"
pass=0 fail=0
ok()   { pass=$((pass + 1)); echo "ok   - $1"; }
bad()  { fail=$((fail + 1)); echo "FAIL - $1"; }
has()  { grep -Fxq "$1" "$FAKE_STATE/installed"; }

cat >"$WORK/list.txt" <<'EOF'
# test list
com.google.android.apps.tachyon   # remove me
com.facebook.system
com.google.android.gms            # denylisted
com.samsung.android.knox.attestation # denylisted via wildcard
com.termux                        # denylisted tool
not.installed.pkg
bad;rm -rf /                      # invalid
#opt com.google.android.videos
EOF

out=$($D check 2>&1); echo "$out" | grep -q 'lists/samsung.txt' && ok "check suggests vendor list" || bad "check: $out"

$D backup "$WORK/bk" >/dev/null 2>&1
[ "$(wc -l <"$WORK/bk/installed.txt")" -eq 10 ] && ok "backup captured 10 packages" || bad "backup"

out=$($D list bixby); [ "$out" = "S com.samsung.android.bixby.agent" ] && ok "list filter + system flag" || bad "list: $out"

out=$($D plan "$WORK/list.txt")
echo "$out" | grep -q 'TARGET    com.google.android.apps.tachyon' && echo "$out" | grep -q 'BLOCKED   com.google.android.gms' &&
	echo "$out" | grep -q 'BLOCKED   com.samsung.android.knox.attestation' && echo "$out" | grep -q 'BLOCKED   com.termux' &&
	echo "$out" | grep -q '2 to act on, 1 not installed (skipped), 3 blocked, 1 invalid' &&
	! echo "$out" | grep -q videos && ok "plan classifies correctly" || bad "plan: $out"
has com.google.android.apps.tachyon && ok "plan made no changes" || bad "plan changed state"

echo n | $D apply "$WORK/list.txt" >/dev/null 2>&1
has com.google.android.apps.tachyon && ok "apply aborts on 'n'" || bad "apply ignored 'n'"

$D -y apply "$WORK/list.txt" >/dev/null 2>&1
! has com.google.android.apps.tachyon && ! has com.facebook.system && has com.google.android.gms && has com.termux &&
	ok "apply removed targets, kept denylisted" || bad "apply"
LOG=$(ls "$DEBLOAT_OUT"/actions-*.log)
[ "$(grep -c 'uninstall' "$LOG")" -eq 2 ] && ok "actions logged" || bad "log: $(cat "$LOG")"

$D -y restore "$LOG" >/dev/null 2>&1
has com.google.android.apps.tachyon && has com.facebook.system && ok "restore from log" || bad "restore"

echo com.google.android.videos >"$WORK/d.txt"
$D -y disable "$WORK/d.txt" >/dev/null 2>&1
grep -Fxq com.google.android.videos "$FAKE_STATE/disabled" && ok "disable" || bad "disable"
$D -y restore com.google.android.videos >/dev/null 2>&1
! grep -Fxq com.google.android.videos "$FAKE_STATE/disabled" && ok "restore re-enables disabled" || bad "re-enable"

$D -y apply "$WORK/list.txt" >/dev/null 2>&1
$D -y restore-backup "$WORK/bk" >/dev/null 2>&1
cmp -s "$WORK/bk/installed.txt" "$FAKE_STATE/installed" && ok "restore-backup returns to snapshot" || bad "restore-backup"

out=$($D commands "$WORK/list.txt")
echo "$out" | grep -qx 'pm uninstall -k --user 0 com.facebook.system' && echo "$out" | grep -q 'BLOCKED (never-remove): com.google.android.gms' &&
	! echo "$out" | grep -q '^pm.*rm -rf' && ok "commands export" || bad "commands: $out"

for f in "$ROOT"/lists/*.txt; do
	bad_lines=$(sed -e 's/#.*//' -e 's/[[:space:]]//g' "$f" | grep -v '^$' | grep -v '^[A-Za-z0-9_.*]*$')
	[ -z "$bad_lines" ] || bad "malformed entries in $f: $bad_lines"
done
DENY=$(sed -e 's/#.*//' -e 's/[[:space:]]//g' "$ROOT/lists/never-remove.txt" | grep -v '^$')
clash=""
for f in "$ROOT"/lists/*.txt; do
	[ "$(basename "$f")" = never-remove.txt ] && continue
	for p in $(sed -e 's/^#opt //' -e 's/^#adv //' -e 's/#.*//' -e 's/[[:space:]]//g' "$f" | grep -v '^$'); do
		set -f; for pat in $DENY; do case $p in $pat) clash="$clash $p" ;; esac; done; set +f
	done
done
[ -z "$clash" ] && ok "no list entry (incl. #opt/#adv) conflicts with never-remove" || bad "denylist clash:$clash"

echo; echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
