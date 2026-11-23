// Kijelölés glow-ja SVG-szűrővel. A Safari (WebKit) SVG elemen nem rajzolja ki a CSS drop-shadow() és
// brightness() függvényeket, a hivatkozott SVG-szűrőt (filter: url(#…)) viszont igen.
//
// A CSS drop-shadow(0 0 r c) a szabvány szerint: az alfa elmosása stdDeviation = r/2 értékkel, c színnel
// kitöltve, az eredeti alá téve. Több réteg egymásra épül (a második az első eredményének árnyéka), mint a
// CSS-ben egymás után írt szűrőknél; a brightness() az árnyékok előtt fut. sRGB-ben számol, mint a CSS.
//
// A flood-color nem a hivatkozó elem színét veszi át (a currentColor a szűrő saját helyén oldódik fel),
// ezért színenként külön szűrő kell: glowId() a fajtából és a színből képez azonosítót.

export const glowKinds = {
  // Más felhasználó kijelölése (doboz kerete, vonal): a munkalap glow-beállításából (graphics.glow, px).
  peer: glow => ({radii: [glow, glow * 2.5]}),
  // Saját kijelölés: doboz felülete (világosítva), keret, csomópont karikája, vonal (világosítva).
  ownSurface: () => ({radii: [2, 6], brightness: 1.18}),
  ownFrame: () => ({radii: [2, 6]}),
  ownWire: () => ({radii: [2, 5], brightness: 1.3}),
  search: () => ({radii: [6]}),
};

export function glowId(kind, color, glow = 3) {
  return ("glow-" + kind + "-" + (kind === "peer" ? glow + "-" : "") + color).replace(/[^\w-]/g, "_");
}

export function glowURL(kind, color, glow) {
  return "url(#" + glowId(kind, color, glow) + ")";
}

// A szűrő leírása {tag, attrs, children} fában; a szerkesztő Vue-csomópontot, a megtekintő DOM-ot épít belőle.
// A szűrőterület a befoglaló téglalaphoz képest arányos: a kis csomópontnak (12 px) is maradjon hely a glow-nak.
// Vízszintes vagy függőleges vonal téglalapja nulla vastag, ezért a vonalak a glow csoportba láthatatlan
// helytartót kapnak (glowPadding), hogy a téglalap mindkét irányban elég nagy legyen.
export function glowFilter(kind, color, glow = 3) {
  const {radii, brightness} = glowKinds[kind](glow);
  const children = [];
  let input = "SourceGraphic";
  if (brightness) {
    children.push({tag: "feComponentTransfer", attrs: {in: input, result: "bright"}, children:
      ["feFuncR", "feFuncG", "feFuncB"].map(tag => ({tag, attrs: {type: "linear", slope: brightness}}))});
    input = "bright";
  }
  radii.forEach((radius, index) => {
    const step = "g" + index;
    children.push(
      {tag: "feGaussianBlur", attrs: {in: input, stdDeviation: radius / 2, result: step + "blur"}},
      {tag: "feFlood", attrs: {style: "flood-color: " + color, result: step + "color"}},
      {tag: "feComposite", attrs: {in: step + "color", in2: step + "blur", operator: "in", result: step + "shadow"}},
      {tag: "feMerge", attrs: {result: step}, children: [
        {tag: "feMergeNode", attrs: {in: step + "shadow"}},
        {tag: "feMergeNode", attrs: {in: input}},
      ]});
    input = step;
  });
  return {tag: "filter", attrs: {id: glowId(kind, color, glow), x: "-100%", y: "-100%", width: "300%", height: "300%",
    "color-interpolation-filters": "sRGB"}, children};
}

// A glow legnagyobb kiterjedése (≈ 3 szórás) a vonal helytartójához.
export function glowReach(kind, glow = 3) {
  return Math.max(...glowKinds[kind](glow).radii) * 1.5;
}

export function glowVNode(h, spec) {
  return h(spec.tag, {key: spec.attrs.id, ...spec.attrs}, spec.children?.map(child => glowVNode(h, child)));
}

export function glowElement(spec) {
  const element = document.createElementNS("http://www.w3.org/2000/svg", spec.tag);
  for (const [key, value] of Object.entries(spec.attrs)) element.setAttribute(key, value);
  for (const child of spec.children ?? []) element.append(glowElement(child));
  return element;
}

// A megtekintőben: a szűrőt egyszer beteszi a vászon defs-ébe, és visszaadja a hivatkozását.
export function ensureGlow(svg, kind, color, glow) {
  const id = glowId(kind, color, glow);
  if (!svg.querySelector("#" + id)) {
    let defs = svg.querySelector(":scope > defs");
    if (!defs) svg.prepend(defs = document.createElementNS("http://www.w3.org/2000/svg", "defs"));
    defs.append(glowElement(glowFilter(kind, color, glow)));
  }
  return "url(#" + id + ")";
}
