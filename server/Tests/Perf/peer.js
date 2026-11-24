// Második felhasználó szimulációja a többfelhasználós méréshez: a szerkesztő lapján (másik böngészőben) futtatva
// felváltva kijelöl és húz dobozokat a megadott ideig. Használat (konzolból vagy automatizálásból): peer(30000)
window.peer = async function (duration = 30000) {
  const wait = ms => new Promise(resolve => setTimeout(resolve, ms));
  const event = (type, x, y, buttons) => new PointerEvent(type, {bubbles: true, cancelable: true, view: window, clientX: x, clientY: y,
    button: 0, buttons, pointerId: 1, pointerType: "mouse", isPrimary: true});
  const until = performance.now() + duration;
  const stats = {selected: 0, dragged: 0};
  for (let round = 0; performance.now() < until; round++) {
    const nodes = [...document.querySelectorAll('[data-node][data-type="box"] .node-surface')].filter(el => {
      const b = el.getBoundingClientRect();
      return b.left > 40 && b.top > 80 && b.right < innerWidth - 60 && b.bottom < innerHeight - 80;
    });
    if (!nodes.length) { await wait(300); continue; }
    const surface = nodes[(round * 7) % nodes.length], b = surface.getBoundingClientRect();
    const x = b.left + b.width / 2, y = b.top + b.height / 2;
    const canvas = document.querySelector("svg.editor-canvas");
    surface.dispatchEvent(event("pointerdown", x, y, 1));
    await wait(180);   // a kijelölés (zárolás) megérkezik
    stats.selected++;
    if (round % 2 === 0) {
      for (let i = 1; i <= 24; i++) { canvas.dispatchEvent(event("pointermove", x + i * 3, y + i * 2, 1)); await wait(33); }
      for (let i = 23; i >= 0; i--) { canvas.dispatchEvent(event("pointermove", x + i * 3, y + i * 2, 1)); await wait(33); }
      stats.dragged++;
    }
    surface.dispatchEvent(event("pointerup", x, y, 0));
    canvas.dispatchEvent(event("pointerup", x, y, 0));
    await wait(250);
  }
  return stats;
};
