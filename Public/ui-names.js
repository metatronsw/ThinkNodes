// Névtér-azonosító: a fejléc sárga gombja kapcsolja (csak adminoknak jelenik meg). Az egér alatti UI-elem
// szótárbeli nevét és class-láncát mutatja, kattintásra vágólapra másolja ("Név (szelektor)"). Esc kilép.
// A szótár: /ui-names.json.
(() => {
  const storageKey = "thinknodes-ui-names";
  let items = null, active = false, badge, outline, banner, frame = 0, last = null;


  function short(el) {
    if (!(el instanceof Element)) return "";
    let text = el.tagName.toLowerCase();
    if (el.id) text += "#" + el.id;
    const classes = [...el.classList].filter(name => !name.startsWith("tn-ui-"));
    if (classes.length) text += "." + classes.join(".");
    return text;
  }

  function chain(el) {
    const parts = [];
    for (let node = el; node && node !== document.body && parts.length < 4; node = node.parentElement) parts.unshift(short(node));
    return parts.join(" › ");
  }

  function lookup(el) {
    for (let node = el; node && node !== document.documentElement; node = node.parentElement) {
      for (const item of items ?? []) {
        try { if (node.matches(item.selector)) return {item, node}; } catch { /* hibás szelektor a szótárban */ }
      }
    }
    return {item: null, node: el};
  }

  function label(el) {
    const value = el.getAttribute?.("aria-label") || el.getAttribute?.("title") || "";
    return value.trim().slice(0, 60);
  }

  function describe(target) {
    const {item, node} = lookup(target);
    const name = item?.name ?? "— névtelen elem —";
    const selector = item?.selector.split(",")[0].trim() ?? short(target);
    return {name, selector, node, item, target};
  }

  function render(info) {
    const box = info.node.getBoundingClientRect();
    Object.assign(outline.style, {left: box.left - 2 + "px", top: box.top - 2 + "px", width: box.width + 4 + "px", height: box.height + 4 + "px"});
    const text = label(info.target) || label(info.node);
    badge.replaceChildren();
    const title = document.createElement("b");
    title.textContent = info.name;
    badge.append(title);
    for (const [caption, value] of [["szelektor", info.selector], ["class-lánc", chain(info.target)], ["felirat", text], ["leírás", info.item?.description]]) {
      if (!value) continue;
      const row = document.createElement("span");
      const key = document.createElement("i");
      key.textContent = caption + ": ";
      row.append(key, value);
      badge.append(row);
    }
  }

  function place(x, y) {
    const {width, height} = badge.getBoundingClientRect();
    badge.style.left = Math.max(6, Math.min(x + 16, innerWidth - width - 6)) + "px";
    badge.style.top = Math.max(6, y + 18 + height > innerHeight ? y - height - 12 : y + 18) + "px";
  }

  function move(event) {
    if (event.target === badge || event.target === outline) return;
    last = event;
    if (frame) return;
    frame = requestAnimationFrame(() => {
      frame = 0;
      const target = last.target instanceof Element ? last.target : null;
      if (!target) return;
      render(describe(target));
      place(last.clientX, last.clientY);
    });
  }

  function swallow(event) {
    event.preventDefault();
    event.stopPropagation();
    event.stopImmediatePropagation();
  }

  async function copy(event) {
    if (event.target instanceof Element && event.target.closest("[data-ui-names]")) return;
    swallow(event);
    if (!(event.target instanceof Element)) return;
    const info = describe(event.target);
    const text = info.item ? `${info.name} (${info.selector})` : chain(event.target);
    try {
      await navigator.clipboard.writeText(text);
      banner.textContent = "Másolva: " + text;
    } catch {
      window.prompt("Másold ki:", text);
    }
    setTimeout(() => { if (active) banner.textContent = bannerText; }, 1600);
  }

  const bannerText = "Névtér-azonosító · kattintás: név másolása · Esc vagy a sárga gomb: kilépés";
  const blocked = ["pointerdown", "pointerup", "mousedown", "mouseup", "dblclick", "contextmenu", "auxclick"];

  async function start() {
    if (active) return;
    active = true;
    localStorage.setItem(storageKey, "1");
    if (!items) {
      try { items = (await (await fetch("/ui-names.json", {cache: "no-cache"})).json()).items ?? []; }
      catch { items = []; }
    }
    if (!active) return;
    if (!document.getElementById("tn-ui-style")) {
      const element = Object.assign(document.createElement("link"), {id: "tn-ui-style", rel: "stylesheet", href: "/ui-names.css?v=2"});
      document.head.append(element);
    }
    outline = Object.assign(document.createElement("div"), {className: "tn-ui-outline"});
    badge = Object.assign(document.createElement("div"), {className: "tn-ui-badge"});
    banner = Object.assign(document.createElement("div"), {className: "tn-ui-banner", textContent: bannerText});
    document.body.append(outline, badge, banner);
    sync();
    addEventListener("pointermove", move, true);
    addEventListener("click", copy, true);
    for (const type of blocked) addEventListener(type, swallow, true);
  }

  function stop() {
    if (!active) return;
    active = false;
    localStorage.removeItem(storageKey);
    removeEventListener("pointermove", move, true);
    removeEventListener("click", copy, true);
    for (const type of blocked) removeEventListener(type, swallow, true);
    for (const element of [outline, badge, banner]) element?.remove();
    sync();
  }

  function sync() {
    for (const button of document.querySelectorAll("[data-ui-names]")) button.setAttribute("aria-pressed", String(active));
  }

  addEventListener("keydown", event => {
    if (active && event.key === "Escape") {
      swallow(event);
      stop();
    }
  }, true);
  addEventListener("click", event => {
    if (!(event.target instanceof Element) || !event.target.closest("[data-ui-names]")) return;
    event.preventDefault();
    active ? stop() : start();
  });

  const boot = () => { if (document.querySelector("[data-ui-names]") && localStorage.getItem(storageKey) === "1") start(); else sync(); };
  document.readyState === "loading" ? addEventListener("DOMContentLoaded", boot, {once: true}) : boot();
  window.thinknodesUINames = {start, stop};
})();
