const shortKeys = new Map(Object.entries({
  position: "pos",
  alignment: "align",
  textColor: "textCol",
  width: "w",
  height: "h",
  verticalAlignment: "vAlign",
  fontSize: "fontSz",
  gridColor: "gridCol",
  gridSpacing: "gridStep",
  sourcePoint: "srcPt",
}));
const modelKeys = new Map([...shortKeys].map(([name, key]) => [key, name]));

function mapKeys(value, keys) {
  if (Array.isArray(value)) return value.map(element => mapKeys(element, keys));
  if (value === null || typeof value !== "object") return value;
  return Object.fromEntries(Object.entries(value).map(([key, field]) =>
    [keys.get(key) ?? key, mapKeys(field, keys)]));
}

export const decodeWorksheet = document => mapKeys(document, modelKeys);
export const encodeWorksheet = document => mapKeys(document, shortKeys);
export const decodeConnection = decodeWorksheet;
