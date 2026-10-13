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
}
