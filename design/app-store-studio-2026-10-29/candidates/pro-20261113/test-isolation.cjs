const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const path = require("node:path");
const os = require("node:os");
const Module = require("node:module");
const ts = require("typescript");
const sharp = require("sharp");
const root = path.resolve(__dirname,"../..");
async function load(relative) {
  const filename = path.join(root,relative);
  const source = await fs.readFile(filename,"utf8");
  const result = ts.transpileModule(source,{reportDiagnostics:true,compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022,esModuleInterop:true,jsx:ts.JsxEmit.ReactJSX}});
  assert.deepEqual((result.diagnostics||[]).filter(d=>d.category===ts.DiagnosticCategory.Error),[]);
  const mod = new Module(filename,module); mod.filename=filename;mod.paths=Module._nodeModulePaths(path.dirname(filename));mod._compile(result.outputText,filename);return mod.exports;
}
(async()=>{
  const old = process.cwd(); const temp = await fs.mkdtemp(path.join(os.tmpdir(),"masso-candidate-isolation-"));
  let checks=0;
  try {
    const exporter = await load("src/app/api/pro-candidate-20261113/export/route.ts");
    const project = await load("src/app/api/pro-candidate-20261113/project/route.ts");
    assert.equal(project.POST,undefined); checks++;
    await fs.mkdir(path.join(temp,"exports/latest"),{recursive:true});
    await fs.writeFile(path.join(temp,"app-store-screenshots.json"),"CANONICAL_SENTINEL");
    await fs.writeFile(path.join(temp,"exports/latest/keep.txt"),"OLD_EXPORT_SENTINEL");
    await fs.mkdir(path.join(temp,"candidates/pro-20261113"),{recursive:true});
    const candidate = await fs.readFile(path.join(root,"candidates/pro-20261113/project.json"));
    await fs.writeFile(path.join(temp,"candidates/pro-20261113/project.json"),candidate);
    process.chdir(temp);
    const projectResponse = await project.GET(); const data = await projectResponse.json();
    assert.equal(projectResponse.status,200); assert.equal(data.state.slidesByDevice.iphone[1].headline.zh,"肌肉恢复估算，\n一眼看清"); checks++;
    assert.equal(data.state.slidesByDevice.iphone[0].textElements[0].text.zh,"也听你要的天数、时长和重点。"); checks++;
    assert.equal(data.state.slidesByDevice.iphone[1].textElements[0].text.zh,"3D 肌肉图，按部位显示。"); checks++;
    assert(!/\bpro\b|unlock|unlimited|premium|解锁|解鎖|免费|免費|订阅|訂閱|有料|無料|유료|무료|freischalt|gratuit|suscrip|assin|платн|бесплатн|اشتراك|مجاني/i.test(JSON.stringify(data.state))); checks++;
    const bytes = await sharp({create:{width:1320,height:2868,channels:4,background:{r:12,g:34,b:56,alpha:0.5}}}).png().toBuffer();
    const dataUrl = "data:image/png;base64,"+bytes.toString("base64");
    const post = body => exporter.POST(new Request("http://unit.invalid",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(body)}));
    const valid = await post({dataUrl,artifactPath:"ios/iphone/1320x2868/zh/01-plan.png"}); const exported=await valid.json();
    assert.equal(valid.status,200); assert.equal(exported.savedPath,"exports/candidates/pro-20261113/ios/iphone/1320x2868/zh/01-plan.png");
    const meta = await sharp(path.join(temp,exported.savedPath)).metadata();assert.equal(meta.width,1320);assert.equal(meta.height,2868);assert.equal(meta.channels,3);assert.equal(meta.hasAlpha,false);checks++;
    for (const artifactPath of ["../app-store-screenshots.json","ios/iphone/1320x2868/zh/03-training.png","ios/iphone/1206x2622/zh/01-plan.png","ios/watch/416x496/zh/01-plan.png","ios/iphone/1320x2868/xx/01-plan.png","ios/iphone/1320x2868/zh/../../01-plan.png"]) {assert.equal((await post({dataUrl,artifactPath})).status,400); checks++;}
    const tiny = await sharp({create:{width:10,height:10,channels:3,background:"white"}}).png().toBuffer();
    assert.equal((await post({dataUrl:"data:image/png;base64,"+tiny.toString("base64"),artifactPath:"ios/iphone/1320x2868/en/02-recovery.png"})).status,400);checks++;
    assert.equal(await fs.readFile(path.join(temp,"app-store-screenshots.json"),"utf8"),"CANONICAL_SENTINEL");
    assert.equal(await fs.readFile(path.join(temp,"exports/latest/keep.txt"),"utf8"),"OLD_EXPORT_SENTINEL");checks++;
    const page = await fs.readFile(path.join(root,"src/app/pro-candidate-20261113/page.tsx"),"utf8");
    const result=ts.transpileModule(page,{reportDiagnostics:true,compilerOptions:{jsx:ts.JsxEmit.ReactJSX,target:ts.ScriptTarget.ES2022}});
    assert.deepEqual((result.diagnostics||[]).filter(d=>d.category===ts.DiagnosticCategory.Error),[]);
    assert(!page.includes('fetch("/api/project"')); assert(!page.includes('fetch("/api/export-image"'));assert(!page.includes("useProject("));checks++;
    console.log(JSON.stringify({checksPassed:checks,networkRequests:0,browserInvoked:false,testPNG:"synthetic unit fixture in temporary directory only; removed",visualRenderVerified:false},null,2));
  } finally { process.chdir(old); await fs.rm(temp,{recursive:true,force:true}); }
})().catch(e=>{console.error(e);process.exitCode=1});
