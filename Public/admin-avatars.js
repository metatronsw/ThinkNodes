import {fetchPage, updateSection, watchPageUpdates} from "./page-updates.js";

document.addEventListener("click", event => {
  const button = event.target.closest("button[data-avatar-dialog]");
  if (button) document.getElementById(button.dataset.avatarDialog)?.showModal();
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
