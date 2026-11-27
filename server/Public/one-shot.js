// Egyszeri eszköz (one-shot): billentyűvel élesített eszköz, amely egyetlen használat után magától visszaáll (a kurzor
// és az egér a megszokott módon működik tovább). Globális: bármely eszköz bejegyezhet egy billentyűt. Élesítéskor az
// eszköz gombja csak fényes keretet kap (app.css .one-shot-armed), a bekapcsolt állapot (aria-pressed) nem változik.
// Az élesítést ugyanaz a billentyű vagy az Escape visszavonja; az eszköz a használat végén a `used`-et hívja.
//
// Eszköz: {button, arm() → igaz, ha élesíthető (pl. ha már be van kapcsolva, nem az), disarm()}.
const shortcuts = new Map();   // kisbetűs billentyű → eszköz
let armed = null, installed = false;

const editable = target => target?.closest?.("input, textarea, select, [contenteditable=''], [contenteditable=true], [contenteditable=plaintext-only]");

function disarm() {
  const tool = armed;
  if (!tool) return;
  armed = null;
  tool.button?.classList.remove("one-shot-armed");
  tool.disarm();
}

function install() {
  if (installed) return;
  installed = true;
  addEventListener("keydown", event => {
    if (event.key === "Escape") { if (armed) disarm(); return; }
    if (event.repeat || event.ctrlKey || event.metaKey || event.altKey || editable(event.target)) return;
    const tool = shortcuts.get(event.key?.toLowerCase());
    if (!tool) return;
    if (armed === tool) { disarm(); event.preventDefault(); return; }
    disarm();
    if (!tool.arm()) return;
    armed = tool;
    tool.button?.classList.add("one-shot-armed");
    event.preventDefault();
  });
  addEventListener("blur", disarm);
}

// Bejegyzés; a visszaadott függvény törli (és ha éppen élesített, visszavonja).
export function registerOneShot(key, tool) {
  install();
  shortcuts.set(key.toLowerCase(), tool);
  return () => {
    if (armed === tool) disarm();
    if (shortcuts.get(key.toLowerCase()) === tool) shortcuts.delete(key.toLowerCase());
  };
}

// Az eszköz egyszeri használata véget ért: visszaáll.
export function oneShotUsed(tool) { if (armed === tool) disarm(); }

export const oneShotArmed = tool => armed === tool;
