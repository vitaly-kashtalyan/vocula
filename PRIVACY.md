# Privacy

Vocula turns your speech into text on this Mac. Nothing you say and nothing you
dictate is sent anywhere.

This document describes what the app actually does, including the parts that are
not reassuring. If a sentence here is ever untrue of the code, the sentence is
the bug.

## While you dictate

The microphone is opened when you press the record key and closed when you
release it. There is no wake word, no always-on capture, and no buffer running
in the background.

**One other thing opens it, and only while you are looking at it.** Settings →
Microphone draws a live level meter beside the microphone in use, so you can see
that it hears you before you rely on it. That needs the input open, and macOS
shows its orange recording dot for as long as it is. It closes the moment you
leave that section or switch to another app; nothing is recorded, because the
levels are measured and the audio is dropped rather than kept; and a device
that costs something to open — a Bluetooth headset, or an iPhone offered over
Continuity Capture — is never opened this way unless you press Test, since
opening a headset takes it out of stereo.

**The audio is never saved.** It is recognised in memory and discarded. There is
no setting to keep it, and no file it could be recovered from.

Recognition runs entirely on this Mac, using a model that was downloaded once.
No audio, no text and no metadata about what you dictate leave the machine at
any point.

## Putting the text in place

Text is inserted by writing it to the system clipboard and sending ⌘V. That
means a dictation passes briefly through the macOS pasteboard, which other
applications can read. The app restores your previous clipboard contents a
second later — long enough for the app you dictated into to have read the
paste. The one exception: if your clipboard held more than 16 MB, it was never
copied and cannot be put back, so the clipboard is emptied instead. Losing what
you had there is a real loss, and the app records it in its diagnostic log; the
dictated text is not left behind.

Before inserting, Vocula checks what is focused. If the cursor is in a field
macOS identifies as a password field, the text is not inserted at all. Secure
input is treated differently, and the difference matters: if it is switched on
*while* you are dictating, the insert is refused; if it was already on when you
started, it is not treated as a block. A background terminal or password manager
holds that flag all day, so refusing on its value would refuse every dictation.

## What is stored on this Mac

**Your dictation history**, if you leave it switched on, in
`~/Library/Application Support/app.vocula.mac/History/` — one file per day.

Each file is encrypted. The key is held in your login Keychain and tied to this
app — but NOT, as this sentence claimed until it was measured, to this Mac; the
last point below says exactly what that costs. So:

- another program running under your account cannot read it silently;
- a copy of the file — in a backup, on another computer, on a USB stick — cannot
  be opened without the key;
- **re-signing the app can put the key out of reach and make the history
  unreadable.** The app never destroys the key to tidy up after that: it leaves
  such days on disk and skips them, so the situation is bad but not final. It
  does still delete them when *you* ask: a day you delete and a "delete
  everything" both remove the file whether or not it can be opened. The
  retention window does not, and that is deliberate — it can only see days it
  managed to read, and a login keychain still locked at startup makes every day
  unreadable at once, so a window that deleted what it could not open would
  destroy a whole history over a temporary condition. The cost is that
  ciphertext under a key you have lost may outlive the year. There is no
  export.

  **The key is NOT bound to this Mac, and we would rather say so than imply
  otherwise.** It is asked for as device-only, but measured: the attribute is not
  stored at all in the keychain the item actually lands in, and the keychain that
  would enforce it refuses this app for want of an entitlement it does not carry.
  So if you migrate this Mac to a new one and your login keychain comes along,
  the history is readable there. What still holds is narrower and worth stating
  exactly: the files alone are useless without the key, another program running
  as you cannot read the key silently, and the key is never put into iCloud
  Keychain.

Deleting is real. Removing a dictation rewrites that day's file without it;
clearing the whole history, or letting the retention window expire, deletes the
file outright. Anything left behind in unreclaimed disk blocks is encrypted and
cannot be read.

History is kept for **one year**, and there is no setting for the length: a
dictation is deleted 365 days after it was made. (It used to default to seven
days with a stepper to change it — that stepper is gone, and the window is
longer, so a copy of this document you remember is out of date.) You can switch
history off entirely, delete a single day, or delete everything at any moment —
all in Settings → History.

**A diagnostic log**, `diagnostics.json`, is **not** encrypted, and this is
worth being precise about. It never contains a transcript: what may be written
is restricted to a fixed list of event names and short values, and anything
else is dropped before it reaches the file. But it does record *when* the app
was used and how a dictation ended when it ended badly. Someone reading it
learns that you dictated at 14:32 and how long you held the key — never what
the text was, and never which language you spoke. A dictation that simply
worked writes no outcome line; the one thing it can write is a measurement of
how unsure the language detector was, as bare percentages that name no
language. It holds the last 2,000 events. "Reveal the Diagnostic Log in Finder" in the menu
takes you to it.

## What leaves this Mac

Two things, and both go to this project's own GitHub releases, over HTTPS.

**The recognition models, once**, the first time you use the app. Each file is
verified against a checksum built into the app, and a file that does not match
it is deleted rather than used.

**A version check, once a day**, while the switch on Settings → Permissions is
on — it ships on, and you can turn it off there. It asks for one small signed
XML file and nothing else. What GitHub learns from it is what any web server
learns from any request: your IP address, the app's name and version in the
User-Agent, and the shape of the TLS connection. Nothing about you, your
settings or your dictation travels with it. Sparkle can also attach a profile of
your Mac — the macOS version, the CPU, the model, the memory — and this app does
not enable that; the key that would is absent from its Info.plist.

Two consequences worth stating rather than burying. GitHub publishes a download
count for every release asset, so the number of copies asking is visible to
anyone who cares to look, including us — it is a count of requests and nothing
more, and we neither collect it nor act on it. And when you accept an update,
the binary you audited is replaced by one you have not; it is signed with the
same certificate and verified against a key compiled into the copy you already
trust, and it is built from this same public source, but it is a different file
than the one you checked.

Nothing is downloaded and nothing is installed until you say so. There are no
accounts, no telemetry, no analytics, no crash reporting and no licence server.

There is one way you can send something yourself: **Report a problem…** opens
*your* mail client with the diagnostic log attached. That log holds app and macOS
versions, the Mac model, per-dictation timings and outcomes, and the identifier
of an audio device when one is lost or switched away from mid-dictation — never
transcript text. Nothing goes anywhere until you press Send, and you can read
and edit the attachment first.

## What this does not protect you from

Said plainly, because a privacy document that only lists its strengths is
advertising:

- **Someone using your unlocked Mac.** The key is available to the app while you
  are logged in, so anyone sitting at your machine can read your history in the
  app, exactly as you can.
- **Software running as you with sufficient privilege.** The encryption raises
  the cost considerably, but a program that can drive the Keychain prompt or
  read this app's memory is a different class of problem.
- **What you dictate into.** Once text is inserted it belongs to the receiving
  application and whatever that application does with it.

FileVault is worth switching on regardless. It protects a Mac that is switched
off; the measures here protect one that is running.

## Removing everything

Delete the app, then delete
`~/Library/Application Support/app.vocula.mac/` — that folder holds the
history, the diagnostic log and the downloaded models — and
`~/Library/Caches/app.vocula.mac/`, where an update is unpacked before it is
installed. The Keychain key can be
removed in Keychain Access; without the history files it opens nothing.

Settings and permissions are remembered elsewhere, and deleting the app does not
clear them: `defaults delete app.vocula.mac` removes your languages, key
bindings, microphone order and appearance, and `tccutil reset Microphone
app.vocula.mac` and `tccutil reset Accessibility app.vocula.mac` withdraw the two
permissions. If you built the app yourself, `./scripts/uninstall-local.sh` does
all of this and reports what it found. A login-item registration is the one thing
no script can reach — remove it in System Settings → General → Login Items.
