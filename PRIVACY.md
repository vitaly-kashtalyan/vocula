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

**Two other things open it: a meeting you record, described in the next section,
and Settings → Microphone, only while you are looking at it.** Settings →
Microphone draws a live level meter beside the microphone in use, so you can see
that it hears you before you rely on it. That needs the input open, and macOS
shows its orange recording dot for as long as it is. It closes the moment you
leave that section or switch to another app; nothing is recorded, because the
levels are measured and the audio is dropped rather than kept; and a device
that costs something to open — a Bluetooth headset, or an iPhone offered over
Continuity Capture — is never opened this way unless you press Test, since
opening a headset takes it out of stereo.

**Dictation never saves audio.** It is recognised in memory and discarded;
there is no setting to keep it, and dictation writes no file it could be
recovered from. A meeting does save audio, and that includes what you dictate
while one records: the meeting holds the same microphone and keeps every sample
it hears, so your dictated words are in that meeting's recording, and the
meeting notes when each dictation began and ended. Once the meeting is
transcribed, those words are in its transcript too, marked as dictated, and its
audio is deleted. The next section says how.

Recognition runs entirely on this Mac, using a model downloaded from this
project's GitHub releases.
No audio, no text and no metadata about what you dictate leave the machine at
any point.

**Clean-up, if you switch it on, runs on this Mac as well.** A language model,
downloaded when you ask for it, rewrites the transcript to remove filler before it is pasted.
It sees that text and nothing else, and the code that runs it makes no network
request.
When its result loses a number, a negation or a question, or changes the
language, the text as recognised is pasted instead. History keeps the text as
recognised beside the cleaned-up one.

## While you record a meeting

*Record Meeting (Beta)*, in Vocula's menu, records two tracks until you choose
*Stop Meeting*: your microphone, and the sound other apps play — the other side
of a call. It also stops by itself after 15 minutes in which neither track heard
anything, when the Mac goes to sleep, and when you quit Vocula. While it records,
and while Vocula transcribes recorded meetings afterwards, a second icon in the
menu bar says so; after a meeting that stopped by itself, stopped at sleep, or
could not start, after a transcript is ready, and when one could not be made or
read, that icon stays to say so until you dismiss it.

**While a meeting records, the Mac does not go to sleep by itself.** Vocula
holds an assertion against idle sleep for as long as the meeting lasts —
`pmset -g assertions` lists it as `vocula.meeting` — so the screen can still
sleep, but the Mac does not. Closing the lid or choosing Sleep still sleeps it,
and that ends the meeting. Any sound any app plays, however faint, counts as
something heard, so a meeting you forgot beside music or a video never reaches
its 15 silent minutes, and keeps the Mac awake until you stop it.

**The microphone stays open for the whole meeting**, and macOS shows its orange
dot for as long as it is. It is the microphone dictation would use at that
moment, taken from your order on Settings → Microphone, which the meeting reads
and never changes. A Bluetooth headset or an iPhone offered over Continuity
Capture is never opened for a meeting — holding one would take a headset out of
stereo for the whole call — so when dictation's microphone is one of those, the
meeting records other apps alone and says so.

**The sound other apps play is captured through macOS's System Audio Recording
permission**, which macOS asks for the first time you record a meeting. That is
everything this Mac plays, from every app, except Vocula's own sounds.

**After a meeting ends, Vocula transcribes it on this Mac**, together with any
earlier meeting still waiting, using its own copy of the recognition model
dictation uses — loaded only while it transcribes, and nothing is sent anywhere.
What your microphone heard becomes lines labelled *Me*, what other apps played
lines labelled *Others*. A line of yours whose words mostly repeat what other
apps played within a second and a half is left out, as the call heard back
through your speakers — so a short reply that echoes the other side can be lost.
It waits while you dictate. It stops when you record another meeting and starts
again once that one ends, from the beginning of the meeting it was on. Quitting
Vocula stops it too, and a meeting that ended because you quit is not
transcribed then: both wait, audio and all, until the next meeting you record
ends. Once a meeting's transcript is written and read back, its audio is
deleted, and speech the model missed or misheard — including speech in a
language you have not ticked — is gone with it, as is any piece of the
recording that can no longer be opened. *Recorded meetings*, below, says where the transcripts
are kept, under which key, and how to delete them.

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

**Recorded meetings**, in `~/Library/Application Support/app.vocula.mac/Meetings/`
— a folder per meeting, named by a random identifier, holding the recording in
pieces three seconds long until the meeting is transcribed, then its transcript,
and a header that says when the meeting started and ended, how it ended —
stopped by you, by itself, at sleep, at quit, or cut off — and when you dictated
during it. Nothing reaches that folder unencrypted: each piece, the transcript
and the header are sealed with AES-GCM in memory before they are written. The key is a second one in
your login Keychain — service `app.vocula.mac`, account `meetings`, separate from
the history's, account `history` — and what is said above about the history key
(what protects it, and that it is not bound to this Mac) is true of this one. It
is read when a meeting starts — if it cannot be read, the meeting does not
start — and again when Vocula transcribes meetings, lists their transcripts or
copies one; those later reads never create a key. The folders' dates still show when a meeting was recorded and roughly how
long it ran.

A meeting's audio stays there until its transcript is written, and until then it
is not small: each track is kept whole as 16 kHz mono 16-bit samples — the sound
of other apps through its silences too — which comes to about 115 MB per track
per hour, so about 230 MB for an hour of meeting. That is computed from the
format, not measured. If a meeting cannot be transcribed, its audio stays, and
Vocula tries again after the next meeting. The transcript stays until you delete
it: **this version cannot delete a meeting**, there is no button for it yet,
and nothing deletes one on a timer. Deleting the `Meetings` folder deletes every meeting in it. The
History switch does not apply to meetings, and neither does deleting history — a
day or everything — nor the one-year retention.

*Copy Transcript*, in Vocula's menu and in the meeting's own icon, puts the
transcript you choose on the clipboard as plain Markdown, leaving out what you
dictated during it. After Vocula restarts it lists nothing until you next record
a meeting, because the meeting key is not read before then. From there it is yours, like anything you copy: Vocula's
encryption does not follow it.

**A diagnostic log**, `diagnostics.json`, is **not** encrypted, and this is
worth being precise about. It never contains a transcript: what may be written
is restricted to a fixed list of event names and short values, and anything
else is dropped before it reaches the file. But it does record *when* the app
was used and how a dictation ended when it ended badly. Someone reading it
learns that you dictated at 14:32 and how long you held the key — never what
the text was, and never which language you spoke. A dictation that simply
worked writes no outcome line; what it can write is a measurement of how unsure
the language detector was, as bare percentages that name no language, and, with
clean-up on, how long a slow pass took or why its result was not used. Lines
about a model name the recognition engine, which says whether one of your
languages is outside the 25 that Parakeet hears. A meeting writes a line when it
starts and one when it stops, saying why it stopped and how many seconds each
track recorded and held sound; a line when it closes an earlier meeting that was
cut off, when it lets the Mac go to sleep, and when it loses the microphone or
opens it again; each transcription pass that transcribed anything writes one line
saying how many meetings it transcribed, how many seconds of audio and pieces it
went through, how many lines the transcripts hold and how many of yours were
dropped as echo, how many pieces of audio it could not open, how long it took
and waited for dictation, and which model it used — never the text; and a line
for each other problem it ran into. It holds the last 2,000 events.
"Reveal the Diagnostic Log in Finder" in the menu takes you to it.

## What leaves this Mac

Two things, and both go to this project's own GitHub releases, over HTTPS.

**The speech model and its voice-activity detector, by themselves, whenever a
launch finds them missing**: the first
launch; the first after an update that changes the engine, or after you pick an
engine on Settings → Models without downloading it; the first after a model was
removed — and at once when a model that will not load is replaced by Whisper. By
itself it never uses a connection macOS marks as expensive or Low Data — an
iPhone hotspot, a cellular link — and waits for another instead; Cancel on
Settings → Models, then its button, downloads on request over whatever you are
connected to. Which file is fetched depends on the languages your Mac lists and
the ones you ticked, so GitHub can tell whether one of them is outside the 25
that Parakeet hears. **The clean-up
model only when you ask for it.** Each file is verified against a checksum built
into the app, and a file that does not match it is deleted rather than used.

**A version check, once a day**, while the switch on Settings → Permissions is
on — it ships on, and you can turn it off there. A copy opened straight from its
disk image, or from the folder it was downloaded to, makes no check at all: the
updater refuses before asking. It asks for one small signed
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

Once you have switched that on, an update is downloaded in the background, so
that installing it does not depend on the network being there at the moment you
press. Nothing is installed until you say so. There are no accounts, no
telemetry, no analytics, no crash reporting and no licence server.

There is one way you can send something yourself: **Report a problem…** opens
*your* mail client with the diagnostic log attached. That log holds app and macOS
versions, the Mac model, per-dictation timings and outcomes, when a meeting
started and stopped, how much of it held sound and how long transcribing took,
and the identifier of an
audio device when one is lost or switched away from mid-dictation — never
transcript text. Nothing goes anywhere until you press Send, and you can read
and edit the attachment first.

## What this does not protect you from

Said plainly, because a privacy document that only lists its strengths is
advertising:

- **Someone using your unlocked Mac.** The key is available to the app while you
  are logged in, so anyone sitting at your machine can read your history in the
  app, and copy any listed meeting transcript from the menu bar, exactly as you
  can.
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
history, the recorded meetings and their transcripts, the diagnostic log and the
downloaded models —
and `~/Library/Caches/app.vocula.mac/`, where an update is unpacked before it is
installed. The Keychain holds two keys under `app.vocula.mac`, accounts
`history` and `meetings`; both can be removed in Keychain Access, and without
the files they open nothing.

Settings and permissions are remembered elsewhere, and deleting the app does not
clear them: `defaults delete app.vocula.mac` removes your languages, key
bindings, microphone order and appearance, and `tccutil reset Microphone
app.vocula.mac`, `tccutil reset Accessibility app.vocula.mac` and `tccutil reset
AudioCapture app.vocula.mac` withdraw the three permissions — quit Vocula
first: a reset under a running copy can stall the Mac's keyboard. If you built
the app yourself, `./scripts/uninstall-local.sh` does all of this and reports
what it found. A login-item registration is the one thing no script can reach —
remove it in System Settings → General → Login Items.
