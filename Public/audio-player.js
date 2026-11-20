const playbackEvents = ["loadedmetadata", "durationchange", "timeupdate", "play", "pause", "ended", "error"];

function syncPlayer(player) {
  const audio = player.querySelector("audio");
  const toggle = player.querySelector("[data-audio-toggle]");
  const seek = player.querySelector("[data-audio-seek]");
  const playing = !audio.paused && !audio.ended;
  const label = playing ? "Szünet" : "Lejátszás";
  toggle.setAttribute("aria-label", label);
  toggle.title = label;
  toggle.querySelector("use").setAttribute("href", "/icons.svg#" + (playing ? "pause" : "play"));
  const duration = Number.isFinite(audio.duration) ? audio.duration : 0;
  seek.disabled = !duration || !!audio.error;
  seek.max = duration;
  seek.value = Math.min(duration, audio.currentTime);
  if (audio.error) player.querySelector("[data-audio-status]").textContent = "A hangfájl nem tölthető be.";
}

export function syncAudioPlayers(root) {
  root.querySelectorAll("[data-audio-player]").forEach(syncPlayer);
}

export function bindAudioPlayers(root) {
  const controller = new AbortController();
  const options = {capture: true, signal: controller.signal};
  for (const name of playbackEvents) {
    root.addEventListener(name, event => {
      if (event.target.localName !== "audio") return;
      const player = event.target.closest("[data-audio-player]");
      if (player) syncPlayer(player);
    }, options);
  }
  root.addEventListener("click", async event => {
    const toggle = event.target.closest("[data-audio-toggle]");
    if (!toggle) return;
    const player = toggle.closest("[data-audio-player]");
    const audio = player.querySelector("audio");
    const status = player.querySelector("[data-audio-status]");
    status.textContent = "";
    try {
      if (audio.paused || audio.ended) {
        if (audio.error) audio.load();
        await audio.play();
      } else audio.pause();
    } catch (error) {
      if (error.name !== "AbortError") status.textContent = "A hangfájl nem játszható le.";
    }
    syncPlayer(player);
  }, options);
  root.addEventListener("input", event => {
    const seek = event.target;
    if (!seek.matches("[data-audio-seek]")) return;
    const audio = seek.closest("[data-audio-player]").querySelector("audio");
    if (Number.isFinite(audio.duration) && Number.isFinite(seek.valueAsNumber)) audio.currentTime = seek.valueAsNumber;
  }, options);
  syncAudioPlayers(root);
  return controller;
}
