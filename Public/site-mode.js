(() => {
  const media = window.matchMedia("(prefers-color-scheme: dark)");
  const picker = document.querySelector("[data-site-mode-picker]");
  function apply() {
    const setting = localStorage.getItem("thinknodes.siteMode") || "auto";
    const mode = setting === "auto" ? (media.matches ? "dark" : "light") : setting;
    document.documentElement.dataset.display = mode;
    document.cookie = "tn_display=" + mode + "; Path=/; SameSite=Lax";
    if (picker) picker.value = setting;
    const viewer = document.querySelector("#worksheet-view");
    if (viewer?.dataset.auto === "true" && viewer.dataset.siteMode !== mode) {
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
      img.setAttribute("src", url.pathname + url.search);
    }
    window.dispatchEvent(new Event("thinknodes-display"));
  }
  picker?.addEventListener("change", () => {
    localStorage.setItem("thinknodes.siteMode", picker.value);
    apply();
  });
  media.addEventListener("change", apply);
  window.addEventListener("storage", apply);
  apply();
})();
