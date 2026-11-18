import {borderPoint, cableColor, canvasBounds, commentColor, edgeGeometry, edgeStyles, labelLayout, limit, paper, shapeDistance, shapes} from "./geometry.js";

const mount = document.querySelector("#editor");
const {path, csrf, role} = mount.dataset;
const d3 = window.d3;
const {createApp, computed, h, nextTick, onMounted, onUnmounted, ref, shallowRef, watch} = window.Vue;
const endpoint = "/api/worksheet/" + path;
const svgNamespace = "http://www.w3.org/2000/svg";

function button(label, onClick, props = {}) {
  return h("button", {type: "button", class: "button", onClick, ...props}, label);
}

function select(value, choices, onChange, props = {}) {
  return h("select", {
    value,
    onChange: event => onChange(event.target.value), ...props,
  }, Object.entries(choices).map(([key, label]) => h("option", {key, value: key}, label)));
}

function field(label, control) {
  return h("label", [h("span", label), control]);
}

function input(value, change, props = {}) {
  return h("input", {value, onInput: event => change(event.target.value), ...props});
}

function numeric(value, change, min, max, props = {}) {
  return input(value, next => {
    const parsed = Number(next);
    if (next !== "" && parsed >= min && parsed <= max) change(parsed);
  }, {
    type: "number", min, max, step: "any",
    onBlur: event => { event.target.value = value; },
    ...props,
  });
}

function checkbox(label, checked, change) {
  return h("label", {class: "check"}, [
    h("input", {type: "checkbox", checked, onChange: event => change(event.target.checked)}),
    label,
  ]);
}

function textarea(value, change) {
  return h("textarea", {value, maxlength: 30000, rows: 7, onInput: event => change(event.target.value)});
}

function draftMarkdown(source) {
  return source.slice(0, 6000)
    .replace(/^\s{0,3}#{1,6}[ \t]+/gm, "")
    .replace(/\*\*([^*]+)\*\*/g, "$1")
    .replace(/\[([^\]]+)\]\([^)]+\)/g, "$1");
}

function shape(node) {
  const x = node.width / 2;
  const y = node.height / 2;
  const style = {fill: node.fill, stroke: node.border, "stroke-width": 1.6};
  if (node.shape === "ellipse") return h("ellipse", {...style, rx: x, ry: y});
  if (node.shape === "diamond") return h("polygon", {...style, points: ["0," + -y, x + ",0", "0," + y, -x + ",0"].join(" ")});
  return h("rect", {...style, x: -x, y: -y, width: node.width, height: node.height, rx: node.shape === "rounded" ? 12 : 0});
}

function arrowDefinition() {
  return h("marker", {id: "arrow", viewBox: "0 0 10 10", markerWidth: 9, markerHeight: 9, refX: 9, refY: 5,
    orient: "auto-start-reverse", markerUnits: "userSpaceOnUse"}, [
    h("path", {d: "M 0 0 L 10 5 L 0 10 z", fill: cableColor}),
  ]);
}

function edgeAppearance(style) {
  return {
    "marker-start": style === "both" ? "url(#arrow)" : undefined,
    "marker-end": style !== "rope" ? "url(#arrow)" : undefined,
    "stroke-dasharray": style === "dashed" ? "7 5" : undefined,
  };
}

async function checked(response) {
  if (response.ok) return response;
  const detail = await response.json().catch(() => ({}));
  throw new Error(detail.reason || "A kérés nem sikerült (" + response.status + ").");
}

createApp({
  setup() {
    const board = ref(null);
    const nodeMap = computed(() => new Map(board.value?.nodes.map(node => [node.id, node])));
    const canvasMarkdown = shallowRef(new Map());
    const markdownSources = computed(() => [...new Set(
      board.value?.nodes.filter(node => node.showMarkdown && node.markdown).map(node => node.markdown)
    )]);
    const drawings = computed(() => new Map(board.value?.nodes.map(node => {
      const markdown = node.showMarkdown && node.markdown
        ? canvasMarkdown.value.get(node.markdown) ?? draftMarkdown(node.markdown) : "";
      const layout = labelLayout(node, markdown);
      return [node.id, {node: {...node, width: layout.width, height: layout.height}, layout}];
    })));
    const drawnNode = id => drawings.value.get(id)?.node;
    const drawnBounds = () => canvasBounds({
      nodes: [...drawings.value.values()].map(drawing => drawing.node), edges: board.value.edges,
    });
    const selected = ref(null);
    const pendingStyle = ref("arrow");
    const connectMode = ref(false);
    const reconnect = ref(null);
    const menu = ref(null);
    const inspector = ref(null);
    const note = ref(null);
    const canvas = ref(null);
    const view = shallowRef(d3.zoomIdentity);
    const size = ref({width: 0, height: 0});
    const gesture = ref(null);
    const preview = ref(null);
    const status = ref("");
    const problem = ref("");
    const saving = ref(false);
    const generation = ref(0);
    const savedGeneration = ref(0);
    const dirty = computed(() => generation.value !== savedGeneration.value);
    let zoom;
    let resizeObserver;
    let lastClick;
    let rightPress = false;
    let noteRequest = 0;

    async function loadCanvasMarkdown(sources, signal) {
      const missing = sources.filter(source => !canvasMarkdown.value.has(source));
      let text = [];
      if (missing.length) {
        const result = await checked(await fetch("/api/markdown/canvas", {
          method: "POST", signal,
          headers: {"Content-Type": "application/json", "X-CSRF-Token": csrf},
          body: JSON.stringify({sources: missing}),
        }));
        ({text} = await result.json());
      }
      if (signal?.aborted) return;
      const current = new Set(markdownSources.value);
      const updated = new Map([...canvasMarkdown.value].filter(([source]) => current.has(source)));
      missing.forEach((source, index) => {
        if (current.has(source)) updated.set(source, text[index]);
      });
      canvasMarkdown.value = updated;
    }

    watch(markdownSources, (sources, _, onCleanup) => {
      const controller = new AbortController();
      const timer = setTimeout(() => loadCanvasMarkdown(sources, controller.signal).catch(() => {
        // Keep the immediate draft visible if a preview request fails.
      }), 80);
      onCleanup(() => {
        clearTimeout(timer);
        controller.abort();
      });
    });

    function modified() {
      generation.value += 1;
      problem.value = "";
      status.value = "";
    }

    const center = () => [size.value.width / 2, size.value.height / 2];
    const worldAtCenter = () => {
      const [centerX, centerY] = center();
      const [x, y] = view.value.invert([centerX, centerY]);
      return {x: x - centerX, y: y - centerY};
    };

    function world(event) {
      const [px, py] = d3.pointer(event, canvas.value);
      const [x, y] = view.value.invert([px, py]);
      const [centerX, centerY] = center();
      return {x: x - centerX, y: y - centerY};
    }

    function clampPoint(point) {
      return {x: limit(point.x, -100000, 100000), y: limit(point.y, -100000, 100000)};
    }

    function measure() {
      const svg = canvas.value;
      if (svg) size.value = {width: svg.clientWidth, height: svg.clientHeight};
    }

    function initializeZoom() {
      if (!canvas.value || zoom) return;
      measure();
      zoom = d3.zoom().scaleExtent([0.0005, 4])
        .filter(event => {
          if (event.type === "wheel") return !gesture.value;
          return !event.button && !event.ctrlKey && !reconnect.value && !gesture.value
            && !event.target.closest("[data-node], [data-edge]");
        })
        .on("start", event => { menu.value = null; if (event.sourceEvent) lastClick = null; })
        .on("zoom", event => { view.value = event.transform; });
      d3.select(canvas.value).call(zoom).on("dblclick.zoom", null);
      resizeObserver = new ResizeObserver(measure);
      resizeObserver.observe(canvas.value);
      fit();
    }

    function fit() {
      if (!zoom || !board.value) return;
      const bounds = drawnBounds();
      const [x, y] = center();
      const scale = limit(Math.min((x * 2 - 40) / bounds.width, (y * 2 - 40) / bounds.height, 1), 0.0005, 1);
      d3.select(canvas.value).call(zoom.transform, d3.zoomIdentity.translate(x * (1 - scale), y * (1 - scale)).scale(scale));
    }

    function centerOrigin() {
      if (!zoom) return;
      d3.select(canvas.value).call(zoom.transform, d3.zoomIdentity);
    }

    function zoomBy(multiplier) {
      if (zoom) d3.select(canvas.value).call(zoom.scaleBy, multiplier);
    }

    function id() {
      // randomUUID is unavailable on plain HTTP at a LAN address.
      return Array.from(crypto.getRandomValues(new Uint8Array(16)), byte => byte.toString(16).padStart(2, "0")).join("");
    }

    async function deleteBoard() {
      if (!confirm("Lomtárba helyezed a munkalapot? Az útvonal egy újabb megnyitása üres lapot hozhat létre.")) return;
      try {
        await checked(await fetch(endpoint, {
          method: "DELETE",
          headers: {"X-CSRF-Token": csrf, "If-Match": '"' + board.value.revision + '"'},
        }));
        savedGeneration.value = generation.value;
        location.assign("/");
      } catch (error) {
        problem.value = error.message;
      }
    }

    function addNode(position = worldAtCenter()) {
      if (!board.value) return;
      const node = {id: id(), title: "Új ötlet", comment: "", markdown: "", autoSize: true, showMarkdown: false, position: clampPoint(position), width: 176, height: 80,
        shape: "rounded", fill: "#dce9ff", textColor: "#182335", border: "#839bbc", fontSize: 16, bold: true, alignment: "center"};
      board.value.nodes.push(node);
      modified();
      openProperties("node", node.id);
    }

    function openProperties(kind, itemID) {
      if (kind !== "worksheet") selected.value = {kind, id: itemID};
      inspector.value = {kind, id: itemID};
      note.value = null;
      menu.value = null;
    }

    function deleteNode(node) {
      if (!confirm("Törlöd ezt a dobozt? A belőle induló kábelek törlődnek, a hozzá érkezők vége a helyén marad.")) return;
      board.value.edges = board.value.edges.filter(edge => edge.source !== node.id);
      for (const edge of board.value.edges) {
        if (edge.target.node === node.id) detach(edge);
      }
      board.value.nodes = board.value.nodes.filter(item => item.id !== node.id);
      selected.value = null;
      inspectNothing();
      modified();
    }

    function removeEdge(edge) {
      board.value.edges = board.value.edges.filter(item => item.id !== edge.id);
      selected.value = null;
      inspectNothing();
      modified();
    }

    function detach(edge) {
      const target = drawnNode(edge.target.node);
      if (!target) return;
      edge.target = {point: clampPoint(borderPoint(target, drawnNode(edge.source).position))};
      modified();
    }

    function inspectNothing() {
      inspector.value = null;
      note.value = null;
      menu.value = null;
    }

    function snap(point, sourceID) {
      const candidates = board.value.nodes;
      for (let index = candidates.length - 1; index >= 0; index -= 1) {
        const node = candidates[index];
        if (node.id !== sourceID && shapeDistance(drawnNode(node.id), point, 12 / view.value.k) <= 1) return node;
      }
      return null;
    }

    function pressNode(event, node) {
      const controlClick = event.ctrlKey && (event.button === 0 || event.button === 2);
      if ((event.button !== 0 && !controlClick) || reconnect.value) return;
      event.preventDefault();
      event.stopPropagation();
      menu.value = null;
      selected.value = {kind: "node", id: node.id};
      event.currentTarget.focus({preventScroll: true});
      const initial = world(event);
      const cabling = controlClick || connectMode.value;
      if (cabling) lastClick = null;
      gesture.value = {type: cabling ? "cable" : "move", pointer: event.pointerId, nodeID: node.id,
        position: {...node.position}, initial, screen: [event.clientX, event.clientY], moved: false};
      if (cabling) preview.value = {source: node.id, point: initial, target: null};
      canvas.value.setPointerCapture(event.pointerId);
    }

    function updatePointer(event) {
      if (!board.value) return;
      const operation = gesture.value;
      if (!operation && !reconnect.value) return;
      if (operation && operation.pointer !== event.pointerId) return;
      const point = world(event);
      if (operation) {
        operation.moved ||= Math.hypot(event.clientX - operation.screen[0], event.clientY - operation.screen[1]) > 3;
        if (operation.type === "move") {
          if (!operation.moved) return;
          const node = nodeMap.value.get(operation.nodeID);
          node.position = clampPoint({x: operation.position.x + point.x - operation.initial.x,
            y: operation.position.y + point.y - operation.initial.y});
          return;
        }
      }
      const source = operation?.nodeID || reconnect.value.source;
      preview.value = {source, point, target: snap(point, source)?.id};
    }

    function finishPointer(event, cancel = false) {
      const operation = gesture.value;
      if (!operation || operation.pointer !== event.pointerId) return;
      if (!cancel) updatePointer(event);
      if (operation.type === "move" && operation.moved) {
        lastClick = null;
        const node = nodeMap.value.get(operation.nodeID);
        if (cancel) node.position = operation.position;
        else modified();
      } else if (operation.type === "move" && !cancel) {
        const time = performance.now();
        const [x, y] = operation.screen;
        if (lastClick?.id === operation.nodeID && time - lastClick.time < 450
            && Math.hypot(x - lastClick.x, y - lastClick.y) < 10) {
          lastClick = null;
          openProperties("node", operation.nodeID);
        } else {
          lastClick = {id: operation.nodeID, time, x, y};
          showNote(nodeMap.value.get(operation.nodeID));
        }
      } else if (operation.type === "cable" && operation.moved && !cancel) {
        const {point, target} = preview.value;
        const edge = {id: id(), source: operation.nodeID, target: target ? {node: target} : {point: clampPoint(point)},
          style: pendingStyle.value};
        board.value.edges.push(edge);
        modified();
        selected.value = {kind: "edge", id: edge.id};
        connectMode.value = false;
      }
      gesture.value = null;
      preview.value = null;
    }

    function retarget(edge) {
      menu.value = null;
      reconnect.value = edge;
      preview.value = null;
    }

    function pressCanvas(event) {
      rightPress = event.button === 2 && !event.ctrlKey;
      if (event.button !== 0 || event.ctrlKey || !reconnect.value) return;
      event.preventDefault();
      event.stopPropagation();
      const point = world(event);
      const edge = reconnect.value;
      const node = snap(point, edge.source);
      edge.target = node ? {node: node.id} : {point: clampPoint(point)};
      reconnect.value = null;
      preview.value = null;
      modified();
    }

    function context(event, kind = "canvas", itemID) {
      event.preventDefault();
      event.stopPropagation();
      if (!rightPress || event.ctrlKey || event.button !== 2 || gesture.value?.type === "cable") return;
      rightPress = false;
      lastClick = null;
      menu.value = {
        kind, id: itemID, x: Math.max(8, Math.min(event.clientX, innerWidth - 244)),
        y: Math.max(8, Math.min(event.clientY, innerHeight - 195)), position: world(event),
      };
    }

    function updateItem(item, key, value) {
      if (item[key] === value) return;
      item[key] = value;
      modified();
    }

    async function showNote(node) {
      if (!node || connectMode.value || reconnect.value) return;
      selected.value = {kind: "node", id: node.id};
      menu.value = null;
      inspector.value = null;
      const request = ++noteRequest;
      note.value = {id: node.id, request, loading: Boolean(node.markdown)};
      if (!node.markdown) return;
      try {
        const rendered = await checked(await fetch("/api/markdown", {method: "POST", headers: {
          "Content-Type": "application/json", "X-CSRF-Token": csrf,
        }, body: JSON.stringify({markdown: node.markdown})}));
        const html = await rendered.text();
        if (note.value?.request === request) note.value = {id: node.id, html, loading: false};
      } catch (error) {
        if (note.value?.request === request) note.value = {id: node.id, error: error.message, loading: false};
      }
    }

    async function save() {
      if (saving.value || !dirty.value) return;
      saving.value = true;
      problem.value = "";
      const version = generation.value;
      const payload = JSON.stringify(board.value);
      try {
        const result = await checked(await fetch(endpoint, {
          method: "PUT",
          headers: {"Content-Type": "application/json", "X-CSRF-Token": csrf, "If-Match": '"' + board.value.revision + '"'},
          body: payload,
        }));
        const saved = await result.json();
        board.value.revision = saved.revision;
        savedGeneration.value = version;
        status.value = "Mentve";
      } catch (error) {
        problem.value = error.message;
      } finally {
        saving.value = false;
      }
    }

    async function exportSVG() {
      if (!board.value || !canvas.value) return;
      await loadCanvasMarkdown(markdownSources.value).catch(() => {});
      await nextTick();
      const bounds = drawnBounds();
      const output = document.createElementNS(svgNamespace, "svg");
      output.setAttribute("viewBox", [bounds.x, bounds.y, bounds.width, bounds.height].join(" "));
      output.setAttribute("width", bounds.width);
      output.setAttribute("height", bounds.height);
      const title = document.createElementNS(svgNamespace, "title");
      title.textContent = board.value.title;
      const background = document.createElementNS(svgNamespace, "rect");
      for (const [key, value] of Object.entries({...bounds, fill: paper})) background.setAttribute(key, value);
      const scene = canvas.value.querySelector("[data-scene]").cloneNode(true);
      scene.removeAttribute("data-scene");
      scene.querySelectorAll("[data-editor-only]").forEach(element => element.remove());
      scene.querySelectorAll("[tabindex], [data-node], [data-edge]").forEach(element => {
        for (const attribute of ["tabindex", "data-node", "data-edge", "class"]) element.removeAttribute(attribute);
      });
      output.append(title, canvas.value.querySelector("defs").cloneNode(true), background, scene);
      const file = new Blob([new XMLSerializer().serializeToString(output)], {type: "image/svg+xml"});
      const url = URL.createObjectURL(file);
      const link = Object.assign(document.createElement("a"), {href: url, download: decodeURIComponent(path.split("/").at(-1)) + ".svg"});
      document.body.append(link);
      link.click();
      link.remove();
      setTimeout(() => URL.revokeObjectURL(url), 30000);
    }

    function keyboard(event) {
      if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "s") {
        event.preventDefault();
        save();
      }
      if (event.key === "Escape") {
        const active = gesture.value;
        if (active) {
          finishPointer({pointerId: active.pointer}, true);
          if (canvas.value.hasPointerCapture(active.pointer)) canvas.value.releasePointerCapture(active.pointer);
        }
        menu.value = null;
        reconnect.value = null;
        preview.value = null;
        connectMode.value = false;
      }
    }

    function beforeUnload(event) {
      if (!dirty.value) return;
      event.preventDefault();
      event.returnValue = "";
    }

    onMounted(async () => {
      window.addEventListener("keydown", keyboard);
      window.addEventListener("beforeunload", beforeUnload);
      try {
        const response = await checked(await fetch(endpoint));
        board.value = await response.json();
        await nextTick();
        initializeZoom();
      } catch (error) {
        problem.value = error.message;
      }
    });

    onUnmounted(() => {
      resizeObserver?.disconnect();
      window.removeEventListener("keydown", keyboard);
      window.removeEventListener("beforeunload", beforeUnload);
    });

    function renderNode(node) {
      const {node: drawn, layout} = drawings.value.get(node.id);
      const highlighted = selected.value?.kind === "node" && selected.value.id === node.id;
      const snapTarget = preview.value?.target === node.id;
      return h("g", {key: node.id, "data-node": node.id, tabindex: 0, role: "button",
        "aria-label": node.title, class: "idea",
        transform: "translate(" + node.position.x + " " + node.position.y + ")",
        onPointerdown: event => pressNode(event, node),
        onContextmenu: event => context(event, "node", node.id),
        onKeydown: event => {
          if (event.key === "Enter") {
            if (event.shiftKey) openProperties("node", node.id);
            else showNote(node);
          }
        },
      }, [
        h("title", node.title),
        highlighted || snapTarget ? h("rect", {"data-editor-only": "", x: -drawn.width / 2 - 4, y: -drawn.height / 2 - 4,
          width: drawn.width + 8, height: drawn.height + 8, rx: 15, fill: "none",
          stroke: snapTarget ? "#16a085" : "#4168e9", "stroke-width": 2, "pointer-events": "none"}) : null,
        shape(drawn),
        h("text", {"font-family": "system-ui, sans-serif", "text-anchor": layout.anchor, "pointer-events": "none"},
          layout.lines.map(line => h("tspan", {
            x: line.x, y: line.y, fill: line.color, "font-size": line.size, "font-weight": line.weight,
            textLength: line.fit, lengthAdjust: line.fit ? "spacingAndGlyphs" : undefined,
          }, line.text))),
      ]);
    }

    function renderEdge(edge) {
      const {d} = edgeGeometry(drawnNode(edge.source), drawnNode(edge.target.node), edge.target.point, edge.style);
      const highlighted = selected.value?.kind === "edge" && selected.value.id === edge.id;
      return h("g", {key: edge.id, "data-edge": edge.id, tabindex: 0, role: "button", "aria-label": edgeStyles[edge.style],
        onClick: () => { selected.value = {kind: "edge", id: edge.id}; },
        onContextmenu: event => context(event, "edge", edge.id),
        onKeydown: event => { if (event.key === "Enter") openProperties("edge", edge.id); },
      }, [
        highlighted ? h("path", {"data-editor-only": "", d, stroke: "#aab9fc", "stroke-width": 7}) : null,
        h("path", {d, ...edgeAppearance(edge.style)}),
        h("path", {"data-editor-only": "", d, stroke: "transparent", "stroke-width": 16, "pointer-events": "stroke"}),
      ]);
    }

    function renderCanvas() {
      const [centerX, centerY] = center();
      const cable = preview.value;
      const cableStyle = reconnect.value?.style || pendingStyle.value;
      const shown = cable && drawnNode(cable.source)
        ? edgeGeometry(drawnNode(cable.source), drawnNode(cable.target), cable.point, cableStyle)
        : null;
      return h("div", {class: "canvas-area"}, [
        h("svg", {ref: canvas, class: "editor-canvas", "aria-label": "Ötletvászon",
          onContextmenu: event => context(event),
          onPointerdownCapture: pressCanvas,
          onPointermove: updatePointer,
          onPointerup: event => finishPointer(event),
          onPointercancel: event => finishPointer(event, true),
          onLostpointercapture: event => finishPointer(event, true),
          onClick: event => {
            if (!event.target.closest("[data-node], [data-edge]")) menu.value = null;
          },
        }, [
          h("defs", [arrowDefinition()]),
          h("g", {transform: view.value + " translate(" + centerX + " " + centerY + ")"}, [
            h("path", {"data-editor-only": "", "pointer-events": "none", stroke: "#aab9cf", "stroke-width": 1,
              d: "M -8 0 H 8 M 0 -8 V 8"}),
            h("g", {"data-scene": ""}, [
              h("g", {fill: "none", stroke: cableColor, "stroke-width": 2, "stroke-linecap": "round"}, board.value?.edges.map(renderEdge)),
              ...(board.value?.nodes.map(renderNode) || []),
            ]),
            shown ? h("path", {d: shown.d, ...edgeAppearance(cableStyle), fill: "none", stroke: "#4168e9", "stroke-width": 2, "pointer-events": "none"}) : null,
          ]),
        ]),
        h("div", {class: "canvas-controls"}, [
          button("−", () => zoomBy(0.8), {"aria-label": "Kicsinyítés"}),
          h("span", Math.round(view.value.k * 100) + "%"),
          button("+", () => zoomBy(1.25), {"aria-label": "Nagyítás"}),
          button("Közép", centerOrigin, {title: "Középre állítás, (0, 0)"}),
          button("Mind", fit, {title: "A teljes vászon megjelenítése"}),
        ]),
        board.value && !board.value.nodes.length ? h("p", {class: "canvas-empty"}, "A vászon üres. Adj hozzá egy ötletet.") : null,
      ]);
    }

    function renderMenu() {
      const open = menu.value;
      if (!open) return null;
      const node = nodeMap.value.get(open.id);
      const edge = board.value?.edges.find(item => item.id === open.id);
      const type = open.kind;
      const entries = type === "node" && node ? [
        button("Szerkesztés", () => openProperties("node", node.id)),
        button("Markdown megnyitása", () => showNote(node)),
        button("Törlés", () => { menu.value = null; deleteNode(node); }, {class: "button danger"}),
      ] : type === "edge" && edge ? [
        button("Szerkesztés", () => openProperties("edge", edge.id)),
        ...(edge.target.node ? [button("Cél leválasztása", () => { detach(edge); menu.value = null; })] : []),
        button("Új cél kijelölése", () => retarget(edge)),
        button("Kapcsolat törlése", () => removeEdge(edge), {class: "button danger"}),
      ] : [
        button("Új ötlet ide", () => { menu.value = null; addNode(open.position); }, {disabled: !board.value}),
        button("Középre állítás", () => { menu.value = null; centerOrigin(); }),
      ];
      return h("div", {class: "context-menu panel", "aria-label": "Műveletek",
        style: {left: open.x + "px", top: open.y + "px"}}, entries);
    }

    function sidebar(label, contents) {
      return h("aside", {class: "inspector", "aria-label": label}, [
        h("div", {class: "inspector-content stack"}, contents),
        h("div", {class: "inspector-footer"}, [
          button(h("svg", {viewBox: "0 0 20 20", width: 20, height: 20, "aria-hidden": "true"}, [
            h("path", {d: "M4 10h11m-5-5 5 5-5 5", fill: "none", stroke: "currentColor",
              "stroke-width": 1.7, "stroke-linecap": "round", "stroke-linejoin": "round"}),
          ]), inspectNothing, {"aria-label": "Oldalsáv bezárása", title: "Oldalsáv bezárása"}),
        ]),
      ]);
    }

    function colorPicker(label, value, change) {
      const apply = next => {
        if (/^#[\da-f]{6}$/i.test(next)) change(next.toLowerCase());
      };
      return h("div", {class: "color-field"}, [
        field(label, input(value, apply, {type: "color", onChange: event => apply(event.target.value)})),
        input(value, apply, {
          maxlength: 7, spellcheck: false, "aria-label": label + " HEX",
          onBlur: event => { event.target.value = value; },
        }),
      ]);
    }

    function renderInspector() {
      if (note.value) {
        const reading = note.value;
        const node = nodeMap.value.get(reading.id);
        if (!node) return null;
        return sidebar("Markdown", [
          h("h2", node.title),
          node.comment ? h("p", {class: "comment", style: {color: commentColor(node.textColor)}}, node.comment) : null,
          reading.loading ? h("p", "Betöltés…") : null,
          reading.error ? h("p", {class: "error"}, reading.error) : null,
          !reading.loading && !reading.error ? h("div", {class: "markdown", innerHTML: reading.html || "<p>Még nincs leírás.</p>"}) : null,
          button("Szerkesztés", () => openProperties("node", node.id)),
        ]);
      }
      if (!inspector.value) return null;
      if (inspector.value.kind === "worksheet") {
        const sheet = board.value;
        return sidebar("Munkalap", [
          field("Cím", input(sheet.title, value => updateItem(sheet, "title", value), {maxlength: 120})),
          field("Megjegyzés", input(sheet.comment || "", value => updateItem(sheet, "comment", value), {maxlength: 500})),
          field("Markdown", textarea(sheet.markdown || "", value => updateItem(sheet, "markdown", value))),
          h("div", {class: "inspector-links"}, [
            h("a", {href: "/export/json/" + path}, "Mentett JSON letöltése"),
            h("a", {href: "/export/markdown/" + path}, "Mentett Markdown letöltése"),
          ]),
          role === "admin" ? button("Munkalap törlése", deleteBoard, {class: "button danger"}) : null,
        ]);
      }
      if (inspector.value.kind === "edge") {
        const edge = board.value.edges.find(item => item.id === inspector.value.id);
        if (!edge) return null;
        const destination = nodeMap.value.get(edge.target.node);
        return sidebar("Kapcsolat", [
          field("Típus", select(edge.style, edgeStyles, value => updateItem(edge, "style", value))),
          h("p", {class: "muted"}, destination ? "Cél · " + destination.title
            : "Szabad végpont · (" + Math.round(edge.target.point.x) + ", " + Math.round(edge.target.point.y) + ")"),
          destination ? button("Cél leválasztása", () => detach(edge)) : null,
          button("Új cél kijelölése", () => retarget(edge)),
          button("Kapcsolat törlése", () => removeEdge(edge), {class: "button danger"}),
        ]);
      }
      const node = nodeMap.value.get(inspector.value.id);
      if (!node) return null;
      const change = (key, value) => updateItem(node, key, value);
      const autoSize = node.autoSize !== false;
      const drawn = drawnNode(node.id);
      const dimension = (key, min, max) => numeric(drawn[key], value => change(key, value), min, max, {disabled: autoSize});
      return sidebar("Ötlet szerkesztése", [
        field("Címke", input(node.title, value => change("title", value), {maxlength: 120})),
        field("Megjegyzés", input(node.comment || "", value => change("comment", value), {maxlength: 500})),
        field("Forma", select(node.shape, shapes, value => change("shape", value))),
        checkbox("Auto size", autoSize, value => change("autoSize", value)),
        h("div", {class: "fields-two"}, [field("Szélesség", dimension("width", 64, 880)), field("Magasság", dimension("height", 40, 680))]),
        h("div", {class: "fields-two"}, [
          field("X", numeric(node.position.x, x => change("position", {...node.position, x}), -100000, 100000)),
          field("Y", numeric(node.position.y, y => change("position", {...node.position, y}), -100000, 100000)),
        ]),
        h("div", {class: "fields-three"}, [
          colorPicker("Háttér", node.fill, value => change("fill", value)),
          colorPicker("Keret", node.border, value => change("border", value)),
          colorPicker("Szöveg", node.textColor, value => change("textColor", value)),
        ]),
        h("div", {class: "fields-two"}, [
          field("Betűméret", numeric(node.fontSize, value => change("fontSize", value), 10, 60)),
          field("Igazítás", select(node.alignment, {left: "Balra", center: "Középre", right: "Jobbra"}, value => change("alignment", value))),
        ]),
        checkbox("Félkövér címke", node.bold, value => change("bold", value)),
        checkbox("Show Markdown", Boolean(node.showMarkdown), value => change("showMarkdown", value)),
        field("Markdown", textarea(node.markdown, value => change("markdown", value))),
        button("Előnézet", () => showNote(node)),
      ]);
    }

    function renderHeader() {
      return h("header", {class: "editor-header"}, [
        h("a", {class: "brand", href: "/"}, "ThinkNodes"),
        h("h1", {title: board.value.title}, board.value.title),
        button("Új ötlet", () => addNode(), {class: "button soft"}),
        button("Kapcsolás", () => { connectMode.value = !connectMode.value; }, {"aria-pressed": connectMode.value}),
        select(pendingStyle.value, edgeStyles, value => { pendingStyle.value = value; }, {"aria-label": "Kábeltípus"}),
        button("Munkalap", () => openProperties("worksheet"), {
          "aria-pressed": inspector.value?.kind === "worksheet",
        }),
        button("SVG letöltése", exportSVG),
        h("a", {class: "button", href: "/" + path}, "Megtekintés"),
        button(saving.value ? "Mentés…" : "Mentés", save, {class: "button primary", disabled: saving.value || !dirty.value}),
        role === "admin" ? h("a", {class: "button", href: "/admin"}, "Admin") : null,
        h("form", {method: "post", action: "/logout"}, [
          h("input", {type: "hidden", name: "csrf", value: csrf}),
          h("button", {class: "button", type: "submit"}, "Kijelentkezés"),
        ]),
      ]);
    }

    return () => {
      if (!board.value) return h("p", {class: problem.value ? "error editor-loading" : "editor-loading"}, problem.value || "Szerkesztő betöltése…");
      const currentStatus = reconnect.value ? "Kattints az új célra vagy a vászonra. Esc a megszakításhoz."
        : connectMode.value ? "Húzz kábelt egy dobozból."
        : dirty.value ? "Mentetlen változtatások" : status.value;
      return [
        renderHeader(),
        h("div", {class: "editor-workspace"}, [
          renderCanvas(),
          problem.value || currentStatus ? h("p", {class: ["canvas-status", {error: problem.value}], role: "status"}, problem.value || currentStatus) : null,
          renderInspector(),
        ]),
        renderMenu(),
      ];
    };
  },
}).mount(mount);
