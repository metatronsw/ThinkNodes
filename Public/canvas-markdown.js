// A doboz markdown-szövegének blokkokra bontása a böngészőben (Sources/ThinkNodes/CanvasMarkdown.swift
// `canvasMarkdown` pontos párja). A szerver a cmark-gfm 0.29-et használja, itt ugyanennek a CommonMark 0.29-es
// specifikációnak a referencia JS-megvalósítása (commonmark.js 0.29.3, Public/vendor/commonmark.js) fut.
// Az egyezést a közös tesztkészlet őrzi: Tests/Fixtures/canvas-markdown.json (Swift- és Node-teszt is).

const sourceLimit = 6000;

// Swift `String.prefix(6000)`: grafémafürtökben számol.
function prefixCharacters(source) {
  if (source.length <= sourceLimit) return source;
  if (typeof Intl !== "undefined" && Intl.Segmenter) {
    let result = "", count = 0;
    for (const {segment} of new Intl.Segmenter(undefined, {granularity: "grapheme"}).segment(source)) {
      if (count++ === sourceLimit) break;
      result += segment;
    }
    return result;
  }
  return Array.from(source).slice(0, sourceLimit).join("");
}

const plain = () => ({bold: false, italic: false, code: false, link: false});

export function canvasMarkdownAvailable(commonmark = globalThis.commonmark) {
  return !!commonmark?.Parser;
}

export function canvasMarkdown(source, commonmark = globalThis.commonmark) {
  const document = new commonmark.Parser().parse(prefixCharacters(source ?? ""));
  const children = node => {
    const result = [];
    for (let child = node.firstChild; child; child = child.next) result.push(child);
    return result;
  };

  function inline(node, format, depth, runs) {
    if (depth >= 64) return;
    format = {...format};
    switch (node.type) {
      case "text": runs.push({text: node.literal ?? "", format}); return;
      case "code": runs.push({text: node.literal ?? "", format: {...format, code: true}}); return;
      case "linebreak":
      // A sor végi sortörés új sort kezd (nem olvad össze a következő sorral).
      case "softbreak": runs.push({text: "\n", format}); return;
      case "strong": format.bold = true; break;
      case "emph": format.italic = true; break;
      case "link": format.link = true; break;
    }
    for (const child of children(node)) inline(child, format, depth + 1, runs);
  }

  const blocks = [];
  let previousEnd = 0;
  let afterBreak = false;
  // Az új blokk elé beírja, hány üres sor volt a forrásban az előző blokk vége óta.
  // A cmark (szerver) sorvég-jelölését követi, ami két helyen eltér a commonmark.js-étől:
  // - vízszintes vonal után a következő blokkig tartó üres sorok nem számítanak;
  // - az aláhúzott (setext) címsor vége az aláhúzás utáni sor.
  function place(node, item) {
    const start = node.sourcepos?.[0]?.[0] ?? 0;
    let end = node.sourcepos?.[1]?.[0] ?? 0;
    if (node.type === "heading" && end > start) end += 1;
    const blank = afterBreak ? 0 : Math.max(0, start - previousEnd - 1);
    if (blank > 0) item.blankLines = blank;
    previousEnd = Math.max(previousEnd, end);
    afterBreak = node.type === "thematic_break";
    blocks.push(item);
  }

  function block(node, depth, quote = false, list = 0) {
    if (depth >= 64) return;
    switch (node.type) {
      case "paragraph":
      case "heading": {
        const runs = [];
        inline(node, plain(), 0, runs);
        if (runs.length) {
          const heading = node.type === "heading";
          const item = {kind: heading ? "heading" : quote ? "quote" : "body", runs};
          if (heading) item.level = node.level;
          if (list > 0) item.indent = list;
          place(node, item);
        }
        return;
      }
      case "code_block":
        place(node, {kind: "code", runs: [{text: node.literal ?? "", format: {...plain(), code: true}}]});
        return;
      case "thematic_break":
        place(node, {kind: "body", runs: [{text: "────", format: plain()}]});
        return;
      case "list": {
        const ordered = node.listType === "ordered";
        let index = node.listStart ?? 0;
        for (const item of children(node)) {
          const first = blocks.length;
          block(item, depth + 1, quote, list + 1);
          if (first < blocks.length) blocks[first].runs.unshift({text: ordered ? index + ". " : "• ", format: plain()});
          index += 1;
        }
        return;
      }
      default:
        for (const child of children(node)) block(child, depth + 1, quote || node.type === "block_quote", list);
    }
  }

  block(document, 0);
  // A szomszédos, azonos formázású darabok összevonva (ugyanígy a Swift-oldalon).
  const same = (a, b) => a.bold === b.bold && a.italic === b.italic && a.code === b.code && a.link === b.link;
  for (const item of blocks) {
    const merged = [];
    for (const run of item.runs) {
      const last = merged.at(-1);
      if (last && same(last.format, run.format)) last.text += run.text;
      else merged.push({text: run.text, format: run.format});
    }
    item.runs = merged;
  }
  return blocks;
}
