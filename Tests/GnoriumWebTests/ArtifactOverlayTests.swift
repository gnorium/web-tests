import Foundation
import Testing
import WebTests
import WebTestsTesting

@Suite("Artifact overlay", .serialized)
struct ArtifactOverlayTests {
  @Test(arguments: [1000, 440])
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
  /// by the homography that takes those corners onto the rendered text
  /// block's, easing in with the overlay's 400ms motion, and overlay off
  /// takes it away again (user, 2026-10-13).
  @Test(arguments: [1000, 440])
  func overlayRegistersTheScansTextBlockUnderTheEditions(width: Int) async throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let assets = root.appendingPathComponent("gnorium-web/Public")
    let css = try ["layout-view.css", "tei-view.css", "artifact-view.css", "canvas-view.css"].map {
      try String(contentsOf: assets.appendingPathComponent("style-sheets/" + $0), encoding: .utf8)
    }.joined(separator: "\n")
    let lines = (1...30).map { #"<span class="tei-line">Line \#($0) of the page, set across the frame's measure.</span>"# }.joined()
    let html = "<!doctype html><html><head><meta charset=\"utf-8\"><style>" + css + #"""
      body{margin:0}.artifact-view{width:100%;height:600px}.artifact-viewer-container{height:560px;flex:none}.tei-line{display:block;font-family:serif!important;white-space:nowrap}</style><link rel="icon" href="data:,"></head><body><div class="artifact-view" data-canvas-shown="true" data-manifest-url="/manifest"><div class="artifact-viewer-container"><div class="artifact-markup-frame"><div class="artifact-markup"><div class="tei-view"><div class="tei-page" data-service-id="/scan" data-active="true" data-text-block="120,90 880,104 868,912 108,898"><div class="tei-page-text" data-layer="rendering" data-framed="true"><div class="tei-text-block" style="--tei-frame-measure: 30; --tei-frame-margin: 5">
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
          // The rendered text block: its text's box, within the frame's measure.
          const target=()=>{const f=r.querySelector('.tei-text-block'),e=f.getBoundingClientRect(),rg=document.createRange(),w=document.createTreeWalker(f,NodeFilter.SHOW_TEXT);let L=1e9,T=1e9,R=-1e9,B=-1e9;
            while(w.nextNode()){if(!w.currentNode.data.trim())continue;rg.selectNodeContents(w.currentNode);const b=rg.getBoundingClientRect();L=Math.min(L,b.left);T=Math.min(T,b.top);R=Math.max(R,b.right);B=Math.max(B,b.bottom)}
            L=Math.max(L,e.left);R=Math.min(R,e.right);return [[L,T],[R,T],[R,B],[L,B]]};
          const off=()=>Math.max(...landed().map((p,i)=>Math.hypot(p[0]-target()[i][0],p[1]-target()[i][1])));
          const none=getComputedStyle(surface()).transform==='none';
          toggle(true);await wait(150);const midway=off();await wait(650);const registered=off();
          const skewed=Math.abs(new DOMMatrix(getComputedStyle(surface()).transform).b)>0.001;
          toggle(false);await wait(800);const cleared=getComputedStyle(surface()).transform==='none';
          return [none,midway>registered+5,registered<2,skewed,cleared,Math.round(registered*100)/100].map(Number);
        })()
        """#, as: [Double].self)
      #expect(checks[0] == 1, "no registration before the overlay")
      #expect(checks[1] == 1, "the registration eases in with the overlay's motion")
      #expect(checks[2] == 1, "the zone's corners land on the rendered text block's within 2px (off by \(checks[5]))")
      #expect(checks[3] == 1, "the scan is turned by its measured skew")
      #expect(checks[4] == 1, "overlay off takes the registration away")
      try await page.expectNoErrors()
    }
  }
}
