# android-debloat

Remove preinstalled bloatware from an Android phone **without root and without
a computer** — using the phone itself or a second Android device as the
controller. Every change is reversible.

📖 **Full step-by-step guide: [docs/PROCEDURE.md](docs/PROCEDURE.md)**

## Quick start (Termux on the same phone, Android 11+)

```sh
# 1. Termux (from F-Droid) + tools
pkg update && pkg install -y android-tools git
git clone https://github.com/iamsanaur/android-debloat && cd android-debloat

# 2. Settings > Developer options > Wireless debugging > Pair device with pairing code
#    (split-screen Termux + Settings so the code stays visible)
adb pair localhost:<pairing-port>     # type the 6-digit code
adb connect localhost:<connect-port>  # port from the Wireless debugging main screen

# 3. Inspect, back up, dry run, apply
sh scripts/debloat.sh check
sh scripts/debloat.sh backup
sh scripts/debloat.sh plan  lists/google.txt lists/third-party-preloads.txt
sh scripts/debloat.sh apply lists/third-party-preloads.txt   # then reboot & test
```

Prefer tapping to typing? Use **Shizuku + Canta** — see method A1 in the guide.
Using a second Android device? See methods B1 (Wi-Fi) and B2 (USB-OTG).

## What's here

| Path | Purpose |
|---|---|
| [`docs/PROCEDURE.md`](docs/PROCEDURE.md) | End-to-end procedure: prep, 4 connection methods, backup, removal, testing, restore, recovery |
| [`scripts/debloat.sh`](scripts/debloat.sh) | POSIX shell tool: `check`, `backup`, `list`, `plan`, `apply`, `disable`, `restore`, `restore-backup`, `commands` |
| [`lists/`](lists) | Package lists per vendor with three tiers: active (low-risk), `#opt` (preference), `#adv` (may break features) |
| [`lists/never-remove.txt`](lists/never-remove.txt) | Safety denylist the script will never touch (system UI, telephony, Play Services, Knox, MIUI security, …) |
| [`tests/run-tests.sh`](tests/run-tests.sh) | Tests against a simulated device (`sh tests/run-tests.sh`) |

## Safety model

- Uses `pm uninstall -k --user 0`: the APK stays on the system partition, so
  `restore` or a factory reset always brings an app back.
- `plan` is a dry run; `apply` asks for confirmation and logs every change.
- Packages in `never-remove.txt` are refused even if a list includes them.
- `backup` snapshots the full package inventory so `restore-backup` can undo
  everything.

## Disclaimer

Use at your own risk. Lists are starting points, not guarantees — package
behaviour differs across models, regions and firmware versions. Review every
`TARGET` in `plan` output before applying.
