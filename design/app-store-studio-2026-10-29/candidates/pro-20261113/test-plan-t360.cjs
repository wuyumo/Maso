const assert=require("node:assert/strict");
const fs=require("node:fs");const path=require("node:path");const ts=require("typescript");const Module=require("node:module");const crypto=require("node:crypto");
const root=path.resolve(__dirname,"../..");
const file=path.join(root,"src/lib/candidate-plan-presentation.ts");
const source=fs.readFileSync(file,"utf8");const out=ts.transpileModule(source,{reportDiagnostics:true,compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}});
assert.deepEqual((out.diagnostics||[]).filter(d=>d.category===ts.DiagnosticCategory.Error),[]);
const m=new Module(file,module);m._compile(out.outputText,file);const {candidatePlanUnit,candidatePlanShiftX,CANDIDATE_PLAN_CSS:css}=m.exports;
const page=fs.readFileSync(path.join(root,"src/app/pro-candidate-20261113/page.tsx"),"utf8");
const expression=page.match(/data-candidate-plan-device=\{([^}]+)\}/)[1];const flag=new Function("slide","target","return "+expression);
const locales=Object.keys(JSON.parse(fs.readFileSync(path.join(root,"candidates/pro-20261113/project.json"))).slidesByDevice.iphone[0].headline);
let flagCases=0;
for(const device of ["iphone","iphone-medium","ipad","duo","watch"])for(const id of ["plan","recovery","training","insights","devices"])for(const locale of locales){assert.equal(flag({id,chat:{}},{device,locale}),id==="plan"&&device!=="watch"?"low-angle-split":undefined);flagCases++;}
assert.equal(flag({id:"plan"},{device:"iphone"}),undefined);
for(const selector of css.split("}").map(x=>x.trim()).filter(Boolean))assert(selector.startsWith('#candidate-poster[data-candidate-plan-device="low-angle-split"]'));
assert(css.includes("direction: ltr"));assert(css.includes("grid-template-columns: minmax(0,1fr) minmax(0,1fr)"));assert(css.includes('::after'));assert(css.includes('rotateX(10deg) skewX(-3deg) scale(1.1)'));assert(css.includes(' > div {'));assert(!/url\(|@import/.test(css));
const chat={x:96,y:745,width:1128,height:2050};const units=[candidatePlanUnit({w:1320,h:2868},true,chat),candidatePlanUnit({w:1260,h:2736},true,chat),candidatePlanUnit({w:2064,h:2752},false,chat),candidatePlanUnit({w:2007,h:2853},false,chat)];assert.deepEqual(units,[1,1260/1320,1792/2050,1893/2050]);
let geometryCases=0;
for(const [canvas,phone] of [[{w:1320,h:2868},true],[{w:1260,h:2736},true],[{w:2064,h:2752},false],[{w:2007,h:2853},false]]){
 const unit=candidatePlanUnit(canvas,phone,chat),shift=candidatePlanShiftX(canvas,phone,chat),left=(phone?chat.x*unit:(canvas.w-chat.width*unit)/2)+shift,bottom=(phone?chat.y*unit:900)+chat.height*unit;
 const project=(x,y)=>{const z=y*1.1*Math.sin(Math.PI/18),w=1-z/4500;return {x:left+(x*1.1+Math.tan(-Math.PI/60)*y*1.1)*unit/w,y:bottom+y*1.1*Math.cos(Math.PI/18)*unit/w};};
 const edge=project(chat.width,0);assert(Math.abs(edge.x-canvas.w*1.02)<.001);assert(edge.y<canvas.h);
 for(const y of [-chat.height,0])for(const x of [50,chat.width-22-64-28]){const point=project(x,y);assert(point.x>=0&&point.x<=canvas.w);assert(point.y>=0&&point.y<=canvas.h);geometryCases++;}
}
assert(css.includes('transform-origin: left bottom'));assert(css.includes('solid #090c10'));assert(css.includes('padding-right: calc(64px'));
const project=JSON.parse(fs.readFileSync(path.join(root,"candidates/pro-20261113/project.json")));assert.deepEqual(project.slidesByDevice.iphone[0].chat.bubbles[0].photos,["/chat/body-front.jpg","/chat/body-back.jpg"]);
for(const [rel,sha] of [["public/chat/body-front.jpg","810e8f38e6687b959c2bacafbc50155d411be3efbdb09d26b893541591226ad0"],["public/chat/body-back.jpg","deebd99977c43d4d41b774ba91398d06c82a354592ecab8afbb560c4a3dce843"]])assert.equal(crypto.createHash("sha256").update(fs.readFileSync(path.join(root,rel))).digest("hex"),sha);
assert(page.includes('toPng(main, exportCaptureOptions(canvas))'));assert(page.includes('width: canvas.w'));assert(page.includes('height: canvas.h'));assert(page.includes('<style>{CANDIDATE_PLAN_CSS}</style>'));
console.log(JSON.stringify({flagCases,geometryCases,geometryEvidence:"mathematical bounds only, not browser paint",scopedSelectors:5,deviceScaleCases:units.length,photoByteHashesUnchanged:2,nativeExportSourceUnchanged:true,browserVisualTest:false,newPosterPNGs:0}));
