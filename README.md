# Journal

A private journal for one Mac. Everything you write is encrypted on disk with a
key derived from your passcode. The app has no network access — not restricted
network access, none: the sandbox entitlement simply isn't there, so the kernel
refuses outbound connections regardless of what the code asks for.

macOS 14+. Swift, SwiftUI, CryptoKit, LocalAuthentication. No third-party code.

---

## Build and install

```bash
./install.sh
```

Builds in Release and copies the app to `/Applications`. The script refuses to
install if the sandbox is off, if a network entitlement has appeared, or if the
debug entitlement is present — so a mistake in the project settings can't
quietly ship an app that's weaker than it claims.

### One optional step, worth doing

Open **Xcode → Settings → Accounts** and add your Apple ID (the free tier is
enough), then run `./install.sh` again.

Without it the app works and your entries are encrypted exactly the same. What
changes is Touch ID. With a team identity, macOS holds the Touch ID key under a
Secure Enclave-backed lock and won't release it without your fingerprint.
Without one, the app falls back to performing that check itself — fine against
someone at your keyboard, weaker against someone who can already run code as
you. **Settings → General** tells you which mode you're in. Daily reminders are
also more reliable with a real signature.

Your passcode and recovery key are unaffected either way.

### Working on the code

```bash
open Journal.xcodeproj          # or build from the command line:
xcodebuild -scheme Journal -configuration Debug build
xcodebuild -scheme Journal -destination 'platform=macOS' test
```

---

## Where your data lives

```
~/Library/Containers/com.karthikvishal.Journal/Data/
    Library/Application Support/Journal/
```

Not the plain `~/Library/Application Support/`. The App Sandbox redirects it
into a container, which is a feature: other sandboxed apps can't read in there.
**Settings → Data → Reveal in Finder** opens it, since it's not a path anyone
would type.

Inside:

| File | What it is |
|---|---|
| `vault.json` | Salts, KDF settings, and your data key wrapped under your passcode and under your recovery key. No secrets in readable form. |
| `entries/<uuid>.enc` | One entry per file, AES-GCM sealed. Filenames are UUIDs, so the directory listing gives away no dates or titles. |
| `index.enc` | Encrypted metadata (dates, titles, moods, tags) so the calendar can draw without decrypting every entry. Rebuilt automatically if lost. |

There is no plaintext anywhere in there. A test asserts this by scanning every
byte of every file for the words it just saved.

---

## Backup and restore

**Settings → Data → Save Encrypted Backup…** writes a single `.journalbackup`
file. Put it on an external drive or anywhere else you like.

It stays encrypted. Entries are already ciphertext on disk, so a backup just
collects those bytes — nothing is decrypted to make one, and it opens with the
same passcode or recovery key as the journal. There's no separate backup
password to invent and lose.

**Restore from Backup…** replaces everything currently on this Mac with the
archive's contents, then locks the app so you come back in through the front
door. It stages the whole restore before touching anything, so a failure
halfway leaves your existing journal intact.

Back up regularly. If your disk dies and you have no backup, the recovery key
won't help — it unlocks data, it doesn't reconstruct it.

---

## If you forget your passcode

Use the recovery key shown during setup. Type it into the same field on the
lock screen; the app recognises its shape. Case, spaces and dashes don't
matter, and `I`/`1` and `O`/`0` are interchangeable, since it's meant to be
read off paper.

**If both the passcode and the recovery key are gone, the entries are gone.**
Not recoverable by you, by this app, or by anyone. There is no backdoor, and
adding one later wouldn't help — the key genuinely does not exist anywhere
outside those two secrets.

You can issue a replacement recovery key any time in **Settings → Security**.
Doing so invalidates the old one immediately.

---

## Locking

The app opens locked, every time. It re-locks when your Mac sleeps, when the
screen locks, after a configurable idle period (default 5 minutes), and on
**⌘L**. Only the idle timer is adjustable; the rest can't be turned off.

Whenever the app isn't frontmost, a curtain covers the window — that's what
hides your writing in Mission Control and the ⌘-Tab switcher, both of which
photograph background windows. The window is also excluded from screen
recording and screen sharing.

Five wrong passcodes in a row starts an escalating delay, growing to 15
minutes. It survives quitting and relaunching.

---

## Keyboard

| | |
|---|---|
| ⌘N | New entry |
| ⌘F | Search |
| ⌘T | Jump to today |
| ⌘B | Browse all entries |
| ⌘L | Lock now |

---

## Exporting

**Settings → Data → Export** writes Markdown files (one per entry, with YAML
front matter) or a single PDF, to a folder you choose.

Exports are **not encrypted** — that's the point of them, but it means those
files sit outside every protection the app otherwise gives you. The app asks
you to confirm, in those words, before writing anything.

---

## How the encryption works

One random 256-bit **data encryption key** encrypts every entry. That key is
never stored directly. It's wrapped three ways:

- **Passcode** — PBKDF2-SHA256, 310,000 rounds, random salt. The high round
  count is what makes guessing your passcode from a copy of the disk expensive.
- **Recovery key** — 160 bits of system randomness, HKDF-SHA256. Nothing to
  guess, so no stretching needed.
- **Touch ID** — the key in the Keychain, released by your fingerprint.

Because only the *wrapping* depends on your passcode, changing it re-wraps one
key rather than re-encrypting your journal — it's instant no matter how much
you've written.

Every sealed box is authenticated against its own identity, so an entry file
can't be renamed over another one and pass as it. A wrong key and a tampered
file are indistinguishable to the app, which is correct: both mean the same
thing.

---

## Tests

```bash
xcodebuild -scheme Journal -destination 'platform=macOS' test
```

79 tests over the encryption, storage, recovery-key, streak, export and backup
layers: round trips, wrong keys, tampered and truncated files, swapped entry
files, corrupt and missing indexes, lockout escalation, and backup/restore.
# Journal
