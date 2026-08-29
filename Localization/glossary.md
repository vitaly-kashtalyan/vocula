# Glossary

What must not vary. A translator working one screen at a time cannot see that
the sidebar says `Microphone` three lines above a sentence quoting Apple's
Microphone pane — and two individually correct German words there read as a bug.
This file is what makes that decision once.

Committed, and checked by `Tests/VoculaKitTests/GlossaryTests`: every term below
must still appear in an English catalog value. A term that no longer appears is
a RETIRED term and a failure, because a glossary that has rotted is worse than
none.

## Never translated

| Term | Why |
|---|---|
| `Vocula` | The product name. |
| `Whisper` | The recognition engine, a product name. |
| `Parakeet` | A second engine, a product name. Not shipped yet — no model in the manifest names it. |
| `Large v3 Turbo` | The model's upstream name. |
| `Silero` | The voice-activity model's upstream name. |
| `fn` | A key, as printed on the keyboard. |
| `Esc` | A key, as printed on the keyboard. |
| `⌘V`, `⌃⇧L`, `⌘Q`, `⌘W`, `⌘Tab`, `⌘Space` | Key chords. The glyphs are the keys. |
| `🌐` | The globe key's own glyph. |
| `tccutil reset Microphone app.vocula.mac` | A command the user TYPES. |
| `/Applications` | A filesystem path. |
| `Raycast`, `Alfred`, `Karabiner`, `BetterTouchTool`, `JetBrains` | Other people's products. |
| `MIT`, `CC-BY` | Licence identifiers. |

## Apple's own names — use what that system says, not a translation of ours

These are read off a real Mac in the target language, never invented.

| English | Where it appears |
|---|---|
| `System Settings → Privacy & Security → Microphone` | `OnboardingModel.microphonePath` |
| `System Settings → Privacy & Security → Accessibility` | `OnboardingModel.accessibilityPath` |
| `System Settings → General → Login Items & Extensions` | `OnboardingModel.loginItemsPath` |
| `System Settings → Keyboard → Press 🌐 key to` | `OnboardingModel.keyboardPath` |
| `System Settings → Screen Time → Content & Privacy` | `OnboardingModel.screenTimePath` |
| `System Settings → Sound → Input` | `refusal.silentInput.volumeDown` |
| `Press 🌐 key to → Do Nothing` | The globe row's title, verbatim from the Keyboard pane |
| `Finder` | Reveal in Finder, and the diagnostics menu item |
| `Dock` | The appearance note about the indicator strip |
| `Spotlight` | The ⌘Space binding warning |
| `Terminal` | The tccutil instruction |
| `Auto` | macOS's automatic appearance |
| `Cancel`, `Delete` | Standard dialog buttons — macOS has its own words |
| `Send` | The mail client's send button |

`Sources/VoculaKit/KeyBinding/SystemHotkeys.swift` holds fifteen more of the
same class, and they are CATALOG KEYS now (`hotkey.*`) rather than a table of
English literals — a conflict warning in a German window has to name the row
that Mac's own pane names — the macOS Keyboard-Shortcuts row names: Move focus to the menu bar,
Move focus to the Dock, Mission Control, Application windows, Show desktop,
Select the previous input source, Select the next input source, Spotlight,
Spotlight search in Finder, Move one space left, Move one space right, Help,
Launchpad, Notification Centre, Quick Note. Every one must match that Mac's own
wording.

## Our own names — one word each, everywhere

The sidebar's section names are quoted inside other sentences ("Open Settings →
Models", "in this app's Microphone settings"), and the Status dashboard reuses
three of them for its cards. They take the SAME key, so they cannot drift; a
translation must pick one word per row and use it in prose too.

| English | Key |
|---|---|
| `Status` | `settings.section.status` |
| `Permissions` | `settings.section.permissions` |
| `Keyboard` | `settings.section.keyboard` |
| `Languages` | `settings.section.languages` |
| `Microphone` | `settings.section.microphone` |
| `Models` | `settings.section.models` |
| `History` | `settings.section.history` |
| `Diagnostics` | `settings.section.diagnostics` |
| `Licence` | `settings.section.licence` |
| `Appearance` | `settings.section.appearance` |
| `Dictation`, `Data`, `App` | The three sidebar group headings |
| `Copy the last transcript` | The menu item, quoted by every refusal that offers recovery |
| `Test` | A VERB, on both the Keyboard and Microphone screens — one word for both |

## Per language

**`dictation`** is the word the whole product turns on, and every language has
to choose ONE rendering and hold it: the noun for the act, the noun for one
saved recording, and the verb are all in the copy. Fill this in as each locale
is reviewed.

| Locale | dictation (act) | a dictation (record) | to dictate |
|---|---|---|---|
| `de` | Diktat | Diktat | diktieren |
| `ru` | диктовка | диктовка | диктовать |
| `es` | dictado | dictado | dictar |
| `fr` | dictée | dictée | dicter |
| `it` | dettatura | dettatura | dettare |
| `pt-BR` | ditado | ditado | ditar |
| `uk` | диктування | диктування | диктувати |
| `pl` | dyktowanie | dyktowanie | dyktować |

**Plural categories are not a translator's choice, they are CLDR's**, and the
same three English words have three different right answers:

| Locale | what `one` covers | so `licence.trialDaysLeft` one-form is |
|---|---|---|
| `en`, `es`, `de`, `fr`, `it`, `pt-BR` | exactly 1 | the words "last day" |
| `ru`, `uk` | 1, 21, 31, 101 | a COUNT — "last day" would lie at 21 |
| `pl` | exactly 1 (21 is `many`) | the words "last day" |

`App/VoculaTests/RussianPluralTests` asserts the value at n = 1, 2, 5, 21 and
101 for exactly this reason. A set-size assertion passes with the forms in the
wrong slots.
