# Contributing

**Pull requests are not accepted.** Not "rarely", not "after review" — the
policy is a flat no, and it is not about the quality of the code offered.

## Why

Copyright follows authorship. A patch merged from someone else leaves their
copyright inside this tree, permanently and without a paper trail. GPL-3.0
keeps distribution working, but it does not consolidate ownership, and two
things stop being possible the moment a single foreign line lands:

- **Relicensing.** Vocula is GPL-3.0 with a paid, notarised binary. Selling that
  binary under any other terms — a commercial licence beside the GPL one, which
  is the ordinary shape of this model — needs permission from every copyright
  holder in the tree, for ever.
- **A clean title.** Anyone acquiring or licensing this work has to be told who
  owns what. "Some of it, from strangers, over several years" is an answer that
  ends conversations.

The usual remedy is a Contributor Licence Agreement — a signed assignment
before a patch is taken. That is a process to run and a record to keep, and this
is a one-person project. Refusing patches costs less and leaves nothing to
administer or lose.

None of this is a judgement about the person offering the patch, and saying so
here rather than in a closing comment is the point: nobody should discover it
after doing the work.

## What is genuinely wanted

- **Bug reports.** Especially with `Settings → Diagnostics` attached — that log
  records anomalies rather than routine, so a line in it is usually the whole
  story. It contains no transcripts.
- **Measurements that contradict what this app claims.** Every number behind a
  decision here was taken on one Mac, one microphone, two languages. A
  measurement from a different machine is worth more here than a patch.
- **Anything about a language.** Whisper's output in a language nobody here
  speaks, an interface string that reads wrong to a native speaker, a plural
  form that is not a plural form.

Open an issue. There is no template to fill in.

## Forking

Fork freely — that is what GPL-3.0 is for, and it needs no permission or
notification. Ship your own build, change whatever you like, including the
licence check. The obligation the licence puts on you is to carry it forward:
your fork stays GPL-3.0 and its source stays available to whoever you give it to.

## Building it

In [README.md](README.md), under "Build it yourself". A clone builds with no Apple
account at all.
