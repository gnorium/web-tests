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
            const values=()=>r.querySelector('.canvas-tile-compositor').getAttribute('transform');
            // Held still: no wheel, drag, touch, pinch or key moves the scan or the text.
            let fixed=()=>{let b=l.getBoundingClientRect();return JSON.stringify([Number(l.dataset.zoom),b.x,b.y,b.width,b.height,values()])};const still=fixed();
            const vb=v.getBoundingClientRect(),cx=vb.x+vb.width/2,cy=vb.y+vb.height/2;
            for(let i=0;i<3;i++){v.dispatchEvent(new WheelEvent('wheel',{deltaY:-40,clientX:cx,clientY:cy,bubbles:true,cancelable:true}));pane.dispatchEvent(new WheelEvent('wheel',{deltaY:-40,clientX:cx,clientY:cy,bubbles:true,cancelable:true}));await wait(30)}
            for(const target of [v,pane]){target.dispatchEvent(new MouseEvent('mousedown',{clientX:cx,clientY:cy,button:0,detail:1,bubbles:true,cancelable:true}));window.dispatchEvent(new MouseEvent('mousemove',{clientX:cx+60,clientY:cy+40,bubbles:true}));window.dispatchEvent(new MouseEvent('mouseup',{bubbles:true}));await wait(30)}
            const touch=(target,name,points)=>{const ts=points.map(([x,y],i)=>new Touch({identifier:i+1,target,clientX:x,clientY:y}));target.dispatchEvent(new TouchEvent(name,{touches:name==='touchend'?[]:ts,changedTouches:ts,bubbles:true,cancelable:true}))};
            for(const target of [v,pane]){touch(target,'touchstart',[[cx,cy]]);touch(target,'touchmove',[[cx+45,cy+30]]);touch(target,'touchend',[[cx+45,cy+30]]);
              touch(target,'touchstart',[[cx-10,cy],[cx+10,cy]]);touch(target,'touchmove',[[cx-80,cy],[cx+80,cy]]);touch(target,'touchend',[[cx-80,cy],[cx+80,cy]]);await wait(30)}
            for(const target of [v,pane]){target.focus();for(const key of ['+','-','0','ArrowLeft','ArrowDown'])target.dispatchEvent(new KeyboardEvent('keydown',{key,bubbles:true,cancelable:true}));await wait(30)}
            const locked=fixed()===still;
            const button=d.querySelector('button'),detachOn=!d.hidden&&getComputedStyle(d).display!=='none'&&button.disabled&&button.getAttribute('aria-disabled')==='true'&&d.getAttribute('aria-pressed')==='false';
            const rules={imageOpacity:getComputedStyle(o).opacity,textOpacity:getComputedStyle(l).opacity,bg:getComputedStyle(r.querySelector('.artifact-markup')).backgroundColor};
            toggle(false);await wait(120);const zoomOffMid=Number(l.dataset.zoom);await wait(480);const zoomBack=Number(l.dataset.zoom);const zoomReturned=fitted<zoomOffMid&&zoomOffMid<zoomBack&&Math.abs(zoomBack-zoomStart)<0.01;const dim=window.innerWidth>480?0:1;
            const detachOff=!button.disabled&&!button.hasAttribute('aria-disabled')&&d.getAttribute('aria-pressed')==='false';
            const panesBack=Math.abs(size()[dim]-before[dim])<1;
            // Detached before the overlay: off and disabled while it is on (the panes synced as overlaid),
            // detached again after.
            const detachTo=on=>d.dispatchEvent(new CustomEvent('toggle-button-update',{detail:on?'true':'false'}));
            detachTo(true);await wait(30);const detachedBefore=d.getAttribute('aria-pressed')==='true'&&!button.disabled;
            toggle(true);await wait(600);const detachedOn=button.disabled&&button.getAttribute('aria-disabled')==='true'&&d.getAttribute('aria-pressed')==='false';
            toggle(false);await wait(600);const detachedAfter=!button.disabled&&!button.hasAttribute('aria-disabled')&&d.getAttribute('aria-pressed')==='true';
            detachTo(false);await wait(30);
            return [zoomReturned,before[dim]<mid[dim]&&mid[dim]<after[dim],whole&&zoomAnimated,locked,detachOn,rules.imageOpacity==='0.5'&&rules.textOpacity==='1',rules.bg==='rgba(0, 0, 0, 0)',detachOff,panesBack,detachedBefore&&detachedOn&&detachedAfter];
           })()
        """#, as: [Bool].self)
      let named = [
        "zoom back animated", "the panes move", "the whole page fits, zoom animated", "no gesture moves the scan or the text",
        "Detach present, disabled and off while on", "opacity", "the text on no ground", "Detach enabled and off after", "panes back",
        "detached before: off and disabled while on, detached again after",
      ]
      for (check, name) in zip(checks, named) { #expect(check, "\(name)") }
      try await page.expectNoErrors()
    }
  }

  /// The JS the tests share: `inkBox(layer)`, the rendered main text
  /// block's ink box (layout_preview's `_TEXT_BLOCK`, rule for rule) in the
  /// layer's window pixels; `homography(source, destination)`, the
  /// transform taking four points to four (each [x, y]), and `apply`.
  static let shared = #"""
    const inkBox=layer => {
      const frame = layer.querySelector('.tei-text-block') || layer;
      const box = layer.getBoundingClientRect();
      const context = document.createElement('canvas').getContext('2d');
      let left = Infinity, top = Infinity, right = -Infinity, bottom = -Infinity;
      const take = (l, t, r, b) => { if (!(r > l && b > t)) return; left = Math.min(left, l); top = Math.min(top, t); right = Math.max(right, r); bottom = Math.max(bottom, b); };
      const blank = code => code === 32 || code === 9 || code === 10 || code === 13;
      const walker = document.createTreeWalker(frame, NodeFilter.SHOW_TEXT);
      const range = document.createRange();
      const rectOf = (node, start, end) => { range.setStart(node, start); range.setEnd(node, end); return range.getBoundingClientRect(); };
      for (let node = walker.nextNode(); node; node = walker.nextNode()) {
        const text = node.data;
        if (!/[^ \t\n\r]/.test(text)) continue;
        const style = getComputedStyle(node.parentElement);
        context.font = style.fontStyle + ' ' + style.fontWeight + ' ' + style.fontSize + ' ' + style.fontFamily;
        context.fontVariantCaps = style.fontVariantCaps; context.fontKerning = style.fontKerning;
        const glyphs = [];
        for (let at = 0; at < text.length;) { const end = at + (text.codePointAt(at) > 0xffff ? 2 : 1); if (!blank(text.charCodeAt(at))) glyphs.push([at, end]); at = end; }
        range.setStart(node, 0); range.setEnd(node, text.length);
        const drawn = [...range.getClientRects()].filter(rect => rect.height > 0);
        const oneLine = drawn.every(rect => rect.top < drawn[0].bottom && drawn[0].top < rect.bottom);
        const lines = [];
        for (const [index, [start, end]] of glyphs.entries()) {
          if (oneLine && index > 0 && index < glyphs.length - 1) continue;
          const rect = rectOf(node, start, end);
          if (!(rect.height > 0)) continue;
          const last = lines[lines.length - 1];
          if (last && rect.top < last.bottom && last.top < rect.bottom) { last.end = end; last.glyphs[1] = [start, end, rect]; }
          else lines.push({start, end, top: rect.top, bottom: rect.bottom, glyphs: [[start, end, rect], [start, end, rect]]});
        }
        for (const line of lines) {
          const drawn = rectOf(node, line.start, line.end), metrics = context.measureText(text.slice(line.start, line.end));
          const font = metrics.fontBoundingBoxAscent + metrics.fontBoundingBoxDescent;
          if (!(font > 0) || !(drawn.height > 0)) continue;
          const scale = drawn.height / font;
          const inkTop = drawn.top + (metrics.fontBoundingBoxAscent - metrics.actualBoundingBoxAscent) * scale;
          const inkBottom = drawn.bottom - (metrics.fontBoundingBoxDescent - metrics.actualBoundingBoxDescent) * scale;
          let inkLeft = Infinity, inkRight = -Infinity;
          for (const [start, end, rect] of line.glyphs) { const glyph = context.measureText(text.slice(start, end)); inkLeft = Math.min(inkLeft, rect.left - glyph.actualBoundingBoxLeft * scale); inkRight = Math.max(inkRight, rect.left + glyph.actualBoundingBoxRight * scale); }
          take(inkLeft, inkTop, inkRight, inkBottom);
        }
      }
      for (const drawn of frame.querySelectorAll('.tei-rule, .tei-figure-image, .tei-frame')) {
        const style = getComputedStyle(drawn);
        const ruled = ['top', 'right', 'bottom', 'left'].some(side => style.getPropertyValue('border-' + side + '-style') !== 'none' && parseFloat(style.getPropertyValue('border-' + side + '-width')) > 0);
        if (drawn.matches('.tei-frame') && !ruled) continue;
        const rect = drawn.getBoundingClientRect(); take(rect.left, rect.top, rect.right, rect.bottom);
      }
      if (frame !== layer) { const edges = frame.getBoundingClientRect(); left = Math.max(left, edges.left); right = Math.min(right, edges.right); }
      return right > left && bottom > top ? [left, top, right, bottom] : null;
    };
    const homography=(source,destination)=>{const rows=[];source.forEach(([x,y],i)=>{const [u,v]=destination[i];rows.push([x,y,1,0,0,0,-u*x,-u*y,u]);rows.push([0,0,0,x,y,1,-v*x,-v*y,v])});
      for(let c=0;c<8;c++){let p=c;for(let r=c+1;r<8;r++)if(Math.abs(rows[r][c])>Math.abs(rows[p][c]))p=r;[rows[c],rows[p]]=[rows[p],rows[c]];for(let r=0;r<8;r++){if(r===c)continue;const f=rows[r][c]/rows[c][c];for(let e=c;e<9;e++)rows[r][e]-=f*rows[c][e]}}
      return [...rows.map((row,i)=>row[8]/row[i]),1]};
    const apply=(h,[x,y])=>{const w=h[6]*x+h[7]*y+h[8];return [(h[0]*x+h[1]*y+h[2])/w,(h[3]*x+h[4]*y+h[5])/w]};
    // Where registration lays the zone (layout_measure.laid_on): onto the ink box's height, centered, the
    // scan's proportions kept.
    const laidOn=(zone,[L,T,R,B])=>{const across=Math.hypot(zone[1][0]-zone[0][0],zone[1][1]-zone[0][1]),down=Math.hypot(zone[3][0]-zone[0][0],zone[3][1]-zone[0][1]),half=across*(B-T)/down/2,mid=(L+R)/2;return [mid-half,T,mid+half,B]};
    """#

  /// With the page's main text block measured on its scan
  /// (`data-text-block`, a skewed quadrilateral in the 0–1000 space),
  /// overlay on lays the whole scan by the homography that takes those
  /// corners onto the rendered main text's ink box, by its height and
  /// centered, the scan's proportions kept, in one motion with the text's
  /// zoom, the panes' move and the scan's opacity, 1 to 0.5 (user,
  /// 2026-10-14); no trim: the view fits the edition's page and all of
  /// the scan. At rest the reader zooms and pans the two as one, never
  /// below the fit, the registration kept at every zoom; Detach is
  /// disabled and off. Overlay off slides the panes apart at the overlay's
  /// zoom, the text's middle and the scan's on one point of the scan, the
  /// opacity back to 1, Detach as it was.
  @Test(arguments: [1440, 440])
  func overlayRegistersTheScansMainTextBlockUnderTheEditions(width: Int) async throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let assets = root.appendingPathComponent("gnorium-web/Public")
    let css = try ["layout-view.css", "tei-view.css", "artifact-view.css", "canvas-view.css"].map {
      try String(contentsOf: assets.appendingPathComponent("style-sheets/" + $0), encoding: .utf8)
    }.joined(separator: "\n")
    let lines = (1...30).map { #"<span class="tei-line">Line \#($0) of the page.</span>"# }.joined()
    let html = "<!doctype html><html><head><meta charset=\"utf-8\"><style>" + css + #"""
      body{margin:0}.artifact-view{width:100%;height:600px}.artifact-viewer-container{height:560px;flex:none}.tei-line{display:block;font-family:serif!important;white-space:nowrap;letter-spacing:0.3em}</style><link rel="icon" href="data:,"></head><body><div class="artifact-view" data-canvas-shown="true" data-manifest-url="/manifest"><div class="artifact-viewer-container"><div class="artifact-markup-frame"><div class="artifact-markup"><div class="tei-view"><div class="tei-page" data-service-id="/scan" data-active="true" data-text-block="300,240 700,248 694,700 294,692"><div class="tei-page-text" data-layer="rendering" data-framed="true" style="--tei-frame-measure: 30; --tei-frame-height: 40; --tei-frame-margin: 5; --tei-page-width: 0; --tei-page-height: 0"><div class="tei-text-block">
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
      let checks = try await page.evaluate("(async()=>{" + Self.shared + #"""
          const wait=ms=>new Promise(resolve=>setTimeout(resolve,ms)),r=document.querySelector('.artifact-view');
          const toggle=on=>r.querySelector('.artifact-overlay-toggle').dispatchEvent(new CustomEvent('toggle-button-update',{detail:on?'true':'false'}));
          const surface=()=>r.querySelector('.canvas-tile-surface'),viewport=r.querySelector('.canvas-viewport'),object=r.querySelector('.artifact-object');
          const pane=r.querySelector('.artifact-markup'),layer=()=>r.querySelector('[data-layer=rendering]');
          const W=1200,H=1600,zone=r.querySelector('.tei-page').dataset.textBlock.split(' ').map(p=>p.split(',').map(Number)).map(([x,y])=>[x/1000*W,y/1000*H]);
          // The image's pixels to the window, through the scan's pan and zoom and the registration's matrix3d.
          const toWindow=([x,y])=>{const v=viewport.getBoundingClientRect(),g=r.querySelector('.canvas-tile-compositor').getAttribute('transform').match(/-?[\d.]+(e-?\d+)?/g).map(Number),t=getComputedStyle(surface()).transform,m=new DOMMatrix(t==='none'?undefined:t);
            const q=m.transformPoint(new DOMPoint(g[0]+x*g[2],g[1]+y*g[2]));return [v.x+q.x/q.w,v.y+q.y/q.w]};
          const target=()=>{const [L,T,R,B]=laidOn(zone,inkBox(layer()));return [[L,T],[R,T],[R,B],[L,B]]};
          const off=()=>{const t=target();return Math.max(...zone.map((p,i)=>{const q=toWindow(p);return Math.hypot(q[0]-t[i][0],q[1]-t[i][1])}))};
          const place=()=>{const b=layer().getBoundingClientRect();return [Number(layer().dataset.zoom),b.x,b.y]};
          const opacity=()=>Number(getComputedStyle(object).opacity);
          const wheel=async(dy,fx,fy,n)=>{const b=pane.getBoundingClientRect();for(let i=0;i<n;i++){pane.dispatchEvent(new WheelEvent('wheel',{deltaY:dy,clientX:b.x+b.width*fx,clientY:b.y+b.height*fy,bubbles:true,cancelable:true}));await wait(20)}};
          await wheel(-40,0.3,0.3,6);await wait(300);
          const none=getComputedStyle(surface()).transform==='none';
          toggle(true);await wait(150);const midway=off(),midOpacity=opacity();
          await wait(650);const registered=off();
          const skewed=Math.abs(new DOMMatrix(getComputedStyle(surface()).transform).b)>0.001;
          const untrimmed=getComputedStyle(surface()).clipPath==='none';
          // The view fits the edition's page and all of the scan, centered.
          const pb=pane.getBoundingClientRect(),lb=layer().getBoundingClientRect();
          const scan=[[0,0],[W,0],[W,H],[0,H]].map(toWindow);
          const box=[Math.min(lb.left,...scan.map(p=>p[0])),Math.min(lb.top,...scan.map(p=>p[1])),Math.max(lb.right,...scan.map(p=>p[0])),Math.max(lb.bottom,...scan.map(p=>p[1]))];
          const fits=box[0]>=pb.left-1&&box[1]>=pb.top-1&&box[2]<=pb.right+1&&box[3]<=pb.bottom+1
            &&(Math.abs(box[2]-box[0]-pane.clientWidth)<1.5||Math.abs(box[3]-box[1]-pane.clientHeight)<1.5)
            &&Math.abs((box[0]+box[2])/2-(pb.left+pb.right)/2)<1.5&&Math.abs((box[1]+box[3])/2-(pb.top+pb.bottom)/2)<1.5;
          const detach=r.querySelector('.artifact-detach-toggle'),detachButton=detach.querySelector('button');
          const detachOn=!detach.hidden&&getComputedStyle(detach).display!=='none'&&detachButton.disabled&&detachButton.getAttribute('aria-disabled')==='true'&&detach.getAttribute('aria-pressed')==='false';
          const restOpacity=opacity();
          // Collective zoom and pan: never below the fit; at twice the fit, dragged and keyed, still registered.
          const fit=place()[0];
          await wheel(40,0.5,0.5,20);const floor=Math.abs(place()[0]-fit)<1e-6;
          for(let i=0;i<60&&place()[0]<2*fit;i++)await wheel(-40,0.5,0.5,1);
          const zoomed=place()[0]>=2*fit*0.98,zoomedOff=off();
          const before=place(),cx=pb.x+8,cy=pb.y+8;
          pane.dispatchEvent(new MouseEvent('mousedown',{clientX:cx,clientY:cy,button:0,detail:1,bubbles:true,cancelable:true}));window.dispatchEvent(new MouseEvent('mousemove',{clientX:cx+30,clientY:cy+40,bubbles:true}));window.dispatchEvent(new MouseEvent('mouseup',{bubbles:true}));await wait(60);
          const dragged=place(),pannedOff=off();
          pane.focus();pane.dispatchEvent(new KeyboardEvent('keydown',{key:'ArrowUp',bubbles:true,cancelable:true}));await wait(60);
          const keyed=place(),keyedOff=off();
          const panned=(dragged[1]!==before[1]||dragged[2]!==before[2])&&(keyed[2]!==dragged[2]);
          // Overlay off from three times the fit about the view's middle (the scan then fills its pane, no edge
          // of it held): the panes slide apart at the overlay's zoom; the text's middle and the scan's on one point.
          pane.dispatchEvent(new KeyboardEvent('keydown',{key:'0',bubbles:true,cancelable:true}));await wait(60);
          for(let i=0;i<90&&place()[0]<3*fit;i++)await wheel(-40,0.5,0.5,1);
          await wait(100);
          const zoom=place()[0];
          const text=inkBox(layer()),layerBox=layer().getBoundingClientRect();
          const laid=laidOn(zone,[(text[0]-layerBox.x)/zoom,(text[1]-layerBox.y)/zoom,(text[2]-layerBox.x)/zoom,(text[3]-layerBox.y)/zoom]);
          const back=homography([[laid[0],laid[1]],[laid[2],laid[1]],[laid[2],laid[3]],[laid[0],laid[3]]],zone);
          toggle(false);await wait(150);const offOpacity=opacity();await wait(850);
          const cleared=getComputedStyle(surface()).transform==='none';
          const kept=Math.abs(place()[0]-zoom)/zoom<0.01;
          const p2=pane.getBoundingClientRect(),l2=layer().getBoundingClientRect(),z2=place()[0];
          const textSpot=apply(back,[(p2.x+pane.clientLeft+pane.clientWidth/2-l2.x)/z2,(p2.y+pane.clientTop+pane.clientHeight/2-l2.y)/z2]);
          const v2=viewport.getBoundingClientRect(),g2=r.querySelector('.canvas-tile-compositor').getAttribute('transform').match(/-?[\d.]+(e-?\d+)?/g).map(Number);
          const scanSpot=[(v2.width/2-g2[0])/g2[2],(v2.height/2-g2[1])/g2[2]];
          const sameSpot=Math.hypot(textSpot[0]-scanSpot[0],textSpot[1]-scanSpot[1])*g2[2];
          const apart=window.innerWidth<=480||p2.right<=v2.left+1;
          const detachOff=!detachButton.disabled&&!detachButton.hasAttribute('aria-disabled')&&detach.getAttribute('aria-pressed')==='false';
          // Detached before the overlay: off and disabled while it is on, detached again after.
          const detachTo=on=>detach.dispatchEvent(new CustomEvent('toggle-button-update',{detail:on?'true':'false'}));
          detachTo(true);await wait(30);toggle(true);await wait(900);const detachedOn=detachButton.disabled&&detach.getAttribute('aria-pressed')==='false';
          toggle(false);await wait(900);const detachedAfter=!detachButton.disabled&&detach.getAttribute('aria-pressed')==='true';detachTo(false);await wait(30);
          // The opacity runs on the motion's own clock (user, 2026-10-14): frame by frame, it reaches its end
          // value on the frame the scan's warp and the text's zoom and place reach theirs, never before, each way.
          const frames=async on=>{const out=[];toggle(on);const began=performance.now();
            while(performance.now()-began<900){await new Promise(r=>requestAnimationFrame(r));const b=layer().getBoundingClientRect();out.push([opacity(),getComputedStyle(surface()).transform,layer().dataset.zoom+'|'+Math.round(b.x)+'|'+Math.round(b.y)])}
            const last=out[out.length-1],settle=k=>out.findIndex((f,i)=>out.slice(i).every(g=>g[k]===last[k]));
            return {together:Math.abs(settle(0)-settle(1))<=1&&Math.abs(settle(0)-settle(2))<=1,between:out.some(f=>f[0]>0.5&&f[0]<1)}};
          const clockOn=await frames(true),clockOff=await frames(false);
          const sameClock=clockOn.together&&clockOff.together&&clockOn.between&&clockOff.between;
          // Reduced motion: the end state at once, each way.
          const media=window.matchMedia;window.matchMedia=q=>q.includes('reduced-motion')?{matches:true}:media.call(window,q);
          const still=document.createElement('style');still.textContent='*{transition:none!important}';document.head.appendChild(still);
          toggle(true);await wait(80);const instantOn=off()<2&&opacity()===0.5;
          toggle(false);await wait(80);const instantOff=getComputedStyle(surface()).transform==='none'&&opacity()===1;
          window.matchMedia=media;still.remove();
          return [none,midway>registered+5,registered<2,skewed,untrimmed,fits,detachOn,midOpacity>0.5&&midOpacity<1,restOpacity===0.5,
            floor,zoomed&&zoomedOff<2,panned&&pannedOff<2&&keyedOff<2,offOpacity>0.5&&offOpacity<1,cleared&&kept,sameSpot<2,apart,detachOff,
            detachedOn&&detachedAfter,instantOn&&instantOff,sameClock,Math.round(registered*100)/100,Math.round(sameSpot*100)/100].map(Number);
        })()
        """#, as: [Double].self)
      let named = [
        "no registration before the overlay", "the registration eases in with the overlay's motion",
        "the zone's corners land on the laid ink box within 2px (off by \(checks[20]))", "the scan is turned by its measured skew",
        "no trim: the whole scan is drawn", "the edition's page and all of the scan fit the view, centered",
        "Detach present, disabled and off while the overlay is on", "the scan's opacity midway in, strictly between 1 and 0.5",
        "the scan at half opacity at rest", "the zoom never goes below the fit",
        "zoomed to twice the fit, the registration holds within 2px", "dragged and keyed, the text and the scan pan as one",
        "the scan's opacity midway out, strictly between 0.5 and 1", "overlay off: the registration gone, the overlay's zoom kept",
        "overlay off: the text's middle and the scan's on one point of the scan within 2px (off by \(checks[21]))",
        "overlay off: the panes side by side", "Detach enabled and off after",
        "detached before: off and disabled while on, detached again after", "with reduced motion the end state applies at once, on and off",
        "the opacity reaches its end on the frame the warp and the zoom reach theirs, on and off, passing between",
      ]
      for (check, name) in zip(checks, named) { #expect(check == 1, "\(name)") }
      try await page.expectNoErrors()
    }
  }

  /// A row of a Skeat canvas at rest in the overlay: the edition's ink
  /// (the reader's `InkExtent` rule, row by row) and the scan's under it, as
  /// drawn (top, bottom, left, right in the window's pixels).
  struct Row: Decodable {
    let text: String
    let edition: [Double]
    let scan: [Double]
  }

  /// The JS that finds each row of the edition's main text and the scan's
  /// ink under it: the scan sampled along the registered axes (a grid in
  /// the window, one scan pixel apart, each point read where the transforms
  /// take it on the image), so a tilted scan's line is a band the height
  /// of its type, never of its tilt; a fleck beside a line's end is none
  /// of its ink (layout_measure's `_without_specks`).
  static let rowsScript: String = {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    return (try? String(contentsOf: root.appendingPathComponent("web-tests/Fixtures/overlay-rows.js"), encoding: .utf8)) ?? ""
  }()

  /// Skeat's first ten canvases with a measured main text block
  /// (design-notes/skeat: each one's TEI with its zone, the work's frame,
  /// its scan), rendered by the dev server's TEI preview and overlaid by the
  /// client at rest (user, 2026-10-14). The fit policy: every row's top and
  /// bottom within 2px of the scan's, and a justified block's measure (its
  /// full rows' edges); a centered or ragged row's width is the face's, its
  /// center's offset reported only. Zoomed to twice the fit, the
  /// registration holds: each row's offsets twice what they were, within
  /// 2px.
  @Test(arguments: [2, 3, 4, 5, 6, 7, 9, 10], [1440, 440])
  func overlayLandsEachLineOfSkeat(canvas: Int, width: Int) async throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let assets = root.appendingPathComponent("gnorium-web/Public")
    let skeat = root.appendingPathComponent("design-notes/skeat")
    var tei = try String(contentsOf: skeat.appendingPathComponent("canvas-\(canvas).xml"), encoding: .utf8)
    struct Frame: Decodable { let body: Double; let measure: Double; let height: Double; let margin: Double }
    let frame = try JSONDecoder().decode(Frame.self, from: Data(contentsOf: skeat.appendingPathComponent("frame.json")))
    let scan = try Data(contentsOf: skeat.appendingPathComponent("scans/canvas-\(canvas).jpg"))
    // The page as a document holds it (gnorium-python `frame_rendition`):
    // the work's frame in its header, its facsimile before its text.
    guard let facsimile = tei.range(of: #"<facsimile\b[\s\S]*?</facsimile>"#, options: .regularExpression) else {
      Issue.record("canvas \(canvas) has no facsimile")
      return
    }
    let surface = String(tei[facsimile])
    tei.removeSubrange(facsimile)
    func number(_ value: Double) -> String { String(format: "%.2f", value) }
    let rendition = "font-size:\(number(frame.body))px;inline-size:\(number(frame.measure))em;block-size:\(number(frame.height))em;margin:\(number(frame.margin))em"
    let document = #"<TEI xmlns="http://www.tei-c.org/ns/1.0"><teiHeader><encodingDesc><tagsDecl><rendition xml:id="text-block" scheme="css" selector="text">"# + rendition + "</rendition></tagsDecl></encodingDesc></teiHeader>" + surface + "<text><body>" + tei + "</body></text></TEI>"
    var request = URLRequest(url: gnorium.baseURL.appendingPathComponent("testaments/tei-preview"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: ["tei": document])
    let preview = String(decoding: try await URLSession.shared.data(for: request).0, as: UTF8.self)
    guard let open = preview.range(of: "<body>"), let close = preview.range(of: "</body>", options: .backwards) else {
      Issue.record("the TEI preview has no body")
      return
    }
    let styles = preview[..<open.lowerBound].matches(of: #/<style[^>]*>[\s\S]*?<\/style>/#).map { String($0.output) }.joined()
    let view = String(preview[open.upperBound..<close.lowerBound]).replacing(#/data-service-id="[^"]*"/#, with: #"data-service-id="/scan""#)
    let css = try ["layout-view.css", "tei-view.css", "artifact-view.css", "canvas-view.css", "tooltip-view.css"].map {
      try String(contentsOf: assets.appendingPathComponent("style-sheets/" + $0), encoding: .utf8)
    }.joined(separator: "\n")
    let html = "<!doctype html><html><head><meta charset=\"utf-8\"><style>" + css + "</style>" + styles + #"""
      <style>body{margin:0}.artifact-view{width:100%;height:100vh}.artifact-viewer-container{height:calc(100vh - 40px);flex:none}</style><link rel="icon" href="data:,"></head><body><div class="artifact-view" data-canvas-shown="true" data-manifest-url="/manifest"><div class="artifact-viewer-container"><div class="artifact-markup-frame"><div class="artifact-markup">
      """# + view + #"""
      </div></div><div class="artifact-object"><div class="canvas-view" data-service-id="/scan"><div class="canvas-viewport"><div class="canvas-spinner"></div></div></div></div></div><footer><div class="artifact-overlay-toggle"><button>Overlay</button></div><div class="artifact-detach-toggle"><button class="button-view"><span class="button-icon">Detach</span></button></div></footer></div><script src="/loader.js"></script></body></html>
      """#
    // The scan's size, from its JPEG's frame header (SOF0–SOF2).
    let bytes = [UInt8](scan)
    var at = 2
    var size: (width: Int, height: Int)?
    while at + 9 < bytes.count, size == nil {
      let marker = bytes[at + 1]
      let length = Int(bytes[at + 2]) << 8 | Int(bytes[at + 3])
      if (0xC0...0xC2).contains(marker) {
        size = (Int(bytes[at + 7]) << 8 | Int(bytes[at + 8]), Int(bytes[at + 5]) << 8 | Int(bytes[at + 6]))
      }
      at += 2 + length
    }
    guard let size else {
      Issue.record("the scan's size is unread")
      return
    }
    var files: [String: FixtureServer.File] = [
      "/": .init(contentType: "text/html", body: Data(html.utf8)),
      "/loader.js": .init(contentType: "text/javascript", body: try Data(contentsOf: assets.appendingPathComponent("loader.js"))),
      "/client.wasm": .init(contentType: "application/wasm", body: try Data(contentsOf: assets.appendingPathComponent("client.wasm"))),
      "/manifest": .init(contentType: "application/json", body: Data(#"{"canvases":[{"id":"/scan","w":\#(size.width),"h":\#(size.height),"img":"/scan.jpg"}]}"#.utf8)),
      "/scan.jpg": .init(contentType: "image/jpeg", body: scan),
    ]
    // The faces the page sets in.
    for font in ["noto-serif.woff2", "noto-serif-italic.woff2", "noto-sans.woff2", "noto-sans-italic.woff2"] {
      files["/fonts/" + font] = .init(contentType: "font/woff2", body: try Data(contentsOf: assets.appendingPathComponent("fonts/" + font)))
    }
    let server = try await FixtureServer(files: files)
    defer { server.stop() }
    let config = BrowserTestConfiguration(baseURL: URL(string: server.baseURL)!, engines: [.chrome], defaultTimeout: .seconds(30))
    try await withPage(.chrome, config, viewport: .init(width: width, height: 900)) { page in
      try await page.goto("/")
      try await expect(page.locator("html")).toHaveAttribute("data-wasm-status", "started")
      try await page.evaluate("document.fonts.ready.then(()=>new Promise(resolve=>setTimeout(resolve,700)))")
      try await page.evaluate("document.querySelector('.artifact-overlay-toggle').dispatchEvent(new CustomEvent('toggle-button-update',{detail:'true'}))")
      // At rest: the motion and the panes' move done.
      try await page.evaluate("new Promise(resolve=>setTimeout(resolve,1200))")
      let rows = try await page.evaluate(Self.rowsScript, as: [Row].self)
      #expect(rows.count == Self.skeatRows[canvas], "canvas \(canvas)'s rows: \(rows.map(\.text))")
      // Each row's top and bottom.
      for row in rows {
        let vertical = max(abs(row.scan[0] - row.edition[0]), abs(row.scan[1] - row.edition[1]))
        #expect(vertical <= Self.landing, "\(row.text): \(row.edition) against the scan's \(row.scan)")
      }
      // Each row's width (user, 2026-10-14): its type's size and the print's spacing measured, a row's ink
      // is as wide as the scan's within the landing, but where the faces' letters differ in width
      // (`faceWidth`: a row of the print's face narrower or wider than Noto's at its measured size, never
      // shimmed), which is reported.
      for (index, row) in rows.enumerated() {
        let width = (row.scan[3] - row.scan[2]) - (row.edition[3] - row.edition[2])
        if Self.faceWidth[canvas, default: []].contains(index) {
          print("canvas \(canvas) row \(index) (\(row.text)): its width is the face's, \(String(format: "%+.1f", width))px from the print's")
        } else {
          #expect(abs(width) <= Self.landing * 2, "\(row.text): its width \(width)px from the print's")
        }
      }
      // A justified block's measure: its full rows' edges, in the median.
      if let widest = rows.map({ $0.edition[3] - $0.edition[2] }).max(), Self.justified.contains(canvas) {
        let full = rows.filter { $0.edition[3] - $0.edition[2] >= widest * 0.97 }
        func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }
        let edges = [median(full.map { $0.scan[2] - $0.edition[2] }), median(full.map { $0.scan[3] - $0.edition[3] })]
        #expect(edges.allSatisfy { abs($0) <= Self.landing }, "the justified measure's edges: \(edges)")
      }
      // Zoomed to twice the fit, about the page's middle: the registration
      // holds, each row's offsets twice what they were.
      let zoomed = try await page.evaluate(#"""
        (async()=>{const p=document.querySelector('.artifact-markup'),l=document.querySelector('.tei-page[data-active=true] [data-layer=rendering]'),b=p.getBoundingClientRect(),fit=Number(l.dataset.zoom);
          for(let i=0;i<80&&Number(l.dataset.zoom)<2*fit;i++){p.dispatchEvent(new WheelEvent('wheel',{deltaY:-40,clientX:b.x+b.width/2,clientY:b.y+b.height/2,bubbles:true,cancelable:true}));await new Promise(r=>setTimeout(r,16))}
          await new Promise(r=>setTimeout(r,300));return Number(l.dataset.zoom)/fit})()
        """#, as: Double.self)
      let twice = try await page.evaluate(Self.rowsScript, as: [Row].self)
      #expect(twice.count == rows.count)
      for (one, two) in zip(rows, twice) {
        let drift = (0..<2).map { abs((two.scan[$0] - two.edition[$0]) - zoomed * (one.scan[$0] - one.edition[$0])) }
        #expect(drift.allSatisfy { $0 <= Self.landing }, "\(one.text) at \(zoomed)× the fit: \(drift)")
      }
      try await page.expectNoErrors()
    }
  }

  /// How far a line's ink may land from the scan's (user, 2026-10-14).
  static let landing = 2.0
  /// Each canvas's rows of main text, its marginalia aside.
  static let skeatRows = [2: 1, 3: 3, 4: 4, 5: 17, 6: 4, 7: 19, 9: 39, 10: 40]
  /// The rows whose width no measured setting reaches (by canvas, from 0),
  /// reported, never shimmed: Noto's letters at the print's measured size
  /// and spacing wider or narrower than the print's (small capitals,
  /// italics, a ragged last line); canvas 7's contents rows span the work's
  /// frame, about a body em wider than canvas 7's print (the frame is
  /// canvas 10's, a scan 1.7% finer).
  static let faceWidth: [Int: Set<Int>] = [
    3: [0], 5: [6, 7, 9, 10, 13], 7: Set(1...18), 9: [18, 24, 28], 10: [13, 37, 38],
  ]
  /// The canvases set in justified paragraphs.
  static let justified: Set<Int> = [9, 10]
}
