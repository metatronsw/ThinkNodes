// Összetett pásztázási terv (a lapon kiértékelve; Chrome: chrome-pan.mjs, Safari: safari-pan.py): 100%-os nagyításon a
// teljes vászon bejárása oda-vissza (jobbra, le, balra, le, jobbra … majd vissza), minden húzás hirtelen rántással kezdődik
// (a táv 60%-a 4 képkocka alatt), utána lassú finomhúzás (40% ~40 képkocka alatt), közte rövid megállás.
// Eredmény: húzások listája {x, y, dx, dy}: (x, y) üres vászonpont a húzás elején (képernyő-koordináta).
window.__panPlan = (() => {
  const area = document.querySelector(".canvas-area"), rect = area.getBoundingClientRect();
  const t = area.__zoom, canvas = document.querySelector(".editor-canvas");
  // A tartalom határa képernyő-koordinátában (a dobozok és vonalak csoportjai).
  let left = Infinity, top = Infinity, right = -Infinity, bottom = -Infinity;
  for (const el of canvas.querySelectorAll("[data-node], [data-edge]")) {
    const b = el.getBoundingClientRect();
    if (!b.width && !b.height) continue;
    left = Math.min(left, b.left); top = Math.min(top, b.top); right = Math.max(right, b.right); bottom = Math.max(bottom, b.bottom);
  }
  const view = {w: rect.width, h: rect.height};
  // A nézet közepének útja a tartalom határain belül (a nézet felével beljebb): kígyózó sávok, majd vissza.
  const cx0 = rect.left + view.w / 2, cy0 = rect.top + view.h / 2;
  const minX = left + view.w * .35, maxX = Math.max(minX, right - view.w * .35);
  const minY = top + view.h * .35, maxY = Math.max(minY, bottom - view.h * .35);
  const rows = Math.max(2, Math.ceil((maxY - minY) / (view.h * .6)) + 1);
  const waypoints = [];
  for (let r = 0; r < rows; r++) {
    const y = minY + (maxY - minY) * r / (rows - 1);
    waypoints.push(r % 2 ? [maxX, y] : [minX, y], r % 2 ? [minX, y] : [maxX, y]);
  }
  const path = [[cx0, cy0], ...waypoints, ...waypoints.slice().reverse(), [cx0, cy0]];
  // A nézet közepének elmozdulása → a tartalmat ellenkező irányba kell húzni. Húzásonként legfeljebb ~ a nézet 55%-a.
  const drags = [];
  for (let i = 1; i < path.length; i++) {
    let dx = -(path[i][0] - path[i - 1][0]), dy = -(path[i][1] - path[i - 1][1]);
    const parts = Math.max(1, Math.ceil(Math.max(Math.abs(dx) / (view.w * .55), Math.abs(dy) / (view.h * .55))));
    for (let p = 0; p < parts; p++) drags.push({dx: dx / parts, dy: dy / parts});
  }
  return {zoom: t?.k, bounds: {left, top, right, bottom}, view, drags: drags.filter(d => Math.hypot(d.dx, d.dy) > 4)};
})();
