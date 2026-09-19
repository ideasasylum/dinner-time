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
      countdown: $("[data-countdown]", el), tick: $(".tick", el), state: $("[data-state]", el)
    }));
    const pad2 = n => String(n).padStart(2, "0");
    const hhmm = secs => { const m = Math.floor(((secs - tz * 60) % 86400 + 86400) % 86400 / 60); return `${pad2(Math.floor(m / 60))}:${pad2(m % 60)}`; };
    const span = s => s >= 3600 ? `${Math.floor(s / 3600)}h ${pad2(Math.floor(s % 3600 / 60))}m` : `${Math.floor(s / 60)}:${pad2(s % 60)}`;
    const done = s => s.el.classList.contains("done");
    const banner = $(".clock", cook);
    const bLabel = $("[data-label]", banner), bDish = $("[data-dish]", banner), bCount = $("[data-count]", banner),
          bUnit = $("[data-unit]", banner), bName = $("[data-headline]", banner), bNext = $("[data-next]", banner),
          bBar = $("[data-progress]", banner), bCooking = $("[data-cooking]", banner);
    steps.forEach(s => s.tick.addEventListener("change", () => {
      s.el.classList.toggle("done", s.tick.checked);
      post(`/plans/${cook.dataset.plan}/steps/${s.id}/done`, { done: s.tick.checked ? "1" : "0" }).catch(() => {});
      render();
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

    let last = Math.floor(Date.now() / 1000);
    const render = () => {
      const now = Math.floor(Date.now() / 1000);
      const pending = steps.filter(s => !done(s));
      // A step you stand over occupies you; anything else is a timer you can walk away from. The board only
      // ever tells you to do the first kind, and reports the second kind as what is cooking.
      const isTimer = s => !s.hands && s.end > s.start;
      const started = s => s.start <= now;
      const late = s => now - s.end > 60;
      const kind = s => !started(s) ? "waiting"
        : late(s) ? "late"
        : isTimer(s) ? (now < s.end ? "cooking" : "ready")
        : now < s.end ? "now" : "ready";

      const byEnd = (a, b) => a.end - b.end;
      const overdue = pending.filter(late).sort(byEnd)[0] || null;
      const ready = pending.filter(s => kind(s) === "ready").sort(byEnd)[0] || null;
      const busy = pending.filter(s => kind(s) === "now").sort(byEnd)[0] || null;
      const next = pending.filter(s => !started(s)).sort((a, b) => a.start - b.start)[0] || null;
      const cooking = pending.filter(s => kind(s) === "cooking").sort(byEnd);

      // Food off the heat beats a knife in your hand; a knife in your hand beats a clock that has not struck.
      let focus = null, state = "done";
      if (overdue) { focus = overdue; state = "late"; }
      else if (ready) { focus = ready; state = "ready"; }
      else if (busy) { focus = busy; state = "now"; }
      else if (next) { focus = next; state = "next"; }

      steps.forEach(s => {
        s.el.classList.remove("current", "overdue", "past", "running", "cooking", "ready");
        if (done(s)) { s.countdown.textContent = ""; s.state.textContent = "Done"; return; }
        const k = kind(s);
        // One lit band, and it is always the step the banner is about, so the page never points two ways.
        if (s === focus && started(s)) s.el.classList.add("current");
        if (k === "late") s.el.classList.add("overdue");
        else if (k === "cooking") s.el.classList.add("cooking");
        else if (k === "ready") s.el.classList.add("ready");
        else if (k === "now" && s !== focus) s.el.classList.add("running");
        s.state.textContent = k === "waiting" ? "Waiting" : k === "cooking" ? "Cooking"
          : k === "ready" ? "Ready" : k === "late" ? "Late" : "Now";
        // The banner carries the focus step's countdown; the row would only repeat it.
        if (s === focus) s.countdown.textContent = "";
        else if (k === "waiting") s.countdown.textContent = "in " + span(s.start - now);
        else if (k === "late") s.countdown.textContent = "late by " + span(now - s.end);
        else if (k === "cooking") s.countdown.textContent = span(s.end - now) + " left";
        else s.countdown.textContent = "";
        if (last < s.start && s.start <= now) notify();
        else if (last < s.end && s.end <= now && isTimer(s)) notify();
      });
      if (last < serveAt && serveAt <= now) notify("Dinner is served", "Everything should be on the table.");
      const serveRow = $(".tl-step.serve", cook);
      if (serveRow) serveRow.classList.toggle("current", now >= serveAt && !pending.length);

      // The banner: what to do, how long it has, what follows.
      banner.dataset.state = state;
      let bar = 0;
      if (focus) {
        bLabel.textContent = state === "late" ? "Late" : state === "ready" ? "Ready" : state === "now" ? "Now" : "Next";
        bName.textContent = focus.name;
        bDish.textContent = focus.place ? focus.dish + " \u00b7 " + focus.place : focus.dish;
        if (state === "late") { bCount.textContent = span(now - focus.end); bUnit.textContent = "over"; bar = 1; }
        else if (state === "ready") { bCount.textContent = span(Math.max(0, now - focus.end)); bUnit.textContent = "ago"; bar = 1; }
        else if (state === "now" && focus.end > focus.start) {
          bCount.textContent = span(focus.end - now); bUnit.textContent = "left";
          bar = (now - focus.start) / (focus.end - focus.start);
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
      const upcoming = pending.filter(s => s !== focus && !started(s)).sort((a, b) => a.start - b.start)[0] || null;
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
