// A szerkesztő tartalom-animációinak ellenőrzése (a lapon kiértékelve): futnak-e, a közös ütemen vannak-e
// (startTime = 0), és a futó pötty a vonal útján van-e (a pötty középpontja és az út legközelebbi pontja).
(() => {
  const anims = document.getAnimations().filter(a => a.animationName?.startsWith("tn-"));
  const out = {db: anims.length, nevek: [...new Set(anims.map(a => a.animationName))].sort(), igazitva: anims.every(a => a.startTime === 0),
    fut: anims.filter(a => a.playState === "running").length};
  const dots = [...document.querySelectorAll(".editor-canvas .wire-dot")];
  out.pottyok = dots.map(dot => {
    const route = dot.closest(".wire")?.querySelector(".wire-line");
    if (!route?.getTotalLength) return null;
    const m = dot.getCTM(), b = dot.getBBox(), cx = b.x + b.width / 2, cy = b.y + b.height / 2;
    const p = new DOMPoint(cx, cy).matrixTransform(m).matrixTransform(route.getCTM().inverse());
    let best = Infinity, total = route.getTotalLength();
    for (let i = 0; i <= 400; i++) { const q = route.getPointAtLength(total * i / 400); best = Math.min(best, Math.hypot(q.x - p.x, q.y - p.y)); }
    return Math.round(best * 10) / 10;
  });
  return JSON.stringify(out);
})()
