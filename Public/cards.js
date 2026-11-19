const list = document.querySelector("#worksheet-cards");
for (const card of list.querySelectorAll(".project-card")) {
  card.style.setProperty("--sheet-color", card.dataset.color);
}
let menu;
function close() { menu?.remove(); menu = null; }
list.addEventListener("contextmenu", event => {
  const card = event.target.closest(".project-card");
  if (!card) return;
  event.preventDefault();
  close();
  menu = document.createElement("div");
  menu.className = "context-menu panel";
  const open = document.createElement("a");
  open.className = "button";
  open.href = card.href;
  open.textContent = "Megnyitás";
  menu.append(open);
  const remove = document.createElement("button");
  remove.className = "button danger";
  remove.textContent = "Törlés";
  remove.disabled = list.dataset.delete !== "true";
  remove.onclick = async () => {
    close();
    if (!confirm("Lomtárba helyezed ezt a munkalapot?")) return;
    try {
      const response = await fetch("/api/worksheet" + card.pathname, {method: "DELETE", headers: {
        "If-Match": '"' + card.dataset.revision + '"', "X-CSRF-Token": list.dataset.csrf,
      }});
      if (!response.ok) throw Error((await response.json()).reason || "A törlés sikertelen.");
      location.reload();
    } catch (error) { alert(error.message); }
  };
  menu.append(remove);
  document.body.append(menu);
  menu.style.left = Math.max(0, Math.min(event.clientX, innerWidth-menu.offsetWidth)) + "px";
  menu.style.top = Math.max(0, Math.min(event.clientY, innerHeight-menu.offsetHeight)) + "px";
  open.focus();
});
document.addEventListener("pointerdown", event => { if (menu && !menu.contains(event.target)) close(); });
document.addEventListener("keydown", event => { if (event.key === "Escape") close(); });
