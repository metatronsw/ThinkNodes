import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";

const root = "Projects";
const archive = path.join(root, ".trash", "2026-11-22-demo-reset");
fs.mkdirSync(archive, {recursive: true});
for (const name of fs.readdirSync(root)) {
  if ([".trash", ".gitignore", ".DS_Store", path.basename(archive), "Demo"].includes(name)) continue;
  fs.renameSync(path.join(root, name), path.join(archive, name));
}

const demo = path.join(root, "Demo");
fs.mkdirSync(path.join(demo, "Lapok"), {recursive: true});
const settingsSource = JSON.parse(fs.readFileSync(path.join(archive, ".settings.json"), "utf8"));
if (!settingsSource.users?.some(user => user.name === "admin")) throw Error("Admin account is missing");
const ids = ["demo-0", "demo-1", "demo-2", "demo-3", "demo-4", "demo-5", "demo-6", "demo-7", "demo-8", "demo-9", "demo-10", "demo-11"];
function box(id, title, text, x, y, shape, fill, options = {}) {
  const node = {id, title, text, pos: {x, y}, w: options.w ?? 260, h: options.h ?? 116,
    shape, fill, textCol: 1, fontSz: options.font ?? 15, bold: true, align: "center"};
  if (options.kind) node.kind = options.kind;
  if (options.parent) node.parent = options.parent;
  if (options.file) node.file = options.file;
  if (options.style) node.textStyle = options.style;
  if (options.link) node.link = options.link;
  return node;
}
function wire(id, source, target, type, color, label, options = {}) {
  return {id, source, target: typeof target === "string" ? {node: target} : {point: target},
    type, appearance: options.appearance ?? "plain", color, startArrow: !!options.start,
    endArrow: options.end !== false, label, labelInLine: true, width: options.width ?? 3,
    animated: !!options.animated};
}
function page(title, text, theme, nodes, edges) {
  return {schemaVersion: 2, title, text, creator: "admin", revision: 1,
    appearance: {theme, palette: 1}, background: 0, gridStep: 32, nodes, edges};
}

const overviewNodes = [
  box("start", "Gondolat", "A kiindulópont egy szerkeszthető doboz. Címet, szöveget, alakzatot, színt és elrendezést adhatsz neki.", -780,-310,"rounded",2,{link:"Lapok/Hierarchia"}),
  box("idea", "Doboz", "A doboz gondolatot vagy fogalmat tartalmaz. Minden alakzat ugyanazt az objektumot jelenítheti meg.", -380,-310,"rectangle",9,{link:"Lapok/Formák"}),
  box("object", "Objektum", "A vonal is objektum. Két végét dobozhoz vagy szabad ponthoz kötheted, irányt, típust és feliratot állíthatsz.", 40,-310,"hexagon",10),
  box("file", "Külső fájl", "Dokumentum, kép és csatolmány külön fájlként kapcsolódhat a dobozhoz. A tartalom a munkalap mellett jelenik meg.", 500,-310,"parallelogram",8),
  box("container", "Konténer", "A konténer dobozokat foglal össze. Húzd rá a kisebb dobozokat, hogy hierarchiát építs.", -350,60,"rounded",15,{kind:"container",w:360,h:240}),
  box("inside", "Csomópont", "A csomópont több vonal találkozását jelöli. Vonalvégek ide köthetők, majd a csomópont dobozra húzva feloldható.", -350,60,"ellipse",6,{w:90,h:90}),
  box("nested", "Gyerekdoboz", "Konténerbe ágyazott doboz. A kapcsolatait a szülő mozgatása együtt tartja.", -350,155,"diamond",14,{parent:"container",w:220,h:88}),
  box("files", "Külső fájlok", "A bemutató csatolmányt, képet, szövegfájlt és munkalapra mutató hivatkozást is tartalmaz.", 420,80,"rounded",12,{kind:"container",w:390,h:280}),
  box("doc", "Dokumentum", "Külső szövegfájl tartalma a dobozban nyílik meg.", 420,5,"rectangle",2,{parent:"files",w:230,h:90,file:{type:"txt",asset:"bemutato.txt",filename:"bemutato.txt"}}),
  box("photo", "Kép", "Külső kép a fájlrendszerből.", 420,105,"ellipse",9,{parent:"files",w:175,h:86,file:{type:"image",asset:"bemutato.svg",filename:"bemutato",alphaEnabled:false}}),
  box("attachment", "Letölthető csatolmány", "A fájl külön letölthető, miközben a vásznon a cím és a leírás látszik.", 420,205,"parallelogram",10,{parent:"files",w:270,h:86,file:{type:"attachment",asset:"bemutato.pdf",filename:"bemutato.pdf"}}),
];
const overviewEdges = [
  wire("flow-idea","start","idea","straight",4,"szerkeszthető"),
  wire("flow-object","idea","object","arc",5,"kapcsolható",{start:true}),
  wire("flow-file","object","file","sCurve",11,"hivatkozott"),
  wire("flow-container","idea","container","lightning",6,"hierarchia",{appearance:"thick",animated:true}),
  wire("flow-junction","container","inside","straight",3,"csomópont",{end:false}),
  wire("flow-nested","inside","nested","zigzag",7,"feloldható"),
  wire("flow-doc","object","doc","arc",14,"tartalom"),
  wire("flow-photo","file","photo","sCurve",12,"kép"),
  wire("flow-attachment","file","attachment","lightning",13,"letöltés",{appearance:"dashed"}),
];
const hierNodes = [
  box("hierarchy-title","Az objektumok hierarchiája","A ThinkNodes munkalap objektumokat, kapcsolatokat és fájlokra mutató hivatkozásokat rendez közös vászonra.",-70,-370,"rounded",9,{w:560,h:140,font:18}),
  box("hierarchy-board","Munkalap","Cím, háttér, téma, rács és bevezető szöveg.",-70,-160,"rounded",2,{kind:"container",w:420,h:260}),
  box("hierarchy-box","Doboz","Szöveg, forma, méret, szín és elrendezés.",-70,-160,"rectangle",10,{parent:"hierarchy-board",w:300,h:145}),
  box("hierarchy-wire","Vonal","Irányított vagy kétirányú objektum, többféle útvonallal.",-70,-160,"ellipse",14,{parent:"hierarchy-board",w:150,h:76}),
  box("hierarchy-joint","Csomópont","Közös kapcsolódási pont több vonal között.",-70,20,"diamond",6,{w:128,h:90}),
  box("hierarchy-file","Külső fájl","Külön tárolt tartalom, a munkalaphoz kapcsolva.",430,10,"parallelogram",12,{w:340,h:156}),
  box("hierarchy-note","Objektummodell","A doboz és a vonal szerkeszthető objektum. A konténer szülő-gyermek viszonyt ad. A fájl önálló forrás, amelyet a doboz jelenít meg.",430,-230,"rounded",15,{w:340,h:150,style:{align:"left",vAlign:"middle",justified:true}}),
];
const hierEdges=[
  wire("h-board","hierarchy-board","hierarchy-box","straight",4,"tartalmaz"),
  wire("h-joint","hierarchy-box","hierarchy-joint","arc",11,"több végpont",{start:true}),
  wire("h-wire","hierarchy-joint","hierarchy-file","sCurve",12,"objektumkapcsolat"),
  wire("h-note","hierarchy-board","hierarchy-note","lightning",14,"leírás",{appearance:"dotted"})
];
const shapeNames=["rectangle","rounded","ellipse","diamond","triangle","pentagon","hexagon","parallelogram"];
const shapeTitles=["Téglalap","Lekerekített","Ellipszis","Rombusz","Háromszög","Ötszög","Hatszög","Paralelogramma"];
const shapeNodes=[box("shape-title","Alakzatok és vizuális modulok","Minden alakzathoz ugyanaz a cím, szöveg, háttér, szín, elmosás és kiemelés tartozik.",0,-350,"rounded",9,{w:660,h:120,font:18})];
shapeNames.forEach((shape,i)=>shapeNodes.push(box("shape-"+i,shapeTitles[i],"Az alakzat vizuális formája külön választható az objektum tartalmától.",(i%4)*310-465,Math.floor(i/4)*220-60,shape,2+i%6,{w:245,h:140})));
const shapeEdges=shapeNames.slice(0,-1).map((_,i)=>wire("shape-link-"+i,"shape-"+i,"shape-"+(i+1),i%2?"zigzag":"arc",4+i%8,"alakzat",{start:i%3===0,appearance:i%3===0?"dashed":"plain"}));
const textBlocks=[
 "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed non risus. Suspendisse lectus tortor, dignissim sit amet, adipiscing nec, ultricies sed, dolor.",
 "Cras elementum ultrices diam. Maecenas ligula massa, varius a, semper congue, euismod non, mi. Proin porttitor, orci nec nonummy molestie.",
 "Nullam accumsan lorem in dui. Cras ultricies mi eu turpis hendrerit fringilla. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices.",
 "Aliquam erat volutpat. Nam dui mi, tincidunt quis, accumsan porttitor, facilisis luctus, metus. Phasellus ultrices nulla quis nibh.",
 "Curabitur lectus. Integer euismod lacus luctus magna. Quisque cursus, metus vitae pharetra auctor, sem massa mattis sem, at interdum magna augue eget diam.",
 "Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia curae; Morbi lacinia molestie dui. Praesent blandit dolor.",
 "Praesent dapibus, neque id cursus faucibus, tortor neque egestas augue, eu vulputate magna eros eu erat. Aliquam erat volutpat.",
 "Nam dui mi, tincidunt quis, accumsan porttitor, facilisis luctus, metus. Pellentesque habitant morbi tristique senectus et netus et malesuada."
];
const loremNodes=[box("lorem-title","Lorem ipsum — szövegpróba","Hosszú címek és bekezdések, több dobozban. A nézet görgethető és szabadon rendezhető.",0,-460,"rectangle",9,{w:840,h:140,font:19})];
textBlocks.forEach((text,i)=>loremNodes.push(box("lorem-"+i,"Bekezdés "+(i+1),text,(i%2)*430-215,Math.floor(i/2)*230-180,["rounded","rectangle","ellipse","parallelogram"][i%4],2+i%8,{w:380,h:185,font:14,style:{align:"left",vAlign:"top",justified:true}})));
const loremedges=textBlocks.slice(1).map((_,i)=>wire("lorem-wire-"+i,"lorem-"+i,"lorem-"+(i+1),"sCurve",i%2?11:4,"folytatás",{appearance:i%3===0?"dashed":"plain"}));
const pages = {
  "Demo.thnode":page("ThinkNodes bemutató","**Üdv a ThinkNodesben.** Ez a projekt megmutatja, hogyan kapcsolódnak össze a dobozok, csomópontok, vonalak, konténerek és külső fájlok. Nyisd meg az aloldalakat a részletes példákhoz.",1,overviewNodes,overviewEdges),
  "Hierarchia.thnode":page("Objektumhierarchia","A doboz tárolja a gondolatot. A csomópont több vonal közös vége. A külső fájl önálló állomány. A konténer dobozokat rendez egymás alá.",1,hierNodes,hierEdges),
  "Formák.thnode":page("Formák és vonalak","A ThinkNodes több alakzatot és kapcsolatstílust rajzol ugyanazon objektummodellre.",3,shapeNodes,shapeEdges),
  "LoremIpsum.thnode":page("Lorem ipsum","Sok doboz és szöveg a tördelés, a méretezés és a nagy vászon kipróbálásához.",2,loremNodes,loremedges),
};
for (const [file, value] of Object.entries(pages)) fs.writeFileSync(path.join(demo,file),JSON.stringify(value,null,2)+"\n");
const textFile="Külső fájl példa\n\nEz a szöveg külön állományban van tárolva, és egy ThinkNodes objektum jeleníti meg.\n";
fs.writeFileSync(path.join(demo,"bemutato.txt"),textFile);
const pdf="%PDF-1.4\n% Demo attachment file\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n2 0 obj<</Type/Pages/Count 0/Kids[]>>endobj\ntrailer<</Root 1 0 R>>\n%%EOF\n";
fs.writeFileSync(path.join(demo,"bemutato.pdf"),pdf);
const svg='<svg xmlns="http://www.w3.org/2000/svg" width="320" height="190" viewBox="0 0 320 190"><rect width="320" height="190" rx="18" fill="#e2edf4"/><path d="M54 132 118 57l44 54 39-42 68 63H54Z" fill="#28688a"/><circle cx="219" cy="58" r="22" fill="#d4bc92"/><text x="24" y="174" font-family="sans-serif" font-size="15" fill="#203d53">Külső SVG fájl</text></svg>';
fs.writeFileSync(path.join(demo,"bemutato.svg"),svg);
const archivedSettings=JSON.parse(fs.readFileSync(path.join(archive,".settings.json"),"utf8"));
fs.writeFileSync(path.join(demo,".settings.json"),JSON.stringify({
  owner:"admin",guestReadable:true,
  mediaFiles:{}, worksheets:{
    "Demo.thnode":{},
    "Lapok/Hierarchia.thnode":{},
    "Lapok/Formák.thnode":{},
    "Lapok/LoremIpsum.thnode":{}
  }
},null,2)+"\n");
for(const file of fs.readdirSync(demo)) if(file.endsWith(".thnode")) {
  const doc=JSON.parse(fs.readFileSync(path.join(demo,file),"utf8"));
  for(const node of doc.nodes) if(node.file?.type==="image") node.file.asset="bemutato.svg";
  fs.writeFileSync(path.join(demo,file),JSON.stringify(doc,null,2)+"\n");
}
for(const file of fs.readdirSync(path.join(demo,"Lapok"))) {
  const full=path.join(demo,"Lapok",file),doc=JSON.parse(fs.readFileSync(full,"utf8"));
  for(const node of doc.nodes) if(node.file?.type==="image") node.file.asset="bemutato.svg";
  fs.writeFileSync(full,JSON.stringify(doc,null,2)+"\n");
}
console.log("Archived previous projects and created Demo with four worksheets.");
