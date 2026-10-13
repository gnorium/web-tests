import Foundation
import Testing
import WebTests
import WebTestsTesting

@Suite("Artifact overlay", .serialized)
struct ArtifactOverlayTests {
  @Test(arguments: [1440, 440])
  func animatedOverlayFitsTEIAndMovesScan(width: Int) async throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let assets = root.appendingPathComponent("gnorium-web/Public")
    let css = try ["layout-view.css", "tei-view.css", "artifact-view.css"].map {
      try String(contentsOf: assets.appendingPathComponent("style-sheets/" + $0), encoding: .utf8)
    }.joined(separator: "\n")
    let html = "<html><head><style>" + css + #"""
      body{margin:0}.artifact-view{width:100%;height:440px}.artifact-viewer-container{height:400px;flex:none}.canvas-view,.canvas-viewport{width:100%;height:100%;position:relative;overflow:hidden}.canvas-tile-surface{position:absolute;inset:0;width:100%;height:100%}.tei-line{font-family:serif!important}</style><link rel="icon" href="data:,"></head><body><div class="artifact-view" data-canvas-shown="true" data-manifest-url="/manifest"><div class="artifact-viewer-container"><div class="artifact-markup-frame"><div class="artifact-markup"><div class="tei-view"><div class="tei-page" data-service-id="/scan"><div class="tei-page-text" data-layer="rendering"><span class="tei-line">Overlay text</span></div></div></div></div></div><div class="artifact-object"><div class="canvas-view" data-service-id="/scan"><div class="canvas-viewport"><div class="canvas-spinner"></div></div></div></div></div><footer><div class="artifact-overlay-toggle"><button>Overlay</button></div><div class="artifact-detach-toggle"><button class="button-view"><span class="button-icon">Detach</span></button></div></footer></div><script src="/loader.js"></script></body></html>
      """#
    let server = try await FixtureServer(files: [
      "/": .init(contentType: "text/html", body: Data(html.utf8)),
      "/loader.js": .init(contentType: "text/javascript", body: try Data(contentsOf: assets.appendingPathComponent("loader.js"))),
      "/client.wasm": .init(contentType: "application/wasm", body: try Data(contentsOf: assets.appendingPathComponent("client.wasm"))),
      "/manifest": .init(contentType: "application/json", body: Data(#"{"canvases":[{"id":"/scan","w":1200,"h":2000,"img":"/scan.svg"}]}"#.utf8)),
      "/scan.svg": .init(contentType: "image/svg+xml", body: Data(#"<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="2000"/>"#.utf8)),
    ])
    defer { server.stop() }
    let config = BrowserTestConfiguration(baseURL: URL(string: server.baseURL)!, engines: [.chrome], defaultTimeout: .seconds(30))
    try await withPage(.chrome, config, viewport: .init(width: width, height: 600)) { page in
      try await page.goto("/")
      try await expect(page.locator("html")).toHaveAttribute("data-wasm-status", "started")
      try await expect(page.locator(".tei-page")).toHaveAttribute("data-active", "true")
      try await page.evaluate("new Promise(resolve=>setTimeout(resolve,700))")
      let checks = try await page.evaluate(#"""
        (async()=>{
            let r=document.querySelector('.artifact-view'),f=r.querySelector('.artifact-markup-frame'),o=r.querySelector('.artifact-object'),l=r.querySelector('[data-layer=rendering]'),v=r.querySelector('.canvas-viewport'),d=r.querySelector('.artifact-detach-toggle');
            const wait=ms=>new Promise(resolve=>setTimeout(resolve,ms));const size=()=>[f.getBoundingClientRect().width,f.getBoundingClientRect().height,o.getBoundingClientRect().width,o.getBoundingClientRect().height];const toggle=on=>r.querySelector('.artifact-overlay-toggle').dispatchEvent(new CustomEvent('toggle-button-update',{detail:on?'true':'false'}));
            let before=size();
            const pane=r.querySelector('.artifact-markup');let pb=pane.getBoundingClientRect();
            for(let i=0;i<8;i++){pane.dispatchEvent(new WheelEvent('wheel',{deltaY:-40,clientX:pb.x+pb.width/2,clientY:pb.y+pb.height/2,bubbles:true,cancelable:true}));await wait(30)}
            const zoomStart=Number(l.dataset.zoom);toggle(true);await wait(120);let mid=size();const zoomMid=Number(l.dataset.zoom);await wait(500);let after=size();
            const fitted=Number(l.dataset.zoom);const fittedBox=l.getBoundingClientRect(),paneBox=pane.getBoundingClientRect();
            const whole=fittedBox.width<=paneBox.width+1&&fittedBox.height<=paneBox.height+1&&pane.scrollLeft===0&&pane.scrollTop===0&&getComputedStyle(pane).overflow==='hidden';
            const zoomAnimated=zoomStart>zoomMid&&zoomMid>fitted;
            const values=()=>r.querySelector('.canvas-tile-compositor').getAttribute('transform').match(/[-\d.]+/g).map(Number);
            v.dispatchEvent(new KeyboardEvent('keydown',{key:'0',bubbles:true,cancelable:true}));await wait(30);
            let vb=v.getBoundingClientRect();const center=()=>(vb.width-1200*values()[2])/2;
            const drag=async dx=>{v.dispatchEvent(new MouseEvent('mousedown',{clientX:vb.x+vb.width/2,clientY:vb.y+200,bubbles:true,cancelable:true}));window.dispatchEvent(new MouseEvent('mousemove',{clientX:vb.x+vb.width/2+dx,clientY:vb.y+200,bubbles:true}));window.dispatchEvent(new MouseEvent('mouseup',{bubbles:true}));await wait(30)};
            const initialX=values()[0];await drag(60);const minimumPan=Math.abs(values()[0]-initialX)>40;
            await drag(center()-values()[0]+4);const snapped=Math.abs(values()[0]-center())<1;
            const touch=(name,x)=>{let t=new Touch({identifier:1,target:v,clientX:x,clientY:vb.y+200});v.dispatchEvent(new TouchEvent(name,{touches:name==='touchend'?[]:[t],changedTouches:[t],bubbles:true,cancelable:true}))};
            const touchX=vb.x+vb.width/2;touch('touchstart',touchX);touch('touchmove',touchX+45);touch('touchend',touchX+45);await wait(30);const touchPan=Math.abs(values()[0]-center())>30;
            await drag(center()-values()[0]);
            const probe=document.createElement('span');probe.style.backgroundColor='var(--background-color-blue)';r.appendChild(probe);const disabledBlue=getComputedStyle(d.querySelector('button')).backgroundColor===getComputedStyle(probe).backgroundColor&&getComputedStyle(d.querySelector('button')).opacity==='0.5';probe.remove();
            let fixed=()=>{let b=l.getBoundingClientRect();return [Number(l.dataset.zoom),b.x,b.y,b.width,b.height]};let textBefore=fixed();let imageBefore=r.querySelector('.canvas-tile-compositor').getAttribute('transform');
            let b=v.getBoundingClientRect();for(let i=0;i<3;i++){v.dispatchEvent(new WheelEvent('wheel',{deltaY:-40,clientX:b.x+b.width/2,clientY:b.y+b.height/2,bubbles:true,cancelable:true}));await wait(30)}
            let zoomed=r.querySelector('.canvas-tile-compositor').getAttribute('transform');
            v.dispatchEvent(new MouseEvent('mousedown',{clientX:b.x+b.width/2,clientY:b.y+b.height/2,bubbles:true,cancelable:true}));
            window.dispatchEvent(new MouseEvent('mousemove',{clientX:b.x+b.width/2,clientY:b.y+b.height/2+25,bubbles:true}));
            window.dispatchEvent(new MouseEvent('mouseup',{bubbles:true}));await wait(30);
            let imageAfter=r.querySelector('.canvas-tile-compositor').getAttribute('transform');let textAfter=fixed();
            if(imageAfter===zoomed)throw new Error('scan pan did not move');
            const rules={active:r.dataset.overlayActive,detach:d.getAttribute('aria-pressed'),disabled:d.querySelector('button').disabled,imageOpacity:getComputedStyle(o).opacity,textOpacity:getComputedStyle(l).opacity,bg:getComputedStyle(r.querySelector('.artifact-markup')).backgroundColor};
            toggle(false);await wait(120);const zoomOffMid=Number(l.dataset.zoom);await wait(480);const zoomBack=Number(l.dataset.zoom);const zoomReturned=fitted<zoomOffMid&&zoomOffMid<zoomBack&&Math.abs(zoomBack-zoomStart)<0.01;const dim=window.innerWidth>480?0:1;return [zoomReturned,before[dim]<mid[dim]&&mid[dim]<after[dim],JSON.stringify(textBefore)===JSON.stringify(textAfter)&&whole&&zoomAnimated&&minimumPan&&snapped&&touchPan&&disabledBlue,rules.detach==='true'&&rules.disabled,rules.imageOpacity==='0.5'&&rules.textOpacity==='1',rules.bg==='rgba(0, 0, 0, 0)',imageBefore!==imageAfter,d.getAttribute('aria-pressed')==='false'&&!d.querySelector('button').disabled,Math.abs(size()[dim]-before[dim])<1];
           })()
        """#, as: [Bool].self)
      #expect(checks.allSatisfy { $0 }, "zoom back animated, geometry, opacity, scan gestures, whole-page fit, minimum-zoom calibration, center snap and disabled-on Detach")
      try await page.expectNoErrors()
    }
  }

  /// With the page's text block measured on its scan (`data-text-block`,
  /// a skewed quadrilateral in the 0–1000 space), overlay on lays the scan
  /// by the homography that takes those corners onto the rendered content's
  /// ink box (its glyphs' ink, not their font boxes nor a line's trailing
  /// letter-spacing, user, 2026-10-14), in one motion with the text's zoom
  /// and the panes' move, trimming the scan's margins away as it comes (a
  /// clip polygon closing in from the image's corners to the zone's); the
  /// edition's whole page fits the view, centered, its margins the page's
  /// ground; zoom and pan stay within the page; overlay off runs it all
  /// back to where the reader was (user, 2026-10-13, 2026-10-14).
  @Test(arguments: [1440, 440])
  func overlayRegistersTheScansTextBlockUnderTheEditions(width: Int) async throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let assets = root.appendingPathComponent("gnorium-web/Public")
    let css = try ["layout-view.css", "tei-view.css", "artifact-view.css", "canvas-view.css"].map {
      try String(contentsOf: assets.appendingPathComponent("style-sheets/" + $0), encoding: .utf8)
    }.joined(separator: "\n")
    let lines = (1...30).map { #"<span class="tei-line">Line \#($0) of the page.</span>"# }.joined()
    let html = "<!doctype html><html><head><meta charset=\"utf-8\"><style>" + css + #"""
      body{margin:0}.artifact-view{width:100%;height:600px}.artifact-viewer-container{height:560px;flex:none}.tei-line{display:block;font-family:serif!important;white-space:nowrap;letter-spacing:0.3em}</style><link rel="icon" href="data:,"></head><body><div class="artifact-view" data-canvas-shown="true" data-manifest-url="/manifest"><div class="artifact-viewer-container"><div class="artifact-markup-frame"><div class="artifact-markup"><div class="tei-view"><div class="tei-page" data-service-id="/scan" data-active="true" data-text-block="120,90 880,104 868,912 108,898"><div class="tei-page-text" data-layer="rendering" data-framed="true"><div class="tei-text-block" style="--tei-frame-measure: 30; --tei-frame-margin: 5">
      """# + lines + #"""
      </div></div></div></div></div></div><div class="artifact-object"><div class="canvas-view" data-service-id="/scan"><div class="canvas-viewport"><div class="canvas-spinner"></div></div></div></div></div><footer><div class="artifact-overlay-toggle"><button>Overlay</button></div><div class="artifact-detach-toggle"><button class="button-view"><span class="button-icon">Detach</span></button></div></footer></div><script src="/loader.js"></script></body></html>
      """#
    let server = try await FixtureServer(files: [
      "/": .init(contentType: "text/html", body: Data(html.utf8)),
      "/loader.js": .init(contentType: "text/javascript", body: try Data(contentsOf: assets.appendingPathComponent("loader.js"))),
      "/client.wasm": .init(contentType: "application/wasm", body: try Data(contentsOf: assets.appendingPathComponent("client.wasm"))),
      "/manifest": .init(contentType: "application/json", body: Data(#"{"canvases":[{"id":"/scan","w":1200,"h":1600,"img":"/scan.svg"}]}"#.utf8)),
      "/scan.svg": .init(contentType: "image/svg+xml", body: Data(#"<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="1600"/>"#.utf8)),
      "/fonts/noto-sans.woff2": .init(contentType: "font/woff2", body: try Data(contentsOf: assets.appendingPathComponent("fonts/noto-sans.woff2"))),
    ])
    defer { server.stop() }
    let config = BrowserTestConfiguration(baseURL: URL(string: server.baseURL)!, engines: [.chrome], defaultTimeout: .seconds(30))
    try await withPage(.chrome, config, viewport: .init(width: width, height: 600)) { page in
      try await page.goto("/")
      try await expect(page.locator("html")).toHaveAttribute("data-wasm-status", "started")
      try await page.evaluate("new Promise(resolve=>setTimeout(resolve,700))")
      let checks = try await page.evaluate(#"""
        (async()=>{
          const wait=ms=>new Promise(resolve=>setTimeout(resolve,ms)),r=document.querySelector('.artifact-view');
          const toggle=on=>r.querySelector('.artifact-overlay-toggle').dispatchEvent(new CustomEvent('toggle-button-update',{detail:on?'true':'false'}));
          const surface=()=>r.querySelector('.canvas-tile-surface');
          // Where the transforms put each zone corner: the scan's pan and zoom,
          // then the registration's matrix3d, from the viewport's corner.
          const landed=()=>{const v=r.querySelector('.canvas-viewport').getBoundingClientRect(),g=r.querySelector('.canvas-tile-compositor').getAttribute('transform').match(/-?[\d.]+/g).map(Number),m=new DOMMatrix(getComputedStyle(surface()).transform==='none'?undefined:getComputedStyle(surface()).transform);
            return r.querySelector('.tei-page').dataset.textBlock.split(' ').map(p=>p.split(',').map(Number)).map(([x,y])=>{const q=m.transformPoint(new DOMPoint(g[0]+x/1000*1200*g[2],g[1]+y/1000*1600*g[2]));return [v.x+q.x/q.w,v.y+q.y/q.w]})};
          // The rendered content's ink box (layout_preview's _TEXT_BLOCK, rule for rule), and the font box
          // the overlay took before (user, 2026-10-14): its text's range boxes.
          const inkBox=layer => {
            const frame = layer.querySelector('.tei-text-block') || layer;
            const box = layer.getBoundingClientRect();
            const context = document.createElement('canvas').getContext('2d');
            let left = Infinity, top = Infinity, right = -Infinity, bottom = -Infinity;
            const take = (l, t, r, b) => {
              if (!(r > l && b > t)) return;
              left = Math.min(left, l); top = Math.min(top, t); right = Math.max(right, r); bottom = Math.max(bottom, b);
            };
            const blank = code => code === 32 || code === 9 || code === 10 || code === 13;
            const walker = document.createTreeWalker(frame, NodeFilter.SHOW_TEXT);
            const range = document.createRange();
            const rectOf = (node, start, end) => {
              range.setStart(node, start); range.setEnd(node, end);
              return range.getBoundingClientRect();
            };
            for (let node = walker.nextNode(); node; node = walker.nextNode()) {
              const text = node.data;
              if (!/[^ \t\n\r]/.test(text)) continue;
              const style = getComputedStyle(node.parentElement);
              context.font = style.fontStyle + ' ' + style.fontWeight + ' ' + style.fontSize + ' ' + style.fontFamily;
              context.fontVariantCaps = style.fontVariantCaps;
              context.fontKerning = style.fontKerning;
              const glyphs = [];
              for (let at = 0; at < text.length;) {
                const end = at + (text.codePointAt(at) > 0xffff ? 2 : 1);
                if (!blank(text.charCodeAt(at))) glyphs.push([at, end]);
                at = end;
              }
              range.setStart(node, 0); range.setEnd(node, text.length);
              const drawn = [...range.getClientRects()].filter(rect => rect.height > 0);
              const oneLine = drawn.every(rect => rect.top < drawn[0].bottom && drawn[0].top < rect.bottom);
              const lines = [];
              for (const [index, [start, end]] of glyphs.entries()) {
                if (oneLine && index > 0 && index < glyphs.length - 1) continue;
                const rect = rectOf(node, start, end);
                if (!(rect.height > 0)) continue;
                const last = lines[lines.length - 1];
                if (last && rect.top < last.bottom && last.top < rect.bottom) {
                  last.end = end; last.glyphs[1] = [start, end, rect];
                } else {
                  lines.push({start, end, top: rect.top, bottom: rect.bottom, glyphs: [[start, end, rect], [start, end, rect]]});
                }
              }
              for (const line of lines) {
                const drawn = rectOf(node, line.start, line.end);
                const metrics = context.measureText(text.slice(line.start, line.end));
                const font = metrics.fontBoundingBoxAscent + metrics.fontBoundingBoxDescent;
                if (!(font > 0) || !(drawn.height > 0)) continue;
                const scale = drawn.height / font;
                const inkTop = drawn.top + (metrics.fontBoundingBoxAscent - metrics.actualBoundingBoxAscent) * scale;
                const inkBottom = drawn.bottom - (metrics.fontBoundingBoxDescent - metrics.actualBoundingBoxDescent) * scale;
                let inkLeft = Infinity, inkRight = -Infinity;
                for (const [start, end, rect] of line.glyphs) {
                  const glyph = context.measureText(text.slice(start, end));
                  inkLeft = Math.min(inkLeft, rect.left - glyph.actualBoundingBoxLeft * scale);
                  inkRight = Math.max(inkRight, rect.left + glyph.actualBoundingBoxRight * scale);
                }
                take(inkLeft, inkTop, inkRight, inkBottom);
              }
            }
            for (const drawn of frame.querySelectorAll('.tei-rule, .tei-figure-image, .tei-frame')) {
              const style = getComputedStyle(drawn);
              const ruled = ['top', 'right', 'bottom', 'left'].some(side =>
                style.getPropertyValue('border-' + side + '-style') !== 'none'
                && parseFloat(style.getPropertyValue('border-' + side + '-width')) > 0);
              if (drawn.matches('.tei-frame') && !ruled) continue;
              const rect = drawn.getBoundingClientRect();
              take(rect.left, rect.top, rect.right, rect.bottom);
            }
            if (frame !== layer) {
              const edges = frame.getBoundingClientRect();
              left = Math.max(left, edges.left);
              right = Math.min(right, edges.right);
            }
            if (!(right > left && bottom > top)) return null;
            return [left - box.x, top - box.y, right - box.x, bottom - box.y];
          };
          const target=()=>{const l=r.querySelector('[data-layer=rendering]'),b=l.getBoundingClientRect(),[L,T,R,B]=inkBox(l);return [[b.x+L,b.y+T],[b.x+R,b.y+T],[b.x+R,b.y+B],[b.x+L,b.y+B]]};
          const fontBox=()=>{const f=r.querySelector('.tei-text-block'),e=f.getBoundingClientRect(),rg=document.createRange(),w=document.createTreeWalker(f,NodeFilter.SHOW_TEXT);let L=1e9,T=1e9,R=-1e9,B=-1e9;
            while(w.nextNode()){if(!w.currentNode.data.trim())continue;rg.selectNodeContents(w.currentNode);const b=rg.getBoundingClientRect();L=Math.min(L,b.left);T=Math.min(T,b.top);R=Math.max(R,b.right);B=Math.max(B,b.bottom)}
            return [Math.max(L,e.left),T,Math.min(R,e.right),B]};
          const off=()=>Math.max(...landed().map((p,i)=>Math.hypot(p[0]-target()[i][0],p[1]-target()[i][1])));
          // The trim: the clip polygon's corners in the image's own pixels (through the scan's pan and zoom).
          const trim=()=>{const c=getComputedStyle(surface()).clipPath;if(c==='none')return null;const g=r.querySelector('.canvas-tile-compositor').getAttribute('transform').match(/-?[\d.]+/g).map(Number);
            const v=c.match(/-?[\d.]+px/g).map(parseFloat);return [0,1,2,3].map(i=>[(v[2*i]-g[0])/g[2],(v[2*i+1]-g[1])/g[2]])};
          const zone=r.querySelector('.tei-page').dataset.textBlock.split(' ').map(p=>p.split(',').map(Number)).map(([x,y])=>[x/1000*1200,y/1000*1600]);
          const image=[[0,0],[1200,0],[1200,1600],[0,1600]];
          const trimAt=t=>t&&Math.max(...t.map((p,i)=>Math.hypot(p[0]-zone[i][0],p[1]-zone[i][1])));
          const pane=r.querySelector('.artifact-markup'),layer=()=>r.querySelector('[data-layer=rendering]');
          const place=()=>{const b=layer().getBoundingClientRect();return [Number(layer().dataset.zoom),b.x,b.y,b.width,b.height,pane.scrollLeft,pane.scrollTop].map(n=>Math.round(n*100)/100)};
          const wheel=async(dy,fx,fy,n)=>{const b=pane.getBoundingClientRect();for(let i=0;i<n;i++){pane.dispatchEvent(new WheelEvent('wheel',{deltaY:dy,clientX:b.x+b.width*fx,clientY:b.y+b.height*fy,bubbles:true,cancelable:true}));await wait(30)}};
          // The reader zoomed in and scrolled before overlay.
          await wheel(-40,0.3,0.3,6);await wait(300);const before=place();
          const none=getComputedStyle(surface()).transform==='none'&&getComputedStyle(surface()).clipPath==='none';
          toggle(true);await wait(150);const midway=off(),midTrim=trimAt(trim()),midImage=trim()&&Math.max(...trim().map((p,i)=>Math.hypot(p[0]-image[i][0],p[1]-image[i][1])));
          await wait(650);const registered=off(),trimmed=trimAt(trim());
          const skewed=Math.abs(new DOMMatrix(getComputedStyle(surface()).transform).b)>0.001;
          // The whole page fits the view, centered: its margins kept, no scroll.
          const pb=pane.getBoundingClientRect(),lb=layer().getBoundingClientRect();
          const inside=(b,slack)=>b.left>=pb.left-slack&&b.top>=pb.top-slack&&b.right<=pb.right+slack&&b.bottom<=pb.bottom+slack;
          const fits=inside(lb,1)&&(Math.abs(lb.width-pane.clientWidth)<1||Math.abs(lb.height-pane.clientHeight)<1)
            &&Math.abs((lb.left+lb.right)/2-(pb.left+pb.right)/2)<1.5&&Math.abs((lb.top+lb.bottom)/2-(pb.top+pb.bottom)/2)<1.5&&pane.scrollLeft===0&&pane.scrollTop===0;
          const fit=place();
          await wheel(40,0.5,0.5,6);await wait(100);const outStops=JSON.stringify(place())===JSON.stringify(fit);
          await wheel(-40,0.2,0.2,12);await wait(100);const zoomedIn=Number(layer().dataset.zoom)>fit[0]*1.5;
          // In each axis the page is centered where it is no longer than the view, else covers it.
          const cl=pb.left+pane.clientLeft,ct=pb.top+pane.clientTop,cw=pane.clientWidth,ch=pane.clientHeight;
          const axis=(start,length,from,view)=>length<=view+1?Math.abs(start+length/2-(from+view/2))<1.5:start<=from+1.5&&start+length>=from+view-1.5;
          const bounded=b=>axis(b.left,b.width,cl,cw)&&axis(b.top,b.height,ct,ch);
          const coveredZoomed=bounded(layer().getBoundingClientRect())&&layer().getBoundingClientRect().height>ch+1;
          const drag=(dx,dy)=>{const x=pb.x+5,y=pb.y+5;pane.dispatchEvent(new MouseEvent('mousedown',{clientX:x,clientY:y,button:0,detail:1,bubbles:true,cancelable:true}));window.dispatchEvent(new MouseEvent('mousemove',{clientX:x+dx,clientY:y+dy,bubbles:true}));window.dispatchEvent(new MouseEvent('mouseup',{bubbles:true}))};
          drag(5000,5000);await wait(60);const topLeft=layer().getBoundingClientRect();
          drag(-9000,-9000);await wait(60);const bottomRight=layer().getBoundingClientRect();
          const panBounded=bounded(topLeft)&&Math.abs(topLeft.top-ct)<1.5&&bounded(bottomRight)&&Math.abs(bottomRight.bottom-ct-ch)<1.5;
          const stillRegistered=off()<2;
          toggle(false);await wait(150);const offTrim=trim(),offMid=offTrim&&trimAt(offTrim)>1;await wait(850);
          const cleared=getComputedStyle(surface()).transform==='none'&&getComputedStyle(surface()).clipPath==='none';
          const restored=JSON.stringify(place())===JSON.stringify(before);
          const ink=target(),font=fontBox(),zoom=Number(layer().dataset.zoom);
          const spacing=parseFloat(getComputedStyle(r.querySelector('.tei-line')).letterSpacing);
          // The ink stands inside the font box, in the layer's own pixels: below its top (the font's ascent
          // over the glyphs'), and in from its right by more than the last glyph's letter-spacing.
          const inkInside=(ink[0][1]-font[1])/zoom>1&&(font[2]-ink[1][0])/zoom>spacing;
          // Reduced motion: the end state at once, each way.
          // (The browser's own reduced motion stops the panes' transition too.)
          const media=window.matchMedia;window.matchMedia=q=>q.includes('reduced-motion')?{matches:true}:media.call(window,q);
          const still=document.createElement('style');still.textContent='*{transition:none!important}';document.head.appendChild(still);
          toggle(true);await wait(60);const instantOn=off()<2&&trimAt(trim())<0.5;
          toggle(false);await wait(60);const instantOff=getComputedStyle(surface()).clipPath==='none'&&JSON.stringify(place())===JSON.stringify(before);
          window.matchMedia=media;still.remove();
          return [none,midway>registered+5,registered<2,skewed,cleared,inkInside,Math.round(registered*100)/100,
            midTrim>5&&midImage>5,trimmed<0.5,fits,outStops,zoomedIn&&coveredZoomed&&panBounded&&stillRegistered,offMid,restored,instantOn&&instantOff].map(Number);
        })()
        """#, as: [Double].self)
      #expect(checks[0] == 1, "no registration before the overlay")
      #expect(checks[1] == 1, "the registration eases in with the overlay's motion")
      #expect(checks[2] == 1, "the zone's corners land on the rendered content's ink box within 2px (off by \(checks[6]))")
      #expect(checks[3] == 1, "the scan is turned by its measured skew")
      #expect(checks[4] == 1, "overlay off takes the registration and the trim away")
      #expect(checks[5] == 1, "the target is the ink, inside the text's font box and short of its trailing letter-spacing")
      #expect(checks[7] == 1, "midway the trim is between the image's corners and the zone's")
      #expect(checks[8] == 1, "at rest the scan is trimmed to its text block")
      #expect(checks[9] == 1, "the edition's whole page fits the view, centered, unscrolled")
      #expect(checks[10] == 1, "zoom out stops at the whole page")
      #expect(checks[11] == 1, "zoom in and pan stay within the page, the scan registered under it")
      #expect(checks[12] == 1, "overlay off runs the trim back out")
      #expect(checks[13] == 1, "overlay off restores the reader's zoom, place and scroll exactly")
      #expect(checks[14] == 1, "with reduced motion the end state applies at once, on and off")
      try await page.expectNoErrors()
    }
  }
}
