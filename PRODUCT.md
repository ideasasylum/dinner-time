# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

One cook, Jamie, planning and cooking a multi-dish dinner at home, mostly a Sunday roast. Planning happens
seated on a phone or Mac; cooking happens with the phone propped on the kitchen counter, hands wet or busy,
glancing from a metre away between tasks. Nobody else uses it (confirmed 2026-09-19).

## Product Purpose

Work a dinner backwards from serving time so every dish lands together, then cook to that clock with an
alert for every step. Success is a roast where the meat has rested, the gravy is made, the yorkshires come
out as everyone sits down, and the cook never had to hold the schedule in their head.

## Positioning

A plan is a set of dishes, each a chain of steps that ends at serving time; the scheduler resolves hands-on
clashes by moving the lower dish earlier, and the plan itself owns a server-side timer that sends a native
notification when each step is due. A kitchen timer counts one thing down; a recipe lists steps without a
clock; this holds the whole dinner against the clock and tells you what to do now.

## Operating Context

- Two ovens and a hob; steps are labelled with where they happen. Ovens and the hob hold several things at
  once, so only hands-on steps are exclusive.
- Plans are reused week to week (copy for next week) and adjusted live (serving time nudged by 5 or 15
  minutes when running late; steps ticked off as done).
- Installed as a PWA on the phone; alerts arrive as Web Push notifications, so the phone can be asleep.
- Local dev with `melee dev`; deployed with `melee push` to a melee server.

## Capabilities and Constraints

- Plans, dishes, steps (name, minutes, place, hands-on), drag-to-reorder within and across dishes.
- Cook view: vertical timeline of computed start times, live clock, countdowns, tick boxes, shift serving
  time, untick everything, keep screen on.
- Alerts: per-device Web Push subscriptions, send-a-test, in-page chime while open.
- Built on melee (Ruby compiled by Spinel): server-rendered ERB, one hand-written stylesheet, one hand-written
  script, no gems, no bundler, no asset pipeline, static files in `public/`. No web fonts unless self-hosted
  (woff2 is servable). Offline shell via service worker.
- Terminology: plan, dish, step, serving time, hands-on, Oven 1, Oven 2, Hob.

## Brand Commitments

Name: Dinner Time. Icon: a clock face on burnt orange. Binding visual constraint volunteered by Jamie
(2026-09-19): "like a clear kitchen timer or cookbook. modern. easy to read at a glance. not too fussy."

## Evidence on Hand

- A Sunday roast preset (beef, roast potatoes, yorkshire puddings, veg, gravy) in `lib/presets.rb`.
- No photos, illustrations or testimonials, and none should be fabricated.

## Product Principles

1. Glanceable first: the thing to do now, and when the next thing is, must read from a metre away.
2. The clock is the truth: every screen relates to serving time; nothing asks the cook to do arithmetic.
3. Calm under pressure: late is a nudge, not an alarm; the interface never shouts.
4. Hands busy, eyes free: big targets, one-thumb operation, no precision gestures mid-cook.
5. Plans are reused: editing must stay quick enough to adjust a plan the same week.

## Accessibility & Inclusion

Read at arm's length in a bright kitchen and in a dim one (dark mode follows the phone). Colour never carries
meaning alone; oven, hob and hands-on labels are always spelled out.
