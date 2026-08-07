# TestFlight — Beta App Description (first public beta, v0.5.25)

Paste into App Store Connect → TestFlight → Test Information → **Beta App Description**.
~2,600 characters (limit 4,000).

---

Thank you for trying the first public beta of Keep Contact.

**What it is**

Keep Contact is for people who live alone, or spend long stretches alone, and
for the people who worry about them. It answers one question: *if something
happened, how long before anyone noticed?*

Most safety apps ask you to check in. Keep Contact tries not to. It reads
ordinary signs from your own phone — that you have used it, that you have moved
about — and stays completely silent while those look normal for you. It has no
daily task, no streak, nothing to remember.

When the signs go quiet for longer than is usual **for you**, it asks you first.
A notification, and a gesture to say you are fine. Only if you do not answer does
it tell the people in your circle. The order matters: your circle should hear
from Keep Contact rarely, so that when they do, they take it seriously.

**Where this build honestly stands**

The circle, the alerts and the escalation work and have been in daily use for
some weeks. What is new, and what we most need tested, is Keep Contact's ability
to tell you are fine on iPhone **while the app is closed**. Until recently it
only knew you were okay for as long as you had it open — which meant a quiet
afternoon looked exactly like a real emergency. That is now handled by two
background paths, and they are the newest part of the app.

So: expect it to be quiet and mostly invisible. Expect the occasional alert that
should not have happened. Please tell us about those.

**Permissions, and what each is really for**

- **Notifications** — how Keep Contact reaches *you* before it reaches anyone
  else. If you decline these, it cannot ask you first.
- **Motion & Fitness** and **Health (steps, read only)** — so that walking about
  counts as a sign you are fine. Keep Contact never writes to Health, and your
  step counts are not uploaded; only the fact that there was movement, and when.
- **Location (Always)** — used only to restart Keep Contact's background
  guardian if iOS shuts it down. No coordinate is read or sent for this.
- **Emergency location sharing** is separate, off by default, and lives on the
  Me screen. Your position is only ever fetched or shared if you turn that on,
  and only during an SOS.

Declining any of them leaves the app working, with fewer ways to tell you are
fine — which means a slightly higher chance of being asked when you were never
in trouble.

**What would help us most**

1. Just live with it for a few days. It should stay out of your way.
2. **Report every alert that was wrong.** You were fine, and it asked anyway —
   roughly when, and what you were doing. This is the single most valuable
   report you can send us, more than any crash.
3. Tell us if anything on screen claims something you doubt. If a switch says it
   is protecting you, we want to know when it is not.

A false alarm is not a small bug here. Every unnecessary alert makes a circle a
little slower to react to the next one, and the next one might be real. If Keep
Contact bothers you or your family for nothing, that is the bug we want most.
