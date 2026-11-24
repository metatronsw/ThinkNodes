import {fetchPage, updateSection, watchPageUpdates} from "./page-updates.js";

document.addEventListener("click", event => {
  const button = event.target.closest("button[data-avatar-dialog]");
  if (button) document.getElementById(button.dataset.avatarDialog)?.showModal();
});

// Törölt projektek: a végleges törlés gombja csak a „Végleg” négyzet bejelölése után használható.
document.addEventListener("change", event => {
  const box = event.target.closest?.("input[data-enables=purge]");
  const button = box?.form?.querySelector("button[data-purge]");
  if (button) button.disabled = !box.checked;
});

watchPageUpdates(async (signal, incoming) => {
  const {response, page} = incoming ?? await fetchPage(signal);
  if (signal.aborted) return;
  if (response.status >= 500) throw Error("Az oldal nem érhető el.");
  if (response.redirected || !page.querySelector(".admin-shell")) { location.reload(); return; }
  if (!response.ok) throw Error("A beállítások nem érhetők el.");
  const current = document.querySelector(".admin-shell");
  const passwordFields = [...current.querySelectorAll("input[type=password]")];
  if (passwordFields.some(field => field.value)) {
    throw Error("A beállítási űrlap szerkesztés alatt áll.");
  }
  updateSection(document, page, ".admin-shell");
});
