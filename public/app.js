(() => {
  "use strict";
  const csrf = document.querySelector('meta[name="csrf-token"]').content;
  const $ = (sel, root = document) => root.querySelector(sel);
  const $$ = (sel, root = document) => Array.from(root.querySelectorAll(sel));

  const post = (url, fields) => {
    const body = new URLSearchParams({ _csrf: csrf, ...fields });
    return fetch(url, { method: "POST", body, headers: { "X-CSRF-Token": csrf }, credentials: "same-origin" });
  };

  // Forms that need the browser's timezone, and a sensible default date.
  $$("form[data-tz]").forEach(f => { f.querySelector('input[name="tz"]').value = new Date().getTimezoneOffset(); });
  $$("input[data-default-date]").forEach(i => {
    const d = new Date();
    if (d.getDay() !== 0) d.setDate(d.getDate() + ((7 - d.getDay()) % 7));
    const pad = n => String(n).padStart(2, "0");
    i.value = `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
  });
  $$("form[data-confirm]").forEach(f => f.addEventListener("submit", e => { if (!confirm(f.dataset.confirm)) e.preventDefault(); }));

  if ("serviceWorker" in navigator) navigator.serviceWorker.register("/sw.js").catch(() => {});

  // ---- Step editor: drag to reorder (pointer events, so it works with a thumb) ----
  const plan = $("#plan");
  if (plan) {
    let drag = null;
    const saveOrder = () => {
      const dishes = $$(".dish", plan).map(d => d.dataset.dish).join(",");
      const order = $$(".steps", plan).flatMap(list => $$(".step", list).map(s => `${s.dataset.step}:${list.dataset.dish}`)).join(",");
      post(`/plans/${plan.dataset.plan}/reorder`, { dishes, order }).catch(() => location.reload());
    };
    const placeholderAt = (target, y) => {
      const { placeholder } = drag;
      const list = target.closest(".steps");
      if (!list) return;
      const over = target.closest(".step");
      if (!over || over === placeholder) { if (!over && !list.contains(placeholder)) list.appendChild(placeholder); return; }
      const r = over.getBoundingClientRect();
      const before = y < r.top + r.height / 2;
      list.insertBefore(placeholder, before ? over : over.nextSibling);
    };
    plan.addEventListener("pointerdown", e => {
      const handle = e.target.closest(".handle");
      if (!handle) return;
      e.preventDefault();
      const step = handle.closest(".step");
      const rect = step.getBoundingClientRect();
      const placeholder = step.cloneNode(true);
      placeholder.classList.add("placeholder");
      placeholder.removeAttribute("id");
      step.parentNode.insertBefore(placeholder, step);
      step.classList.add("dragging");
      step.style.setProperty("--w", rect.width + "px");
      step.style.left = rect.left + "px";
      step.style.top = rect.top + "px";
      document.body.classList.add("is-dragging");
      drag = { step, placeholder, dy: e.clientY - rect.top, dx: e.clientX - rect.left, y: e.clientY, raf: 0 };
      handle.setPointerCapture(e.pointerId);
      const autoscroll = () => {
        if (!drag) return;
        const edge = 70, max = 14;
        if (drag.y < edge) window.scrollBy(0, -max * (1 - drag.y / edge));
        else if (drag.y > innerHeight - edge) window.scrollBy(0, max * (1 - (innerHeight - drag.y) / edge));
        drag.raf = requestAnimationFrame(autoscroll);
      };
      drag.raf = requestAnimationFrame(autoscroll);
    });
    plan.addEventListener("pointermove", e => {
      if (!drag) return;
      drag.y = e.clientY;
      drag.step.style.top = (e.clientY - drag.dy) + "px";
      drag.step.style.left = (e.clientX - drag.dx) + "px";
      const target = document.elementFromPoint(e.clientX, e.clientY);
      if (target) placeholderAt(target, e.clientY);
    });
    const finish = () => {
      if (!drag) return;
      cancelAnimationFrame(drag.raf);
      const { step, placeholder } = drag;
      placeholder.parentNode.insertBefore(step, placeholder);
      placeholder.remove();
      step.classList.remove("dragging");
      step.style.cssText = "";
      document.body.classList.remove("is-dragging");
      drag = null;
      saveOrder();
    };
    plan.addEventListener("pointerup", finish);
    plan.addEventListener("pointercancel", finish);
    plan.addEventListener("click", e => { if (e.target.closest(".handle")) e.preventDefault(); });
  }

  // ---- Passkeys: the two WebAuthn ceremonies ----
  //
  // Everything crossing the wire is base64url, because an ArrayBuffer does not survive a form post. The
  // public key comes from getPublicKey() rather than out of the attestation object, which is what saves the
  // server from decoding CBOR.
  const bufToB64u = buf => btoa(String.fromCharCode(...new Uint8Array(buf))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  const b64uToBuf = text => {
    const padded = (text + "=".repeat((4 - text.length % 4) % 4)).replace(/-/g, "+").replace(/_/g, "/");
    return Uint8Array.from(atob(padded), c => c.charCodeAt(0));
  };
  const deviceName = () => {
    const ua = navigator.userAgent;
    const device = /iPhone/.test(ua) ? "iPhone" : /iPad/.test(ua) ? "iPad" : /Android/.test(ua) ? "Android"
      : /Mac/.test(ua) ? "Mac" : /Windows/.test(ua) ? "Windows" : "Browser";
    const browser = /Firefox/.test(ua) ? "Firefox" : /Chrome|CriOS/.test(ua) ? "Chrome" : /Safari/.test(ua) ? "Safari" : "Browser";
    return device + " · " + browser;
  };
  const authStatus = msg => $$("[data-auth-status]").forEach(el => { el.textContent = msg; });
  const passkeysWork = window.PublicKeyCredential && navigator.credentials;

  const enrol = async () => {
    const res = await post("/auth/register/options", {});
    if (!res.ok) throw new Error(await res.text());
    const options = await res.json();
    options.challenge = b64uToBuf(options.challenge);
    options.user.id = b64uToBuf(options.user.id);
    options.excludeCredentials = (options.excludeCredentials || []).map(c => ({ type: c.type, id: b64uToBuf(c.id) }));
    const credential = await navigator.credentials.create({ publicKey: options });
    const key = credential.response.getPublicKey && credential.response.getPublicKey();
    if (!key) throw new Error("this browser cannot hand over the passkey's public key");
    const done = await post("/auth/register", {
      credential_id: bufToB64u(credential.rawId),
      client_data: bufToB64u(credential.response.clientDataJSON),
      authenticator_data: bufToB64u(credential.response.getAuthenticatorData()),
      public_key: bufToB64u(key),
      label: deviceName()
    });
    if (!done.ok) throw new Error(await done.text());
  };

  const signIn = async () => {
    const res = await post("/auth/login/options", {});
    if (!res.ok) throw new Error(await res.text());
    const options = await res.json();
    options.challenge = b64uToBuf(options.challenge);
    const assertion = await navigator.credentials.get({ publicKey: options });
    const done = await post("/auth/login", {
      credential_id: bufToB64u(assertion.rawId),
      client_data: bufToB64u(assertion.response.clientDataJSON),
      authenticator_data: bufToB64u(assertion.response.authenticatorData),
      signature: bufToB64u(assertion.response.signature),
      user_handle: assertion.response.userHandle ? bufToB64u(assertion.response.userHandle) : ""
    });
    if (!done.ok) throw new Error(await done.text());
  };

  // A cancelled ceremony is the user changing their mind, not a failure worth shouting about.
  const ceremony = async (work, done) => {
    if (!passkeysWork) { authStatus("This browser cannot use passkeys."); return; }
    try {
      authStatus("");
      await work();
      done();
    } catch (e) {
      if (e && (e.name === "NotAllowedError" || e.name === "AbortError")) authStatus("Cancelled.");
      else authStatus(String((e && e.message) || e).slice(0, 200));
    }
  };

  const setupForm = $("form[data-setup]");
  if (setupForm) setupForm.addEventListener("submit", e => {
    e.preventDefault();
    ceremony(async () => {
      const claim = await post("/auth/setup", { secret: setupForm.secret.value, name: setupForm.name.value });
      if (!claim.ok) throw new Error(await claim.text());
      await enrol();
    }, () => { location.href = "/"; });
  });

  const signInBtn = $("[data-signin]");
  if (signInBtn) {
    signInBtn.addEventListener("click", () => ceremony(signIn, () => { location.href = "/"; }));
    if (passkeysWork) signInBtn.focus();
  }

  const addBtn = $("[data-add-passkey]");
  if (addBtn) addBtn.addEventListener("click", () => ceremony(enrol, () => location.reload()));

  // ---- Push subscription: the native notifications come from the server ----
  let audio = null;
  const wakeAudio = () => { if (!audio) { try { audio = new (window.AudioContext || window.webkitAudioContext)(); } catch (_) {} } };
  document.addEventListener("pointerdown", wakeAudio, { once: true });
  const notifyBtns = $$("[data-notify]"), statusEls = $$("[data-notify-status]");
  if (notifyBtns.length) {
    const say = msg => statusEls.forEach(el => { el.textContent = msg; });
    const toKey = b64 => {
      const pad = "=".repeat((4 - b64.length % 4) % 4);
      const raw = atob((b64 + pad).replace(/-/g, "+").replace(/_/g, "/"));
      return Uint8Array.from(raw, c => c.charCodeAt(0));
    };
    const supported = "serviceWorker" in navigator && "PushManager" in window && "Notification" in window;
    const standalone = matchMedia("(display-mode: standalone)").matches || navigator.standalone === true;
    const ios = /iPhone|iPad|iPod/.test(navigator.userAgent);
    const label = () => {
      const device = ios ? "iPhone" : /Android/.test(navigator.userAgent) ? "Android" : /Mac/.test(navigator.userAgent) ? "Mac" : "Browser";
      const browser = /Firefox/.test(navigator.userAgent) ? "Firefox" : /Chrome|CriOS/.test(navigator.userAgent) ? "Chrome" : "Safari";
      return device + " · " + browser;
    };
    const reflect = async () => {
      if (!supported) {
        say(ios && !standalone ? "Add this to your home screen first (Share, then Add to Home Screen), and enable alerts from there." : "This browser can't receive push notifications.");
        notifyBtns.forEach(b => { b.disabled = true; });
        return;
      }
      if (Notification.permission === "denied") { say("Notifications are blocked for this site in your browser settings."); return; }
      const reg = await navigator.serviceWorker.ready;
      const sub = await reg.pushManager.getSubscription();
      notifyBtns.forEach(b => { b.textContent = sub ? "Alerts are on for this device" : b.dataset.label; });
      if (sub) say("This device gets a notification for every step.");
    };
    const subscribe = async () => {
      if (!supported) return;
      wakeAudio();
      const permission = await Notification.requestPermission();
      if (permission !== "granted") { reflect(); return; }
      try {
        const reg = await navigator.serviceWorker.ready;
        const vapid = await fetch("/push/key", { credentials: "same-origin" }).then(r => r.text());
        const sub = (await reg.pushManager.getSubscription()) || await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: toKey(vapid) });
        const j = sub.toJSON();
        const r = await post("/push/subscribe", { endpoint: j.endpoint, p256dh: j.keys.p256dh, auth: j.keys.auth, label: label() });
        if (!r.ok) throw new Error("server said " + r.status);
        say("Alerts are on for this device. Use Send a test to check.");
        notifyBtns.forEach(b => { b.textContent = "Alerts are on for this device"; });
        if (location.pathname === "/") setTimeout(() => location.reload(), 600);
      } catch (e) { say("Couldn't subscribe: " + e.message); }
    };
    notifyBtns.forEach(b => b.addEventListener("click", subscribe));
    reflect();
  }

  // ---- Cook view: live clock, countdowns, alerts ----
  const cook = $("#cook");
  if (cook) {
    const tz = parseInt(cook.dataset.tz, 10);
    const serveAt = parseInt(cook.dataset.serve, 10);
    const steps = $$(".tl-step[data-step]", cook).map(el => ({
      el, id: el.dataset.step, name: el.dataset.name, dish: el.dataset.dish, place: el.dataset.place, hands: el.dataset.hands === "1",
      start: parseInt(el.dataset.start, 10), end: parseInt(el.dataset.end, 10),
      minutes: parseInt(el.dataset.minutes, 10) * 60, started: parseInt(el.dataset.started || "0", 10),
      countdown: $("[data-countdown]", el), tick: $(".tick", el), state: $("[data-state]", el)
    }));
    const pad2 = n => String(n).padStart(2, "0");
    const hhmm = secs => { const m = Math.floor(((secs - tz * 60) % 86400 + 86400) % 86400 / 60); return `${pad2(Math.floor(m / 60))}:${pad2(m % 60)}`; };
    const span = s => s >= 3600 ? `${Math.floor(s / 3600)}h ${pad2(Math.floor(s % 3600 / 60))}m` : `${Math.floor(s / 60)}:${pad2(s % 60)}`;
    const done = s => s.el.classList.contains("done");
    const banner = $(".clock", cook);
    const bLabel = $("[data-label]", banner), bDish = $("[data-dish]", banner), bCount = $("[data-count]", banner),
          bUnit = $("[data-unit]", banner), bName = $("[data-headline]", banner), bNext = $("[data-next]", banner),
          bBar = $("[data-progress]", banner), bCooking = $("[data-cooking]", banner),
          bStart = $("[data-start-focus]", banner), bBehind = $("[data-behind]", banner),
          bBehindText = $("[data-behind-text]", banner), bCatchUp = $("[data-catch-up]", banner);
    let startTarget = null;
    // One control, and the word beside it says which thing the tap does: a step that has not begun starts,
    // one that is under way finishes. Tapping the tick to mean "yes, it is in the oven" is what the cook
    // reached for before starting was recordable at all.
    const planId = cook.dataset.plan;
    const markStarted = s => {
      s.started = Math.floor(Date.now() / 1000);
      post(`/plans/${planId}/steps/${s.id}/started`, { started: "1" }).catch(() => {});
      render();
    };
    const markDone = (s, done) => {
      s.el.classList.toggle("done", done);
      if (done && !s.started) s.started = s.start;
      post(`/plans/${planId}/steps/${s.id}/done`, { done: done ? "1" : "0" }).catch(() => {});
      render();
    };
    steps.forEach(s => s.tick.addEventListener("change", () => {
      const wasChecked = s.tick.checked;
      if (!s.started && wasChecked) { s.tick.checked = false; markStarted(s); return; }
      markDone(s, wasChecked);
    }));

    // In-page alerts while the page is open: a chime and a buzz; the native notification comes from the server.
    const chime = () => {
      if (!audio) return;
      const t = audio.currentTime;
      [0, 0.18, 0.36].forEach((off, i) => {
        const o = audio.createOscillator(), g = audio.createGain();
        o.frequency.value = [880, 1108, 1318][i]; o.type = "sine";
        g.gain.setValueAtTime(0.0001, t + off); g.gain.exponentialRampToValueAtTime(0.4, t + off + 0.02); g.gain.exponentialRampToValueAtTime(0.0001, t + off + 0.5);
        o.connect(g).connect(audio.destination); o.start(t + off); o.stop(t + off + 0.55);
      });
    };
    const notify = () => {
      if (navigator.vibrate) navigator.vibrate([200, 100, 200]);
      chime();
    };

    // Keep the screen on while cooking; the lock drops when the tab is hidden, so take it again on return.
    const wakeBtn = $("[data-wake]");
    let lock = null;
    const wake = async () => {
      if (!("wakeLock" in navigator)) return;
      try { lock = await navigator.wakeLock.request("screen"); lock.addEventListener("release", () => { lock = null; reflectWake(); }); } catch (_) { lock = null; }
      reflectWake();
    };
    const reflectWake = () => {
      if (!wakeBtn) return;
      if (!("wakeLock" in navigator)) { wakeBtn.textContent = "Screen lock not supported"; wakeBtn.disabled = true; return; }
      wakeBtn.textContent = lock ? "Screen stays on · tap to stop" : "Keep screen on";
    };
    if (wakeBtn) wakeBtn.addEventListener("click", () => { if (lock) { lock.release(); localStorage.removeItem("wake"); } else { localStorage.setItem("wake", "1"); wake(); } });
    document.addEventListener("visibilitychange", () => { if (document.visibilityState === "visible" && localStorage.getItem("wake") === "1") wake(); });
    if (localStorage.getItem("wake") === "1") wake();
    reflectWake();

    // Auto-scroll: the live row sits under the banner, and the banner survives scrolling away. A manual scroll
    // wins for twelve seconds so the app never fights a thumb.
    const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
    let userScrolledAt = 0, programmatic = false, focusId = null;
    addEventListener("scroll", () => { if (!programmatic) userScrolledAt = Date.now(); }, { passive: true });
    // The browser restores the old scroll position around load, which would undo the first jump; and the web
    // font swapping in changes every row height. So the opening scroll waits for both, and only then lands.
    if ("scrollRestoration" in history) history.scrollRestoration = "manual";
    const settled = Promise.all([
      document.fonts ? document.fonts.ready : Promise.resolve(),
      document.readyState === "complete" ? Promise.resolve() : new Promise(r => addEventListener("load", r, { once: true }))
    ]);
    const stick = () => {
      const barH = (($(".bar") || {}).offsetHeight) || 0;
      cook.style.setProperty("--bar-h", barH + "px");
      cook.style.setProperty("--stick", barH + banner.offsetHeight + "px");
    };
    addEventListener("resize", stick);
    stick();
    const scrollToRow = (el, smooth) => {
      if (!el) return;
      stick();
      programmatic = true;
      el.scrollIntoView({ behavior: smooth && !reduceMotion ? "smooth" : "auto", block: "start" });
      setTimeout(() => { programmatic = false; }, smooth && !reduceMotion ? 900 : 80);
    };
    // The opening jump happens while rows are still settling into their final heights, so it lands three
    // times over 300ms. Each one is instant, so the corrections are invisible.
    const landOn = el => {
      if (!el) return;
      const go = () => { stick(); el.scrollIntoView({ behavior: "auto", block: "start" }); };
      programmatic = true;
      go();
      requestAnimationFrame(go);
      setTimeout(() => { go(); programmatic = false; }, 300);
    };

    bStart.addEventListener("click", () => { if (startTarget) markStarted(startTarget); });
    bCatchUp.addEventListener("click", () => {
      const minutes = bCatchUp.dataset.minutes;
      post(`/plans/${planId}/shift`, { minutes }).then(() => location.reload()).catch(() => {});
    });

    let last = Math.floor(Date.now() / 1000);
    const render = () => {
      const now = Math.floor(Date.now() / 1000);
      const pending = steps.filter(s => !done(s));
      // A step you stand over occupies you; anything else is a timer you can walk away from. The board only
      // ever tells you to do the first kind, and reports the second kind as what is cooking.
      const isTimer = s => !s.hands && s.minutes > 0;
      // A step's own clock: the plan's finish until it actually begins, and its real one after.
      const finish = s => s.started ? s.started + s.minutes : s.end;
      const kind = s => !s.started ? (s.start > now ? "waiting" : "to-start")
        : now < finish(s) ? (isTimer(s) ? "cooking" : "now")
        : "ready";

      const byFinish = (a, b) => finish(a) - finish(b);
      const ready = pending.filter(s => kind(s) === "ready").sort(byFinish)[0] || null;
      const toStart = pending.filter(s => kind(s) === "to-start").sort((a, b) => a.start - b.start)[0] || null;
      const busy = pending.filter(s => kind(s) === "now").sort(byFinish)[0] || null;
      const next = pending.filter(s => kind(s) === "waiting").sort((a, b) => a.start - b.start)[0] || null;
      const cooking = pending.filter(s => kind(s) === "cooking").sort(byFinish);

      // Something off the heat beats something due to go on; either beats a knife already in your hand,
      // which can pause; and all of them beat a clock that has not struck yet.
      let focus = null, state = "done";
      if (ready) { focus = ready; state = "ready"; }
      else if (toStart) { focus = toStart; state = "to-start"; }
      else if (busy) { focus = busy; state = "now"; }
      else if (next) { focus = next; state = "next"; }

      steps.forEach(s => {
        s.el.classList.remove("current", "now", "cooking", "ready", "to-start");
        if (done(s)) { s.countdown.textContent = ""; s.state.textContent = "Done"; return; }
        const k = kind(s);
        // The lamp says what state a step is in; the lit band says which one the banner is about. Keeping
        // those on separate channels is what stops two steps in the same state from looking like two states.
        if (s === focus && k !== "waiting") s.el.classList.add("current");
        if (k === "to-start") s.el.classList.add("to-start");
        else if (k === "cooking") s.el.classList.add("cooking");
        else if (k === "ready") s.el.classList.add("ready");
        else if (k === "now") s.el.classList.add("now");
        s.state.textContent = k === "waiting" ? "Waiting" : k === "to-start" ? "Start"
          : k === "cooking" ? "Cooking" : k === "ready" ? "Ready" : "Now";
        // The banner carries the focus step's countdown; the row would only repeat it.
        if (s === focus) s.countdown.textContent = "";
        else if (k === "waiting") s.countdown.textContent = "in " + span(s.start - now);
        else if (k === "to-start") s.countdown.textContent = now - s.start > 60 ? "due " + span(now - s.start) + " ago" : "";
        else if (k === "cooking") s.countdown.textContent = span(finish(s) - now) + " left";
        else s.countdown.textContent = "";
        if (last < s.start && s.start <= now && !s.started) notify();
        else if (s.started && last < finish(s) && finish(s) <= now && isTimer(s)) notify();
      });
      if (last < serveAt && serveAt <= now) notify("Dinner is served", "Everything should be on the table.");
      const serveRow = $(".tl-step.serve", cook);
      if (serveRow) serveRow.classList.toggle("current", now >= serveAt && !pending.length);

      // The banner: what to do, how long it has, what follows.
      banner.dataset.state = state;
      let bar = 0;
      if (focus) {
        bLabel.textContent = state === "ready" ? "Ready" : state === "to-start" ? "Start" : state === "now" ? "Now" : "Next";
        bName.textContent = focus.name;
        bDish.textContent = focus.place ? focus.dish + " \u00b7 " + focus.place : focus.dish;
        if (state === "ready") { bCount.textContent = span(Math.max(0, now - finish(focus))); bUnit.textContent = "ago"; bar = 1; }
        else if (state === "to-start") {
          const over = now - focus.start;
          bCount.textContent = over > 60 ? span(over) : "Now";
          bUnit.textContent = over > 60 ? "late to start" : "";
        } else if (state === "now" && focus.minutes > 0) {
          bCount.textContent = span(finish(focus) - now); bUnit.textContent = "left";
          bar = (now - focus.started) / focus.minutes;
        } else if (state === "now") { bCount.textContent = span(Math.max(0, serveAt - now)); bUnit.textContent = "to serve"; }
        else { bCount.textContent = span(focus.start - now); bUnit.textContent = "to go"; }
      } else {
        bLabel.textContent = now >= serveAt ? "Served" : "Ready";
        bName.textContent = steps.length ? (now >= serveAt ? "Dinner is served" : "Everything is done") : "Nothing to cook yet";
        bDish.textContent = "";
        const toServe = serveAt - now;
        bCount.textContent = toServe > 0 ? span(toServe) : "";
        bUnit.textContent = toServe > 0 ? "to serve" : "";
      }
      // "Then" means the next thing that has not started. When the cook is behind, everything left has already
      // started, and naming one of them with its long-gone time would read as a schedule rather than a backlog.
      const upcoming = pending.filter(s => s !== focus && kind(s) === "waiting").sort((a, b) => a.start - b.start)[0] || null;
      const others = pending.filter(s => s !== focus).length;
      const follow = upcoming || pending.filter(s => s !== focus).sort((a, b) => a.start - b.start)[0] || null;
      bNext.textContent = state === "next" ? "Nothing to do until then"
        : upcoming ? "Then " + hhmm(upcoming.start) + " " + upcoming.name
        : others ? others + " more to do"
        : focus ? "Last one" : "";
      bBar.style.transform = "scaleX(" + Math.min(1, Math.max(0, bar)) + ")";

      // What is looking after itself: the ovens and the hob, in the order they will want you back.
      bCooking.textContent = "";
      cooking.forEach(c => {
        const row = document.createElement("span");
        if (c.place) {
          const box = document.createElement("span");
          box.className = "platform";
          box.textContent = c.place;
          row.appendChild(box);
        }
        const what = document.createElement("span");
        what.textContent = c.dish + " until " + hhmm(c.end);
        row.appendChild(what);
        bCooking.appendChild(row);
      });
      bCooking.hidden = cooking.length === 0;

      bStart.hidden = state !== "to-start";
      startTarget = state === "to-start" ? focus : null;

      // How far behind: the worst overshoot anything unfinished is already committed to. A step that began
      // late finishes late by the same margin; one that has not begun cannot finish before now plus its own
      // length. The cook decides what to do about it, so the offer is a button and never automatic.
      let behind = 0;
      pending.forEach(s => {
        const late = s.started ? s.started + s.minutes - s.end : now - s.start;
        if (late > behind) behind = late;
      });
      if (behind >= 120) {
        const minutes = Math.ceil(behind / 60);
        const to = Math.ceil(minutes / 5) * 5;
        bBehindText.textContent = minutes + " min behind";
        bCatchUp.textContent = "Dinner at " + hhmm(serveAt + to * 60);
        bCatchUp.dataset.minutes = String(to);
        bBehind.hidden = false;
      } else {
        bBehind.hidden = true;
      }

      // The banner holds what you are doing; park the list on what comes next, so the two never repeat each
      // other. The step in the banner sits just above the fold, one flick away.
      const id = focus ? focus.id : "end";
      if (id !== focusId) {
        const first = focusId === null;
        focusId = id;
        const target = (follow || {}).el || serveRow;
        if (first) settled.then(() => { if (!userScrolledAt) landOn(target); });
        else if (Date.now() - userScrolledAt > 12000) scrollToRow(target, true);
      }
      last = now;
    };
    render();
    setInterval(render, 1000);
    document.addEventListener("visibilitychange", () => { if (document.visibilityState === "visible") render(); });
  }
})();
