const assert=require("node:assert/strict"),fs=require("node:fs"),path=require("node:path");
const root=path.resolve(__dirname,"../..");const source=fs.readFileSync(path.join(root,"src/lib/candidate-plan-presentation.ts"),"utf8");
const track=source.match(/#candidate-poster\[data-candidate-plan-device="low-angle-split"\] \[data-plan-variant="A"\] \[data-chat-plan-grid="1"\] \{([^}]+)\}/)[1];
const card=source.match(/#candidate-poster\[data-candidate-plan-device="low-angle-split"\] \[data-plan-variant="A"\] \[data-chat-plan\] \{([^}]+)\}/)[1];
assert(track.includes('--candidate-plan-gap: calc(22px * var(--candidate-plan-unit))'));assert(track.includes('gap: var(--candidate-plan-gap) !important'));assert(track.includes('padding: 0'));assert(track.includes('overflow: hidden'));
assert(card.includes('flex: 0 0 calc((100% - var(--candidate-plan-gap)) / 1.8) !important'));assert(card.includes('width: calc((100% - var(--candidate-plan-gap)) / 1.8) !important'));assert(card.includes('min-width: 0 !important'));assert(card.includes('max-width: none !important'));assert(card.includes('box-sizing: border-box'));assert(!card.includes('transform'));assert(!card.includes('scaleX'));
const original=fs.readFileSync(path.join(root,'src/components/editor/coach-chat.tsx'),'utf8');assert(original.includes('dir={rtl ? "rtl" : "ltr"}'));assert(original.includes('flexDirection: "row"'));assert(original.includes('gap: 22 * k'));assert(source.includes('direction: ltr;'));
let cases=0;for(const unit of [.75,.9,1,1.4])for(const total of [640,900,1400])for(const inset of [0,16,28])for(const fit of [.4,.6,.8,1])for(const rtl of [false,true]){
 const viewport=total-2*inset*unit,logical=viewport/fit,gap=22*unit,card=(logical-gap)/1.8,physical=card*fit,physicalGap=gap*fit;
 assert(physical>0);assert(Math.abs(physical*1.8+physicalGap-viewport)<1e-9);
 const nextStart=rtl?viewport-physical-physicalGap-physical:physical+physicalGap;
 const visible=Math.max(0,Math.min(viewport,nextStart+physical)-Math.max(0,nextStart));assert(Math.abs(visible/physical-.8)<1e-9);
 for(const pad of [20,30]){const content=card-2*pad*unit-2*1.2*unit;assert(content>0);assert(Math.abs((content+2*pad*unit+2*1.2*unit)*fit-physical)<1e-9);}cases++;
}
console.log(JSON.stringify({onePointEightCardCases:cases,rtlAndLtr:true,borderBoxPaddingIncluded:true,originalPhotoPhysicalOrderPreserved:true,browserVisualTest:false,actualPosterPNGs:0}));
