(() => {
  const media = window.matchMedia("(prefers-color-scheme: dark)");
  const modes = ["auto", "light", "dark"];
  const names = {auto: "Automatikus", light: "Világos", dark: "Sötét"};
  const settingKey = "thinknodes.siteMode";
  let setting = "auto";
  function apply() {
    const saved = localStorage.getItem(settingKey);
    setting = modes.includes(saved) ? saved : "auto";
    const mode = setting === "auto" ? (media.matches ? "dark" : "light") : setting;
    document.documentElement.dataset.display = mode;
    document.cookie = "tn_display=" + mode + "; Path=/; SameSite=Lax";
    const picker = document.querySelector("[data-site-mode-picker]");
    if (picker) {
      const label = "Megjelenés: " + names[setting];
      picker.dataset.mode = setting;
      picker.setAttribute("aria-label", label);
      picker.title = label;
      picker.querySelector("use")?.setAttribute("href", "/icons.svg#display-" + setting);
    }
    const viewer = document.querySelector("#worksheet-view");
    if (viewer && viewer.dataset.siteMode !== mode) {
      const url = new URL(location.href);
      url.searchParams.set("mode", mode);
      location.replace(url);
      return;
    }
    for (const link of document.querySelectorAll('a[href^="/export/svg/"]')) {
      const url = new URL(link.href);
      url.searchParams.set("mode", mode);
      link.setAttribute("href", url.pathname + url.search + url.hash);
    }
    for (const img of document.querySelectorAll('img[src^="/api/preview/"]')) {
      const url = new URL(img.src);
      url.searchParams.set("mode", mode);
      const source = url.pathname + url.search;
      if (img.getAttribute("src") !== source) img.setAttribute("src", source);
    }
    window.dispatchEvent(new Event("thinknodes-display"));
  }
  document.addEventListener("click", event => {
    if (!event.target.closest?.("[data-site-mode-picker]")) return;
    localStorage.setItem(settingKey, modes[(modes.indexOf(setting) + 1) % modes.length]);
    apply();
  });
  media.addEventListener("change", apply);
  window.addEventListener("storage", apply);
  window.addEventListener("thinknodes-page-updated", apply);
  apply();
})();
