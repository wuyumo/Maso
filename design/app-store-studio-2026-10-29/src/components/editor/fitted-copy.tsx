"use client";
import * as React from "react";

// Keep the complete copy inside the allocated space, including long translated
// text and user edits. Measure at the canvas's native size, not preview size.
export function FittedCopy({children}:{children:React.ReactNode}) {
 const box = React.useRef<HTMLDivElement>(null);
 const content = React.useRef<HTMLDivElement>(null);
 const [scale,setScale] = React.useState(1);
 React.useLayoutEffect(() => {
  const update = () => {
   if (!box.current || !content.current) return;
   const available = box.current.clientHeight;
   const required = content.current.scrollHeight;
   if (available && required) setScale(Math.min(1, available / required));
  };
  update();
  const observer = new ResizeObserver(update);
  if (box.current) observer.observe(box.current);
  if (content.current) observer.observe(content.current);
  return () => observer.disconnect();
 }, [children]);
 return <div ref={box} data-copy-box style={{width:"100%",height:"100%",display:"flex",alignItems:"center",minWidth:0}}>
  <div ref={content} data-copy-content style={{width:"100%",minWidth:0,overflowWrap:"anywhere",transform:`scale(${scale})`,transformOrigin:"center center"}}>{children}</div>
 </div>;
}
