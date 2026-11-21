let timer, request, tooltip;
export function hideTooltip() {
  clearTimeout(timer);
  request?.abort();
  tooltip?.remove();
}
export function showTooltip(event, render, justified) {
  hideTooltip();
  const {currentTarget} = event;
  const signal = (request = new AbortController()).signal;
  timer = setTimeout(async () => {
    try {
      const html = await render(signal);
      if (signal.aborted || !currentTarget.isConnected) return;
      tooltip = document.createElement("div");
      tooltip.className = "formatted-text canvas-tooltip";
      if (justified) tooltip.classList.add("justified-text");
      tooltip.setAttribute("role", "tooltip");
      tooltip.innerHTML = html;
      document.body.append(tooltip);
      const {width, height} = tooltip.getBoundingClientRect();
      const box = currentTarget.getBoundingClientRect();
      const left = box.right+width+12 <= innerWidth ? box.right+8 : box.left-width-8;
      tooltip.style.left = Math.max(4, Math.min(left, innerWidth-width-4)) + "px";
      tooltip.style.top = Math.max(4, Math.min(box.top, innerHeight-height-4)) + "px";
    } catch { /* Hover previews are optional when disconnected. */ }
  }, 350);
}
