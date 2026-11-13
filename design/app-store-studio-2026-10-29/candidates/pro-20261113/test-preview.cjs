const assert=require("node:assert/strict");
const fs=require("node:fs/promises");const path=require("node:path");const os=require("node:os");const Module=require("node:module");const ts=require("typescript");const sharp=require("sharp");
const root=path.resolve(__dirname,"../..");
async function load(relative) {const filename=path.join(root,relative);const src=await fs.readFile(filename,"utf8");const out=ts.transpileModule(src,{reportDiagnostics:true,compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022,esModuleInterop:true,jsx:ts.JsxEmit.ReactJSX}});assert.deepEqual((out.diagnostics||[]).filter(d=>d.category===ts.DiagnosticCategory.Error),[]);const m=new Module(filename,module);m.filename=filename;m.paths=Module._nodeModulePaths(path.dirname(filename));m._compile(out.outputText,filename);return m.exports;}
function nodes(element,result=[]) {if(element&&typeof element==="object"&&element.props){result.push(element);for(const child of [element.props.children].flat(Infinity))nodes(child,result);}return result;}
(async()=>{
 let checks=0; const m=await load("src/components/editor/candidate-preview-controls.tsx");
 const invalid=m.parsePreviewTarget("?device=unknown&slide=unknown&locale=invalid");assert.deepEqual(invalid,{device:"iphone",slide:"plan",locale:"zh"});checks++;
 let roundtrips=0;
 for(const device of m.DEVICES)for(const page of m.pagesForDevice(device.id))for(const locale of m.LOCALES){const target={device:device.id,slide:page.id,locale:locale[0]};assert.deepEqual(m.parsePreviewTarget(m.targetSearch(target)),target);roundtrips++;}checks++;
 const first={device:"iphone",slide:"plan",locale:"zh"};assert.equal(m.adjacentTarget(first,-1).slide,"plan");assert.equal(m.adjacentTarget(first,1).slide,"recovery");assert.equal(m.adjacentTarget({...first,slide:"devices"},1).slide,"devices");checks++;
 for(let i=0;i<5;i++){
  const target={...first,slide:m.PAGES[i].id};let changed=null;let exported=0;
  const props={target,mode:"fit",scale:0.2,ready:true,busy:false,error:null,onTarget:t=>changed=t,onMode:()=>{},onExport:()=>exported++};
  const tree=nodes(m.CandidatePreviewControls(props));const current=tree.filter(n=>n.props["aria-current"]==="page");assert.equal(current.length,1);assert.equal(current[0].props["data-page"],target.slide);
  const prev=tree.find(n=>n.props["aria-label"]==="上一张");const next=tree.find(n=>n.props["aria-label"]==="下一张");assert.equal(prev.props.disabled,i===0);assert.equal(next.props.disabled,i===4);
  next.props.onClick();assert.equal(changed.slide,m.PAGES[Math.min(4,i+1)].id);
  const save=tree.find(n=>n.props["data-export"]==="candidate");assert.equal(save.props.disabled,i>2);if(!save.props.disabled){save.props.onClick();assert.equal(exported,1);}
  tree.find(n=>n.props["aria-label"]==="语言").props.onChange({target:{value:"ar"}});assert.equal(changed.locale,"ar");assert.equal(changed.slide,target.slide);
  tree.find(n=>n.props["aria-label"]==="设备").props.onChange({target:{value:"ipad"}});assert.equal(changed.device,"ipad");assert.equal(changed.slide,target.slide);
  for(const state of [{ready:false},{busy:true},{error:"missing image"}])assert.equal(nodes(m.CandidatePreviewControls({...props,...state})).find(n=>n.props["data-export"]==="candidate").props.disabled,true);
  checks++;
 }
 const sizes=[{device:"iphone",w:1320,h:2868},{device:"iphone-medium",w:1206,h:2622},{device:"ipad",w:2064,h:2752},{device:"duo",w:2007,h:2853}];
 let fitCases=0;
 for(const canvas of sizes)for(const viewport of [{w:320,h:300},{w:390,h:600},{w:1440,h:720},{w:2560,h:1440}]){const scale=m.fitScale(viewport,canvas);assert(scale>0&&scale<=1);assert(canvas.w*scale<=viewport.w-32+0.01);assert(canvas.h*scale<=viewport.h-32+0.01);fitCases++;}checks++;
 const old=process.cwd();const temp=await fs.mkdtemp(path.join(os.tmpdir(),"masso-preview-size-test-"));
 try {const handler=await load("src/app/api/pro-candidate-20261113/export/route.ts");process.chdir(temp);
  for(const canvas of sizes){
   const options=m.exportCaptureOptions(canvas);assert.equal(options.width,canvas.w);assert.equal(options.canvasWidth,canvas.w);assert.equal(options.height,canvas.h);assert.equal(options.canvasHeight,canvas.h);assert.equal(options.pixelRatio,1);assert.equal(options.style.transform,"none");
   const png=await sharp({create:{width:canvas.w,height:canvas.h,channels:4,background:{r:22,g:44,b:66,alpha:0.3}}}).png().toBuffer();
   const response=await handler.POST(new Request("http://unit.invalid",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({dataUrl:"data:image/png;base64,"+png.toString("base64"),artifactPath:`ios/${canvas.device}/${canvas.w}x${canvas.h}/zh/01-plan.png`})}));assert.equal(response.status,200);const result=await response.json();assert(result.savedPath.startsWith("exports/candidates/pro-20261113/"));assert(!result.savedPath.includes("latest"));const meta=await sharp(path.join(temp,result.savedPath)).metadata();assert.equal(meta.width,canvas.w);assert.equal(meta.height,canvas.h);assert.equal(meta.channels,3);checks++;
  }
 }finally{process.chdir(old);await fs.rm(temp,{recursive:true,force:true});}
 const source=await fs.readFile(path.join(root,"src/app/pro-candidate-20261113/page.tsx"),"utf8");assert(source.includes('React.useState<"fit"|"actual">("fit")'));assert(source.includes('toPng(main, exportCaptureOptions(canvas))'));assert(source.includes('data-preview-scale={scale}'));assert(source.includes('window.history.pushState'));assert(source.includes('window.addEventListener("popstate",sync)'));assert(source.indexOf('<CandidatePreviewControls')<source.indexOf('<main id="candidate-poster"'));assert(source.includes('new ResizeObserver(measure)'));checks++;
 const punctuation=JSON.parse(await fs.readFile(path.join(root,"candidates/pro-20261113/punctuation-audit.json"),"utf8"));assert.equal(punctuation.changedFields,56);for(const field of punctuation.fieldAudit){if(field.changed)assert.equal(field.after,field.before.slice(0,-1));else assert.equal(field.after,field.before);}checks++;
 const nativeAudit=JSON.parse(await fs.readFile(path.join(root,"candidates/pro-20261113/native51-source-audit.json"),"utf8"));assert.equal(nativeAudit.export03Enabled,"onlyzh/en/zh-Hantiphoneandiphone-medium");assert.equal(nativeAudit.matchingWatchCaptureExecuted,true);assert.equal(m.canExportPage({...first,slide:"training"}),true);
 for(const asset of nativeAudit.rawPhoneAssets){const bytes=await fs.readFile(path.join(root,asset.candidateAsset));assert.equal(require("node:crypto").createHash("sha256").update(bytes).digest("hex"),asset.sha256);const meta=await sharp(bytes).metadata();assert.equal(meta.width,1206);assert.equal(meta.height,2622);assert.equal(asset.activeInPoster,true);}checks++;
 console.log(JSON.stringify({checksPassed:checks,targetRoundtrips:roundtrips,fitCases,exactSizePNGHandlerTests:4,browserVisualTest:false,networkRequests:0,generatedPNGs:"temporary synthetic test fixtures, removed; not candidate posters"},null,2));
})().catch(e=>{console.error(e);process.exitCode=1});
