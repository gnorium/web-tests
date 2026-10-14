(async()=>{
  const r=document.querySelector('.artifact-view'),page=r.querySelector('.tei-page[data-active=true]'),layer=page.querySelector('[data-layer=rendering]'),frame=layer.querySelector('.tei-text-block')||layer;
  // The edition's rows: each drawn row's ink (the reader's InkExtent rule), the main text's alone.
  const context=document.createElement('canvas').getContext('2d'),range=document.createRange();
  const rectOf=(node,start,end)=>{range.setStart(node,start);range.setEnd(node,end);return range.getBoundingClientRect()};
  const rows=[];
  const walker=document.createTreeWalker(frame,NodeFilter.SHOW_TEXT);
  for(let node=walker.nextNode();node;node=walker.nextNode()){
    const text=node.data;if(!/[^ \t\n\r]/.test(text))continue;
    const style=getComputedStyle(node.parentElement);
    context.font=style.fontStyle+' '+style.fontWeight+' '+style.fontSize+' '+style.fontFamily;
    context.fontVariantCaps=style.fontVariantCaps;context.fontKerning=style.fontKerning;
    const lines=[];
    for(let at=0;at<text.length;){
      const end=at+(text.codePointAt(at)>0xffff?2:1);
      if(!/[ \t\n\r]/.test(text[at])){
        const rect=rectOf(node,at,end);
        if(rect.height>0){
          const last=lines[lines.length-1];
          if(last&&rect.top<last.bottom&&last.top<rect.bottom){last.end=end;last.glyphs[1]=[at,end,rect]}
          else lines.push({start:at,end,top:rect.top,bottom:rect.bottom,glyphs:[[at,end,rect],[at,end,rect]]});
        }
      }
      at=end;
    }
    for(const line of lines){
      const drawn=rectOf(node,line.start,line.end),metrics=context.measureText(text.slice(line.start,line.end));
      const scale=drawn.height/(metrics.fontBoundingBoxAscent+metrics.fontBoundingBoxDescent);
      const top=drawn.top+(metrics.fontBoundingBoxAscent-metrics.actualBoundingBoxAscent)*scale,bottom=drawn.bottom-(metrics.fontBoundingBoxDescent-metrics.actualBoundingBoxDescent)*scale;
      let left=Infinity,right=-Infinity;
      for(const [start,end,rect] of line.glyphs){const glyph=context.measureText(text.slice(start,end));left=Math.min(left,rect.left-glyph.actualBoundingBoxLeft*scale);right=Math.max(right,rect.left+glyph.actualBoundingBoxRight*scale)}
      const row=rows.find(o=>top<o.bottom&&o.top<bottom);
      if(row){row.left=Math.min(row.left,left);row.right=Math.max(row.right,right);row.top=Math.min(row.top,top);row.bottom=Math.max(row.bottom,bottom);row.text+=' '+text.slice(line.start,line.end)}
      else rows.push({top,bottom,left,right,text:text.slice(line.start,line.end)});
    }
  }
  rows.sort((a,b)=>a.top-b.top);
  // The transforms as drawn: the image's pixels to the window and back.
  const surface=r.querySelector('.canvas-tile-surface'),view=r.querySelector('.canvas-viewport').getBoundingClientRect();
  const g=r.querySelector('.canvas-tile-compositor').getAttribute('transform').match(/-?[\d.]+(e-?\d+)?/g).map(Number);
  const m=new DOMMatrix(getComputedStyle(surface).transform==='none'?undefined:getComputedStyle(surface).transform),inverse=m.inverse();
  const toWindow=(x,y)=>{const q=m.transformPoint(new DOMPoint(g[0]+x*g[2],g[1]+y*g[2]));return [view.x+q.x/q.w,view.y+q.y/q.w]};
  const toImage=(x,y)=>{const q=inverse.transformPoint(new DOMPoint(x-view.x,y-view.y));return [(q.x/q.w-g[0])/g[2],(q.y/q.w-g[1])/g[2]]};
  // The scan's pixels, its ink by Otsu's threshold over its text block, specks out by the binary median.
  const manifest=await (await fetch(r.dataset.manifestUrl)).json(),canvas=manifest.canvases[0];
  const image=new Image();image.src=canvas.img;await image.decode();
  const W=image.naturalWidth,H=image.naturalHeight,sx=W/canvas.w,sy=H/canvas.h;
  const c=document.createElement('canvas');c.width=W;c.height=H;const cx=c.getContext('2d');cx.drawImage(image,0,0);const px=cx.getImageData(0,0,W,H).data;
  const gray=new Uint8Array(W*H);for(let i=0;i<W*H;i++)gray[i]=(px[4*i]+px[4*i+1]+px[4*i+2])/3;
  const zone=page.dataset.textBlock.split(' ').map(p=>p.split(',').map(Number)).map(([x,y])=>[x/1000*W,y/1000*H]);
  const zx0=Math.floor(Math.min(...zone.map(p=>p[0]))),zx1=Math.ceil(Math.max(...zone.map(p=>p[0]))),zy0=Math.floor(Math.min(...zone.map(p=>p[1]))),zy1=Math.ceil(Math.max(...zone.map(p=>p[1])));
  const histogram=new Array(256).fill(0);for(let y=zy0;y<zy1;y++)for(let x=zx0;x<zx1;x++)histogram[gray[y*W+x]]++;
  let total=0,sum=0;histogram.forEach((n,v)=>{total+=n;sum+=v*n});let below=0,belowSum=0,best=-1,threshold=0;
  for(let v=0;v<256;v++){below+=histogram[v];belowSum+=v*histogram[v];if(!below||below===total)continue;const a=belowSum/below,b=(sum-belowSum)/(total-below),between=below*(total-below)*(a-b)*(a-b);if(between>best){best=between;threshold=v}}
  const dark=(x,y)=>x>=0&&y>=0&&x<W&&y<H&&gray[y*W+x]<=threshold;
  // Specks out as layout_measure takes them out: the binary median of the smallest odd window that holds a
  // stroke (the modal length of the zone's horizontal ink runs).
  const runs=new Map();for(let y=zy0;y<zy1;y+=2){let n=0;for(let x=zx0;x<=zx1;x++){if(x<zx1&&dark(x,y))n++;else if(n){runs.set(n,(runs.get(n)||0)+1);n=0}}}
  const stroke=[...runs.entries()].reduce((a,b)=>b[1]>a[1]?b:a,[1,0])[0],half=Math.max(1,Math.floor(stroke/2)),area=(2*half+1)**2;
  // The row's band by that filter (a fleck under a line is no row of it); its edges across by the 3×3 one, so
  // small type's thin strokes keep their extent.
  const solid=(x,y)=>{let n=0;for(let dy=-half;dy<=half;dy++)for(let dx=-half;dx<=half;dx++)if(dark(x+dx,y+dy))n++;return n*2>area};
  const ink=(x,y)=>{let n=0;for(let dy=-1;dy<=1;dy++)for(let dx=-1;dx<=1;dx++)if(dark(x+dx,y+dy))n++;return n>=5};
  // Sampled along the registered axes (the scan's pixels as laid under the text): a grid in the
  // window one scan pixel apart, each point read where the transforms take it on the image, so a
  // tilted scan's line is a band the height of its type, not of its tilt.
  const a0=toWindow(0,0),a1=toWindow(1000,0),step=Math.hypot(a1[0]-a0[0],a1[1]-a0[1])/1000/sx;
  const sample=(X,Y)=>{const [ix,iy]=toImage(X,Y);return ink(Math.round(ix*sx),Math.round(iy*sy))};
  const sampleSolid=(X,Y)=>{const [ix,iy]=toImage(X,Y);return solid(Math.round(ix*sx),Math.round(iy*sy))};
  const out=[];
  rows.forEach((row,i)=>{
    const above=i>0?(rows[i-1].bottom+row.top)/2:row.top-(row.bottom-row.top),below=i<rows.length-1?(row.bottom+rows[i+1].top)/2:row.bottom+(row.bottom-row.top);
    const pad=row.bottom-row.top,X0=row.left-pad,X1=row.right+pad;
    const ny=Math.ceil((below-above)/step),nx=Math.ceil((X1-X0)/step);
    const grid=new Uint8Array(nx*ny),rowInk=new Array(ny).fill(0);
    for(let j=0;j<ny;j++)for(let k=0;k<nx;k++){if(sample(X0+k*step,above+j*step))grid[j*nx+k]=1;if(sampleSolid(X0+k*step,above+j*step))rowInk[j]++}
    // The window's bands of inked rows, white within a quarter of the row's height bridged (an accent
    // over its letter); the row's ink is the band holding the most, never a fleck apart.
    const bridge=(row.bottom-row.top)/4/step,bands=[];
    rowInk.forEach((n,k)=>{if(!n)return;const band=bands[bands.length-1];if(band&&k-band.end<=bridge){band.end=k+1;band.ink+=n}else bands.push({start:k,end:k+1,ink:n})});
    if(!bands.length){out.push({text:row.text,edition:[row.top,row.bottom,row.left,row.right],scan:[0,0,0,0]});return}
    const band=bands.reduce((a,b)=>b.ink>a.ink?b:a);
    // Its type's core: the rows of the band at least half as inked as its most (layout_measure's).
    const inBand=rowInk.slice(band.start,band.end),most=Math.max(...inBand),coreRows=inBand.map((n,k)=>n*2>=most?k:-1).filter(k=>k>=0);
    const core=coreRows.length?coreRows[coreRows.length-1]-coreRows[0]+1:0;
    const colInk=new Array(nx).fill(0);for(let j=band.start;j<band.end;j++)for(let k=0;k<nx;k++)colInk[k]+=grid[j*nx+k];
    // A fleck beside the line's end is none of its ink: an end piece no taller than half its core (no
    // letter's body), no wider than the core, parted from the rest by more white than that
    // (layout_measure's _without_specks).
    const runs=[];colInk.forEach((n,k)=>{if(!n)return;const run=runs[runs.length-1];if(run&&run.end===k)run.end=k+1;else runs.push({start:k,end:k+1})});
    const tall=run=>{let t=Infinity,b=-Infinity;for(let j=band.start;j<band.end;j++)for(let k=run.start;k<run.end;k++)if(grid[j*nx+k]){t=Math.min(t,j);b=Math.max(b,j)}return b-t+1};
    const speck=(run,gap)=>core>0&&run.end-run.start<=core&&tall(run)*2<=core&&gap>core;
    while(runs.length>1&&speck(runs[0],runs[1].start-runs[0].end))runs.shift();
    while(runs.length>1&&speck(runs[runs.length-1],runs[runs.length-1].start-runs[runs.length-2].end))runs.pop();
    const first=runs[0].start,last=runs[runs.length-1].end;
    out.push({text:row.text,edition:[row.top,row.bottom,row.left,row.right].map(v=>+v.toFixed(2)),
      scan:[above+band.start*step,above+band.end*step,X0+first*step,X0+last*step].map(v=>+v.toFixed(2))});
  });
  return out;
})()
