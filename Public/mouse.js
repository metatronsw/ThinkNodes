// The layer's coordinate system is the worksheet, including the editor's pan and zoom.
export function sharedMouse(send) {
  const ns = "http://www.w3.org/2000/svg";
  const cursors = new Map();
  let layer, enabled = false, pending, timer, listeners;
  function hide() {
    clearTimeout(timer);
    timer = undefined;
    if (pending) send(null);
    pending = null;
  }
  function receive(frame) {
    if (!frame) {
      cursors.clear();
      layer?.replaceChildren();
      return;
    }
    let marker = cursors.get(frame.cursor);
    if (!frame.point) {
      marker?.remove();
      cursors.delete(frame.cursor);
      return;
    }
    if (!marker) {
      marker = document.createElementNS(ns, "path");
      marker.setAttribute("d", "M0 0L4 18L8 12L15 10Z");
      marker.setAttribute("fill", frame.color);
      marker.setAttribute("stroke", "white");
      cursors.set(frame.cursor, marker);
      layer?.append(marker);
    }
    marker.setAttribute("transform", 'translate(' + frame.point.x + ' ' + frame.point.y + ')');
  }
  function bind(svg, parent, controls, before = null) {
    listeners?.abort();
    hide();
    listeners = new AbortController();
    const options = {signal: listeners.signal};
    layer?.remove();
    layer = document.createElementNS(ns, "g");
    layer.setAttribute("data-editor-only", "");
    layer.setAttribute("pointer-events", "none");
    layer.setAttribute("aria-hidden", "true");
    parent.append(layer);
    layer.append(...cursors.values());
    if (!controls) return;
    const button = document.createElement("button");
    button.type = "button";
    button.className = "button mouse-share";
    button.title = "Saját egérmutató megosztása";
    button.setAttribute("aria-label", button.title);
    button.setAttribute("aria-pressed", String(enabled));
    button.innerHTML = '<svg class="ui-icon" aria-hidden="true" viewBox="0 0 24 24"><path fill="currentColor" d="M4 2l4 19 4-7 8-3z"/></svg>';
    controls.insertBefore(button, before);
    button.addEventListener("click", () => {
      enabled = !enabled;
      button.setAttribute("aria-pressed", String(enabled));
      if (!enabled) hide();
    }, options);
    svg.addEventListener("pointermove", event => {
      if (!enabled || event.pointerType === "touch") return;
      const matrix = layer.getScreenCTM();
      if (!matrix) return;
      const {x, y} = new DOMPoint(event.clientX, event.clientY).matrixTransform(matrix.inverse());
      pending = {x, y};
      if (!timer) timer = setTimeout(() => { timer = undefined; send(pending); }, 50);
    }, options);
    svg.addEventListener("pointerleave", hide, options);
    window.addEventListener("blur", hide, options);
    window.addEventListener("pagehide", hide, options);
  }
  return {bind, receive, stop() { hide(); listeners?.abort(); receive(null); }};
}
