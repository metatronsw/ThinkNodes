import {avatarSymbol} from "./presence.js";
import {playPingSound} from "./ping.js?v=4";

// Csevegés munkalaponként (csak bejelentkezve). Az előzmények a szerverről jönnek (`/api/chat/<lap>`), az új és törölt
// üzenetek a WebSocketen (`{chat: …}`). Eszköztár gomb olvasatlan-számlálóval; a panel a vászon jobb alsó részén.
// Enter: küldés, Shift+Enter: új sor. Aki megemlít (@név), annál az üzenet kiemelt, és hangjelzés szól.
export function sharedChat({path, csrf, me, admin = () => false}) {
  let button, badge, panel, list, input, area, listeners;
  let messages = [], loaded = false, stale = true, open = false, unread = 0;
  const readKey = "thinknodes:chat-read:" + path;
  const lastRead = () => { try { return localStorage.getItem(readKey) ?? ""; } catch { return ""; } };
  const markRead = () => {
    const last = messages.at(-1);
    if (last) try { localStorage.setItem(readKey, last.time); } catch {}
    unread = 0;
    showBadge();
  };
  const mentions = message => {
    const name = me();
    return !!name && message.author !== name && message.text.toLocaleLowerCase("hu").includes("@" + name.toLocaleLowerCase("hu"));
  };
  function showBadge() {
    if (!badge) return;
    badge.textContent = unread > 99 ? "99+" : String(unread);
    badge.hidden = unread === 0;
    button?.setAttribute("aria-label", "Csevegés" + (unread ? ", " + unread + " olvasatlan" : ""));
  }
  function time(value) {
    const date = new Date(value), now = new Date();
    const clock = date.toLocaleTimeString("hu-HU", {hour: "2-digit", minute: "2-digit"});
    return date.toDateString() === now.toDateString() ? clock : date.toLocaleDateString("hu-HU", {month: "short", day: "numeric"}) + " " + clock;
  }
  function row(message) {
    const item = document.createElement("li");
    item.className = "chat-message";
    item.dataset.id = message.id;
    if (message.author === me()) item.dataset.own = "";
    if (mentions(message)) item.dataset.mention = "";
    const head = document.createElement("div");
    head.className = "chat-head";
    head.append(avatarSymbol(message.avatar || 1, message.color));
    const name = document.createElement("strong");
    name.textContent = message.author;
    if (message.color) name.style.color = message.color;
    const when = document.createElement("time");
    when.dateTime = message.time;
    when.textContent = time(message.time);
    head.append(name, when);
    if (message.author === me() || admin()) {
      const remove = document.createElement("button");
      remove.type = "button";
      remove.className = "chat-delete";
      remove.title = "Üzenet törlése";
      remove.setAttribute("aria-label", remove.title);
      remove.textContent = "×";
      remove.addEventListener("click", () => send({delete: message.id}).catch(error => alert(error.message)));
      head.append(remove);
    }
    const text = document.createElement("div");
    text.className = "chat-text";
    text.textContent = message.text;
    item.append(head, text);
    return item;
  }
  function render() {
    if (!list) return;
    const atBottom = list.scrollHeight - list.scrollTop - list.clientHeight < 40;
    list.replaceChildren(...messages.map(row));
    if (!messages.length) {
      const empty = document.createElement("li");
      empty.className = "chat-empty";
      empty.textContent = "Még nincs üzenet ezen a lapon.";
      list.append(empty);
    }
    if (atBottom || open) list.scrollTop = list.scrollHeight;
  }
  async function load() {
    const response = await fetch("/api/chat/" + path, {headers: {Accept: "application/json"}});
    if (!response.ok) throw Error((await response.json().catch(() => ({}))).reason || "A csevegés nem érhető el.");
    messages = await response.json();
    loaded = true;
    stale = false;
    const seen = lastRead();
    unread = open ? 0 : messages.filter(m => m.time > seen && m.author !== me()).length;
    if (open) markRead();
    showBadge();
    render();
  }
  async function send(body) {
    const response = await fetch("/api/chat/" + path, {method: "POST",
      headers: {"Content-Type": "application/json", "X-CSRF-Token": csrf}, body: JSON.stringify(body)});
    if (!response.ok) throw Error((await response.json().catch(() => ({}))).reason || "Az üzenet nem ment el.");
    return response.json();
  }
  // WebSocket-üzenet: új vagy törölt üzenet; `null` = a kapcsolat megszakadt (újracsatlakozáskor újratölt).
  function receive(message) {
    if (!message) { stale = true; return; }
    if (message.deleted) {
      messages = messages.filter(m => m.id !== message.id);
      render();
      return;
    }
    if (messages.some(m => m.id === message.id)) return;
    messages = [...messages, message];
    if (open) markRead();
    else if (message.author !== me()) { unread++; showBadge(); }
    if (mentions(message)) playPingSound();
    render();
  }
  function toggle(force, mention) {
    open = force ?? !open;
    panel.hidden = !open;
    button?.setAttribute("aria-pressed", String(open));
    if (open) {
      if (stale || !loaded) load().catch(error => { messages = []; render(); input.placeholder = error.message; });
      else { markRead(); render(); }
      if (mention) {
        const prefix = input.value && !input.value.endsWith(" ") ? " " : "";
        if (!input.value.includes("@" + mention)) input.value += prefix + "@" + mention + " ";
      }
      input.focus();
      input.setSelectionRange(input.value.length, input.value.length);
    }
  }
  async function submit() {
    const text = input.value.trim();
    if (!text) return;
    input.disabled = true;
    try {
      receive(await send({text}));
      input.value = "";
    } catch (error) { alert(error.message); }
    finally { input.disabled = false; input.focus(); }
  }
  // `area`: a panel ide kerül (a vászon tárolója); `controls`: az eszköztár (a gomb ide).
  function bind(host, controls, before = null) {
    listeners?.abort();
    listeners = new AbortController();
    const options = {signal: listeners.signal};
    area = host;
    button = document.createElement("button");
    button.type = "button";
    button.className = "button chat-tool";
    button.title = "Csevegés (ezen a lapon)";
    button.setAttribute("aria-pressed", "false");
    button.innerHTML = '<svg class="ui-icon" aria-hidden="true" viewBox="0 0 24 24"><use href="/icons.svg#comment"/></svg>';
    badge = document.createElement("span");
    badge.className = "chat-badge";
    badge.hidden = true;
    button.append(badge);
    controls?.insertBefore(button, before);
    button.addEventListener("click", () => toggle(), options);
    panel?.remove();
    panel = document.createElement("section");
    panel.className = "chat-panel panel";
    panel.hidden = !open;
    panel.setAttribute("aria-label", "Csevegés");
    const head = document.createElement("header");
    const title = document.createElement("strong");
    title.textContent = "Csevegés";
    const close = document.createElement("button");
    close.type = "button";
    close.className = "chat-close";
    close.title = "Bezárás";
    close.setAttribute("aria-label", "Bezárás");
    close.textContent = "×";
    close.addEventListener("click", () => toggle(false), options);
    head.append(title, close);
    list = document.createElement("ol");
    list.className = "chat-list";
    const form = document.createElement("form");
    form.className = "chat-form";
    input = document.createElement("textarea");
    input.rows = 2;
    input.maxLength = 2000;
    input.placeholder = "Üzenet… (Enter: küldés, Shift+Enter: új sor)";
    input.setAttribute("aria-label", "Üzenet");
    const sendButton = document.createElement("button");
    sendButton.type = "submit";
    sendButton.className = "button";
    sendButton.textContent = "Küldés";
    form.append(input, sendButton);
    form.addEventListener("submit", event => { event.preventDefault(); submit(); }, options);
    input.addEventListener("keydown", event => {
      event.stopPropagation();
      if (event.key === "Enter" && !event.shiftKey && !event.isComposing) { event.preventDefault(); submit(); }
      if (event.key === "Escape") toggle(false);
    }, options);
    for (const type of ["pointerdown", "wheel", "dblclick", "click", "contextmenu"]) panel.addEventListener(type, event => event.stopPropagation(), options);
    panel.append(head, list, form);
    area.append(panel);
    render();
    if (!loaded) load().catch(() => {});
  }
  return {bind, receive, open: mention => toggle(true, mention), stop() { listeners?.abort(); panel?.remove(); button?.remove(); }};
}
