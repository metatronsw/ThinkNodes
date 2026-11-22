// A munkalap fejlécének fokozatos tömörítése görgetősáv helyett (app.css „Fejléc fokozatos tömörítése”):
// teljes → ikonos gombok → sorszámos útvonal → két sor (széles logóval) → két sor sorszámos útvonallal
// → két sor ikonos logóval. Mindkét sornak egy sorban kell maradnia.
const levels = [[], ["compact"], ["compact", "numbered"], ["compact", "stacked"], ["compact", "stacked", "numbered"],
  ["compact", "stacked", "numbered", "narrow-brand"]];
const every = [...new Set(levels.flat())];

const firstRow = ".header-left, .worksheet-close, .sidebar-open-canvas";

function singleLine(elements) {
  const tops = elements.filter(element => element.getBoundingClientRect().width > 0)
    .map(element => element.getBoundingClientRect().top);
  return !tops.length || Math.max(...tops) - Math.min(...tops) < 3;
}

function overflowing(nav) {
  if (nav.scrollWidth > nav.clientWidth + 1) return true;
  if (nav.classList.contains("stacked")) {
    const first = [...nav.children].filter(child => child.matches(firstRow));
    const second = [...nav.children].filter(child => !child.matches(firstRow) && !child.matches(".header-parent"))
      .flatMap(child => child.matches(".header-button, .button") ? [child] : [...child.querySelectorAll(".header-button, .button")]);
    if (!singleLine(first) || !singleLine(second)) return true;
  }
  const crumbs = nav.querySelector(".breadcrumbs");
  if (crumbs && crumbs.scrollWidth > crumbs.clientWidth + 1) return true;
  const right = nav.getBoundingClientRect().right + 1;
  return [...nav.querySelectorAll(".header-button, .button")].some(button => {
    const bounds = button.getBoundingClientRect();
    return bounds.width > 0 && bounds.right > right;
  });
}

function fit(nav) {
  for (const level of levels) {
    nav.classList.remove(...every);
    nav.classList.add(...level);
    if (!overflowing(nav)) return;
  }
}

function watch(nav) {
  let queued = false;
  const schedule = () => {
    if (queued) return;
    queued = true;
    requestAnimationFrame(() => { queued = false; fit(nav); });
  };
  new ResizeObserver(schedule).observe(nav.parentElement ?? nav);
  new MutationObserver(schedule).observe(nav, {childList: true, subtree: true, characterData: true});
  window.addEventListener("resize", schedule);
  document.fonts?.ready?.then(schedule);
  schedule();
}

document.querySelectorAll(".worksheet-nav").forEach(watch);
