# End-to-end Android debloat procedure (no PC, no root)

This guide removes preinstalled bloatware using **only your phone**, or **a
second Android device** as the controller. It works on Android 11 and newer
without a computer. Android 8–10 needs one extra step (see
[Appendix A](#appendix-a-android-810)).

> **Time needed:** 30–60 minutes the first time.
> **Risk:** low if you follow the order below. Everything is reversible.

---

## Contents

0. [How debloating works (read once)](#0-how-debloating-works)
1. [Prepare](#1-prepare)
2. [Pick your method](#2-pick-your-method)
3. [Enable Developer options & Wireless debugging](#3-enable-developer-options--wireless-debugging)
4. [Connect — the four methods](#4-connect)
5. [Back up and choose what to remove](#5-back-up-and-choose-what-to-remove)
6. [Dry run](#6-dry-run)
7. [Remove in batches](#7-remove-in-batches)
8. [Reboot and test](#8-reboot-and-test)
9. [Undo / restore](#9-undo--restore)
10. [Troubleshooting & recovery](#10-troubleshooting--recovery)
11. [After system updates](#11-after-system-updates)

---

## 0. How debloating works

Preinstalled apps live on the read-only system partition. Without root you
can't delete them, but Android's package manager can **uninstall them for your
user account**:

```
pm uninstall -k --user 0 <package>      # app disappears for you
cmd package install-existing <package>  # app comes back
```

- The APK stays on the system partition, so a **factory reset always brings
  everything back** — you cannot permanently brick a phone this way.
- It frees RAM/CPU/battery (the app no longer runs, updates or shows ads) and
  any storage used by its updates/data, but not the original APK's space.
- These commands need the `shell` privilege, which you get through **ADB**
  (Android Debug Bridge). ADB can come from: the same phone (Wireless debugging
  + Termux, or Shizuku), or another Android device (Wi-Fi or USB-OTG cable).

**Alternative:** `pm disable-user` freezes an app instead of uninstalling it.
Use it when you're unsure — undo with `pm enable`.

---

## 1. Prepare

- [ ] **Back up your data** (photos, chats, 2FA codes). Debloating doesn't touch
      your data, but a recovery factory reset would.
- [ ] Battery **above 50 %**.
- [ ] Note your phone's **brand, model and Android version**
      (Settings → About phone).
- [ ] Be connected to **any Wi-Fi network** (Wireless debugging requires Wi-Fi;
      internet access is not required — a hotspot from another phone works).
- [ ] Install **replacements first** for anything you plan to remove that you
      still need a function for: browser, keyboard, launcher, gallery, file
      manager, SMS app. Set them as default.
- [ ] Samsung One UI 6+: turn **off** Settings → Security and privacy →
      **Auto Blocker** (it blocks ADB commands). Turn it back on afterwards.

---

## 2. Pick your method

| Method | Hardware | Ease | Best for |
|---|---|---|---|
| **A1. Shizuku + Canta** | your phone only | ★★★★★ GUI, tap to remove | most people |
| **A2. Termux on the same phone** | your phone only | ★★★ commands | using this repo's lists/script, full logs |
| **B1. Another Android over Wi-Fi** | 2nd Android device | ★★★ commands | a friend's phone, or keeping the target hands-free |
| **B2. Another Android over USB-OTG** | 2nd Android + OTG cable | ★★★ | no Wi-Fi, Android 8–10 targets |

All methods do the same thing underneath. You can mix them — e.g. remove with
Canta, inspect with Termux.

---

## 3. Enable Developer options & Wireless debugging

On the **phone you want to debloat** (the *target*):

1. **Settings → About phone** → tap **Build number** 7 times
   (Xiaomi: *MIUI/HyperOS version*; OnePlus/OPPO/realme: *Version → Build number*;
   Samsung: *Software information → Build number*). Enter your PIN.
2. **Settings → System → Developer options** (Samsung/Xiaomi: at the bottom of
   Settings or under *Additional settings*):
   - **USB debugging** → on.
   - **Wireless debugging** → on → *Allow* on this network. (Android 11+)
   - Xiaomi only: also **USB debugging (Security settings)** → on, if you later
     get `SecurityException` errors (needs a SIM and Mi account).
3. Keep Wireless debugging's screen handy — you'll need its **IP address &
   port** and its **Pair device with pairing code** button.

> Wireless debugging turns itself off when Wi-Fi drops or after a reboot. If a
> connection fails later, just turn it back on and reconnect (no re-pairing).

---

## 4. Connect

Do **one** of the four methods, then go to [step 5](#5-back-up-and-choose-what-to-remove).

### A1. Same phone — Shizuku + Canta (GUI, easiest)

1. Install **Shizuku** (Google Play, or GitHub `RikkaApps/Shizuku`).
2. Open Shizuku → **Start via Wireless debugging** → **Pairing**. It asks for
   notification permission — allow it.
3. Open Developer options → Wireless debugging → **Pair device with pairing
   code**. A 6-digit code appears. Pull down the notification shade and type the
   code into Shizuku's notification reply box.
4. Back in Shizuku tap **Start**. It should say *Shizuku is running*.
5. Install **Canta** (F-Droid or GitHub `samolego/Canta`), open it and grant the
   Shizuku permission.
6. Canta shows every app with a recommendation badge (sourced from the
   Universal Android Debloater community list). Then follow steps 5–8 below,
   using Canta instead of the script:
   - Write down/screenshot what you remove (Canta also keeps an *Uninstalled* tab).
   - Remove only **Recommended** items first; avoid **Expert/Unsafe** ones.
   - Restore from Canta's *Uninstalled* tab.

> Want the script with Shizuku instead? See [A2 variant: rish](#a2-variant-shizuku-rish-no-adb-pairing).

### A2. Same phone — Termux + Wireless debugging (uses this repo)

1. Install **Termux** from **F-Droid** or GitHub (the Play Store build is
   outdated).
2. In Termux:
   ```sh
   pkg update && pkg upgrade -y
   pkg install -y android-tools git
   git clone https://github.com/iamsanaur/android-debloat
   cd android-debloat
   ```
3. Put Termux and Settings **side by side** (split screen / pop-up view) —
   the pairing code disappears if you leave Settings.
4. Settings → Developer options → Wireless debugging → **Pair device with
   pairing code**. Note the code and the port in `IP:PORT` (e.g. `…:37123`).
5. In Termux:
   ```sh
   adb pair localhost:37123      # use the PAIRING port, then type the code
   ```
   Expect `Successfully paired`.
6. Close the pairing dialog. The main Wireless debugging screen shows a
   *different* port under **IP address & Port** (e.g. `…:41255`):
   ```sh
   adb connect localhost:41255   # use the CONNECT port
   adb devices                   # shows "localhost:41255  device"
   ```
   If several devices show up, add `-s localhost:41255` to every script command.
7. Verify: `sh scripts/debloat.sh check`

#### A2 variant: Shizuku `rish` (no adb pairing)

If Shizuku is already running (A1 steps 1–4): Shizuku → **Use Shizuku in
terminal apps** → **Export files** to a folder, then in Termux:

```sh
cp /sdcard/<folder>/rish* ~/ && chmod +x ~/rish
sed -i 's/PKG/com.termux/' ~/rish        # the exported file asks you to set this
export PATH="$HOME:$PATH"
sh scripts/debloat.sh --rish check
```

Add `--rish` to every command in the rest of this guide.

### B1. Another Android device over Wi-Fi

Target = the phone you're debloating. Controller = the other Android device.

1. Put both on the **same Wi-Fi** (or turn on the controller's hotspot and join
   it from the target).
2. On the **controller**, do A2 steps 1–2 (install Termux, `android-tools`,
   clone the repo).
3. On the **target**: Developer options → Wireless debugging → **Pair device
   with pairing code**. Note `IP:PAIRPORT` and the code.
4. On the **controller**:
   ```sh
   adb pair 192.168.1.23:37123          # target's IP and pairing port, then the code
   adb connect 192.168.1.23:41255       # target's IP and the main-screen port
   adb devices
   sh scripts/debloat.sh check
   ```
   The `check` output should show the **target's** model, not the controller's.

### B2. Another Android device over USB-OTG cable

You need a USB-OTG adapter or a USB-C ↔ USB-C cable, and the target needs
**USB debugging** on.

1. On the controller install **Bugjaeger** (Google Play) — it speaks ADB over
   USB from one Android device to another.
2. Connect the cable; on the target tap **Allow USB debugging** (tick *Always
   allow*).
3. Bugjaeger's **shell** tab gives you an `adb shell` on the target. Generate
   the commands with the script on any device that has this repo (even the
   controller in Termux, no connection needed):
   ```sh
   sh scripts/debloat.sh commands lists/google.txt lists/samsung.txt > my-commands.txt
   ```
   Already-blocked dangerous packages are commented out. Paste the lines into
   Bugjaeger's shell **a few at a time**. Before that, run
   `pm list packages > /sdcard/packages-before.txt` in the shell as your backup.
4. Undo any line with `cmd package install-existing <package>`.

> B2 doesn't get the automatic backup/log/denylist checks at run-time, so prefer
> B1 or A2 when Wi-Fi is available.

---

## 5. Back up and choose what to remove

From here on, commands are for methods A2/B1 (add `--rish` for the rish
variant, or `-s <serial>` if several devices are connected).

### 5.1 Back up the package inventory — do not skip

```sh
sh scripts/debloat.sh backup
```

Creates `backups/<maker>-<model>-<date>/` with every installed/system/disabled
package. This is your **undo-everything** snapshot. Copy the folder somewhere
safe (cloud, another device) — e.g. `cp -r backups /sdcard/Download/`
(run `termux-setup-storage` first).

### 5.2 Pick your lists

`check` printed suggested lists. Each list has three tiers:

| Line looks like | Meaning | Default |
|---|---|---|
| `com.foo.bar  # note` | low-risk bloat | **removed** |
| `#opt com.foo.bar` | safe, but you might use it | kept — delete `#opt ` to remove |
| `#adv com.foo.bar` | can break features (note says which) | kept — delete `#adv ` only after research |

Edit with `nano lists/samsung.txt` (Termux: `pkg install nano`). Put your own
finds in `lists/custom.txt`.

### 5.3 Find & research other packages

```sh
sh scripts/debloat.sh list            # everything; S = system app, U = app you installed
sh scripts/debloat.sh list facebook   # filter by word
```

Before adding an unknown package, look it up — search the package name in the
**Universal Android Debloater Next Generation** list
(`github.com/Universal-Debloater-Alliance/universal-android-debloater-next-generation`,
file `resources/assets/uad_lists.json`) or simply web-search the name. Rules of
thumb:

- **Safe-ish:** obvious apps you can see in the launcher, partner apps
  (Facebook, Netflix, games), `*.analytics`, ads, "tips", AR stickers.
- **Dangerous:** names containing `provider`, `framework`, `systemui`,
  `telephony`, `ims`, `bluetooth`, `nfc`, `wifi`, `knox`, `security`,
  `permission`, `packageinstaller`, `setupwizard`, `launcher`, `keyboard`,
  `webview`, `gms`, `gsf`, `overlay`. The script's
  [`never-remove`](../lists/never-remove.txt) list already blocks the
  worst of these.
- **When unsure:** use `disable` instead of `apply`, or leave it.

---

## 6. Dry run

```sh
sh scripts/debloat.sh plan lists/google.txt lists/third-party-preloads.txt lists/samsung.txt
```

Nothing changes. Output:

```
  TARGET    com.samsung.android.bixby.agent
  BLOCKED   com.google.android.gms  (in never-remove list)
...
23 to act on, 41 not installed (skipped), 1 blocked, 0 invalid
```

Read every `TARGET` line. If something surprises you, remove it from the list.

---

## 7. Remove in batches

Do one list at a time, rebooting and testing between batches, so if something
breaks you know which batch did it.

```sh
sh scripts/debloat.sh apply lists/third-party-preloads.txt   # batch 1 - partner apps
# reboot + quick test (step 8)
sh scripts/debloat.sh apply lists/google.txt                 # batch 2
# reboot + quick test
sh scripts/debloat.sh apply lists/samsung.txt                # batch 3 - your brand
# reboot + full test
sh scripts/debloat.sh apply lists/custom.txt                 # batch 4 - your own picks
```

Each run shows the plan, asks `[y/N]`, then prints `OK`/`FAIL` per package and
appends to `backups/actions-<device>.log`.

**Same-phone users (A2):** the connection may drop after a reboot — turn
Wireless debugging back on and `adb connect localhost:<new port>` (no
re-pairing). Ports change every time.

---

## 8. Reboot and test

Reboot, then check:

- [ ] Phone boots and unlocks normally (PIN/fingerprint/face)
- [ ] Make and receive a **call**; send and receive an **SMS**
- [ ] **Mobile data**, **Wi-Fi**, **Bluetooth**, **hotspot**
- [ ] **Camera** (photo + video), **gallery** opens photos
- [ ] **Notifications** arrive (e.g. send yourself a chat message)
- [ ] **Play Store** installs/updates an app
- [ ] Banking / payment / NFC tap-to-pay, if you use them
- [ ] Keyboard, launcher/home screen, share sheet, screenshots
- [ ] Location / maps, alarms, battery stats
- [ ] Use the phone normally for 1–2 days before the next risky batch

Anything broken → [step 9](#9-undo--restore) for the most recent batch.

---

## 9. Undo / restore

```sh
# one or more packages
sh scripts/debloat.sh restore com.samsung.android.bixby.agent

# everything a list removed (lists and the action log are both valid input)
sh scripts/debloat.sh restore lists/samsung.txt
sh scripts/debloat.sh restore backups/actions-samsung-SM-S921B.log

# full undo back to the backup snapshot
sh scripts/debloat.sh restore-backup backups/samsung-SM-S921B-20261110-153000
```

Manual equivalent in any adb shell:
`cmd package install-existing <package>` (or `pm install-existing <package>`),
then `pm enable <package>` if it was disabled.

If an app comes back but misbehaves, update it from the Play Store / Galaxy
Store, or clear its data in Settings → Apps.

---

## 10. Troubleshooting & recovery

| Symptom | Fix |
|---|---|
| `adb: command not found` | `pkg install android-tools` (Termux) |
| `failed to connect` / `connection refused` | Wireless debugging turned off or port changed — re-enable it, use the port on its main screen |
| `adb pair` fails | Use the **pairing** port (from the pairing dialog), keep the dialog open (split screen), code expires in ~1 min |
| `more than one device/emulator` | `adb devices`, then pass `-s <serial>` to the script |
| `unauthorized` | Accept the prompt on the target, or revoke authorisations in Developer options and re-pair |
| `Failure [not installed for 0]` | Already gone — harmless |
| `SecurityException` (Xiaomi) | Enable **USB debugging (Security settings)** |
| Commands blocked (Samsung) | Turn off **Auto Blocker** |
| `Failure [DELETE_FAILED_INTERNAL_ERROR]` | Package is protected by the OEM — use `disable` instead, or leave it |
| App keeps coming back | System update reinstalled it — see step 11 |
| Lost home screen | Your launcher was removed: `restore` it, or install another launcher from Play Store via a browser link |
| No calls/SMS/data | `restore` the last batch immediately |

### Bootloop or the phone won't get past the lock screen

1. **Wait** 5 minutes and try a second reboot — some apps rebuild caches.
2. If ADB still connects (USB debugging stays authorised over cable, so try
   B2 from another Android device): `restore-backup` / `cmd package
   install-existing` the last batch.
3. **Safe mode** (hold Power-off → long-press *Power off* → *Safe mode*) may let
   you in to turn Wireless debugging on and restore.
4. Last resort: **factory reset from recovery** (power off; hold Power +
   Volume Up, or Power + Volume Down depending on brand → *Wipe data/factory
   reset*). All system apps return; personal data is erased — this is why
   step 1 says back up first.

---

## 11. After system updates

Major OS updates (and sometimes monthly ones) may reinstall removed packages or
add new ones.

```sh
sh scripts/debloat.sh backup                       # new snapshot
sh scripts/debloat.sh plan lists/*.txt             # see what came back
sh scripts/debloat.sh apply <same lists as before>
```

Afterwards you can turn **Wireless debugging** and **USB debugging** off (and
Samsung's Auto Blocker back on). Debloated apps stay removed while debugging is
off.

---

## Appendix A: Android 8–10

Wireless debugging (pairing) doesn't exist before Android 11. Options:

- **B2** (USB-OTG from another Android with Bugjaeger) works directly.
- Or, once, from any ADB host (another Android via OTG, or a computer): run
  `adb tcpip 5555`. Then on the target's Termux: `adb connect localhost:5555`,
  and the script works as in A2 until the next reboot.
- On Android 8 and older, `install-existing` may not be available: restore via
  factory reset, so prefer `disable` on those versions.

## Appendix B: Command reference

```
sh scripts/debloat.sh [options] <command> [args]

options:  -s SERIAL | --rish | --local | -u USER | -y | --no-keep-data
commands: check | backup [DIR] | list [FILTER] | plan LIST... | apply LIST...
          disable LIST... | restore PKG|FILE... | restore-backup DIR
          commands LIST... | help
```

Environment variables: `DEBLOAT_OUT` (backup/log folder), `DENYLIST`
(alternative never-remove file), `RISH` (path to rish), `ANDROID_SERIAL`.
