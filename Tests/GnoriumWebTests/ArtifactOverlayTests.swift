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
            const zoomStart=Number(l.dataset.zoom);toggle(true);await wait(120);let mid=size();const opacityOnMid=Number(getComputedStyle(o).opacity),textOnMid=getComputedStyle(l).opacity;const zoomMid=Number(l.dataset.zoom);await wait(500);let after=size();
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
            toggle(false);await wait(120);const zoomOffMid=Number(l.dataset.zoom);const opacityOffMid=Number(getComputedStyle(o).opacity);await wait(480);const zoomBack=Number(l.dataset.zoom);const zoomReturned=fitted<zoomOffMid&&zoomOffMid<zoomBack&&Math.abs(zoomBack-zoomStart)<0.01;const dim=window.innerWidth>480?0:1;
            const detachOff=!button.disabled&&!button.hasAttribute('aria-disabled')&&d.getAttribute('aria-pressed')==='false';
            const panesBack=Math.abs(size()[dim]-before[dim])<1;
            // Detached before the overlay: off and disabled while it is on (the panes synced as overlaid),
            // detached again after.
            const detachTo=on=>d.dispatchEvent(new CustomEvent('toggle-button-update',{detail:on?'true':'false'}));
            detachTo(true);await wait(30);const detachedBefore=d.getAttribute('aria-pressed')==='true'&&!button.disabled;
            toggle(true);await wait(600);const detachedOn=button.disabled&&button.getAttribute('aria-disabled')==='true'&&d.getAttribute('aria-pressed')==='false';
            toggle(false);await wait(600);const detachedAfter=!button.disabled&&!button.hasAttribute('aria-disabled')&&d.getAttribute('aria-pressed')==='true';
            detachTo(false);await wait(30);
            return [zoomReturned,before[dim]<mid[dim]&&mid[dim]<after[dim],whole&&zoomAnimated,locked,detachOn,rules.imageOpacity==='0'&&rules.textOpacity==='1',rules.bg==='rgba(0, 0, 0, 0)'&&!r.querySelector('.artifact-structure'),detachOff,panesBack,detachedBefore&&detachedOn&&detachedAfter,opacityOnMid>0&&opacityOnMid<1&&opacityOffMid>0&&opacityOffMid<1&&textOnMid==='1'];
           })()
        """#, as: [Bool].self)
      let named = [
        "zoom back animated", "the panes move", "the whole page fits, zoom animated", "no gesture moves the scan or the text",
        "Detach present, disabled and off while on", "at rest the scan faded out, the text opaque",
        "the text on no ground of its own; no structure without a measured text block",
        "Detach enabled and off after", "panes back", "detached before: off and disabled while on, detached again after",
        "the scan fades on the overlay's clock, both ways, the text never",
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
    const inkBox=layer => inkOf(layer, layer.querySelector('.tei-text-block') || layer, true);
    // One element's text's ink (a line's), no rule or frame.
    const inkIn=element => inkOf(element, element, false);
    const inkOf=(layer, frame, ruled) => {
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
      if (ruled) for (const drawn of frame.querySelectorAll('.tei-rule, .tei-figure-image, .tei-frame')) {
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
  /// (`data-text-block`, a skewed quadrilateral in the 0–1000 space) and
  /// its measured lines (`data-scan-layout`, the tools' zones), overlay on
  /// draws the structure overlay (user, 2026-10-14): the edition's lines
  /// solid and the scan's dashed, laid by the homography that takes the
  /// text block's corners onto the rendered main text's ink box (by its
  /// height, centered, the scan's proportions kept), the scan fading out
  /// and the lines fading in on the overlay's one clock, the text never
  /// fading, no scan pixels at rest; a pair within a quarter of the body's leading quiet, one past it
  /// orange, an edition line the scan lacks green, a scan line the edition
  /// lacks red. The view fits the edition's page and the scan's structure,
  /// centered; at rest the reader zooms and pans both as one, never below
  /// the fit, the registration kept at every zoom; Detach is disabled and
  /// off. Overlay off slides the panes apart at the overlay's zoom, the
  /// text's middle and the scan's on one point of the scan, Detach as it
  /// was.
  @Test(arguments: [1440, 440])
  func overlayDrawsTheScansStructureOverTheEditions(width: Int) async throws {
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
      "/manifest": .init(contentType: "application/json", body: Data(#"{"canvases":[{"id":"/scan","w":4800,"h":6400,"img":"/scan.svg"}]}"#.utf8)),
      "/scan.svg": .init(contentType: "image/svg+xml", body: Data(#"<svg xmlns="http://www.w3.org/2000/svg" width="4800" height="6400"/>"#.utf8)),
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
          const pane=r.querySelector('.artifact-markup'),layer=()=>r.querySelector('[data-layer=rendering]'),pageEl=r.querySelector('.tei-page');
          // A scan four times the text's actual size: room to zoom the overlay past twice its fit.
          const W=4800,H=6400,zone=pageEl.dataset.textBlock.split(' ').map(p=>p.split(',').map(Number)).map(([x,y])=>[x/1000*W,y/1000*H]);
          // The scan's measured lines, planted as the tools would write them: each edition line's ink taken
          // back through the registration into the 0–1000 space, but line 10 (the edition's alone), the last
          // half a leading low (a pair off) and one more line two leadings under it (the scan's alone).
          const zoom0=Number(layer().dataset.zoom),lb0=layer().getBoundingClientRect();
          const toLayer=([x,y])=>[(x-lb0.x)/zoom0,(y-lb0.y)/zoom0];
          const [L,T,R,B]=laidOn(zone,[...toLayer(inkBox(layer()).slice(0,2)),...toLayer(inkBox(layer()).slice(2))]);
          const back=homography([[L,T],[R,T],[R,B],[L,B]],zone);
          const rows=[...layer().querySelectorAll('.tei-line')].map(line=>{const [l,t,r2,b]=inkIn(line);return [...toLayer([l,t]),...toLayer([r2,b])]});
          const pitch=rows[1][1]-rows[0][1],rem=parseFloat(getComputedStyle(layer().querySelector('.tei-text-block')).fontSize);
          pageEl.dataset.bodyLeading=String(pitch/rem);
          const quad=([l,t,r2,b])=>[[l,t],[r2,t],[r2,b],[l,b]].map(p=>apply(back,p)).map(([x,y])=>(x/W*1000).toFixed(2)+','+(y/H*1000).toFixed(2)).join(' ');
          const planted=rows.map((row,i)=>i===29?[row[0],row[1]+pitch/2,row[2],row[3]+pitch/2]:row).filter((row,i)=>i!==9);
          const last=rows[rows.length-1];planted.push([last[0],last[1]+2*pitch,last[2],last[3]+2*pitch]);
          pageEl.dataset.scanLayout=['block main '+zone.map(([x,y])=>(x/W*1000)+' '+(y/H*1000)).join(' ').replace(/,/g,' ')]
            .concat(planted.map(row=>'line - '+quad(row).replace(/[ ,]/g,' '))).join(';');
          // Its scan block's corners in the window, as drawn, and where the registration lays them.
          const scanBlock=()=>{const p=r.querySelector('.artifact-structure [data-side=scan][data-kind=block]');if(!p)return null;const b=layer().getBoundingClientRect(),z=Number(layer().dataset.zoom);
            return p.getAttribute('points').split(' ').map(q=>q.split(',').map(Number)).map(([x,y])=>[b.x+x*z,b.y+y*z])};
          const target=()=>{const [L,T,R,B]=laidOn(zone,inkBox(layer()));return [[L,T],[R,T],[R,B],[L,B]]};
          const off=()=>{const s=scanBlock(),t=target();return s?Math.max(...s.map((q,i)=>Math.hypot(q[0]-t[i][0],q[1]-t[i][1]))):Infinity};
          const place=()=>{const b=layer().getBoundingClientRect();return [Number(layer().dataset.zoom),b.x,b.y]};
          const states=side=>[...new Map([...r.querySelectorAll('.artifact-structure [data-side='+side+'][data-kind=line]')].map(e=>[e.dataset.row,e.dataset.state])).values()];
          const wheel=async(dy,fx,fy,n)=>{const b=pane.getBoundingClientRect();for(let i=0;i<n;i++){pane.dispatchEvent(new WheelEvent('wheel',{deltaY:dy,clientX:b.x+b.width*fx,clientY:b.y+b.height*fy,bubbles:true,cancelable:true}));await wait(20)}};
          await wheel(-40,0.3,0.3,6);await wait(300);
          // Coming on, midway: the scan fading out, the structure's lines fading in, the text itself.
          const fades=()=>{const s=r.querySelector('.artifact-structure');return [Number(getComputedStyle(object).opacity),s?Number(getComputedStyle(s).opacity):-1,getComputedStyle(layer()).opacity]};
          toggle(true);await wait(150);const onMid=fades();
          await wait(650);
          const registered=off();const atRest=fades();
          // At rest: the scan unwarped and faded out, the structure whole; the planted divergences marked, every other line quiet.
          const unwarped=getComputedStyle(surface()).transform==='none'&&atRest[0]===0&&atRest[1]===1&&atRest[2]==='1';
          const between=f=>f[0]>0&&f[0]<1&&f[1]>0&&f[1]<1&&f[2]==='1';
          const edition=states('edition'),scan=states('scan');
          const count=(list,state)=>list.filter(s=>s===state).length;
          const marked=edition.length===30&&scan.length===30&&count(edition,'extra')===1&&count(edition,'off')===1&&count(scan,'off')===1
            &&count(scan,'missing')===1&&count(edition,'within')===28&&count(scan,'within')===28;
          const strokes=(()=>{const q=r.querySelector('.artifact-structure [data-side=edition][data-state=within]'),o=r.querySelector('.artifact-structure [data-state=off]'),s=r.querySelector('.artifact-structure [data-side=scan]');
            return getComputedStyle(q).strokeWidth==='1px'&&getComputedStyle(o).strokeWidth==='2px'&&getComputedStyle(q).strokeDasharray==='none'&&getComputedStyle(s).strokeDasharray!=='none'})();
          // The view fits the edition's page and the scan's structure, centered.
          const pb=pane.getBoundingClientRect(),lb=layer().getBoundingClientRect(),reach=scanBlock()||[];
          const box=[Math.min(lb.left,...reach.map(p=>p[0])),Math.min(lb.top,...reach.map(p=>p[1])),Math.max(lb.right,...reach.map(p=>p[0])),Math.max(lb.bottom,...reach.map(p=>p[1]))];
          const fits=box[0]>=pb.left-1&&box[1]>=pb.top-1&&box[2]<=pb.right+1&&box[3]<=pb.bottom+1
            &&(Math.abs(box[2]-box[0]-pane.clientWidth)<1.5||Math.abs(box[3]-box[1]-pane.clientHeight)<1.5)
            &&Math.abs((box[0]+box[2])/2-(pb.left+pb.right)/2)<1.5&&Math.abs((box[1]+box[3])/2-(pb.top+pb.bottom)/2)<1.5;
          const detach=r.querySelector('.artifact-detach-toggle'),detachButton=detach.querySelector('button');
          const detachOn=!detach.hidden&&getComputedStyle(detach).display!=='none'&&detachButton.disabled&&detachButton.getAttribute('aria-disabled')==='true'&&detach.getAttribute('aria-pressed')==='false';
          // Collective zoom and pan: never below the fit; at twice the fit, dragged and keyed, still registered.
          const fit=place()[0];
          await wheel(40,0.5,0.5,20);const floor=Math.abs(place()[0]-fit)<1e-6;
          for(let i=0;i<60&&place()[0]<2*fit;i++)await wheel(-40,0.5,0.5,1);
          const zoomed=place()[0]>=2*fit*0.98,zoomedOff=off();
          // A drag from the blank right of the lines (a press on text selects it).
          const before=place(),cx=pb.right-8,cy=pb.y+pb.height/2;
          pane.dispatchEvent(new MouseEvent('mousedown',{clientX:cx,clientY:cy,button:0,detail:1,bubbles:true,cancelable:true}));window.dispatchEvent(new MouseEvent('mousemove',{clientX:cx-30,clientY:cy+40,bubbles:true}));window.dispatchEvent(new MouseEvent('mouseup',{bubbles:true}));await wait(60);
          const dragged=place(),pannedOff=off();
          // The key away from the edge the drag moved toward.
          pane.focus();pane.dispatchEvent(new KeyboardEvent('keydown',{key:'ArrowDown',bubbles:true,cancelable:true}));await wait(60);
          const keyed=place(),keyedOff=off();
          const panned=(dragged[1]!==before[1]||dragged[2]!==before[2])&&(keyed[2]!==dragged[2]);
          // Overlay off from three times the fit about the view's middle: the panes slide apart at the
          // overlay's zoom; the text's middle and the scan's on one point of the scan.
          pane.dispatchEvent(new KeyboardEvent('keydown',{key:'0',bubbles:true,cancelable:true}));await wait(60);
          for(let i=0;i<90&&place()[0]<3*fit;i++)await wheel(-40,0.5,0.5,1);
          await wait(100);
          const zoom=place()[0];
          const text=inkBox(layer()),layerBox=layer().getBoundingClientRect();
          const laid=laidOn(zone,[(text[0]-layerBox.x)/zoom,(text[1]-layerBox.y)/zoom,(text[2]-layerBox.x)/zoom,(text[3]-layerBox.y)/zoom]);
          const backward=homography([[laid[0],laid[1]],[laid[2],laid[1]],[laid[2],laid[3]],[laid[0],laid[3]]],zone);
          // The image's box on screen, through its pan and zoom.
          const imageBox=()=>{const v=viewport.getBoundingClientRect(),g=r.querySelector('.canvas-tile-compositor').getAttribute('transform').match(/-?[\d.]+(e-?\d+)?/g).map(Number);return [v.x+g[0],v.y+g[1],W*g[2],H*g[2]]};
          const exitFrom=imageBox();
          toggle(false);await wait(150);const offMid=fades(),exitMid=imageBox();await wait(850);const exitTo=imageBox();
          // Midway out, the image between where the overlay laid it and its own view: moving into its pane
          // (its place strictly between on an axis it moves along), its size between (the panes part at the
          // overlay's zoom, so it may keep it), never jumping to either end.
          const strictly=(a,m,b)=>Math.min(a,b)<m&&m<Math.max(a,b),within=(a,m,b)=>Math.min(a,b)-0.5<=m&&m<=Math.max(a,b)+0.5;
          const exitMoving=[0,1].some(k=>strictly(exitFrom[k],exitMid[k],exitTo[k]))&&within(exitFrom[2],exitMid[2],exitTo[2])&&within(exitFrom[3],exitMid[3],exitTo[3]);const gone=!r.querySelector('.artifact-structure')&&getComputedStyle(object).opacity==='1';
          const kept=Math.abs(place()[0]-zoom)/zoom<0.01;
          const p2=pane.getBoundingClientRect(),l2=layer().getBoundingClientRect(),z2=place()[0];
          const textSpot=apply(backward,[(p2.x+pane.clientLeft+pane.clientWidth/2-l2.x)/z2,(p2.y+pane.clientTop+pane.clientHeight/2-l2.y)/z2]);
          const v2=viewport.getBoundingClientRect(),g2=r.querySelector('.canvas-tile-compositor').getAttribute('transform').match(/-?[\d.]+(e-?\d+)?/g).map(Number);
          const scanSpot=[(v2.width/2-g2[0])/g2[2],(v2.height/2-g2[1])/g2[2]];
          const sameSpot=Math.hypot(textSpot[0]-scanSpot[0],textSpot[1]-scanSpot[1])*g2[2];
          const apart=window.innerWidth<=480||p2.right<=v2.left+1;
          const detachOff=!detachButton.disabled&&!detachButton.hasAttribute('aria-disabled')&&detach.getAttribute('aria-pressed')==='false';
          const detachTo=on=>detach.dispatchEvent(new CustomEvent('toggle-button-update',{detail:on?'true':'false'}));
          detachTo(true);await wait(30);toggle(true);await wait(900);const detachedOn=detachButton.disabled&&detach.getAttribute('aria-pressed')==='false';
          toggle(false);await wait(900);const detachedAfter=!detachButton.disabled&&detach.getAttribute('aria-pressed')==='true';detachTo(false);await wait(30);
          // Reduced motion: the end state at once, each way.
          const media=window.matchMedia;window.matchMedia=q=>q.includes('reduced-motion')?{matches:true}:media.call(window,q);
          const still=document.createElement('style');still.textContent='*{transition:none!important}';document.head.appendChild(still);
          toggle(true);await wait(80);const instantOn=off()<2&&fades()[0]===0&&fades()[1]===1;
          toggle(false);await wait(80);const instantOff=!r.querySelector('.artifact-structure')&&getComputedStyle(object).opacity==='1';
          window.matchMedia=media;still.remove();
          return [registered<2,unwarped,marked,strokes,fits,detachOn,floor,zoomed&&zoomedOff<2,panned&&pannedOff<2&&keyedOff<2,gone&&kept,sameSpot<2,apart,detachOff,
            detachedOn&&detachedAfter,instantOn&&instantOff,Math.round(registered*100)/100,Math.round(sameSpot*100)/100,edition.length,scan.length,count(edition,'extra'),count(edition,'off'),count(scan,'off'),count(scan,'missing'),zoomedOff,pannedOff,keyedOff,between(onMid)&&between(offMid),exitMoving].map(Number);
        })()
        """#, as: [Double].self)
      let named = [
        "the scan's block corners land on the laid ink box within 2px (off by \(checks[15]))",
        "at rest no scan pixels: the scan unwarped and faded out, the structure whole, the text opaque",
        "the planted divergences marked (one extra, one pair off, one missing), every other line quiet (rows \(checks[17]), \(checks[18]); extra \(checks[19]), off \(checks[20]), \(checks[21]), missing \(checks[22]))",
        "quiet strokes 1px, marked 2px, the edition's solid, the scan's dashed",
        "the edition's page and the scan's structure fit the view, centered",
        "Detach present, disabled and off while the overlay is on", "the zoom never goes below the fit",
        "zoomed to twice the fit, the registration holds within 2px (off by \(checks[23]))", "dragged and keyed, the text and its structure pan as one (off by \(checks[24]), \(checks[25])))",
        "overlay off: the structure gone, the overlay's zoom kept",
        "overlay off: the text's middle and the scan's on one point of the scan within 2px (off by \(checks[16]))",
        "overlay off: the panes side by side", "Detach enabled and off after",
        "detached before: off and disabled while on, detached again after", "with reduced motion the end state applies at once, on and off",
      ]
      for (check, name) in zip(checks, named) { #expect(check == 1, "\(name)") }
      #expect(checks[26] == 1, "midway, each way, the scan and the structure's lines strictly between, the text opaque")
      #expect(checks[27] == 1, "midway out, the image's box between the overlay's and its own pane's")
      try await page.expectNoErrors()
    }
  }

  /// The structure overlay's scene, worked out apart from the reader (the
  /// rule of `StructurePairing` and gnorium-python's structure image, step
  /// for step): the edition's rows (each line's ink, side by side one row),
  /// main text and marginalia apart, and the scan's lines (`data-scan-layout`)
  /// laid in the layer by the registration, paired by dynamic programming,
  /// each row's state; `{edition: [...], scan: [...], main: [top, bottom] of
  /// the scan's main blocks laid, target: [top, bottom] of the laid ink box}`
  /// in the window's pixels.
  static let structureScript = Self.shared + #"""
    const structureOf=()=>{
      const r=document.querySelector('.artifact-view'),page=r.querySelector('.tei-page[data-active=true]'),layer=page.querySelector('[data-layer=rendering]'),frame=layer.querySelector('.tei-text-block')||layer;
      const b=layer.getBoundingClientRect(),z=Number(layer.dataset.zoom),toLayer=([x,y])=>[(x-b.x)/z,(y-b.y)/z];
      const context=document.createElement('canvas').getContext('2d'),range=document.createRange();
      const rectOf=(node,start,end)=>{range.setStart(node,start);range.setEnd(node,end);return range.getBoundingClientRect()};
      const rowsOf=roots=>{const lines=[];for(const root of roots){const walker=document.createTreeWalker(root,NodeFilter.SHOW_TEXT);
        for(let node=walker.nextNode();node;node=walker.nextNode()){const text=node.data;if(!/[^ \t\n\r]/.test(text))continue;
          const style=getComputedStyle(node.parentElement);context.font=style.fontStyle+' '+style.fontWeight+' '+style.fontSize+' '+style.fontFamily;context.fontVariantCaps=style.fontVariantCaps;context.fontKerning=style.fontKerning;
          // Its setting across (the edges the print aligns) and its type's em in the window's pixels.
          const ta=style.textAlign,rtl=style.direction==='rtl',setting=ta==='justify'?'justified':ta==='center'?'center':(ta==='right'||(ta==='end'&&!rtl)||(ta==='start'&&rtl))?'right':'left';
          const lineEm=parseFloat(style.fontSize)*z,blockEl=node.parentElement.closest('.tei-block');
          const found=[];for(let at=0;at<text.length;){const end=at+(text.codePointAt(at)>0xffff?2:1);if(!/[ \t\n\r]/.test(text[at])){const rect=rectOf(node,at,end);if(rect.height>0){const last=found[found.length-1];
            if(last&&rect.top<last.bottom&&last.top<rect.bottom){last.end=end;last.glyphs[1]=[at,end,rect]}else found.push({start:at,end,top:rect.top,bottom:rect.bottom,glyphs:[[at,end,rect],[at,end,rect]]})}}at=end}
          for(const line of found){const drawn=rectOf(node,line.start,line.end),m=context.measureText(text.slice(line.start,line.end)),s=drawn.height/(m.fontBoundingBoxAscent+m.fontBoundingBoxDescent);
            const top=drawn.top+(m.fontBoundingBoxAscent-m.actualBoundingBoxAscent)*s,bottom=drawn.bottom-(m.fontBoundingBoxDescent-m.actualBoundingBoxDescent)*s;
            let left=Infinity,right=-Infinity;for(const [st,en,rect] of line.glyphs){const g=context.measureText(text.slice(st,en));left=Math.min(left,rect.left-g.actualBoundingBoxLeft*s);right=Math.max(right,rect.left+g.actualBoundingBoxRight*s)}
            if(right>left&&bottom>top)lines.push([left,top,right,bottom,setting,lineEm,blockEl])}}}
        lines.sort((a,c)=>a[1]-c[1]);const rows=[];for(const l of lines){const last=rows[rows.length-1];if(last&&l[1]<last[3]){last[0]=Math.min(last[0],l[0]);last[2]=Math.max(last[2],l[2]);last[3]=Math.max(last[3],l[3])}else rows.push([...l])}
        // A justified block's last line is set from its start alone.
        rows.forEach((row,k)=>{if(row[4]==='justified'&&row[6]&&!rows.slice(k+1).some(o=>o[6]===row[6]))row[4]='left'});return rows};
      const editionMain=rowsOf([frame]);
      // The edition's notes: each child of a margin area, its rows, box and sides.
      const notes=[];for(const margin of layer.querySelectorAll('.tei-margin')){const place=margin.dataset.place||'',sides=[];
        if(place.startsWith('top'))sides.push('top');if(place.startsWith('bottom'))sides.push('bottom');if(place.endsWith('left'))sides.push('margin-left');if(place.endsWith('right'))sides.push('margin-right');
        for(const note of margin.querySelectorAll(':scope > *')){const rows=rowsOf([note]);if(!rows.length)continue;
          notes.push({rows,sides,box:[Math.min(...rows.map(r=>r[0])),Math.min(...rows.map(r=>r[1])),Math.max(...rows.map(r=>r[2])),Math.max(...rows.map(r=>r[3]))]})}}
      const img=JSON.parse(document.querySelector('#manifest-size').textContent),W=img[0],H=img[1];
      const zone=page.dataset.textBlock.split(' ').map(p=>p.split(',').map(Number)).map(([x,y])=>[x/1000*W,y/1000*H]);
      // Laid as the reader lays it: a derived block on the frame whole; a block spanning the frame's
      // measure (its ink at both sides within a word space of the frame's face) on its ink box whole; any
      // other by its height, centered.
      const ink=inkBox(layer),edges=frame.getBoundingClientRect(),fs=getComputedStyle(frame);
      context.font=fs.fontStyle+' '+fs.fontWeight+' '+fs.fontSize+' '+fs.fontFamily;const space=context.measureText(' ').width*z;
      const spans=!!ink&&frame!==layer&&ink[0]-edges.left<=space&&edges.right-ink[2]<=space;
      const laid=page.dataset.textBlockDerived==='true'?[edges.left,edges.top,edges.right,edges.bottom]:spans?ink:laidOn(zone,ink);
      const h=homography(zone,[[laid[0],laid[1]],[laid[2],laid[1]],[laid[2],laid[3]],[laid[0],laid[3]]]);
      const quads=[],marginBlocks=[];let main=true;
      for(const entry of page.dataset.scanLayout.split(';')){const p=entry.split(' ');const pts=p.slice(2).map(Number);const q=[0,1,2,3].map(i=>apply(h,[pts[2*i]/1000*W,pts[2*i+1]/1000*H]));
        const box=[Math.min(...q.map(v=>v[0])),Math.min(...q.map(v=>v[1])),Math.max(...q.map(v=>v[0])),Math.max(...q.map(v=>v[1]))];
        if(p[0]==='block'){main=p[1]!=='marginalia';quads.push({kind:'block',main,box});if(!main)marginBlocks.push({box,lines:[]})}
        else if(p[0]==='line'){quads.push({kind:'line',main,box});if(!main&&marginBlocks.length)marginBlocks[marginBlocks.length-1].lines.push(box)}}
      const rowsFrom=lines=>{lines.sort((a,c)=>a[1]-c[1]);const rows=[];for(const l of lines){const last=rows[rows.length-1];if(last&&l[1]<last[3]){last[0]=Math.min(last[0],l[0]);last[2]=Math.max(last[2],l[2]);last[3]=Math.max(last[3],l[3])}else rows.push([...l])}return rows};
      const scanMain=rowsFrom(quads.filter(q=>q.kind==='line'&&q.main).map(q=>q.box));
      // Each scan block of marginalia to the nearest note on its side of the frame.
      const F=(()=>{const e=frame.getBoundingClientRect();return [e.left,e.top,e.right,e.bottom]})();
      const sidesOf=([l,t,r2,b])=>{const beyond=[['top',F[1]-b],['bottom',t-F[3]],['margin-left',F[0]-r2],['margin-right',l-F[2]]],clear=beyond.filter(x=>x[1]>=0).map(x=>x[0]);
        if(clear.length)return clear;const m=(t+b)/2,c=(l+r2)/2,near=[['top',m-F[1]],['bottom',F[3]-m],['margin-left',c-F[0]],['margin-right',F[2]-c]];return [near.reduce((a,x)=>x[1]<a[1]?x:a)[0]]};
      const dist=(a,c)=>Math.abs(a[0]-c[0])+Math.abs(a[1]-c[1])+Math.abs(a[2]-c[2])+Math.abs(a[3]-c[3]);
      const gathered=notes.map(()=>[]),alone=[];
      for(const block of marginBlocks){const sides=sidesOf(block.box);let best=-1,far=Infinity;
        notes.forEach((note,i)=>{if(note.sides.some(x=>sides.includes(x))){const d=dist(note.box,block.box);if(d<far){far=d;best=i}}});
        if(best>=0)gathered[best].push(...block.lines);else alone.push(...block.lines)}
      const L=Number(page.dataset.bodyLeading)*parseFloat(getComputedStyle(frame).fontSize)*z;
      // Across: the edges the edition's line is set by, past an em of its type.
      const across=(e,s)=>{const em=e[5],set=e[4];if(!(em>0)||!set)return true;const l=Math.abs(e[0]-s[0])<=em,r=Math.abs(e[2]-s[2])<=em;
        return set==='left'?l:set==='right'?r:set==='center'?Math.abs((e[0]+e[2])/2-(s[0]+s[2])/2)<=em:l&&r};
      // Paired on e and s (each from its own box for a note), judged where each stands (E, S), by L.
      const pair=(e,s,L,E=e,S=s)=>{const n=e.length,m=s.length,c=[...Array(n+1)].map(()=>Array(m+1).fill(0)),st=[...Array(n+1)].map(()=>Array(m+1).fill(0));
        for(let i=0;i<=n;i++)for(let j=0;j<=m;j++){if(!i&&!j)continue;let best=Infinity,mv=0;if(i&&j)best=c[i-1][j-1]+Math.abs(e[i-1][1]-s[j-1][1])+Math.abs(e[i-1][3]-s[j-1][3]);
          if(i&&c[i-1][j]+L<best){best=c[i-1][j]+L;mv=1}if(j&&c[i][j-1]+L<best){best=c[i][j-1]+L;mv=2}c[i][j]=best;st[i][j]=mv}
        const es=Array(n).fill('within'),ss=Array(m).fill('within');let i=n,j=m;
        while(i||j){const mv=st[i][j];if(mv===0){const ok=Math.abs(E[i-1][1]-S[j-1][1])<=L/4&&Math.abs(E[i-1][3]-S[j-1][3])<=L/4&&across(E[i-1],S[j-1]);es[i-1]=ss[j-1]=ok?'within':'off';i--;j--}else if(mv===1){es[i-1]='extra';i--}else{ss[j-1]='missing';j--}}
        return [es,ss]};
      const moved=(rows,[x,y])=>rows.map(r=>[r[0]-x,r[1]-y,r[2]-x,r[3]-y]);
      const [em,sm]=pair(editionMain,scanMain,L);const eg=[],sg=[];
      // A note's own L: its scan rows' median pitch, else its edition rows', else the body's.
      const pitch=rows=>{if(rows.length<2)return null;const d=rows.slice(1).map((r,k)=>r[1]-rows[k][1]).sort((a,c)=>a-c);return d[Math.floor(d.length/2)]};
      notes.forEach((note,i)=>{const rows=rowsFrom(gathered[i]);const reach=rows.length?[Math.min(...rows.map(r=>r[0])),Math.min(...rows.map(r=>r[1]))]:[note.box[0],note.box[1]];
        const own=pitch(rows)||pitch(note.rows)||L;
        const [e,s2]=pair(moved(note.rows,[note.box[0],note.box[1]]),moved(rows,reach),own,note.rows,rows);eg.push(...e);sg.push(...s2)});
      sg.push(...pair([],rowsFrom(alone),L)[1]);
      const mainBlocks=quads.filter(q=>q.kind==='block'&&q.main).map(q=>q.box);
      return {edition:em.concat(eg),scan:sm.concat(sg),main:mainBlocks.length?[Math.min(...mainBlocks.map(q=>q[1])),Math.max(...mainBlocks.map(q=>q[3]))]:[],target:[laid[1],laid[3]]}};
    const drawnStates=side=>[...new Map([...document.querySelectorAll('.artifact-structure [data-side='+side+'][data-kind=line]')].map(e=>[e.dataset.row,e.dataset.state])).values()];
    """#

  /// What the scene counts: each state's lines, each side.
  struct Scene: Decodable {
    let expected: [String: [String: Int]]
    let drawn: [String: [String: Int]]
    let main: [Double]
    let target: [Double]
  }

  /// Skeat's first ten canvases with a text block zone and the tools'
  /// measured layout (canvas 2's zone derived: the work frame placed on a
  /// scan with no main text) (design-notes/skeat: each one's TEI with its
  /// zones and the witness's renditions, `header.xml`; its scan), rendered
  /// by the dev server's TEI preview (its words marked, as a reader's) and
  /// read by the client (user, 2026-10-14). Side by side, a word of the
  /// edition bands its word on the scan, and the band's word on the scan
  /// marks the edition's. Overlay on draws the structure: the scan's main
  /// blocks laid on the rendered main text's ink box by its height, and
  /// every line's state as the pairing rule gives it, worked out apart;
  /// zoomed to twice the fit, the registration holds. Each canvas's marked
  /// lines are reported.
  @Test(arguments: [2, 3, 4, 5, 6, 7, 9, 10], [1440, 440])
  func structureOverlayAndWordsOfSkeat(canvas: Int, width: Int) async throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let assets = root.appendingPathComponent("gnorium-web/Public")
    let skeat = root.appendingPathComponent("design-notes/skeat")
    var tei = try String(contentsOf: skeat.appendingPathComponent("canvas-\(canvas).xml"), encoding: .utf8)
    let renditions = try String(contentsOf: skeat.appendingPathComponent("header.xml"), encoding: .utf8)
    let scan = try Data(contentsOf: skeat.appendingPathComponent("scans/canvas-\(canvas).jpg"))
    guard let facsimile = tei.range(of: #"<facsimile\b[\s\S]*?</facsimile>"#, options: .regularExpression) else {
      Issue.record("canvas \(canvas) has no facsimile")
      return
    }
    let surface = String(tei[facsimile])
    #expect(surface.contains(#"type="line""#), "canvas \(canvas) keeps no measured lines")
    tei.removeSubrange(facsimile)
    let document = #"<TEI xmlns="http://www.tei-c.org/ns/1.0"><teiHeader><encodingDesc><tagsDecl>"# + renditions + "</tagsDecl></encodingDesc></teiHeader>" + surface + "<text><body>" + tei + "</body></text></TEI>"
    var request = URLRequest(url: gnorium.baseURL.appendingPathComponent("testaments/tei-preview"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: ["tei": document, "words": true])
    let preview = String(decoding: try await URLSession.shared.data(for: request).0, as: UTF8.self)
    guard let open = preview.range(of: "<body>"), let close = preview.range(of: "</body>", options: .backwards) else {
      Issue.record("the TEI preview has no body")
      return
    }
    let styles = preview[..<open.lowerBound].matches(of: #/<style[^>]*>[\s\S]*?<\/style>/#).map { String($0.output) }.joined()
    let view = String(preview[open.upperBound..<close.lowerBound]).replacing(#/data-service-id="[^"]*"/#, with: #"data-service-id="/scan""#)
    let css = try [
      "layout-view.css", "tei-view.css", "artifact-view.css", "canvas-view.css", "tooltip-view.css", "sheet-view.css",
      "dialog-sheet-view.css", "gloss-sheet-view.css",
    ].map {
      try String(contentsOf: assets.appendingPathComponent("style-sheets/" + $0), encoding: .utf8)
    }.joined(separator: "\n")
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
    let html = "<!doctype html><html><head><meta charset=\"utf-8\"><style>" + css + "</style>" + styles + #"""
      <style>body{margin:0}.artifact-view{width:100%;height:100vh}.artifact-viewer-container{height:calc(100vh - 40px);flex:none}</style><link rel="icon" href="data:,"></head><body><script type="application/json" id="manifest-size">[\#(size.width),\#(size.height)]</script><div class="artifact-view" data-canvas-shown="true" data-manifest-url="/manifest"><div class="artifact-viewer-container"><div class="artifact-markup-frame"><div class="artifact-markup">
      """# + view + #"""
      </div></div><div class="artifact-object"><div class="canvas-view" data-service-id="/scan"><div class="canvas-viewport"><div class="canvas-spinner"></div></div></div></div></div><footer><div class="artifact-overlay-toggle"><button>Overlay</button></div><div class="artifact-detach-toggle"><button class="button-view"><span class="button-icon">Detach</span></button></div></footer></div><script src="/loader.js"></script></body></html>
      """#
    var files: [String: FixtureServer.File] = [
      "/": .init(contentType: "text/html", body: Data(html.utf8)),
      "/loader.js": .init(contentType: "text/javascript", body: try Data(contentsOf: assets.appendingPathComponent("loader.js"))),
      "/client.wasm": .init(contentType: "application/wasm", body: try Data(contentsOf: assets.appendingPathComponent("client.wasm"))),
      "/manifest": .init(contentType: "application/json", body: Data(#"{"canvases":[{"id":"/scan","w":\#(size.width),"h":\#(size.height),"img":"/scan.jpg"}]}"#.utf8)),
      "/scan.jpg": .init(contentType: "image/jpeg", body: scan),
      "/gloss": .init(contentType: "text/html", body: Data(#"<div class="gloss-view"><p>A gloss.</p></div>"#.utf8)),
    ]
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
      // Side by side: each word of the edition hovered until one bands its
      // scan word; the band's middle on the scan marks that word again.
      if canvas != 2 {
        let words = try await page.evaluate(#"""
          (async()=>{const wait=ms=>new Promise(r=>setTimeout(r,ms)),words=[...document.querySelectorAll('.tei-page[data-active=true] .tei-word')];let paired=0,round=0;
            for(const word of words){word.dispatchEvent(new MouseEvent('mouseover',{bubbles:true}));await wait(5);const band=document.querySelector('.canvas-word');
              if(!band||band.hidden)continue;paired++;if(round)continue;const b=band.getBoundingClientRect(),o=document.querySelector('.artifact-object');
              o.dispatchEvent(new MouseEvent('mousemove',{clientX:b.x+b.width/2,clientY:b.y+b.height/2,bubbles:true}));await wait(5);
              round=word.dataset.corresponding==='true'&&document.querySelectorAll('.tei-word[data-corresponding=true]').length===1?1:-1}
            return [words.length,paired,round]})()
          """#, as: [Int].self)
        print("canvas \(canvas) at \(width): \(words[1]) of \(words[0]) words correspond")
        #expect(words[1] > 0, "canvas \(canvas): no word of the edition bands its scan word")
        #expect(words[2] == 1, "canvas \(canvas): the scan's word under the band does not mark the edition's")
        if let directory = ProcessInfo.processInfo.environment["GNORIUM_SCREENSHOT_DIR"] {
          // A word in the page's middle hovered: its band on the scan.
          _ = try await page.evaluate(#"""
            (async()=>{const words=[...document.querySelectorAll('.tei-page[data-active=true] .tei-word')];
              for(const word of words.slice(Math.floor(words.length/2)).concat(words)){word.dispatchEvent(new MouseEvent('mouseover',{bubbles:true}));await new Promise(r=>setTimeout(r,5));
                const band=document.querySelector('.canvas-word');if(band&&!band.hidden){word.dataset.corresponding='true';break}}return 1})()
            """#)
          try await page.screenshot(to: URL(fileURLWithPath: directory).appendingPathComponent("skeat-canvas-\(canvas)-words-\(width).png"))
        }
      }
      // A word's gloss covers the text pane exactly, never the image's
      // (user, 2026-10-14), side by side (1440) and stacked (440).
      if canvas == 5 {
        let gloss = try await page.evaluate(#"""
          (async()=>{const wait=ms=>new Promise(r=>setTimeout(r,ms)),R=e=>e.getBoundingClientRect(),p=document.querySelector('.artifact-markup'),o=document.querySelector('.artifact-object');
            document.querySelector('.tei-view').dataset.gloss='/gloss';const before=R(o);
            const w=[...p.querySelectorAll('.tei-word')].find(w=>{const b=R(w),r=R(p);return b.top>r.top&&b.bottom<r.bottom&&b.left>r.left&&b.right<r.right});
            w.click();await wait(500);const s=R(document.querySelector('.gloss-sheet .sheet-panel')),q=R(p),a=R(o);
            const covers=Math.abs(s.left-q.left)<=1&&Math.abs(s.top-q.top)<=1&&Math.abs(s.width-q.width)<=1&&Math.abs(s.height-q.height)<=1;
            const apart=s.right<=a.left+1||s.bottom<=a.top+1,still=Math.abs(a.left-before.left)<1&&Math.abs(a.top-before.top)<1&&Math.abs(a.width-before.width)<1&&Math.abs(a.height-before.height)<1;
            (document.activeElement||document.body).dispatchEvent(new KeyboardEvent('keydown',{key:'Escape',bubbles:true}));await wait(500);return JSON.stringify([covers,apart,still,[s.left,s.top,s.width,s.height],[q.left,q.top,q.width,q.height],[a.left,a.top,a.width,a.height]])})()
          """#, as: String.self)
        #expect(gloss.hasPrefix("[true,true,true"), "the gloss at \(width): covers the text pane, clear of the image, the image unmoved: \(gloss)")
      }
      try await page.evaluate("document.querySelector('.artifact-overlay-toggle').dispatchEvent(new CustomEvent('toggle-button-update',{detail:'true'}))")
      // At rest: the motion and the panes' move done.
      try await page.evaluate("new Promise(resolve=>setTimeout(resolve,1200))")
      let read = "(()=>{" + Self.structureScript + #"""
        const tally=list=>list.reduce((t,s)=>(t[s]=(t[s]||0)+1,t),{});const s=structureOf();
        return {expected:{edition:tally(s.edition),scan:tally(s.scan)},drawn:{edition:tally(drawnStates('edition')),scan:tally(drawnStates('scan'))},main:s.main,target:s.target}})()
        """#
      let scene = try await page.evaluate(read, as: Scene.self)
      if let directory = ProcessInfo.processInfo.environment["GNORIUM_SCREENSHOT_DIR"] {
        try await page.screenshot(to: URL(fileURLWithPath: directory).appendingPathComponent("skeat-canvas-\(canvas)-structure-\(width).png"))
      }
      print("canvas \(canvas) at \(width): \(scene.drawn)")
      #expect(scene.drawn == scene.expected, "canvas \(canvas): drawn \(scene.drawn), the rule gives \(scene.expected)")
      #expect(!(scene.drawn["edition"] ?? [:]).isEmpty, "canvas \(canvas): no structure drawn")
      if scene.main.count == 2 {
        let off = zip(scene.main, scene.target).map { abs($0 - $1) }
        #expect(off.allSatisfy { $0 <= Self.landing }, "canvas \(canvas): the scan's main blocks laid \(scene.main), the ink box \(scene.target)")
      }
      // Zoomed to twice the fit about the page's middle: the registration
      // holds, the scene as it was.
      let zoomed = try await page.evaluate(#"""
        (async()=>{const p=document.querySelector('.artifact-markup'),l=document.querySelector('.tei-page[data-active=true] [data-layer=rendering]'),b=p.getBoundingClientRect(),fit=Number(l.dataset.zoom);
          for(let i=0;i<80&&Number(l.dataset.zoom)<2*fit;i++){p.dispatchEvent(new WheelEvent('wheel',{deltaY:-40,clientX:b.x+b.width/2,clientY:b.y+b.height/2,bubbles:true,cancelable:true}));await new Promise(r=>setTimeout(r,16))}
          await new Promise(r=>setTimeout(r,300));return Number(l.dataset.zoom)/fit})()
        """#, as: Double.self)
      let twice = try await page.evaluate(read, as: Scene.self)
      #expect(twice.drawn == scene.drawn)
      if twice.main.count == 2 {
        let off = zip(twice.main, twice.target).map { abs($0 - $1) }
        #expect(off.allSatisfy { $0 <= Self.landing * zoomed }, "canvas \(canvas) at \(zoomed)× the fit: \(off)")
      }
      try await page.expectNoErrors()
    }
  }

  /// How far the scan's laid structure may land from the edition's ink: the
  /// measurement's precision, two pixels (gnorium-python
  /// `type_scale.PIXELS`).
  static let landing = 2.0
}
