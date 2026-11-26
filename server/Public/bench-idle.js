// Üresjárati mérés (teszt ág; Tests/Perf/safari-idle.py): a szerkesztő ?bench=VÁLTOZAT&list=…&start=…&step=… címmel
// nyílik meg; a változatot a dobozok megjelenése után kapcsolja be, a `start + (k+1)·step` időpontban a következő
// változatra tölti újra magát, az utolsó után a főoldalra lép (ott nincs animáció). A CPU-t kívülről mérjük.
const q = new URLSearchParams(location.search);
const list = (q.get("list") ?? "alap").split(","), name = q.get("bench"), start = Number(q.get("start")), step = Number(q.get("step") ?? 15) * 1000;
const DOT = '<circle r="5" fill="#e33"><animateMotion dur="3s" repeatCount="indefinite" path="M0,0 L300,0"/></circle>';
const P = "*{animation-play-state:paused!important}";
// A szerkesztő CSP-je (style-src 'self') a beszúrt <style> elemet tiltja; a CSSOM-mal készült lap nem esik alá.
const css = text => { const sheet = new CSSStyleSheet(); sheet.replaceSync(text); document.adoptedStyleSheets = [...document.adoptedStyleSheets, sheet]; };
const pauseSmil = () => document.querySelectorAll("svg").forEach(s => s.pauseAnimations?.());
const keep = test => { css(".canvas-aurora > i{animation:none!important}"); document.querySelectorAll(".editor-canvas :is(animate, animateMotion, animateTransform)").forEach(a => { if (!test(a)) a.remove(); }); window.__kept = document.querySelectorAll(".editor-canvas :is(animate, animateMotion, animateTransform)").length; };
const stopSmil = () => document.querySelectorAll(".editor-canvas :is(animate, animateMotion, animateTransform)").forEach(a => a.remove());
const variants = {
  alap: () => {},
  // A vezérlősáv kapcsolói (localStorage; egyszeri újratöltéssel). Csak ideiglenes böngészőprofilban használd.
  animaciok_ki: () => { if (localStorage.getItem("tnMotionOff") !== "1") { localStorage.setItem("tnMotionOff", "1"); location.reload(); } },
  hatter_ki: () => { if (localStorage.getItem("tnPlainBackground") !== "1") { localStorage.setItem("tnPlainBackground", "1"); location.reload(); } },
  aurora_torol: () => document.querySelector(".canvas-aurora")?.remove(),
  aurora_all: () => css(".canvas-aurora > i{animation:none!important}"),
  css_szunet: () => css(P),
  smil_szunet: () => pauseSmil(),
  mind_szunet: () => { css(P); pauseSmil(); },
  mind_aurora: () => { css(P); pauseSmil(); document.querySelector(".canvas-aurora")?.remove(); },
  backdrop: () => css("*{backdrop-filter:none!important;-webkit-backdrop-filter:none!important}"),
  backdrop_aurora: () => { css("*{backdrop-filter:none!important;-webkit-backdrop-filter:none!important}"); css(".canvas-aurora > i{animation:none!important}"); },
  csak_smil: () => css(".canvas-aurora > i{animation:none!important}"),
  egy_potty: () => {
    css(".canvas-aurora > i{animation:none!important}"); stopSmil();
    const g = document.createElementNS("http://www.w3.org/2000/svg", "g");
    g.innerHTML = '<circle r="5" fill="#e33"><animateMotion dur="3s" repeatCount="indefinite" path="M0,0 L300,0"/></circle>';
    document.querySelector(".editor-canvas")?.append(g);
  },
  // Csak a megadott SMIL-animációk maradnak (a háttérfény áll): melyik animációtípus drága?
  csak_doboz: () => keep(a => !!a.closest(".node-motion")),
  csak_vonal: () => keep(a => !a.closest(".node-motion")),
  doboz_pulse: () => keep(a => !!a.closest('[data-box-animation="pulse"]')),
  doboz_blink: () => keep(a => !!a.closest('[data-box-animation="blink"]')),
  doboz_rock: () => keep(a => !!a.closest('[data-box-animation="rock"]')),
  doboz_hop: () => keep(a => !!a.closest('[data-box-animation="hop"]')),
  vonal_vastag: () => keep(a => !a.closest(".node-motion") && ["d", "stroke-width"].includes(a.getAttribute("attributeName"))),
  vonal_minta: () => keep(a => a.getAttribute("attributeName") === "stroke-dashoffset"),
  vonal_potty: () => keep(a => a.tagName === "animateMotion"),
  fo_torol: () => { css(".canvas-aurora > i{animation:none!important}"); document.querySelectorAll(".editor-canvas foreignObject").forEach(f => f.remove()); },
  fo_rejt: () => css(".canvas-aurora > i{animation:none!important} .editor-canvas foreignObject{display:none!important}"),
  vaszon_none: () => css(".canvas-aurora > i{animation:none!important} .editor-canvas{display:none!important}"),
  fajldoboz_torol: () => { css(".canvas-aurora > i{animation:none!important}"); document.querySelectorAll(".editor-canvas [data-node]").forEach(n => { if (n.querySelector("foreignObject")) n.remove(); }); },
  // SMIL helyett CSS-animáció ugyanazokra az effektekre (próba): doboz – transzform / átlátszóság, vonal – vastagság,
  // szaggatás eltolása, futó pötty – offset-path.
  css_csere: () => smilToCss(),
  css_doboz: () => smilToCss(a => !!a.closest(".node-motion")),
  css_racs: () => { smilToCss(); document.querySelector(".canvas-grid-draw")?.remove(); },
  css_racs_aurora: () => { smilToCss(); document.querySelector(".canvas-grid-draw")?.remove(); document.querySelector(".canvas-aurora")?.remove(); },
  css_will: () => { smilToCss(); css(".tn-css-box, .editor-canvas [style*='animation']{will-change:transform}"); },
  css_racs_nowill: () => { smilToCss(); css(".canvas-grid-draw{will-change:auto!important}"); },
  smil_racs_aurora: () => { document.querySelector(".canvas-grid-draw")?.remove(); document.querySelector(".canvas-aurora")?.remove(); },
  css_reteg_nowill: () => { smilToCss(); css(".canvas-layer{will-change:auto!important}"); },
  csend: () => { stopSmil(); document.querySelector(".canvas-grid-draw")?.remove(); document.querySelector(".canvas-aurora")?.remove(); },
  potty_vaszon: () => { variants.csend(); const g = document.createElementNS("http://www.w3.org/2000/svg", "g"); g.innerHTML = DOT; document.querySelector(".editor-canvas")?.append(g); },
  potty_kulon: () => { variants.csend(); const d = document.createElement("div"); d.style.cssText = "position:absolute;left:400px;top:400px;width:320px;height:20px;will-change:transform;pointer-events:none"; d.innerHTML = '<svg width="320" height="20" style="overflow:visible"><g transform="translate(10 10)">' + DOT + '</g></svg>'; document.querySelector(".canvas-area").append(d); },
  potty_css_vaszon: () => { variants.csend(); const g = document.createElementNS("http://www.w3.org/2000/svg", "g"); g.innerHTML = '<circle r="5" fill="#e33" style="offset-path:path(\'M0,0 L300,0\');animation:tn-dot 3s linear infinite"/>'; css("@keyframes tn-dot{to{offset-distance:100%}}"); document.querySelector(".editor-canvas")?.append(g); },
  potty_steps: () => { variants.csend(); const g = document.createElementNS("http://www.w3.org/2000/svg", "g"); g.innerHTML = '<circle r="5" fill="#e33" style="offset-path:path(\'M0,0 L300,0\');animation:tn-dot 3s steps(60) infinite"/>'; css("@keyframes tn-dot{to{offset-distance:100%}}"); document.querySelector(".editor-canvas")?.append(g); },
  potty_js20: () => { variants.csend(); const g = document.createElementNS("http://www.w3.org/2000/svg", "g"); g.innerHTML = '<circle r="5" fill="#e33"/>'; document.querySelector(".editor-canvas")?.append(g); const c = g.firstChild, t0 = performance.now(); setInterval(() => c.setAttribute("cx", ((performance.now() - t0) / 10) % 300), 50); },
  css_lep20: () => { smilToCss(); stepAll(20); },
  css_lep30: () => { smilToCss(); stepAll(30); },
  css_lep20_racs: () => { smilToCss(); stepAll(20); document.querySelector(".canvas-grid-draw")?.remove(); },
  igazitott20: () => { smilToCss(); align(20); },
  igazitott12: () => { smilToCss(); align(12); },
  vaszon_rejt: () => css(".editor-canvas{visibility:hidden!important}"),
  racs_torol: () => document.querySelector(".canvas-grid-draw")?.remove(),
  rejtett: () => css(".editor-workspace{visibility:hidden!important}"),
};
const tag = document.createElement("div");
tag.style.cssText = "position:fixed;left:8px;bottom:60px;z-index:99999;font:12px system-ui;background:#000a;color:#fff;padding:2px 6px;border-radius:4px;pointer-events:none";
tag.textContent = "bench: " + name;
document.body.append(tag);
(function apply() {
  if (!document.querySelector("[data-node]")) { setTimeout(apply, 200); return; }
  setTimeout(() => variants[name]?.(), 300);
})();
const k = list.indexOf(name);
const next = list[k + 1];
// `hold`: nincs továbblépés (WebDriveres mérésnél a vezérlő tölti be a következő változatot).
if (!q.has("hold")) setTimeout(() => {
  if (!next) { location.replace("/"); return; }
  const url = new URL(location.href);
  url.searchParams.set("bench", next);
  location.replace(url.href);
}, Math.max(0, start + (k + 1) * step - Date.now()));

function smilToCss(only = () => true) {
  css(".canvas-aurora > i{animation:none!important}" +
    "@keyframes tn-pulse{50%{transform:scale(1.09)}} @keyframes tn-blink{50%{opacity:.28}}" +
    "@keyframes tn-rock{8%{transform:rotate(8deg)}19%{transform:rotate(-6deg)}30%{transform:rotate(3deg)}40%{transform:rotate(-1deg)}49%,100%{transform:rotate(0)}}" +
    "@keyframes tn-hop{6%{transform:translateY(1px) scale(1.03,.95)}15%{transform:translateY(-17px) scale(1.035,1.06)}24%{transform:scale(1.045,.96)}32%{transform:translateY(-4px) scale(.99,1.02)}40%,100%{transform:none}}" +
    ".tn-css-box{transform-box:fill-box;transform-origin:center}" +
    "@keyframes tn-dash{to{stroke-dashoffset:var(--tn-shift)}} @keyframes tn-thick{50%{stroke-width:var(--tn-thick)}} @keyframes tn-dot{to{offset-distance:100%}}");
  let replaced = 0;
  for (const a of [...document.querySelectorAll(".editor-canvas :is(animate, animateMotion, animateTransform)")]) {
    const target = a.parentElement, attr = a.getAttribute("attributeName"), dur = a.getAttribute("dur");
    if (!only(a)) { a.remove(); continue; }
    const box = a.closest(".node-motion");
    if (box) {
      if (!box.classList.contains("tn-css-box")) {
        box.classList.add("tn-css-box");
        box.style.animation = "tn-" + box.dataset.boxAnimation + " " + dur + " ease-in-out infinite";
        replaced++;
      }
    } else if (attr === "stroke-dashoffset") {
      target.style.setProperty("--tn-shift", a.getAttribute("values").split(";")[1] + "px");
      target.style.animation = "tn-dash " + dur + " linear infinite"; replaced++;
    } else if (attr === "stroke-width") {
      target.style.setProperty("--tn-thick", a.getAttribute("values").split(";")[1] + "px");
      target.style.animation = "tn-thick " + dur + " ease-in-out infinite"; replaced++;
    } else if (a.tagName === "animateMotion") {
      target.style.offsetPath = "path('" + a.getAttribute("path") + "')";
      target.style.animation = "tn-dot " + dur + " linear infinite"; replaced++;
    }
    a.remove();
  }
  window.__kept = replaced;
}

// Lépésszám-korlát a CSS-animációkra (próba): kulcskockánkénti steps(), hogy a böngésző a lépések között ne rajzoljon.
function stepAll(fps) {
  for (const el of document.querySelectorAll(".editor-canvas .tn-css-box, .editor-canvas [style*='animation']")) {
    const dur = parseFloat(getComputedStyle(el).animationDuration) || 2;
    const segments = el.classList.contains("tn-css-box") ? 6 : 1;
    el.style.animationTimingFunction = "steps(" + Math.max(1, Math.round(dur * fps / segments)) + ")";
  }
}

// Közös óraütemre igazított lépések (próba): minden animáció időtartama 1/fps egész többszöröse, kulcskockánként annyi
// lépés, ahány 1/fps hosszú szakasz esik rá (a kulcskockák helyét is a rácsra kerekítve), és mindegyik a közös idővonal
// nullpontjához igazítva indul (startTime = 0): a lépések mind k/fps másodpercre esnek, így másodpercenként legfeljebb fps
// képkocka keletkezik, akárhány animáció fut.
function align(fps) {
  for (const anim of document.getAnimations()) {
    const effect = anim.effect, timing = effect.getTiming();
    if (!(effect.target?.closest?.(".editor-canvas"))) continue;
    const ticks = Math.max(1, Math.round(timing.duration / 1000 * fps));
    const frames = effect.getKeyframes().map(f => ({...f, offset: Math.round(f.computedOffset * ticks) / ticks}));
    effect.setKeyframes(frames.map((f, i) => {
      const next = frames[i + 1];
      const span = next ? Math.max(1, Math.round((next.offset - f.offset) * ticks)) : 1;
      const {computedOffset, ...rest} = f;
      return {...rest, easing: "steps(" + span + ")"};
    }));
    effect.updateTiming({duration: ticks * 1000 / fps, easing: "linear"});
    anim.startTime = 0;
  }
}
