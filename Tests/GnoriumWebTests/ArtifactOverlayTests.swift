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
      body{margin:0}.artifact-view{width:100%;height:440px}.artifact-viewer-container{height:400px;flex:none}.image-view,.image-viewport{width:100%;height:100%;position:relative;overflow:hidden}.image-tile-surface{position:absolute;inset:0;width:100%;height:100%}.tei-line{font-family:serif!important}</style><link rel="icon" href="data:,"></head><body><div class="artifact-view" data-canvas-shown="true" data-manifest-url="/manifest"><div class="artifact-viewer-container"><div class="artifact-markup-frame"><div class="artifact-markup"><div class="tei-view"><div class="tei-page" data-service-id="/scan"><div class="tei-page-text" data-layer="rendering"><span class="tei-line">Overlay text</span></div></div></div></div></div><div class="artifact-object"><div class="image-view" data-service-id="/scan"><div class="image-viewport"><div class="image-spinner"></div></div></div></div></div><footer><div class="artifact-overlay-toggle"><button>Overlay</button></div><div class="artifact-detach-toggle"><button class="button-view"><span class="button-icon">Detach</span></button></div></footer></div><script src="/loader.js"></script></body></html>
      """#
    let server = try await FixtureServer(files: [
      "/": .init(contentType: "text/html", body: Data(html.utf8)),
      "/loader.js": .init(contentType: "text/javascript", body: try Data(contentsOf: assets.appendingPathComponent("loader.js"))),
      "/client.wasm": .init(contentType: "application/wasm", body: try Data(contentsOf: assets.appendingPathComponent("client.wasm"))),
      "/manifest": .init(contentType: "application/json", body: Data(#"{"canvases":[{"id":"/scan","w":1200,"h":2000,"imgs":["/scan.svg"]}]}"#.utf8)),
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
            let r=document.querySelector('.artifact-view'),f=r.querySelector('.artifact-markup-frame'),o=r.querySelector('.artifact-object'),l=r.querySelector('[data-layer=rendering]'),v=r.querySelector('.image-viewport'),d=r.querySelector('.artifact-detach-toggle');
            const wait=ms=>new Promise(resolve=>setTimeout(resolve,ms));const size=()=>[f.getBoundingClientRect().width,f.getBoundingClientRect().height,o.getBoundingClientRect().width,o.getBoundingClientRect().height];const toggle=on=>r.querySelector('.artifact-overlay-toggle').dispatchEvent(new CustomEvent('toggle-button-update',{detail:on?'true':'false'}));
            let before=size();
            const pane=r.querySelector('.artifact-markup');let pb=pane.getBoundingClientRect();
            for(let i=0;i<8;i++){pane.dispatchEvent(new WheelEvent('wheel',{deltaY:-40,clientX:pb.x+pb.width/2,clientY:pb.y+pb.height/2,bubbles:true,cancelable:true}));await wait(30)}
            const zoomStart=Number(l.dataset.zoom);toggle(true);await wait(120);let mid=size();const opacityOnMid=Number(getComputedStyle(o).opacity),textOnMid=getComputedStyle(l).opacity;const zoomMid=Number(l.dataset.zoom);await wait(500);let after=size();
            const fitted=Number(l.dataset.zoom);const fittedBox=l.getBoundingClientRect(),paneBox=pane.getBoundingClientRect();
            const whole=fittedBox.width<=paneBox.width+1&&fittedBox.height<=paneBox.height+1&&pane.scrollLeft===0&&pane.scrollTop===0&&getComputedStyle(pane).overflow==='hidden';
            const zoomAnimated=zoomStart>zoomMid&&zoomMid>fitted;
            const values=()=>r.querySelector('.image-tile-compositor').getAttribute('transform');
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
            return [zoomReturned,before[dim]<mid[dim]&&mid[dim]<after[dim],whole&&zoomAnimated,locked,detachOn,rules.imageOpacity==='0.25'&&rules.textOpacity==='1',rules.bg==='rgba(0, 0, 0, 0)'&&!r.querySelector('.artifact-structure'),detachOff,panesBack,detachedBefore&&detachedOn&&detachedAfter,opacityOnMid>0&&opacityOnMid<1&&opacityOffMid>0&&opacityOffMid<1&&textOnMid==='1'];
           })()
        """#, as: [Bool].self)
      let named = [
        "zoom back animated", "the panes move", "the whole page fits, zoom animated", "no gesture moves the scan or the text",
        "Detach present, disabled and off while on", "at rest the scan faded to a quarter, the text opaque",
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

  /// The synthetic page the structure tests read: thirty lines in a work
  /// frame, its text block measured on a blank scan four times the text's
  /// actual size; `blankPage`, a second page after it laid in blank, with
  /// no markup of its own (`data-has-markup`), on a canvas of its own;
  /// `blankCanvas`, a second page with markup whose canvas the manifest
  /// shows with no image (`"blank":true`: changed at its source, no copy of
  /// what was sent kept).
  static func structureServer(blankPage: Bool = false, blankCanvas: Bool = false, imageSwitch: Bool = false) async throws -> FixtureServer {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let assets = root.appendingPathComponent("gnorium-web/Public")
    let css = try ["layout-view.css", "tei-view.css", "artifact-view.css", "image-view.css"].map {
      try String(contentsOf: assets.appendingPathComponent("style-sheets/" + $0), encoding: .utf8)
    }.joined(separator: "\n")
    let lines = (1...30).map { #"<span class="tei-line">Line \#($0) of the page.</span>"# }.joined()
    let blank: String =
      if blankPage {
        #"<div class="tei-page" data-service-id="/blank" data-active="false" data-has-markup="false"><div class="tei-page-text" data-layer="rendering" data-framed="false"></div></div>"#
      } else if blankCanvas {
        #"<div class="tei-page" data-service-id="/blank" data-active="false" data-has-markup="true"><div class="tei-page-text" data-layer="rendering" data-framed="false"><div class="tei-text-block">"#
          + lines + "</div></div></div>"
      } else {
        ""
      }
    let manifest: String =
      if blankPage {
        #"{"canvases":[{"id":"/scan","w":4800,"h":6400,"imgs":["/scan.svg"]},{"id":"/blank","w":4800,"h":6400,"imgs":["/scan.svg"]}]}"#
      } else if blankCanvas {
        #"{"canvases":[{"id":"/scan","w":4800,"h":6400,"imgs":["/scan.svg"]},{"blank":true,"id":"/blank","w":4800,"h":6400}]}"#
      } else {
        #"{"canvases":[{"id":"/scan","w":4800,"h":6400,"imgs":["/scan.svg"]}]}"#
      }
    let html = "<!doctype html><html><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"><style>" + css + #"""
      body{margin:0}.artifact-view{width:100%;height:600px}.artifact-viewer-container{height:560px;flex:none}.tei-line{display:block;font-family:serif!important;white-space:nowrap;letter-spacing:0.3em}</style><link rel="icon" href="data:,"></head><body><div class="artifact-view" data-canvas-shown="true" data-manifest-url="/manifest">
      """# + (imageSwitch ? #"<header><div class="artifact-canvas-toggle"><button>Image</button></div></header>"# : "") + #"""
      <div class="artifact-viewer-container"><div class="artifact-markup-frame"><div class="artifact-markup"><div class="tei-view"><div class="tei-page" data-service-id="/scan" data-active="true" data-has-markup="true" data-text-block="300,240 700,248 694,700 294,692"><div class="tei-page-text" data-layer="rendering" data-framed="true" style="--tei-frame-measure: 30; --tei-frame-height: 40; --tei-frame-margin: 5; --tei-page-width: 0; --tei-page-height: 0"><div class="tei-text-block">
      """# + lines + "</div></div></div>" + blank + #"""
      </div></div></div><div class="artifact-object"><div class="image-view" data-service-id="/scan"><div class="image-viewport"><div class="image-spinner"></div></div></div></div></div><footer><div class="artifact-overlay-toggle"><button>Overlay</button></div><div class="artifact-detach-toggle"><button class="button-view"><span class="button-icon">Detach</span></button></div></footer></div><script src="/loader.js"></script></body></html>
      """#
    var files: [String: FixtureServer.File] = [
      "/": .init(contentType: "text/html", body: Data(html.utf8)),
      "/loader.js": .init(contentType: "text/javascript", body: try Data(contentsOf: assets.appendingPathComponent("loader.js"))),
      "/client.wasm": .init(contentType: "application/wasm", body: try Data(contentsOf: assets.appendingPathComponent("client.wasm"))),
      "/manifest": .init(
        contentType: "application/json",
        body: Data(manifest.utf8)),
      "/scan.svg": .init(contentType: "image/svg+xml", body: Data(#"<svg xmlns="http://www.w3.org/2000/svg" width="4800" height="6400"/>"#.utf8)),
      "/fonts/noto-sans.woff2": .init(contentType: "font/woff2", body: try Data(contentsOf: assets.appendingPathComponent("fonts/noto-sans.woff2"))),
    ]
    // The built stylesheets the client asks for as it draws (`loader.js`:
    // the list, then each sheet a view registers), so a page loads clean.
    let sheets = assets.appendingPathComponent("style-sheets")
    for name in try FileManager.default.contentsOfDirectory(atPath: sheets.path)
    where name.hasSuffix(".css") || name.hasSuffix(".json") {
      files["/style-sheets/\(name)"] = .init(
        contentType: name.hasSuffix(".css") ? "text/css" : "application/json",
        body: try Data(contentsOf: sheets.appendingPathComponent(name)))
    }
    return try await FixtureServer(files: files)
  }

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
    let server = try await Self.structureServer()
    defer { server.stop() }
    let config = BrowserTestConfiguration(baseURL: URL(string: server.baseURL)!, engines: [.chrome], defaultTimeout: .seconds(30))
    try await withPage(.chrome, config, viewport: .init(width: width, height: 600)) { page in
      try await page.goto("/")
      try await expect(page.locator("html")).toHaveAttribute("data-wasm-status", "started")
      try await page.evaluate("new Promise(resolve=>setTimeout(resolve,700))")
      let checks = try await page.evaluate("(async()=>{" + Self.shared + #"""
          const wait=ms=>new Promise(resolve=>setTimeout(resolve,ms)),r=document.querySelector('.artifact-view');
          const toggle=on=>r.querySelector('.artifact-overlay-toggle').dispatchEvent(new CustomEvent('toggle-button-update',{detail:on?'true':'false'}));
          const surface=()=>r.querySelector('.image-tile-surface'),viewport=r.querySelector('.image-viewport'),object=r.querySelector('.artifact-object');
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
          pageEl.dataset.scanLayout=['block main - '+zone.map(([x,y])=>(x/W*1000)+' '+(y/H*1000)).join(' ').replace(/,/g,' ')]
            .concat(planted.map(row=>'line - - '+quad(row).replace(/[ ,]/g,' '))).join(';');
          // Its scan block's corners in the window, as drawn, and where the registration lays them.
          // Through the drawing's own transform to the screen: the edition and its structure turned onto the image.
          const scanBlock=()=>{const p=r.querySelector('.artifact-structure [data-side=scan][data-kind=block]');if(!p)return null;const m=p.getScreenCTM();
            return p.getAttribute('points').split(' ').map(q=>q.split(',').map(Number)).map(([x,y])=>{const q=new DOMPoint(x,y).matrixTransform(m);return [q.x,q.y]})};
          // The image's place on screen (its pan and zoom), and its text block's corners there: where the
          // scan's structure, laid on the edition laid on the image, must land (user, 2026-10-28).
          const imageBox=()=>{const c=r.querySelector('.image-tile-compositor'),b=c.getBoundingClientRect();return [b.x,b.y,b.width,b.height,b.width/W]};
          // The edition turned as the scan is photographed: the scan's structure on the image's text block's own
          // four corners (user, 2026-10-28).
          const target=()=>{const [x,y,w,h]=imageBox();return zone.map(([zx,zy])=>[x+zx/W*w,y+zy/H*h])};
          const off=()=>{const s=scanBlock(),t=target();return s?Math.max(...s.map((q,i)=>Math.hypot(q[0]-t[i][0],q[1]-t[i][1]))):Infinity};
          const place=()=>{const b=layer().getBoundingClientRect();return [Number(layer().dataset.zoom),b.x,b.y]};
          const states=side=>[...new Map([...r.querySelectorAll('.artifact-structure [data-side='+side+'][data-kind=line]')].map(e=>[e.dataset.row,e.dataset.state])).values()];
          const wheel=async(dy,fx,fy,n)=>{const b=pane.getBoundingClientRect();for(let i=0;i<n;i++){pane.dispatchEvent(new WheelEvent('wheel',{deltaY:dy,clientX:b.x+b.width*fx,clientY:b.y+b.height*fy,bubbles:true,cancelable:true}));await wait(20)}};
          await wheel(-40,0.3,0.3,6);await wait(300);const editionBefore=place(),imageBefore=imageBox(),viewBefore=viewport.getBoundingClientRect();
          // Coming on, midway: the scan fading out, the structure's lines fading in, the text itself.
          const fades=()=>{const s=r.querySelector('.artifact-structure');return [Number(getComputedStyle(object).opacity),s?Number(getComputedStyle(s).opacity):-1,getComputedStyle(layer()).opacity]};
          toggle(true);await wait(150);const onMid=fades();
          await wait(650);
          const registered=off();const atRest=fades();
          // At rest: the image as its pane shows it, unwarped, at a quarter; the structure whole; the planted divergences
          // marked, every other line quiet.
          const unwarped=getComputedStyle(surface()).transform==='none'&&Math.abs(atRest[0]-0.25)<1e-6&&atRest[1]===1&&atRest[2]==='1';
          const between=f=>f[0]>0&&f[0]<1&&f[1]>0&&f[1]<1&&f[2]==='1';
          const edition=states('edition'),scan=states('scan');
          const count=(list,state)=>list.filter(s=>s===state).length;
          const marked=edition.length===30&&scan.length===30&&count(edition,'extra')===1&&count(edition,'off')===1&&count(scan,'off')===1
            &&count(scan,'missing')===1&&count(edition,'within')===28&&count(scan,'within')===28;
          const strokes=(()=>{const q=r.querySelector('.artifact-structure [data-side=edition][data-state=within]'),o=r.querySelector('.artifact-structure [data-state=off]'),s=r.querySelector('.artifact-structure [data-side=scan]');
            return getComputedStyle(q).strokeWidth==='1px'&&getComputedStyle(o).strokeWidth==='2px'&&getComputedStyle(q).strokeDasharray==='none'&&getComputedStyle(s).strokeDasharray!=='none'})();
          // The image as its pane showed it before the overlay (its zoom following the edition's, the panes linked),
          // never moved by the overlay: its pane made the overlay's whole, the same point at its middle (centered along
          // a side it no longer fills) and the same zoom over its fit (`ImageView`'s resize).
          const vb=viewport.getBoundingClientRect(),ib=imageBox();
          const seen=([x,y,w,h,z],v)=>[(v.x+v.width/2-x)/w,(v.y+v.height/2-y)/h,z/Math.min(v.width/W,v.height/H)];
          const fits=(()=>{const a=seen(imageBefore,viewBefore),b=seen(ib,vb);
            // Along a side it no longer fills, centered in its pane, as its pane centers any image narrower than it.
            const along=(k,extent,size)=>extent<=size+1?Math.abs(b[k]-0.5)<1e-3:Math.abs(a[k]-b[k])<1e-3;
            return along(0,ib[2],vb.width)&&along(1,ib[3],vb.height)&&Math.abs(a[2]-b[2])<1e-3})();
          const pb=pane.getBoundingClientRect();
          const detach=r.querySelector('.artifact-detach-toggle'),detachButton=detach.querySelector('button');
          const detachOn=!detach.hidden&&getComputedStyle(detach).display!=='none'&&detachButton.disabled&&detachButton.getAttribute('aria-disabled')==='true'&&detach.getAttribute('aria-pressed')==='false';
          // The overlay's zoom and pan the image's, the edition on it: never below its fit; at twice the fit,
          // dragged and keyed, still registered.
          const fit=Math.min(vb.width/W,vb.height/H);
          await wheel(40,0.5,0.5,20);const floor=Math.abs(imageBox()[4]-fit)<1e-9;
          for(let i=0;i<60&&imageBox()[4]<2*fit;i++)await wheel(-40,0.5,0.5,1);
          const zoomed=imageBox()[4]>=2*fit*0.98,zoomedOff=off();
          // A drag from the blank right of the lines (a press on text selects it).
          const before=place(),cx=pb.right-8,cy=pb.y+pb.height/2;
          pane.dispatchEvent(new MouseEvent('mousedown',{clientX:cx,clientY:cy,button:0,detail:1,bubbles:true,cancelable:true}));window.dispatchEvent(new MouseEvent('mousemove',{clientX:cx-30,clientY:cy+40,bubbles:true}));window.dispatchEvent(new MouseEvent('mouseup',{bubbles:true}));await wait(60);
          const dragged=place(),pannedOff=off();
          // The key away from the edge the drag moved toward.
          pane.focus();pane.dispatchEvent(new KeyboardEvent('keydown',{key:'ArrowDown',bubbles:true,cancelable:true}));await wait(60);
          const keyed=place(),keyedOff=off();
          const panned=(dragged[1]!==before[1]||dragged[2]!==before[2])&&(keyed[2]!==dragged[2]);
          // Overlay off from three times the image's fit: the image keeps its view, the edition slides back to
          // where it was before the overlay (user, 2026-10-28).
          pane.dispatchEvent(new KeyboardEvent('keydown',{key:'0',bubbles:true,cancelable:true}));await wait(60);
          for(let i=0;i<90&&imageBox()[4]<3*fit;i++)await wheel(-40,0.5,0.5,1);
          await wait(100);
          const imageZoom=seen(imageBox(),viewport.getBoundingClientRect())[2],editionFrom=place();
          toggle(false);await wait(150);const offMid=fades(),editionMid=place();await wait(850);
          const editionTo=place();
          // Midway out, the edition between where it lay on the image and where it goes back to, never jumping.
          const strictly=(a,m,b)=>Math.min(a,b)<m&&m<Math.max(a,b);
          const exitMoving=[0,1,2].some(k=>strictly(editionFrom[k],editionMid[k],editionTo[k]));
          const gone=!r.querySelector('.artifact-structure')&&getComputedStyle(object).opacity==='1';
          const kept=Math.abs(seen(imageBox(),viewport.getBoundingClientRect())[2]-imageZoom)/imageZoom<0.01;
          const sameSpot=Math.max(Math.abs(editionTo[0]-editionBefore[0])*1000,Math.abs(editionTo[1]-editionBefore[1]),Math.abs(editionTo[2]-editionBefore[2]));
          const p2=pane.getBoundingClientRect(),v2=viewport.getBoundingClientRect();
          const apart=window.innerWidth<=480||p2.right<=v2.left+1;
          const detachOff=!detachButton.disabled&&!detachButton.hasAttribute('aria-disabled')&&detach.getAttribute('aria-pressed')==='false';
          const detachTo=on=>detach.dispatchEvent(new CustomEvent('toggle-button-update',{detail:on?'true':'false'}));
          detachTo(true);await wait(30);toggle(true);await wait(900);const detachedOn=detachButton.disabled&&detach.getAttribute('aria-pressed')==='false';
          toggle(false);await wait(900);const detachedAfter=!detachButton.disabled&&detach.getAttribute('aria-pressed')==='true';detachTo(false);await wait(30);
          // Reduced motion: the end state at once, each way.
          const media=window.matchMedia;window.matchMedia=q=>q.includes('reduced-motion')?{matches:true}:media.call(window,q);
          const still=document.createElement('style');still.textContent='*{transition:none!important}';document.head.appendChild(still);
          toggle(true);await wait(80);const instantOn=off()<2&&Math.abs(fades()[0]-0.25)<1e-6&&fades()[1]===1;
          toggle(false);await wait(80);const instantOff=!r.querySelector('.artifact-structure')&&getComputedStyle(object).opacity==='1';
          window.matchMedia=media;still.remove();
          return [registered<2,unwarped,marked,strokes,fits,detachOn,floor,zoomed&&zoomedOff<2,panned&&pannedOff<2&&keyedOff<2,gone&&kept,sameSpot<2,apart,detachOff,
            detachedOn&&detachedAfter,instantOn&&instantOff,Math.round(registered*100)/100,Math.round(sameSpot*100)/100,edition.length,scan.length,count(edition,'extra'),count(edition,'off'),count(scan,'off'),count(scan,'missing'),zoomedOff,pannedOff,keyedOff,between(onMid)&&between(offMid),exitMoving].map(Number);
        })()
        """#, as: [Double].self)
      let named = [
        "the scan's structure lands on the image's text block within 2px (off by \(checks[15]))",
        "at rest the image as its pane shows it, unwarped, at a quarter, the structure whole, the text opaque",
        "the planted divergences marked (one extra, one pair off, one missing), every other line quiet (rows \(checks[17]), \(checks[18]); extra \(checks[19]), off \(checks[20]), \(checks[21]), missing \(checks[22]))",
        "quiet strokes 1px, marked 2px, the edition's solid, the scan's dashed",
        "the image as its pane showed it before the overlay: the same point at its middle, the same zoom over its fit",
        "Detach present, disabled and off while the overlay is on", "the zoom never goes below the fit",
        "the image zoomed to twice its fit, the registration holds within 2px (off by \(checks[23]))", "dragged and keyed, the image pans and the edition and its structure stay on it (off by \(checks[24]), \(checks[25])))",
        "overlay off: the structure gone, the image keeps its zoom over its fit",
        "overlay off: the edition back where it was before the overlay within 2px (off by \(checks[16]))",
        "overlay off: the panes side by side", "Detach enabled and off after",
        "detached before: off and disabled while on, detached again after", "with reduced motion the end state applies at once, on and off",
      ]
      for (check, name) in zip(checks, named) { #expect(check == 1, "\(name)") }
      #expect(checks[26] == 1, "midway, each way, the scan and the structure's lines strictly between, the text opaque")
      #expect(checks[27] == 1, "midway out, the edition between where it lay on the image and where it goes back to")
      try await page.expectNoErrors()
    }
  }

  /// Overlay on and off four times (user, 2026-10-14), the text zoomed in
  /// first (the synced image with it, past its fit): every exit as the
  /// first—midway, the image's pane strictly between the overlay's and
  /// side by side on each axis it moves along, the image moving (and, its
  /// scan not laid by a text block, scaling with its pane), its
  /// proportions kept; every end the same box as the first. With and
  /// without a measured text block.
  @Test(arguments: [1440, 440], [true, false])
  func everyOverlayExitIsTheFirsts(width: Int, registered: Bool) async throws {
    let server = try await Self.structureServer()
    defer { server.stop() }
    let config = BrowserTestConfiguration(baseURL: URL(string: server.baseURL)!, engines: [.chrome], defaultTimeout: .seconds(30))
    try await withPage(.chrome, config, viewport: .init(width: width, height: 600)) { page in
      try await page.goto("/")
      try await expect(page.locator("html")).toHaveAttribute("data-wasm-status", "started")
      try await page.evaluate("new Promise(resolve=>setTimeout(resolve,700))")
      let cycles = try await page.evaluate(#"""
        (async()=>{const wait=ms=>new Promise(r=>setTimeout(r,ms)),r=document.querySelector('.artifact-view'),W=4800,H=6400;
          const toggle=on=>r.querySelector('.artifact-overlay-toggle').dispatchEvent(new CustomEvent('toggle-button-update',{detail:on?'true':'false'}));
          const viewport=r.querySelector('.image-viewport'),object=r.querySelector('.artifact-object');
          const image=()=>{const v=viewport.getBoundingClientRect(),g=r.querySelector('.image-tile-compositor').getAttribute('transform').match(/-?[\d.]+(e-?\d+)?/g).map(Number);return [v.x+g[0],v.y+g[1],W*g[2],H*g[2]]};
          const pane=()=>{const b=object.getBoundingClientRect();return [b.x,b.y,b.width,b.height]};
          if(!REGISTERED)r.querySelector('.tei-page').removeAttribute('data-text-block');
          const m=r.querySelector('.artifact-markup'),mb=m.getBoundingClientRect();
          for(let i=0;i<6;i++){m.dispatchEvent(new WheelEvent('wheel',{deltaY:-40,clientX:mb.x+mb.width/2,clientY:mb.y+mb.height/2,bubbles:true,cancelable:true}));await wait(30)}
          await wait(400);
          const out=[];
          for(let cycle=0;cycle<4;cycle++){toggle(true);await wait(900);const from=[image(),pane()];toggle(false);await wait(150);const mid=[image(),pane()];await wait(850);out.push({from,mid,to:[image(),pane()]})}
          return JSON.stringify(out)})()
        """#.replacingOccurrences(of: "REGISTERED", with: registered ? "true" : "false"), as: String.self)
      struct Sample: Decodable { let from: [[Double]]; let mid: [[Double]]; let to: [[Double]] }
      let samples = try JSONDecoder().decode([Sample].self, from: Data(cycles.utf8))
      func strictly(_ a: Double, _ m: Double, _ b: Double) -> Bool { min(a, b) < m && m < max(a, b) }
      for (index, sample) in samples.enumerated() {
        let pane = (sample.from[1], sample.mid[1], sample.to[1])
        // The pane parts on both of the axes it moves along.
        let moving = (0..<4).filter { abs(pane.0[$0] - pane.2[$0]) > 1 }
        #expect(!moving.isEmpty && moving.allSatisfy { strictly(pane.0[$0], pane.1[$0], pane.2[$0]) },
          "cycle \(index + 1) at \(width): the image's pane midway out \(pane.1), from \(pane.0) to \(pane.2)")
        let image = (sample.from[0], sample.mid[0], sample.to[0])
        #expect([0, 1].contains { strictly(image.0[$0], image.1[$0], image.2[$0]) },
          "cycle \(index + 1) at \(width): the image midway out \(image.1), from \(image.0) to \(image.2)")
        // Its size changing as its pane's fit does (stacked, its height),
        // midway between.
        if !registered, abs(image.0[2] - image.2[2]) > 1 {
          #expect(strictly(image.0[2], image.1[2], image.2[2]), "cycle \(index + 1) at \(width): the image scales with its pane")
        }
        #expect(abs(image.1[2] / image.1[3] - image.0[2] / image.0[3]) < 1e-6, "cycle \(index + 1): the image's proportions")
        let first = samples[0].to
        #expect(zip(sample.to[0] + sample.to[1], first[0] + first[1]).allSatisfy { abs($0 - $1) < 1 },
          "cycle \(index + 1) at \(width) ends at \(sample.to), the first at \(first)")
      }
      try await page.expectNoErrors()
    }
  }

  /// The text at its fit, overlay on and off without zooming in it
  /// leaves the text at its own pane's fit (user, 2026-10-17), side by side
  /// and stacked on a phone, where the overlay's fit is about twice the
  /// pane's: no scrollport on either axis, ringed (a page's diff state) or
  /// not, at every device scale, and the fit kept as the fit, which
  /// follows the pane. The overlay framed the page in the pane's whole
  /// client box, a few pixels taller than its room, and off kept that
  /// zoom: the pane scrolled by them (on a phone, by half the page).
  @Test(arguments: [
    (1440, 600, 1.0, false, false), (1440, 600, 1.0, true, false), (1309, 600, 1.1, true, false),
    (1152, 600, 1.25, true, false), (1234, 600, 1.75, true, false), (1440, 600, 2.0, true, false),
    (375, 812, 3.0, true, true),
  ])
  func overlayOffAtTheFitLeavesNoScrollport(width: Int, height: Int, scale: Double, ringed: Bool, touch: Bool) async throws {
    let server = try await Self.structureServer()
    defer { server.stop() }
    let config = BrowserTestConfiguration(baseURL: URL(string: server.baseURL)!, engines: [.chrome], defaultTimeout: .seconds(30))
    try await withPage(.chrome, config, viewport: .init(width: width, height: height, deviceScaleFactor: scale, touch: touch)) { page in
      try await page.goto("/")
      try await expect(page.locator("html")).toHaveAttribute("data-wasm-status", "started")
      try await page.evaluate("new Promise(resolve=>setTimeout(resolve,700))")
      let states = try await page.evaluate((Self.atTheFit + #"""
          const out=[state()];
          for(let cycle=0;cycle<2;cycle++){toggle(true);await wait(900);toggle(false);await wait(900);out.push(state())}
          return JSON.stringify(out)})()
        """#).replacingOccurrences(of: "RINGED", with: ringed ? "true" : "false"), as: String.self)
      let samples = try JSONDecoder().decode([[Double]].self, from: Data(states.utf8))
      let named = ["before", "after one overlay", "after two"]
      for (sample, name) in zip(samples, named) {
        #expect(sample[1] <= sample[2] && sample[3] <= sample[4],
          "\(name) at \(width)×\(scale)\(ringed ? ", ringed" : ""): no scrollport (scroll \(sample[3])×\(sample[1]), client \(sample[4])×\(sample[2]))")
        #expect(sample[5] == 1, "\(name) at \(width)×\(scale): the text kept at its fit")
        #expect(abs(sample[0] - samples[0][0]) < 1e-6, "\(name) at \(width)×\(scale): its zoom \(sample[0]), the fit's \(samples[0][0])")
      }
      try await page.expectNoErrors()
    }
  }

  /// A zoom the reader chose in the overlay is the image's (user,
  /// 2026-10-28: the image stays as its pane shows it, the edition laid on
  /// it), side by side and stacked on a phone: zoomed in the overlay, the
  /// image past its fit and the edition on it; overlay off, the image
  /// keeps that zoom and the edition is back where it was before, at its
  /// pane's fit.
  @Test(arguments: [(1440, 600, 1.0, false), (375, 812, 3.0, true)])
  func overlayOffKeepsAZoomChosenInTheOverlay(width: Int, height: Int, scale: Double, touch: Bool) async throws {
    let server = try await Self.structureServer()
    defer { server.stop() }
    let config = BrowserTestConfiguration(baseURL: URL(string: server.baseURL)!, engines: [.chrome], defaultTimeout: .seconds(30))
    try await withPage(.chrome, config, viewport: .init(width: width, height: height, deviceScaleFactor: scale, touch: touch)) { page in
      try await page.goto("/")
      try await expect(page.locator("html")).toHaveAttribute("data-wasm-status", "started")
      try await page.evaluate("new Promise(resolve=>setTimeout(resolve,700))")
      let states = try await page.evaluate((Self.atTheFit + #"""
          // The image's zoom over its fit: its drawn width over its viewport's fit width.
          const imageOver=()=>{const vp=[...document.querySelectorAll('.image-viewport')].find(e=>e.getBoundingClientRect().width>0),c=vp.querySelector('.image-tile-compositor')||vp.firstElementChild,r=c.getBoundingClientRect(),b=vp.getBoundingClientRect();return Math.max(r.width/b.width,r.height/b.height)};
          const fit=state(),imageBefore=imageOver();toggle(true);await wait(900);const imageOn=imageOver();
          const o=pane.getBoundingClientRect();
          for(let i=0;i<6;i++){pane.dispatchEvent(new WheelEvent('wheel',{deltaY:-40,clientX:o.x+o.width/2,clientY:o.y+o.height/2,bubbles:true,cancelable:true}));await wait(30)}
          await wait(100);const chosen=state(),imageChosen=imageOver();toggle(false);await wait(900);
          return JSON.stringify([fit,chosen,state(),[imageBefore,imageChosen,imageOver(),imageOn]])})()
        """#).replacingOccurrences(of: "RINGED", with: "false"), as: String.self)
      let samples = try JSONDecoder().decode([[Double]].self, from: Data(states.utf8))
      let (fit, chosen, after, image) = (samples[0], samples[1], samples[2], samples[3])
      #expect(chosen[0] > fit[0] * 1.2, "at \(width): the edition zoomed with the image, \(chosen[0]) over the pane's fit \(fit[0])")
      #expect(abs(image[3] - image[0]) < 0.02, "at \(width): overlay on, the image as its pane showed it, \(image[0]), now \(image[3])")
      #expect(image[1] > image[0] * 1.2, "at \(width): the image zoomed in the overlay, \(image[1]) over \(image[0])")
      #expect(abs(image[2] - image[1]) / image[1] < 0.02, "at \(width): off, the image keeps its zoom \(image[1]), now \(image[2])")
      #expect(abs(after[0] - fit[0]) < 1e-6 && after[5] == 1, "at \(width): off, the edition back at its fit \(fit[0]), now \(after[0])")
      try await page.expectNoErrors()
    }
  }

  /// A page with no markup of its own (`TEIView`'s `data-has-markup`,
  /// `TEIRenderer.hasMarkup`: a page laid in blank) has nothing for the
  /// overlay to lay, and a page shown with no image (`blankCanvas`, the
  /// manifest's `"blank":true`) nothing to compare its text against (user,
  /// 2026-10-17)—one rule (`ArtifactView`'s `overlayApplies`): turned to
  /// with the overlay on, the overlay goes off; its switch is disabled there
  /// (`disabled`, `aria-disabled`), its label kept; back on a page with
  /// markup and an image, with a measured text block or without one, it is
  /// enabled again, the overlay still off. The page with no image shows its
  /// text alone, as with the images off (`data-canvas-shown`, the image pane
  /// put away); the page with one, its image again.
  @Test(arguments: [true, false], [false, true])
  func overlayIsOffAndDisabledOnAPageWithNoMarkupOrNoImage(registered: Bool, blankCanvas: Bool) async throws {
    let server = try await Self.structureServer(blankPage: !blankCanvas, blankCanvas: blankCanvas)
    defer { server.stop() }
    let config = BrowserTestConfiguration(baseURL: URL(string: server.baseURL)!, engines: [.chrome], defaultTimeout: .seconds(30))
    try await withPage(.chrome, config, viewport: .init(width: 1440, height: 600)) { page in
      try await page.goto("/")
      try await expect(page.locator("html")).toHaveAttribute("data-wasm-status", "started")
      try await page.evaluate("new Promise(resolve=>setTimeout(resolve,700))")
      let checks = try await page.evaluate(#"""
        (async()=>{const wait=ms=>new Promise(r=>setTimeout(r,ms)),r=document.querySelector('.artifact-view');
          const wrap=r.querySelector('.artifact-overlay-toggle'),button=wrap.querySelector('button');
          if(!REGISTERED)r.querySelector('.tei-page').removeAttribute('data-text-block');
          const turn=async index=>{r.dispatchEvent(new CustomEvent('artifact-show-canvas',{detail:String(index)}));await wait(900)};
          const shown=()=>r.querySelector('.artifact-markup .tei-page[data-active=true]').dataset.serviceId;
          const enabled=()=>!button.disabled&&!button.hasAttribute('aria-disabled')&&button.textContent.trim()==='Overlay';
          const disabled=()=>button.disabled&&button.getAttribute('aria-disabled')==='true'&&button.textContent.trim()==='Overlay';
          const off=()=>r.dataset.overlayActive==='false'&&wrap.getAttribute('aria-pressed')==='false'&&button.getAttribute('aria-pressed')==='false'
            &&r.dataset.overlayRegistered!=='true'&&!r.querySelector('.artifact-structure');
          const pane=()=>getComputedStyle(r.querySelector('.artifact-object')).display;
          const imaged=()=>r.dataset.canvasShown==='true'&&pane()!=='none';
          const alone=()=>r.dataset.canvasShown==='false'&&pane()==='none';
          const second=()=>BLANKCANVAS?alone():imaged();
          const enabledFirst=shown()==='/scan'&&enabled();
          // On, as its switch turns it on: pressed, then its event.
          wrap.setAttribute('aria-pressed','true');button.setAttribute('aria-pressed','true');
          wrap.dispatchEvent(new CustomEvent('toggle-button-update',{detail:'true'}));await wait(900);
          const on=r.dataset.overlayActive==='true';
          await turn(1);const offOnBlank=shown()==='/blank'&&off()&&disabled()&&second();
          await turn(0);const enabledBack=shown()==='/scan'&&enabled()&&off()&&imaged();
          await turn(1);const disabledAgain=shown()==='/blank'&&disabled()&&off()&&second();
          return [enabledFirst,on,offOnBlank,enabledBack,disabledAgain].map(Number)})()
        """#.replacingOccurrences(of: "REGISTERED", with: registered ? "true" : "false")
          .replacingOccurrences(of: "BLANKCANVAS", with: blankCanvas ? "true" : "false"), as: [Int].self)
      let lacking = blankCanvas ? "no image" : "no markup"
      let named = [
        "a page with markup and an image: the switch enabled", "the overlay on",
        "turned to a page with \(lacking): the overlay off, its switch disabled"
          + (blankCanvas ? ", the text alone" : ", the image shown"),
        "back on a page with markup and an image: enabled, the overlay still off, the image shown",
        "on the page with \(lacking) again: disabled, off" + (blankCanvas ? ", the text alone" : ""),
      ]
      for (check, name) in zip(checks, named) { #expect(check == 1, "\(name) (registered: \(registered))") }
      try await page.expectNoErrors()
    }
  }

  /// The images put away (the header's Image switch) with the overlay
  /// on take the overlay with them (user, 2026-10-18): the pane leaves
  /// overlay mode as the overlay's own switch would leave it (not active,
  /// not registered, not fading, the pane scrolling again), the overlay's
  /// switch off and disabled. The images back on bring the overlay back as
  /// it was: on, registered, its switch pressed and enabled.
  @Test(arguments: [true, false])
  func imagesOffTakeTheOverlayWithThem(registered: Bool) async throws {
    let server = try await Self.structureServer(imageSwitch: true)
    defer { server.stop() }
    let config = BrowserTestConfiguration(baseURL: URL(string: server.baseURL)!, engines: [.chrome], defaultTimeout: .seconds(30))
    try await withPage(.chrome, config, viewport: .init(width: 1440, height: 600)) { page in
      try await page.goto("/")
      try await expect(page.locator("html")).toHaveAttribute("data-wasm-status", "started")
      try await page.evaluate("new Promise(resolve=>setTimeout(resolve,700))")
      let checks = try await page.evaluate(#"""
        (async()=>{const wait=ms=>new Promise(r=>setTimeout(r,ms)),r=document.querySelector('.artifact-view');
          if(!REGISTERED)r.querySelector('.tei-page').removeAttribute('data-text-block');
          const press=(wrap,on)=>{wrap.setAttribute('aria-pressed',on?'true':'false');wrap.querySelector('button').setAttribute('aria-pressed',on?'true':'false');
            wrap.dispatchEvent(new CustomEvent('toggle-button-update',{detail:on?'true':'false'}))};
          const images=r.querySelector('.artifact-canvas-toggle'),overlay=r.querySelector('.artifact-overlay-toggle'),button=overlay.querySelector('button');
          const pane=r.querySelector('.artifact-markup');
          press(images,true);await wait(900);
          const imagesOn=r.dataset.canvasShown==='true';
          press(overlay,true);await wait(900);
          const on=()=>r.dataset.overlayActive==='true'&&overlay.getAttribute('aria-pressed')==='true'&&button.getAttribute('aria-pressed')==='true'
            &&!button.disabled&&(r.dataset.overlayRegistered==='true')===REGISTERED;
          const overlayOn=on();
          press(images,false);await wait(900);
          const off=r.dataset.canvasShown==='false'&&r.dataset.overlayActive==='false'&&r.dataset.overlayRegistered!=='true'
            &&r.dataset.overlayFading!=='true'&&overlay.getAttribute('aria-pressed')==='false'&&button.getAttribute('aria-pressed')==='false'
            &&button.disabled&&button.getAttribute('aria-disabled')==='true'&&getComputedStyle(pane).overflowY==='auto'
            &&!r.querySelector('.artifact-structure');
          press(images,true);await wait(900);
          const back=r.dataset.canvasShown==='true'&&on();
          return [imagesOn,overlayOn,off,back].map(Number)})()
        """#.replacingOccurrences(of: "REGISTERED", with: registered ? "true" : "false"), as: [Int].self)
      let named = [
        "the images on", "the overlay on",
        "the images off: the overlay off in the pane and its switch, disabled, the pane scrolling",
        "the images back on: the overlay back on, its switch pressed",
      ]
      for (check, name) in zip(checks, named) { #expect(check == 1, "\(name) (registered: \(registered))") }
      try await page.expectNoErrors()
    }
  }

  /// A word whose `@facs` names several zones of one scan line—a title's
  /// letter-spaced "OF", a zone a letter, as on prod madrigal dd5cc0b2's
  /// page 3—is banded on the scan as one box, the union of its zones,
  /// never its letters apart; the scan's point between two of its letters
  /// marks it (user, 2026-10-18). A word broken over two lines is a band a
  /// line. The model's grouping is the authority: words are planted as the
  /// tools write them (`data-scan-layout`, `data-word-zones`).
  @Test(arguments: [1440, 440])
  func aLetterSpacedWordIsBandedAsOneBox(width: Int) async throws {
    let server = try await Self.structureServer()
    defer { server.stop() }
    let config = BrowserTestConfiguration(baseURL: URL(string: server.baseURL)!, engines: [.chrome], defaultTimeout: .seconds(30))
    try await withPage(.chrome, config, viewport: .init(width: width, height: 600)) { page in
      try await page.goto("/")
      try await expect(page.locator("html")).toHaveAttribute("data-wasm-status", "started")
      try await page.evaluate("new Promise(resolve=>setTimeout(resolve,700))")
      let checks = try await page.evaluate(#"""
        (async()=>{const wait=ms=>new Promise(r=>setTimeout(r,ms)),r=document.querySelector('.artifact-view');
          const page=r.querySelector('.tei-page'),lines=[...page.querySelectorAll('.tei-line')];
          // "OF" letter-spaced on line 1 (a zone a letter), "bro-ken" broken over lines 1 and 2, and "gypsy" with descenders.
          lines[0].innerHTML='<span class="tei-word" data-line="1" data-word="1">OF</span> <span class="tei-word" data-line="1" data-word="2">bro-</span> <span class="tei-word" data-line="1" data-word="4">gypsy</span>';
          lines[1].innerHTML='<span class="tei-word" data-line="1" data-word="2">ken</span>';
          const zone=(type,id,[l,t,r,b])=>[type,type==='block'?'main':'-',id,l,t,r,t,r,b,l,b].join(' ');
          page.dataset.scanLayout=[zone('block','-',[300,300,400,350]),zone('line','-',[300,300,400,320]),
            zone('word','a1',[300,300,310,320]),zone('word','a2',[330,300,340,320]),zone('word','a3',[360,300,370,320]),
            zone('word','b1',[380,300,400,320]),zone('line','-',[300,330,400,350]),zone('word','b2',[300,330,330,350]),zone('word','d1',[340,330,370,350])].join(';');
          page.dataset.wordZones='1:1 a1 a2 a3;1:2 b1 b2;1:4 d1';
          const bands=()=>[...document.querySelectorAll('.image-word')].filter(b=>!b.hidden).map(b=>b.getBoundingClientRect());
          const words=[...page.querySelectorAll('.tei-word')],object=r.querySelector('.artifact-object');
          words[0].dispatchEvent(new MouseEvent('mouseover',{bubbles:true}));await wait(100);
          const of=bands();
          // One band, the union's shape: 70 by 20 of the 0–1000 space on a 4800 by 6400 scan.
          const ratio=of.length===1?(of[0].width/of[0].height)/((70*4800)/(20*6400)):0;
          const one=of.length===1&&Math.abs(ratio-1)<0.05;
          // The word marked as the scan's, its point on the scan (`at`: the band's fraction across).
          const leave=async()=>{object.dispatchEvent(new MouseEvent('mouseleave'));r.querySelector('.artifact-markup').dispatchEvent(new MouseEvent('mouseleave'));await wait(50)};
          const viaScan=async(w,across)=>{w.dispatchEvent(new MouseEvent('mouseover',{bubbles:true}));await wait(100);const b=bands()[0];await leave();
            object.dispatchEvent(new MouseEvent('mousemove',{clientX:b.x+across*b.width,clientY:b.y+b.height/2,bubbles:true}));await wait(100)};
          // The edition's band as its word's face says it: the glyphs' width less the letter-spacing trailing the last
          // letter; down, the face's ink envelope ("ÉÅfhgjpqy|" at 200px, measured in the word's font) scaled by the
          // span's own font size and set on its baseline—whatever letters the word holds—in the span's own pixels
          // (the zoom taken out). [matches, baseline, band top and bottom in the window's, band height in the span's].
          const measure=w=>{const range=document.createRange();range.setStart(w,0);range.setEnd(w,w.childNodes.length);
            const rects=[...range.getClientRects()].filter(q=>q.width>0),own=w.getBoundingClientRect(),scale=own.width/w.offsetWidth,style=getComputedStyle(w);
            const text=[Math.min(...rects.map(q=>q.left)),Math.max(...rects.map(q=>q.right)),Math.min(...rects.map(q=>q.top)),Math.max(...rects.map(q=>q.bottom))];
            const ctx=document.createElement('canvas').getContext('2d');ctx.font=style.fontStyle+' '+style.fontWeight+' 200px '+style.fontFamily;ctx.fontVariantCaps=style.fontVariantCaps;
            const m=ctx.measureText('ÉÅfhgjpqy|'),unit=parseFloat(style.fontSize)*scale/200,baseline=rects[0].top+m.fontBoundingBoxAscent*unit;
            const inkTop=baseline-m.actualBoundingBoxAscent*unit,inkBottom=baseline+m.actualBoundingBoxDescent*unit;
            const spacing=parseFloat(style.letterSpacing)||0;
            const px=name=>parseFloat(w.style.getPropertyValue('--artifact-band-'+name));
            const matches=w.dataset.band==='true'&&Math.abs(px('width')*scale-(text[1]-text[0]-spacing*scale))<1&&Math.abs(px('height')*scale-(inkBottom-inkTop))<1
              &&Math.abs(px('x')*scale-(text[0]-own.left))<1&&Math.abs(px('y')*scale-(inkTop-own.top))<1&&getComputedStyle(w).backgroundImage.includes('gradient');
            return {matches,spacing,scale,baseline,height:px('height'),
              bottom:own.top+(px('y')+px('height'))*scale,top:own.top+px('y')*scale,box:text[3]-text[2]}};
          // The scan between O and F (x 320 of 300–370) marks the word.
          await leave();
          let gap=false,hug=false,caps=false,zoomed=false,of2=null;
          if(of.length===1){const b=of[0];object.dispatchEvent(new MouseEvent('mousemove',{clientX:b.x+(320-300)/70*b.width,clientY:b.y+b.height/2,bubbles:true}));await wait(100);
            gap=words[0].dataset.corresponding==='true'&&bands().length===1;
            const m=measure(words[0]);hug=m.spacing>0&&m.matches;
            of2=m;
            // Zoomed with it marked, the band follows.
            const pane=r.querySelector('.artifact-markup'),pb=pane.getBoundingClientRect(),layer=r.querySelector('[data-layer=rendering]'),before=Number(layer.dataset.zoom),scaled=m.scale;
            for(let i=0;i<8;i++){pane.dispatchEvent(new WheelEvent('wheel',{deltaY:-40,clientX:pb.x+pb.width/2,clientY:pb.y+pb.height/2,bubbles:true,cancelable:true}));await wait(30)}
            await wait(400);const now=measure(words[0]);
            zoomed=Number(layer.dataset.zoom)>before&&words[0].dataset.corresponding==='true'&&Math.abs(now.scale-scaled)>0.01&&now.matches}
          await leave();
          // The same line, the same band: "OF" (capitals alone) and "gypsy" (descenders) share one top and one bottom, within a pixel;
          // the descender word's band is no taller than its neighbor's and still reaches below its baseline.
          await viaScan(words[0],0.5);
          const o=measure(words[0]);
          await leave();
          await viaScan(words[2],0.5);
          const g=measure(words[2]);
          of2=o;
          caps=!!of2&&g.matches&&Math.abs(g.top-of2.top)<1&&Math.abs(g.bottom-of2.bottom)<1;
          const descends=words[2].dataset.corresponding==='true'&&g.matches&&!!of2&&g.height<=of2.height+1&&g.bottom>g.baseline+1;
          // A smaller span's band is proportionally smaller: the same word at half the size.
          await leave();
          words[2].style.fontSize=(parseFloat(getComputedStyle(words[2]).fontSize)/2)+'px';await wait(100);
          await viaScan(words[2],0.5);
          const h=measure(words[2]);
          const smaller=h.matches&&Math.abs(h.height/g.height-0.5)<0.05;
          words[2].style.fontSize='';
          await leave();
          words[1].dispatchEvent(new MouseEvent('mouseover',{bubbles:true}));await wait(100);
          const broken=bands().length===2&&words[3].dataset.corresponding==='true';
          // The pair: the marked word and the scan's band wear one yellow at one opacity (user, 2026-10-18).
          const probe=document.createElement('div');document.body.appendChild(probe);
          probe.style.backgroundColor='color-mix(in srgb, var(--color-yellow) calc(var(--opacity-low) * 100%), transparent)';
          const mixed=getComputedStyle(probe).backgroundColor;
          probe.style.backgroundColor='var(--color-yellow)';const solid=getComputedStyle(probe).backgroundColor;probe.remove();
          const scanBand=[...document.querySelectorAll('.image-word')].find(b=>!b.hidden),scanStyle=getComputedStyle(scanBand);
          const lowOpacity=getComputedStyle(document.documentElement).getPropertyValue('--opacity-low').trim();
          const marked=page.querySelector('.tei-word[data-corresponding="true"]');
          const yellow=!!scanBand&&scanStyle.backgroundColor===solid&&Math.abs(parseFloat(scanStyle.opacity)-parseFloat(lowOpacity))<0.001
            &&!!marked&&marked.dataset.band==='true'&&getComputedStyle(marked).backgroundImage.split(mixed).length===3;
          return [one,gap,hug,caps,zoomed,descends,smaller,broken,yellow].map(Number)})()
        """#, as: [Int].self)
      let named = [
        "the letter-spaced word: one band, the union of its zones",
        "the scan between its letters marks the word",
        "the edition's band hugs the letter-spaced word: its glyphs' width less the trailing letter-spacing, its face's ink envelope down",
        "words of one size on a line share one band top and bottom: an all-capitals word's and a lowercase one's",
        "zoomed with the word marked, the band follows",
        "a word with descenders: its band is no taller than its neighbor's and reaches below the baseline",
        "a smaller span's band is proportionally smaller",
        "the word broken over lines: a band a line, its other part marked",
        "the marked word and the scan's band wear one yellow at one opacity",
      ]
      for (check, name) in zip(checks, named) { #expect(check == 1, "\(name) (width \(width))") }
      try await page.expectNoErrors()
    }
  }

  /// The fixture's reader at the text's fit, side by side or stacked:
  /// `RINGED` rings the pane (gnorium-web TestamentView's diff state: its
  /// border round); `toggle(on)`, `state()` (zoom, scroll and client
  /// height, width, the fit stored), `wait`, `pane` defined; the caller
  /// closes the function.
  static let atTheFit = #"""
    (async()=>{const wait=ms=>new Promise(r=>setTimeout(r,ms)),r=document.querySelector('.artifact-view');
      const toggle=on=>r.querySelector('.artifact-overlay-toggle').dispatchEvent(new CustomEvent('toggle-button-update',{detail:on?'true':'false'}));
      const pane=r.querySelector('.artifact-markup'),layer=()=>r.querySelector('[data-layer=rendering]');
      if(RINGED){const ring=document.createElement('style');ring.textContent='.artifact-markup{border:1px solid #888!important}';document.head.appendChild(ring);await wait(300)}
      // To its fit: zoomed out past it, never below it.
      const b=pane.getBoundingClientRect();
      for(let i=0;i<40;i++){pane.dispatchEvent(new WheelEvent('wheel',{deltaY:40,clientX:b.x+b.width/2,clientY:b.y+b.height/2,bubbles:true,cancelable:true}));await wait(10)}
      await wait(400);
      const state=()=>[Number(layer().dataset.zoom),pane.scrollHeight,pane.clientHeight,pane.scrollWidth,pane.clientWidth,sessionStorage.getItem('gnorium:artifact-zoom:rendering')==='fit'?1:0];
    """#

  /// The structure overlay's scene, worked out apart from the reader (the
  /// rule of `StructurePairing` and gnorium-python's structure image, step
  /// for step): the edition's rows (each line's ink, side by side one row),
  /// main text and marginalia apart, and the scan's lines (`data-scan-layout`)
  /// laid in the layer by the registration, paired by dynamic programming,
  /// each row's state; `{edition: [...], scan: [...], main: [top, bottom] of
  /// the scan's main blocks laid, target: [top, bottom] of the laid ink box}`
  /// in the window's pixels.
  static let structureScript = Self.shared + #"""
    // Beside a row, not under it (artifact-core `StructurePairing.beside`): on its baseline (7) where both have one,
    // within half the taller's height; else overlapping down the page by more than half the shorter's height.
    const beside=(row,line)=>row[7]!=null&&line[7]!=null?Math.abs(row[7]-line[7])<Math.max(row[3]-row[1],line[3]-line[1])/2
      :Math.min(row[3],line[3])-Math.max(row[1],line[1])>Math.min(row[3]-row[1],line[3]-line[1])/2;
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
            // Its baseline (7): the font box's top plus the font's ascent; (8) the em of the line it is of.
            if(right>left&&bottom>top)lines.push([left,top,right,bottom,setting,lineEm,blockEl,drawn.top+m.fontBoundingBoxAscent*s,lineEm])}}}
        lines.sort((a,c)=>a[1]-c[1]);const rows=[];for(const l of lines){const last=rows[rows.length-1];if(last&&beside(last,l)){
          // A left-set line beside a right-set one: both edges judged, no block's last line.
          if((last[4]==='left'&&l[4]==='right')||(last[4]==='right'&&l[4]==='left')){last[4]='justified';last[6]=null}
          last[0]=Math.min(last[0],l[0]);last[1]=Math.min(last[1],l[1]);last[2]=Math.max(last[2],l[2]);last[3]=Math.max(last[3],l[3]);
          // A row's baseline its largest type's, the lower of equal ones.
          if(l[8]>last[8]||(l[8]===last[8]&&l[7]>last[7])){last[7]=l[7];last[8]=l[8]}}else rows.push([...l])}
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
      // measure (its ink at both sides within a word space of the frame's face) by its ink's width, from its
      // left, its proportions kept; any other by its height, centered.
      const ink=inkBox(layer),edges=frame.getBoundingClientRect(),fs=getComputedStyle(frame);
      context.font=fs.fontStyle+' '+fs.fontWeight+' '+fs.fontSize+' '+fs.fontFamily;const space=context.measureText(' ').width*z;
      const spans=!!ink&&frame!==layer&&ink[0]-edges.left<=space&&edges.right-ink[2]<=space;
      // Where the work's frame is declared (`data-scan-em`), always at the type's scale (user, 2026-10-17): the rendered em over
      // the work's em on the scan, the scan at its own size from the block's top, centered across it (artifact-core
      // `OverlayRegistration.laid`); else by the block, a derived one the frame whole.
      const scanEm=Number(page.dataset.scanEm)/1000*W,renderedEm=parseFloat(fs.fontSize)*z,typeScale=scanEm>0&&renderedEm>0?renderedEm/scanEm:0;
      // Across by the edge the block is set from (`OverlayRegistration.anchor`): more than half its lines left, from its
      // left; right, from its right; else centered.
      const settings=[];{const w=document.createTreeWalker(frame,NodeFilter.SHOW_TEXT);for(let n=w.nextNode();n;n=w.nextNode()){const st=getComputedStyle(n.parentElement),ta=st.textAlign,rtl=st.direction==='rtl';
        const set=ta==='justify'?'justified':ta==='center'?'center':(ta==='right'||(ta==='end'&&!rtl)||(ta==='start'&&rtl))?'right':'left';
        for(const rect of (()=>{range.selectNodeContents(n);return [...range.getClientRects()]})())if(rect.height>0)settings.push(set)}}
      const anchor=settings.filter(x=>x==='left').length*2>settings.length?'left':settings.filter(x=>x==='right').length*2>settings.length?'right':'center';
      const typedOn=([L,T,R],s)=>{const across=Math.hypot(zone[1][0]-zone[0][0],zone[1][1]-zone[0][1]),down=Math.hypot(zone[3][0]-zone[0][0],zone[3][1]-zone[0][1]),w=across*s,left=anchor==='left'?L:anchor==='right'?R-w:(L+R)/2-w/2;return [left,T,left+w,T+down*s]};
      const derived=page.dataset.textBlockDerived==='true',laid=typeScale>0?typedOn(derived?[edges.left,edges.top,edges.right]:ink,typeScale):derived?[edges.left,edges.top,edges.right,edges.bottom]:spans?(()=>{const across=Math.hypot(zone[1][0]-zone[0][0],zone[1][1]-zone[0][1]),down=Math.hypot(zone[3][0]-zone[0][0],zone[3][1]-zone[0][1]),sc=(ink[2]-ink[0])/across;return [ink[0],ink[1],ink[2],ink[1]+down*sc]})():laidOn(zone,ink);
      const h=homography(zone,[[laid[0],laid[1]],[laid[2],laid[1]],[laid[2],laid[3]],[laid[0],laid[3]]]);
      const quads=[],marginBlocks=[];let main=true;
      for(const entry of page.dataset.scanLayout.split(';')){const p=entry.split(' ');const pts=p.slice(3).map(Number);const q=[0,1,2,3].map(i=>apply(h,[pts[2*i]/1000*W,pts[2*i+1]/1000*H]));
        const box=[Math.min(...q.map(v=>v[0])),Math.min(...q.map(v=>v[1])),Math.max(...q.map(v=>v[0])),Math.max(...q.map(v=>v[1]))];
        // A line's baseline (7): the middle of its <path type="baseline">'s two ends, laid as its corners are.
        if(pts.length===12){const a=apply(h,[pts[8]/1000*W,pts[9]/1000*H]),c2=apply(h,[pts[10]/1000*W,pts[11]/1000*H]);box[7]=(a[1]+c2[1])/2}
        if(p[0]==='block'){main=p[1]!=='marginalia';quads.push({kind:'block',main,box});if(!main)marginBlocks.push({box,lines:[]})}
        else if(p[0]==='line'){quads.push({kind:'line',main,box});if(!main&&marginBlocks.length)marginBlocks[marginBlocks.length-1].lines.push(box)}}
      const rowsFrom=lines=>{lines.sort((a,c)=>a[1]-c[1]);const rows=[];for(const l of lines){const last=rows[rows.length-1];if(last&&beside(last,l)){last[0]=Math.min(last[0],l[0]);last[1]=Math.min(last[1],l[1]);last[2]=Math.max(last[2],l[2]);last[3]=Math.max(last[3],l[3]);
        if(l[7]!=null&&(last[7]==null||l[7]>last[7]))last[7]=l[7]}else rows.push([...l])}return rows};
      // Where a row's letters sit: its baseline, else its ink's bottom (typeface is not parity).
      const seat=r=>r[7]!=null?r[7]:r[3];
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
      // Its size (`StructurePairing.sized`): its width against the print line's by the page's ratio of the two (the
      // median over the main text's pairs), within an em of its type or a sixth of the width.
      let ratio=0;const sized=(e,s)=>{const want=(s[2]-s[0])*ratio;return !(ratio>0&&want>0)||Math.abs((e[2]-e[0])-want)<=Math.max(e[5]||0,want*0.15)};
      // Paired on e and s (each from its own box for a note), judged where each stands (E, S), by L.
      const pair=(e,s,L,E=e,S=s)=>{const n=e.length,m=s.length,c=[...Array(n+1)].map(()=>Array(m+1).fill(0)),st=[...Array(n+1)].map(()=>Array(m+1).fill(0));
        for(let i=0;i<=n;i++)for(let j=0;j<=m;j++){if(!i&&!j)continue;let best=Infinity,mv=0;if(i&&j)best=c[i-1][j-1]+2*Math.abs(seat(e[i-1])-seat(s[j-1]));
          if(i&&c[i-1][j]+L<best){best=c[i-1][j]+L;mv=1}if(j&&c[i][j-1]+L<best){best=c[i][j-1]+L;mv=2}c[i][j]=best;st[i][j]=mv}
        const es=Array(n).fill('within'),ss=Array(m).fill('within'),pairs=[];let i=n,j=m;
        while(i||j){const mv=st[i][j];if(mv===0){const ok=Math.abs(seat(E[i-1])-seat(S[j-1]))<=L/4&&across(E[i-1],S[j-1])&&sized(E[i-1],S[j-1]);es[i-1]=ss[j-1]=ok?'within':'off';pairs.push([i-1,j-1]);i--;j--}else if(mv===1){es[i-1]='extra';i--}else{ss[j-1]='missing';j--}}
        return [es,ss,pairs]};
      // Down the page by its lines (`OverlayRegistration.baselineShift`): the median distance from the scan's paired
      // baselines to the edition's, three pairs at least; the whole scan moved by it (a margin block's lines are its quads').
      // Across by the median distance between their set edges (`OverlayRegistration.edgeShift`).
      {const median=d=>{d.sort((a,c)=>a-c);return d.length<3?0:d.length%2?d[(d.length-1)/2]:(d[d.length/2-1]+d[d.length/2])/2};
        const pairs=pair(editionMain,scanMain,L)[2];
        const dy=median(pairs.map(([e,k])=>seat(editionMain[e])-seat(scanMain[k])));
        const dx=median(pairs.map(([e,k])=>{const a=editionMain[e],b=scanMain[k];return a[4]==='left'?a[0]-b[0]:a[4]==='right'?a[2]-b[2]:a[4]==='center'?(a[0]+a[2])/2-(b[0]+b[2])/2:a[4]==='justified'?(a[0]-b[0]+a[2]-b[2])/2:null}).filter(x=>x!=null));
        if(dx||dy){const move=r=>{r[0]+=dx;r[2]+=dx;r[1]+=dy;r[3]+=dy;if(r[7]!=null)r[7]+=dy};scanMain.forEach(move);quads.forEach(q=>move(q.box));laid[0]+=dx;laid[2]+=dx;laid[1]+=dy;laid[3]+=dy}}
      const moved=(rows,[x,y])=>rows.map(r=>{const m=[r[0]-x,r[1]-y,r[2]-x,r[3]-y];if(r[7]!=null)m[7]=r[7]-y;return m});
      {const r=pair(editionMain,scanMain,L)[2].filter(([e,k])=>scanMain[k][2]>scanMain[k][0]).map(([e,k])=>(editionMain[e][2]-editionMain[e][0])/(scanMain[k][2]-scanMain[k][0])).sort((a,c)=>a-c);
        ratio=r.length?(r.length%2?r[(r.length-1)/2]:(r[r.length/2-1]+r[r.length/2])/2):0}
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
  /// read by the client (user, 2026-10-14). Side by side, every word of
  /// the edition bands its zones on the scan, as the tools linked them
  /// (each `<w>`'s `@facs`, user, 2026-10-15), and a band's zone on the scan
  /// marks the edition's word; a word broken over lines is one: either part
  /// bands both its zones and marks the other part. Overlay on draws the structure: the scan's main
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
      "layout-view.css", "tei-view.css", "artifact-view.css", "image-view.css", "tooltip-view.css", "sheet-view.css",
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
      </div></div><div class="artifact-object"><div class="image-view" data-service-id="/scan"><div class="image-viewport"><div class="image-spinner"></div></div></div></div></div><footer><div class="artifact-overlay-toggle"><button>Overlay</button></div><div class="artifact-detach-toggle"><button class="button-view"><span class="button-icon">Detach</span></button></div></footer></div><script src="/loader.js"></script></body></html>
      """#
    var files: [String: FixtureServer.File] = [
      "/": .init(contentType: "text/html", body: Data(html.utf8)),
      "/loader.js": .init(contentType: "text/javascript", body: try Data(contentsOf: assets.appendingPathComponent("loader.js"))),
      "/client.wasm": .init(contentType: "application/wasm", body: try Data(contentsOf: assets.appendingPathComponent("client.wasm"))),
      "/manifest": .init(contentType: "application/json", body: Data(#"{"canvases":[{"id":"/scan","w":\#(size.width),"h":\#(size.height),"imgs":["/scan.jpg"]}]}"#.utf8)),
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
      // Side by side: every word of the edition, hovered, bands its zones;
      // a band's middle on the scan marks its word again (each of its
      // parts), and a broken word's either part bands both its zones and
      // marks the other part.
      if canvas != 2 {
        let words = try await page.evaluate(#"""
          (async()=>{const wait=ms=>new Promise(r=>setTimeout(r,ms)),words=[...document.querySelectorAll('.tei-page[data-active=true] .tei-word')];let paired=0,round=0,broken=0;
            const place=w=>w.dataset.line+':'+w.dataset.word,o=document.querySelector('.artifact-object');
            const bands=()=>[...document.querySelectorAll('.image-word')].filter(b=>!b.hidden);
            for(const word of words){word.dispatchEvent(new MouseEvent('mouseover',{bubbles:true}));await wait(5);const shown=bands();
              if(!shown.length)continue;paired++;
              const parts=words.filter(w=>place(w)===place(word));
              if(parts.length>1&&broken===0)broken=shown.length>=parts.length&&parts.filter(w=>w!==word).every(w=>w.dataset.corresponding==='true')?1:-1;
              if(round)continue;const b=shown[0].getBoundingClientRect();
              o.dispatchEvent(new MouseEvent('mousemove',{clientX:b.x+b.width/2,clientY:b.y+b.height/2,bubbles:true}));await wait(5);
              const marked=[...document.querySelectorAll('.tei-word[data-corresponding=true]')];
              round=marked.length>0&&marked.some(w=>w===word)?1:-1;
              o.dispatchEvent(new MouseEvent('mouseleave',{bubbles:true}));await wait(5)}
            return [words.length,paired,round,broken]})()
          """#, as: [Int].self)
        print("canvas \(canvas) at \(width): \(words[1]) of \(words[0]) words band their zones")
        #expect(words[0] > 0 && words[1] == words[0], "canvas \(canvas): \(words[0] - words[1]) words band no zone")
        #expect(words[2] == 1, "canvas \(canvas): the scan's word under the band does not mark the edition's")
        #expect(words[3] >= 0, "canvas \(canvas): a broken word's part does not band and mark the whole word")
        if let directory = ProcessInfo.processInfo.environment["GNORIUM_SCREENSHOT_DIR"] {
          // A word in the page's middle hovered: its band on the scan.
          _ = try await page.evaluate(#"""
            (async()=>{const words=[...document.querySelectorAll('.tei-page[data-active=true] .tei-word')];
              for(const word of words.slice(Math.floor(words.length/2)).concat(words)){word.dispatchEvent(new MouseEvent('mouseover',{bubbles:true}));await new Promise(r=>setTimeout(r,5));
                const band=document.querySelector('.image-word');if(band&&!band.hidden){word.dataset.corresponding='true';break}}return 1})()
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
        // A click on a word's band on the scan does what a click on the word
        // does (user, 2026-10-18): its gloss opens over the text pane, the
        // pane brought to the word first; a press that moved (a pan) opens
        // nothing.
        let band = try await page.evaluate(#"""
          (async()=>{const wait=ms=>new Promise(r=>setTimeout(r,ms)),R=e=>e.getBoundingClientRect(),o=document.querySelector('.artifact-object'),p=document.querySelector('.artifact-markup');
            document.querySelector('.tei-view').dataset.gloss='/gloss';
            const words=[...p.querySelectorAll('.tei-page[data-active=true] .tei-word')],word=words[Math.floor(words.length/2)];
            word.dispatchEvent(new MouseEvent('mouseover',{bubbles:true}));await wait(100);
            const band=[...document.querySelectorAll('.image-word')].find(b=>!b.hidden);if(!band)return 'noband';
            const b=R(band),x=b.x+b.width/2,y=b.y+b.height/2;
            o.dispatchEvent(new MouseEvent('mouseleave',{bubbles:true}));await wait(50);p.scrollTop=0;p.scrollLeft=0;await wait(50);
            const press=(down,up)=>{o.dispatchEvent(new MouseEvent('mousedown',{clientX:down[0],clientY:down[1],bubbles:true}));o.dispatchEvent(new MouseEvent('mouseup',{clientX:up[0],clientY:up[1],bubbles:true}));o.dispatchEvent(new MouseEvent('click',{clientX:up[0],clientY:up[1],bubbles:true}))};
            press([x,y],[x+20,y]);await wait(500);const open=()=>[...document.querySelectorAll('.gloss-sheet .sheet-panel')].some(e=>R(e).width>0),panned=!open();
            o.dispatchEvent(new MouseEvent('mouseleave',{bubbles:true}));press([x,y],[x,y]);await wait(600);
            const w=R(word),q=R(p);
            const opened=open(),shown=w.bottom>q.top&&w.top<q.bottom&&w.right>q.left&&w.left<q.right;
            (document.activeElement||document.body).dispatchEvent(new KeyboardEvent('keydown',{key:'Escape',bubbles:true}));await wait(500);
            return JSON.stringify([panned,opened,shown])})()
          """#, as: String.self)
        #expect(band == "[true,true,true]", "a click on a word's band at \(width): a pan opens nothing, a click opens its gloss, the pane at the word: \(band)")
      }
      try await page.evaluate("document.querySelector('.artifact-overlay-toggle').dispatchEvent(new CustomEvent('toggle-button-update',{detail:'true'}))")
      // At rest: the motion and the panes' move done.
      try await page.evaluate("new Promise(resolve=>setTimeout(resolve,1200))")
      let read = "(()=>{" + Self.structureScript + #"""
        const tally=list=>list.reduce((t,s)=>(t[s]=(t[s]||0)+1,t),{});
        // Read unturned: the overlay turns the edition onto the image as it is photographed, and the rule reads the
        // layout's own rows (a turned line's box is its bounds); its states are the same wherever the page lies.
        const turned=[...document.querySelectorAll('.artifact-markup [data-page-scale=true]')],kept=turned.map(f=>f.style.transform);
        turned.forEach(f=>f.style.transform='none');const s=structureOf();turned.forEach((f,i)=>f.style.transform=kept[i]);
        return {expected:{edition:tally(s.edition),scan:tally(s.scan)},drawn:{edition:tally(drawnStates('edition')),scan:tally(drawnStates('scan'))},main:s.main,target:s.target}})()
        """#
      let scene = try await page.evaluate(read, as: Scene.self)
      if let directory = ProcessInfo.processInfo.environment["GNORIUM_SCREENSHOT_DIR"] {
        try await page.screenshot(to: URL(fileURLWithPath: directory).appendingPathComponent("skeat-canvas-\(canvas)-structure-\(width).png"))
      }
      print("canvas \(canvas) at \(width): \(scene.drawn)")
      #expect(scene.drawn == scene.expected, "canvas \(canvas): drawn \(scene.drawn), the rule gives \(scene.expected)")
      // The model's structure image judges the canvas alike (gnorium-python
      // `test_structure_skeat`): both held to the same counts.
      let shared = try JSONDecoder().decode(
        [String: [String: [String: Int]]].self, from: Data(contentsOf: skeat.appendingPathComponent("structure.json")))
      #expect(scene.drawn == shared[String(canvas)], "canvas \(canvas): drawn \(scene.drawn), the image's \(shared[String(canvas)] ?? [:])")
      // A page whose only lines are the copy's (a provenance stamp) draws
      // the scan's alone: copy evidence never joins the edition (user,
      // 2026-10-26).
      #expect(!scene.drawn.values.allSatisfy { $0.isEmpty }, "canvas \(canvas): no structure drawn")
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
