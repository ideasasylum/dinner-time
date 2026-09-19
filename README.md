# Dinner Time

Live at [dinner.apps.ideasasylum.com](https://dinner.apps.ideasasylum.com).

A phone-first web app for planning a dinner backwards from the time you want to eat, then cooking to the
clock with an alert for every step. Built on [melee](https://melee.ideasasylum.com/).

## How a plan works

- A **plan** has a name and a serving time.
- A plan has **dishes** (Beef, Roast potatoes, Yorkshire puddings, Gravy…). Each dish is a **chain of steps**
  done in order, and the last step of every chain finishes at serving time.
- A **step** has a duration, an optional place (Oven 1, Oven 2, Hob) and a hands-on flag.
- Only one hands-on step can happen at a time. When two clash, the one from the dish lower down the list is
  moved earlier (and everything before it in its chain moves with it). Reorder the dishes to change who wins.
  Ovens and the hob are labels only, since they can hold several things at once.
- A step is either **hands-on**, which occupies you for its duration, or a **timer** you start and walk away
  from. The board only ever tells you to do the first kind. Timers report themselves on the cooking strip
  under the banner, so the beef roasting for two hours never poses as a task.
- The **Cook** tab lays the result out as a vertical timeline with a live clock, countdowns, tick boxes, and
  buttons to nudge the serving time when you're running late.

## Alerts

Each plan is a durable object with its own timer. Whenever the plan changes, it re-arms the timer for the
start of the next step nobody has been told about; when the timer fires, the worker sends one alert (several
steps starting together share one message) and re-arms. A plan typed in late does not alert for steps that
are already long past, and a step that moves back into the future gets a fresh alert.

Alerts are native notifications over Web Push (`lib/web_push.rb`: RFC 8291 aes128gcm encryption and RFC 8292
VAPID, sent with `Melee::HTTP.post`). Tap **Enable alerts on this device** on the home page in each browser
that should get them; **Send a test** checks the whole path. The VAPID keypair is minted once and kept with
`setting`; the browsers' subscriptions live in `push_subscriptions`, and one the push service reports gone is
dropped. Set the contact the push services see with `melee env VAPID_SUBJECT mailto:you@example.com`. On an
iPhone the app has to be on the home screen before Safari allows push.

The Cook page also chimes and buzzes while it is open, and **Keep screen on** holds a wake lock. The app
installs to the home screen as a PWA, and plans you have opened still load with the wifi down.

## Look

A station departure board: the cook page is a navy board of rows (time, step, dish and place, lamp and state
word), one lit band for the step to do now, amber only for NOW and LATE and primary actions. Type is Barlow
Semi Condensed, self-hosted in `public/fonts/`, at four sizes. The rules live in `DESIGN.md`; product truth in
`PRODUCT.md`; the direction contract is the first comment in `views/layout.erb`.

## Layout

```
app.rb                   routes; the plans index lives in the app database
lib/plan.rb              Plan < Durable: dishes, steps, ticks, the timer and the alert
lib/schedule.rb          the backwards scheduler (pure, tested)
lib/clock.rb             time formatting in the browser's zone, no Date, no server TZ
lib/alerts.rb            push subscriptions and the fan-out to every device
lib/web_push.rb          RFC 8291 encryption and VAPID, over Melee::HTTP
lib/presets.rb           the Sunday roast starter plan
db/migrations/           the plans index and push subscriptions
db/objects/plan/         each plan object's own tables
views/                   index (plans, devices), plan (step editor), cook (timeline)
public/app.js            drag to reorder, live timeline, push subscription, wake lock
public/sw.js             service worker: network-first pages and code, cache-first fonts and icons, push, notification click
public/fonts/            Barlow Semi Condensed 500 and 700, latin subset, under the SIL Open Font License (OFL.txt)
test/app_test.rb         melee test, including firing the timer
```

## Run it

```sh
melee dev              # CRuby, reload by restart, http://127.0.0.1:4567
melee test             # test/app_test.rb under CRuby
melee test --both      # the same file under CRuby and the compiled binary, diffed
melee check            # compile with Spinel, no deploy
melee push             # deploy to the server in melee.toml
melee objects Plan     # the plan objects and their pending timers
```

One compiled-runtime rule learned here: a durable method must not be named `shift`; `melee check` now lists
the sixteen names Spinel resolves to the built-in. The test file masks the VAPID key's shape so that
`melee test --both` can compare the two runs even though each database mints its own key.
