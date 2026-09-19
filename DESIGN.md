---
name: Dinner Time
description: The whole dinner as one station departure board, read from a metre away.
colors:
  board: "#ffffff"
  board-lit: "#fdeaea"
  board-deep: "#f3f3f1"
  board-ink: "#141414"
  board-dim: "#7a7a76"
  board-line: "#e4e4e0"
  board-cap-lit: "#3a3a38"
  red: "#d8232a"
  red-hover: "#e5333a"
  red-ink: "#ffffff"
  ground: "#ececea"
  paper: "#ffffff"
  ink: "#141414"
  muted: "#6a6a67"
  line: "#d7d7d3"
  field: "#ffffff"
  danger: "#b42318"
typography:
  clock:
    fontFamily: "Barlow Semi Condensed, Arial Narrow, Helvetica Neue, Arial, system-ui, sans-serif"
    fontSize: "2.75rem"
    fontWeight: 700
    lineHeight: 1.05
    letterSpacing: "-0.01em"
  time:
    fontFamily: "Barlow Semi Condensed, Arial Narrow, Helvetica Neue, Arial, system-ui, sans-serif"
    fontSize: "1.75rem"
    fontWeight: 700
    lineHeight: 1
    letterSpacing: "-0.01em"
  body:
    fontFamily: "Barlow Semi Condensed, Arial Narrow, Helvetica Neue, Arial, system-ui, sans-serif"
    fontSize: "1.1875rem"
    fontWeight: 500
    lineHeight: 1.35
    letterSpacing: "normal"
  name:
    fontFamily: "Barlow Semi Condensed, Arial Narrow, Helvetica Neue, Arial, system-ui, sans-serif"
    fontSize: "1.1875rem"
    fontWeight: 700
    lineHeight: 1.2
    letterSpacing: "normal"
  cap:
    fontFamily: "Barlow Semi Condensed, Arial Narrow, Helvetica Neue, Arial, system-ui, sans-serif"
    fontSize: "0.9375rem"
    fontWeight: 700
    lineHeight: 1
    letterSpacing: "0.06em"
rounded:
  box: "3px"
  chip: "4px"
  control: "6px"
  panel: "8px"
spacing:
  hair: "4px"
  tight: "6px"
  sm: "8px"
  md: "12px"
  row: "14px"
  lg: "16px"
  wide: "24px"
components:
  button-primary:
    backgroundColor: "{colors.red}"
    textColor: "{colors.red-ink}"
    typography: "{typography.cap}"
    rounded: "{rounded.control}"
    padding: "0 14px"
    height: "46px"
  button-primary-hover:
    backgroundColor: "{colors.red-hover}"
  button-secondary:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    typography: "{typography.cap}"
    rounded: "{rounded.control}"
    padding: "0 14px"
    height: "46px"
  button-danger:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.danger}"
    typography: "{typography.cap}"
    rounded: "{rounded.control}"
    padding: "0 14px"
    height: "46px"
  button-small:
    padding: "0 10px"
    height: "38px"
  input:
    backgroundColor: "{colors.field}"
    textColor: "{colors.ink}"
    typography: "{typography.body}"
    rounded: "{rounded.control}"
    padding: "0 12px"
    height: "46px"
  card:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    rounded: "{rounded.panel}"
    padding: "16px"
  board:
    backgroundColor: "{colors.board}"
    textColor: "{colors.board-ink}"
    rounded: "{rounded.panel}"
  departure-row:
    typography: "{typography.name}"
    padding: "12px 14px"
    height: "60px"
  departure-row-current:
    backgroundColor: "{colors.board-lit}"
    textColor: "{colors.board-ink}"
  departure-row-serve:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.paper}"
  departure-row-serve-current:
    backgroundColor: "{colors.red}"
    textColor: "{colors.red-ink}"
  platform-box:
    typography: "{typography.cap}"
    rounded: "{rounded.box}"
    padding: "0 6px"
  platform-box-hands:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.paper}"
  chip-cook:
    textColor: "{colors.red}"
    rounded: "{rounded.chip}"
    padding: "0 10px"
    height: "34px"
  chip-cook-hover:
    backgroundColor: "{colors.red}"
    textColor: "{colors.red-ink}"
  tabs:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.muted}"
    typography: "{typography.cap}"
    height: "60px"
  tabs-on:
    textColor: "{colors.red}"
  notice:
    backgroundColor: "{colors.red}"
    textColor: "{colors.red-ink}"
    rounded: "{rounded.control}"
    padding: "10px 14px"
---

# Design System: Dinner Time

## Overview

**Creative North Star: "The Station Departure Board"**

The dinner is one departure board. Every step is a row: a time on the left, what and where in the middle, a lamp and a one-word status on the right. The board is a white enamel field with black tabular numerals and grey captions, like the mechanical timer on the kitchen shelf; it is one object in one finish, day and night, and does not follow the phone's colour scheme. Around the board sits the concourse: a light grey ground with ruled white forms. The two materials are close cousins (white on grey) and are told apart by the 1px rule and the 8px corner, not by contrast.

One typeface (Barlow Semi Condensed, self-hosted at 500 and 700) at four fixed sizes does all the work. Hierarchy is carried by size, weight and ink-versus-grey, not by colour or ornament. Red is the only hue and it is reserved: on the board it means NOW or LATE (the lamp, the state word, the countdown); on the concourse it means the one primary action. Late is a word and a lit ring, never an alarm.

The system is dense but glanceable. Rows are 60px tall with 28px times so the current step reads from a metre away; captions and controls sit at 15px because they are read at arm's length. Motion is nearly absent: the current band fades in over 0.4s, lamps snap between states, nothing pulses. Icons are inline SVG strokes only; the app icon shares the same three materials (white face, black hands, one red hand).

**Key Characteristics:**
- White board on a light grey concourse, one scheme in both OS modes
- One face, four sizes (15 / 19 / 28 / 44), tabular lining numerals everywhere
- One red, reserved for NOW, LATE, countdowns and the primary action
- Status as a lamp plus a spelled-out word; colour never carries meaning alone
- Platform-style boxes for Oven 1, Oven 2, Hob, and a black-filled Hands-on
- Ruled 1px dividers, no shadows at rest, no decorative imagery

## Colors

A white board with black type and warm-grey dimming, one red lamp, a pale red band under the row that needs you, and a light grey concourse of ruled white forms; the whole thing is a single light scheme.

### Primary
- **Enamel White** (`board`): the field of every board: cook timeline, home departures, dish sections in the editor, and the title bar on board pages.
- **Pale Red Band** (`board-lit`): the one tinted band under the current row on the cook board, an open step in the editor. It is the attention row, not the accent: it never carries text of its own meaning and is always paired with black type.
- **Board Deep** (`board-deep`): the page ground behind the cook board, a shade below white so the board's edges read on wide screens.
- **Board Ink** (`board-ink`): times, names, the banner step name, board-head counts, running-row state words. The only full-strength value on the board.
- **Board Dim** (`board-dim`): captions, waiting times and names, waiting lamps, waiting and done state words, column heads, chevrons, drag handles, the Edit mark.
- **Board Rule** (`board-line`): every 1px divider inside or around a board, the tabs' top rule, and the board-page title bar's rule.
- **Lit Caption** (`board-cap-lit`): captions inside a current or running row, a step darker than Board Dim so the whole row steps up together. Set as a literal in the stylesheet, not a custom property.

### Secondary
- **Timer Red** (`red`): the lamp disc for NOW, the lamp ring for LATE, the state word and countdown on both, the serve row once serving time has passed with steps outstanding, the active tab and its 2px top rule, the primary button, the notice bar, the Cook chip's stroke, the open menu button, checkbox accent, text caret, selection and focus ring. Nothing else.
- **Red Hover** (`red-hover`): primary button hover only.
- **Red Ink** (`red-ink`): text on any red surface. It is white; on this palette red is always a filled shape with white type or a stroke with red type.

### Tertiary
- **Danger Red** (`danger`): text colour of Remove and Delete buttons on the concourse. Darker and duller than Timer Red so a destructive control never reads as a lamp. It never appears on the board.

### Neutral (the concourse)
- **Grey Ground** (`ground`): page background and sticky title bar on home and editor pages; the `theme-color` off the board.
- **Paper** (`paper`): cards, menu sheet, secondary buttons, the bottom tabs, the open step editor inside a dish board, a dragged step. Same white as the board, told apart by its 1px rule.
- **Ink** (`ink`): body text on the concourse, the serve row's fill, the Hands-on box's fill.
- **Muted** (`muted`): form labels, hints, empty states, placeholder text, the tabs at rest, hover border of controls.
- **Rule** (`line`): 1px borders on cards, controls, the title bar and the device list.
- **Field** (`field`): input and select backgrounds.

### Named Rules
**The Red Reservation Rule.** On the board, red means one of two words: NOW or LATE. On the concourse it means the single primary action. Destructive text is `danger`, not `red`. Any third meaning dilutes the lamp.

**The One Scheme Rule.** `color-scheme: light` is declared and there is no `prefers-color-scheme` block. The board and the concourse look the same on a phone in dark mode as in light; the four review captures were taken with the OS in dark mode to prove it. Native controls (date and time pickers) follow suit.

**The Spelled-Out Rule.** No status, place or hands-on flag is carried by colour alone. Every lamp has its word; every place has its box with the name in it.

## Typography

**Display Font:** Barlow Semi Condensed 700 (with Arial Narrow, Helvetica Neue, Arial, system-ui)
**Body Font:** Barlow Semi Condensed 500 (same stack)

**Character:** A single narrow grotesk at two weights, set with `tabular-nums lining-nums` on the body so every time column aligns. Condensed width is what lets 28px times and 19px names share a phone row. Headings are tracked in slightly (-0.01em) and `text-wrap: balance`. Both weights are preloaded and self-hosted as woff2.

### Hierarchy
- **Clock** (700, 44px / 2.75rem, 1.05): held in reserve. No element ships at this size since the banner replaced the three-clock row; it stays in the ramp as the size a single glanceable number would take.
- **Time** (700, 28px / 1.75rem, 1): row start times, the banner countdown and the banner step name, the page title in the bar, minutes in the step editor.
- **Body** (500, 19px / 1.1875rem, 1.35): running text, hints inside boards, the "Now: ... next in" line, checkbox labels, inputs, the Serving line on the editor.
- **Name** (700, 19px, 1.2): step and plan names, card headings, dish headings (uppercase, .06em).
- **Cap** (700, 15px / 0.9375rem, uppercase, .04-.1em tracking): everything small: captions, form labels, state words, platform boxes, buttons, tabs, board heads, column heads. Tracking widens with role: boxes .04em, buttons .05em, labels and states .06em, board heads .08em, tabs and clock heads .1em. Captions that are not labels (dish, duration, countdown, hints) are 15px at 500 and sentence case.

### Named Rules
**The Four Sizes Rule.** 15, 19, 28, 44. A new surface picks from these; it does not add a fifth.

**The Tabular Rule.** Every number is tabular lining. Times are 700; a unit or suffix beside a number drops to 500 and 15px (the `min` after minutes in the editor).

**The Uppercase-Is-Small Rule.** Uppercase is only ever at 15px with tracking, and only for labels, states, boxes, buttons and heads. Body copy and names are sentence case; the one exception is dish headings on the editor board (19px uppercase), which act as section heads of a board.

## Layout

Single column. Concourse content sits in a 680px `wrap` with 14px 16px padding (20px 24px from 720px). The cook page is a full-bleed white board up to 820px on a `board-deep` ground, ruled left and right with `board-line` on wide screens rather than rounded or shadowed.

Vertical chrome: a sticky title bar at the top (10px vertical padding plus the top safe-area inset, 1px rule beneath; ground-coloured on the concourse, white on board pages), fixed bottom tabs 60px tall plus the bottom safe-area inset, and on the cook page a second sticky band (the banner) pinned under the bar at its measured height. Body padding-bottom clears the tabs.

The board grammar is the row. A departure row is a three-column grid: `max-content` time, fluid main, right-hand lamp or affordance (64px lamp well on the cook page; a chevron plus an absolutely placed Cook chip on home, with 130px right padding to clear them; a 44px drag handle at left and minutes at right on the editor). Rows are 12px 14px padded (14px 20px from 720px), at least 60px tall, and separated by 1px `board-line` rules, never by gap. Inside the main cell, name, caption and countdown stack with a 3px gap; caption items wrap with a 4px 8px gap.

Concourse forms stack at 12px (`stack`), pair controls in a wrapping flex `row` at 8px, and cards sit 12px apart with 16px inside. Menu sheets drop from the bar at `min(92vw, 360px)` with 14px padding and 10px internal gap. Dish boards sit 14px apart in the editor.

One breakpoint (720px) only loosens padding and rules the cook board's edges. Nothing reflows.

## Elevation & Depth

Flat by default. Depth on the board is tonal and very shallow: `board-deep` ground, `board` field, `board-lit` band, then the `ink` serve row as the one dark object. On the concourse depth is a 1px `line` rule around white on grey. No surface at rest carries a shadow. Row hover on the cook board is a 2.5% black wash.

### Shadow Vocabulary
- **Sheet drop** (`box-shadow: 0 14px 34px -10px rgba(0, 0, 0, .3)`): the menu sheet that opens from the title bar, because it floats over content.
- **Drag lift** (`box-shadow: 0 16px 30px -10px rgba(0, 0, 0, .35)`): a step while it is being dragged. Removed on drop.

Both are neutral black, offset downward, heavily negative-spread; they read as an object lifted off the board, not as an outline.

### Named Rules
**The Lifted-Only Rule.** A shadow appears only while something is physically above the page (an open sheet, a dragged row). Nothing at rest is shadowed.

**The One Band Rule.** Exactly one row on the cook board sits on `board-lit` at any moment: the current step (the hands-on one when several run at once, else the one ending soonest). Other running steps darken to `board-ink` type but stay on the white field. A late step keeps the field and lights its ring red; it only takes the band if nothing else is current.

## Shapes

Small, tight radii that scale with the object: 3px on platform boxes, 4px on the Cook chip and the focus ring, 6px on every control (buttons, inputs, selects, the notice, the menu button, a dragged step), 8px on panels (cards, boards, the menu sheet). Corners are never larger than 8px and nothing is a pill.

Borders are 1px `line` on the concourse and 1px `board-line` on the board, 1.5px `currentColor` on platform boxes and 1.5px `red` on the Cook chip, 2px `red` on focus at 2px offset. Lamps are 24px SVG circles: a 2px grey ring waiting, a red disc with an 18% red halo now, a 3px red ring with the same halo late, a 3px black ring running, a grey disc with a white tick done.

## Components

### Buttons
Blocky, uppercase, control-height: they read as timer buttons rather than web buttons.
- **Shape:** 6px radius, 46px tall, 0 14px padding, 15px 700 uppercase with .05em tracking.
- **Primary:** red field, white text, red border. One per form or sheet.
- **Secondary:** white field, ink text, 1px `line` border; hover darkens the border to `muted`.
- **Danger:** secondary with `danger` text. Only for Remove and Delete.
- **Small:** 38px tall, 0 10px padding, for shift-time and dish-move rows.
- **Hover / Focus:** primary hovers to `red-hover`; all controls take the global 2px red focus ring at 2px offset. Disabled is 50% opacity.

### Chips
- **Cook chip** (home board): 34px tall, 4px radius, 1.5px red stroke, red uppercase text, absolutely positioned at the row's right edge inside the chevron. Hover fills red with white text. It is the only outlined red element.

### Cards / Containers
- **Card** (concourse): 8px radius, white field, 1px `line` border, 16px inside, 12px between. Heading is Name size with 8px below.
- **Board:** 8px radius, white field, `overflow: hidden`, no border (the grey ground is its edge). Optional `board-head`: 15px uppercase .08em `board-dim` with a bold `board-ink` count, 1px rule beneath.
- **Menu sheet:** white, 8px radius, 1px `line`, 14px padding, sheet drop shadow, opened from a `details` in the bar; the summary fills red with white dots while open.
- **Notice:** red bar, 6px radius, 10px 14px, 700 weight, white text.

### Inputs / Fields
- **Style:** 46px tall, 0 12px, 6px radius, white `field` background, 1px `line` border, body type. Full width of their column.
- **Label:** 15px uppercase .06em `muted` above, 6px gap. Checkbox labels are body size, sentence case, 22px box with red `accent-color`, 46px min height.
- **Hover:** border to `muted`. **Focus:** global red ring. **Disabled:** 50% opacity. Caret and selection are red.

### Navigation
- **Title bar:** sticky, ground-coloured (white on board pages), 1px rule, chevron back at left, Time-size title truncated to one line, three-dot menu at right.
- **Tabs:** fixed bottom, white with a 1px `board-line` top rule, 60px plus safe area, two equal links in Cap type with .1em tracking, `muted` at rest; the active tab is red with a 2px red inset top rule.

### Departure Row (signature)
The unit of the whole system. Time (28px 700) at left, then name (19px 700) over a caption line (15px `board-dim`: dish, platform boxes, duration and end time, and a "Moved earlier" tag when the scheduler shifted it), then the lamp well (64px) with a 24px lamp over its state word. Rows are `label`s wrapping a hidden checkbox so the whole row is the tap target; hover is a 2.5% black wash. States, set by the render loop:
- **Waiting:** grey 2px ring, `board-dim` time and name, word "Waiting", countdown "in m:ss".
- **Running** (concurrent, not the band): black 3px ring, ink type, `board-cap-lit` caption, word "Now" in `board-ink`.
- **Current** (the band): `board-lit` background, red disc with halo, ink type, red "Now" and red countdown "m:ss left".
- **Overdue:** red 3px ring with halo, ink type, red "Late" and "late by m:ss". Never pulsing, never an alarm.
- **Done:** grey disc with white tick, name struck through at 1.5px, everything at `board-dim` 75% opacity, no countdown.
- **Serve row:** inverted, `ink` field with white type, no lamp; turns red with white type once serving time passes with steps outstanding.
The background transition is `.4s cubic-bezier(.16, 1, .3, 1)` and is switched off under `prefers-reduced-motion`. Lamp state changes snap.

### Platform Box (signature)
A place is a box: 1.5px `currentColor` border, 3px radius, 0 6px padding, 15px 700 uppercase .04em, inheriting the row's caption colour. Hands-on is the filled variant (`ink` fill, white text) and stays black in every row state; it is the darkest thing on a waiting row on purpose, because it is the one place the cook's hands are needed.

### Banner (signature)
Sticky under the bar on the cook page, three lines and a progress rule, always about exactly one step:

1. **Head** — the state word in Cap caps at .1em (`Now` and `Late` in `red`, `Next` and the finished states in `board-dim`), the step's dish and place beside it in 15px `board-dim`, and on the right the countdown at Time size with its unit in Cap caps beside it. `Now` counts down the time left, `Late` counts up the time over, `Next` counts down to the start, and a finished board counts down to serving.
2. **Name** — the step itself at Time size, 700, the largest black type on the page.
3. **Foot** — "Then hh:mm <next step>" on the left, "Serve hh:mm" on the right, both 15px `board-dim`.

4. **Cooking strip** — present only while something is running unattended: one line of `OVEN 1 Beef until 23:32` entries in 15px `board-dim` above a hairline, ordered by which wants the cook back first, ellipsised rather than wrapped.

A 3px `red` rule along the bottom edge fills with the running step's progress and sits full while a step is late. The whole banner takes the `board-lit` wash and a `red` bottom rule in the late state.

**The Two Kinds Rule.** A step the cook must stand over (hands-on) occupies them; every other step with a duration is a timer they can walk away from. The banner only ever names the first kind, or the next step due, or says "Nothing to do until then". A timer never becomes the instruction, because it asks nothing; it reports itself on the cooking strip and in its own row. Priority when several things are true at once: something late, then a timer that has finished, then the hands-on step in progress, then the next step due.

The banner never repeats the list: it carries the focus step's countdown, so that step's own row shows none, and the list auto-scrolls to the step *after* the banner's, putting the focus row one flick above the fold. It shows dish and place precisely because its row is usually off-screen above.

State words and lamps, one pair per condition: **Waiting** an empty `board-dim` ring; **Cooking** the same ring with a `red` core, a timer running with nothing asked of the cook; **Now** a solid `red` disc with its glow, the hands-on step in progress; **Ready** a thick `red` ring with a core, a timer that has run out; **Late** a thick `red` ring; **Done** a `board-dim` disc with a white tick. The lit `board-lit` band goes only to the step the banner names, and only once it has started.

`--bar-h` and `--stick` are measured in script and set on the cook element: the banner pins at `--bar-h` so no row can show through under the title bar, and rows carry `scroll-margin-top: var(--stick)` so an auto-scrolled row clears the whole sticky stack.

## Do's and Don'ts

### Do:
- **Do** put every list of timed things on a white board as departure rows with a 28px time, a name and a right-hand status; the home page's plans list uses the same row as the cook timeline.
- **Do** keep one light scheme; do not add a `prefers-color-scheme` block or per-scheme tokens.
- **Do** spell out every state, place and hands-on flag as a word inside a box or beside a lamp; colour is reinforcement.
- **Do** pick from 15 / 19 / 28 / 44 and from 700 / 500 only; set numbers tabular.
- **Do** separate rows with 1px rules and lift only what is physically above the page (sheet, drag).
- **Do** keep controls 46px tall (38px small) with 6px corners, and make the whole row the tap target.
- **Do** self-host every asset; one stylesheet, one script, no CDN.

### Don't:
- **Don't** use red for a third meaning. On the board it is NOW or LATE; on the concourse it is the one primary action. Destructive text uses `danger`.
- **Don't** let a timer become an instruction: if it asks nothing of the cook, it belongs on the cooking strip, not in the banner.
- **Don't** pulse a lamp, sound the board, or animate anything other than the current band's background.
- **Don't** put more than one row on `board-lit` at a time.
- **Don't** add a fifth type size, a second typeface, or a system display face.
- **Don't** shadow a surface at rest, or round a corner past 8px.
- **Don't** introduce photos, illustrations or icon fonts; the only icons are inline SVG strokes (chevrons, dots, plus, drag handle, lamp).
