// Próba-SVG ellenőrzése (Public/bench-anim.svg): futnak-e az animációk, és a pötty a vonalon van-e.
// A böngészőben értékelendő kifejezés; az eredmény JSON. Chrome (CDP) és Safari (WebDriver) is ezt futtatja.
(() => {
  const anims = document.getAnimations();
  const out = {animations: anims.length, names: anims.map(a => a.animationName ?? a.effect?.target?.getAttribute("class"))};
  const route = document.getElementById("route"), total = route.getTotalLength(), dot = document.querySelector(".dot");
  const svg = document.documentElement, ctm = svg.getScreenCTM();
  out.dot = [0.4, 1.3, 2.25].map(t => {
    anims.forEach(a => { a.pause(); a.currentTime = t * 1000; });
    const progress = Math.floor(t / 3 * 60) / 60, p = route.getPointAtLength(total * progress);
    const r = dot.getBoundingClientRect(), cx = (r.left + r.width / 2 - ctm.e) / ctm.a, cy = (r.top + r.height / 2 - ctm.f) / ctm.d;
    return {t, hiba_px: Math.round(Math.hypot(cx - p.x, cy - p.y) * 10) / 10};
  });
  anims.forEach(a => { a.currentTime = 750; });
  const cs = sel => getComputedStyle(document.querySelector(sel));
  out.pulse = cs(".pulse").transform;
  out.taper_d = cs(".taper").d?.slice(0, 40) ?? "nincs d tulajdonság";
  out.taper_box_h = Math.round(document.querySelector(".taper").getBoundingClientRect().height);
  out.taper2_sw = cs(".taper2").strokeWidth;
  out.arrow = cs(".arrow").transform;
  out.dash = cs(".dash").strokeDashoffset;
  return JSON.stringify(out);
})()
