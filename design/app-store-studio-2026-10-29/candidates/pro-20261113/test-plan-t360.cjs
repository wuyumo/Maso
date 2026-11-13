const assert=require("node:assert/strict");
const fs=require("node:fs");const path=require("node:path");const ts=require("typescript");const Module=require("node:module");const crypto=require("node:crypto");
const root=path.resolve(__dirname,"../..");
const file=path.join(root,"src/lib/candidate-plan-presentation.ts");
const source=fs.readFileSync(file,"utf8");const out=ts.transpileModule(source,{reportDiagnostics:true,compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}});
assert.deepEqual((out.diagnostics||[]).filter(d=>d.category===ts.DiagnosticCategory.Error),[]);
const m=new Module(file,module);m._compile(out.outputText,file);const {candidatePlanUnit,CANDIDATE_PLAN_CSS:css}=m.exports;
const page=fs.readFileSync(path.join(root,"src/app/pro-candidate-20261113/page.tsx"),"utf8");
const expression=page.match(/data-candidate-plan-device=\{([^}]+)\}/)[1];const flag=new Function("slide","target","return "+expression);
let flagCases=0;
for(const device of ["iphone","iphone-medium","ipad","duo","watch"])for(const id of ["plan","recovery","training","insights","devices"])for(const locale of ["zh","en","ar"]){assert.equal(flag({id,chat:{}},{device,locale}),id==="plan"&&device!=="watch"?"low-angle-split":undefined);flagCases++;}
assert.equal(flag({id:"plan"},{device:"iphone"}),undefined);
for(const selector of css.split("}").map(x=>x.trim()).filter(Boolean))assert(selector.startsWith('#candidate-poster[data-candidate-plan-device="low-angle-split"]'));
assert(css.includes("direction: ltr"));assert(css.includes("grid-template-columns: minmax(0,1fr) minmax(0,1fr)"));assert(css.includes('::after'));assert(css.includes('rotateX(4deg) skewX(-1deg)'));assert(css.includes(' > div {'));assert(!/url\(|@import/.test(css));
const chat={width:1128,height:2050};const units=[candidatePlanUnit({w:1320,h:2868},true,chat),candidatePlanUnit({w:1260,h:2736},true,chat),candidatePlanUnit({w:2064,h:2752},false,chat),candidatePlanUnit({w:2007,h:2853},false,chat)];assert.deepEqual(units,[1,1260/1320,1792/2050,1893/2050]);
const project=JSON.parse(fs.readFileSync(path.join(root,"candidates/pro-20261113/project.json")));assert.deepEqual(project.slidesByDevice.iphone[0].chat.bubbles[0].photos,["/chat/body-front.jpg","/chat/body-back.jpg"]);
for(const [rel,sha] of [["public/chat/body-front.jpg","810e8f38e6687b959c2bacafbc50155d411be3efbdb09d26b893541591226ad0"],["public/chat/body-back.jpg","deebd99977c43d4d41b774ba91398d06c82a354592ecab8afbb560c4a3dce843"]])assert.equal(crypto.createHash("sha256").update(fs.readFileSync(path.join(root,rel))).digest("hex"),sha);
assert(page.includes('toPng(main, exportCaptureOptions(canvas))'));assert(page.includes('width: canvas.w'));assert(page.includes('height: canvas.h'));assert(page.includes('<style>{CANDIDATE_PLAN_CSS}</style>'));
console.log(JSON.stringify({flagCases,scopedSelectors:5,deviceScaleCases:units.length,photoByteHashesUnchanged:2,nativeExportSourceUnchanged:true,browserVisualTest:false,newPosterPNGs:0}));
