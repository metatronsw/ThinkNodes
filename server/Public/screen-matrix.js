// Munkalap → képernyő leképezés egy SVG-csoportra (a lézer és a megosztott egérmutató közös segédje).
// Safari (18.6) getScreenCTM-je nem tartalmazza a vászon fölötti HTML-elemek CSS-transzformját; a szerkesztő ezzel mozgatja
// a vásznat görgős nagyítás és pásztázás közben (editor.js previewView). Ilyenkor a mutató és a rajz rossz helyre került.
// A vászon (gyökér-SVG) valódi helye és mérete (getBoundingClientRect, minden böngészőben a transzformmal együtt) adja a
// korrekciót; Chrome-ban, és nyugalomban mindenhol, ez egységmátrix, és a getScreenCTM változatlanul érvényes.
export function screenMatrix(layer, root) {
  const matrix = layer?.isConnected ? layer.getScreenCTM() : null;
  if (!matrix || !root || root.viewBox?.baseVal?.width) return matrix;
  const own = root.getScreenCTM(), box = root.getBoundingClientRect();
  if (!own || !root.clientWidth) return matrix;
  const scale = box.width / root.clientWidth / (own.a || 1);
  if (Math.abs(scale - 1) < 1e-6 && Math.abs(own.e - box.left) < .01 && Math.abs(own.f - box.top) < .01) return matrix;
  return new DOMMatrix([scale, 0, 0, scale, box.left - scale * own.e, box.top - scale * own.f]).multiply(matrix);
}
