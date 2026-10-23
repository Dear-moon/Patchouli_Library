import 'dart:convert';
import 'dart:io';
import 'package:wenku8_flutter/archive_icons.dart';

/// Flutter's actual geometry and clocks, not an exaggerated CSS mockup.
void exportIconStudio(Directory output) {
  output.createSync(recursive: true);
  final svg = Directory('${output.path}/svg')..createSync(recursive: true);
  List<String> frames(
    ArchiveSymbol source,
    ArchiveSymbol target,
    bool from,
    bool to,
  ) => [
    for (var i = 0; i <= 32; i++)
      ArchiveIconArt.svg(
        source,
        towards: target,
        active: from,
        towardsActive: to,
        progress: ArchiveIconMotion.stateAt(i / 32),
        gesture: ArchiveIconMotion.frame(i / 32),
      ),
  ];
  final entries = [
    for (final symbol in ArchiveSymbol.values)
      {
        'id': symbol.name,
        'label': symbol.label,
        'group': symbol.group,
        'static': ArchiveIconArt.svg(symbol),
        'on': ArchiveIconArt.svg(_target(symbol), active: true),
        'onFrames': frames(symbol, _target(symbol), false, true),
        'offFrames': frames(_target(symbol), symbol, true, false),
        'hoverFrames': frames(symbol, symbol, false, false),
        'activeFrames': frames(_target(symbol), _target(symbol), true, true),
      },
  ];
  for (final symbol in ArchiveSymbol.values) {
    File(
      '${svg.path}/${symbol.name}.svg',
    ).writeAsStringSync(ArchiveIconArt.svg(symbol));
  }
  File('${output.path}/index.html').writeAsStringSync(
    _html.replaceFirst('/*ICON_DATA*/[]', jsonEncode(entries)),
  );
}

ArchiveSymbol _target(ArchiveSymbol s) => switch (s) {
  ArchiveSymbol.play => ArchiveSymbol.pause,
  ArchiveSymbol.pause => ArchiveSymbol.play,
  ArchiveSymbol.bookmark => ArchiveSymbol.bookmarked,
  ArchiveSymbol.bookmarked => ArchiveSymbol.bookmark,
  ArchiveSymbol.forward => ArchiveSymbol.down,
  ArchiveSymbol.down => ArchiveSymbol.forward,
  ArchiveSymbol.circle => ArchiveSymbol.selected,
  ArchiveSymbol.selected => ArchiveSymbol.circle,
  ArchiveSymbol.eye => ArchiveSymbol.eyeOff,
  ArchiveSymbol.eyeOff => ArchiveSymbol.eye,
  _ => s,
};

const _html = r'''<!doctype html>
<html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>折页墨线 · 轻小说文库动态图标 II</title>
<style>
:root{color-scheme:light;--paper:#f4f3ef;--surface:#fdfcfa;--ink:#181818;--muted:#70746c;--line:#d8dbd5;--soft:rgba(24,24,24,.055)}
:root.dark{color-scheme:dark;--paper:#191919;--surface:#242424;--ink:#f2f2f2;--muted:#b7b7b7;--line:#3c3c3c;--soft:rgba(255,255,255,.065)}
*{box-sizing:border-box}body{margin:0;color:var(--ink);background:var(--paper);font-family:system-ui,-apple-system,"PingFang SC","Microsoft YaHei",sans-serif}
main{max-width:1160px;margin:0 auto;padding:42px 44px 32px}.code{font:10px/1.5 ui-monospace,SFMono-Regular,monospace;letter-spacing:1.3px;color:var(--muted)}
header{display:flex;align-items:center;justify-content:space-between;gap:20px}button{font:inherit;color:inherit;cursor:pointer;touch-action:manipulation}button:focus-visible{outline:2px solid var(--ink);outline-offset:4px}button:disabled{opacity:.4;cursor:default}
.tools{display:flex;gap:8px;align-items:center}.tool{border:1px solid var(--line);border-radius:24px;background:transparent;padding:8px 14px;font-size:12px}.tool:hover{background:var(--soft)}
h1{font-family:"Songti SC","Noto Serif CJK SC","STSong",serif;font-size:50px;font-weight:600;letter-spacing:3px;margin:38px 0 12px}p{color:var(--muted);line-height:1.8;margin:0}.intro{display:flex;align-items:end;justify-content:space-between;gap:24px}.intro p{font-size:14px}
.featured{margin:32px 0 28px;display:grid;grid-template-columns:repeat(6,minmax(0,1fr));border-block:1px solid var(--line);padding:24px 0 20px;gap:8px}
.feature{border:0;background:transparent;display:flex;flex-direction:column;align-items:center;gap:12px;position:relative;padding:12px 4px;border-radius:4px}.feature:hover{background:var(--soft)}.feature .glyph svg{width:52px;height:52px}.feature .name{font-size:14px}.feature .note{font-size:11px;color:var(--muted);letter-spacing:.5px}.feature .mini{position:absolute;top:49px;right:12px;opacity:.35;pointer-events:none}.feature .mini svg{width:20px;height:20px}
.hero{display:flex;align-items:center;justify-content:space-between;gap:24px;padding:4px 0 28px;margin-bottom:18px}.dock{display:flex;gap:6px;border-radius:36px;background:var(--surface);padding:6px 10px;box-shadow:0 4px 18px var(--soft)}
.dock button,.actions button{border:0;background:transparent;display:flex;flex-direction:column;align-items:center;gap:6px}.dock button{min-width:58px;padding:7px;color:var(--muted);font-size:11px}.dock .current{color:var(--ink)}.dock .current:after{content:"";width:12px;height:1.5px;background:var(--ink)}.dock button:not(.current):after{content:"";height:1.5px}
.hero svg{width:24px;height:24px}.actions{display:flex;gap:12px}.actions button{background:var(--surface);border-radius:50%;width:48px;height:48px;justify-content:center}
section{margin:0 0 26px}h2{display:flex;align-items:center;gap:18px;font:13px/1.5 system-ui;color:var(--muted);font-weight:400;margin:0 0 10px}h2:after{content:"";height:1px;background:var(--line);flex:1}h2 .code{min-width:145px}
.grid{display:grid;grid-template-columns:repeat(9,minmax(0,1fr));gap:2px}.tile{border:0;border-radius:4px;background:transparent;display:flex;align-items:center;justify-content:center;flex-direction:column;gap:13px;height:96px;min-width:0}.tile:hover{background:var(--soft)}.tile svg{width:28px;height:28px;flex:none}.tile span{font-size:12px;color:var(--muted);white-space:nowrap}.tile[aria-pressed="true"] span{color:var(--ink)}
footer{display:flex;justify-content:space-between;gap:20px;padding-top:22px;border-top:1px solid var(--line);font-size:12px;color:var(--muted)}
@media(max-width:760px){main{padding:24px 20px}h1{font-size:40px}.intro{align-items:start;flex-direction:column;gap:8px}.intro p{font-size:12px}.featured{grid-template-columns:repeat(3,minmax(0,1fr));padding:18px 0;gap:12px}.feature .glyph svg{width:46px;height:46px}.feature .mini{right:8px;top:42px}.feature .mini svg{width:18px;height:18px}.hero{flex-wrap:wrap;gap:20px}.grid{grid-template-columns:repeat(5,minmax(0,1fr))}.tile{height:92px}.tools{gap:5px}.tool{padding:7px 9px}.code{font-size:9px}h2 .code{min-width:125px}}
@media(max-width:400px){.grid{grid-template-columns:repeat(4,minmax(0,1fr))}header{flex-wrap:wrap}.feature .mini{display:none}}
</style>
<main><header><span class="code">WENKU8 / ICONOGRAPHY 02</span><div class="tools"><button class="tool" id="replay">播放一轮</button><button class="tool" id="motion">动效已开启</button><button class="tool" id="theme">深色预览</button></div></header>
<div class="intro"><div><h1>折页墨线</h1><p>纸页与档案 · <span id="count"></span> 枚动态图标 · 第二版</p></div><p>折角有形，墨点有节奏。<br>轻点后完整演绎，回落时错开半拍。</p></div>
<div class="featured" aria-label="核心动效展示"></div>
<div class="hero"><nav class="dock" aria-label="导航演示"></nav><div class="actions" aria-label="阅读操作演示"></div></div>
<div id="catalogue"></div><footer><span class="code">FOLDED PAPER / INK / 640ms</span><span>悬停或点按预览 · 动作结束即静止</span></footer></main>
<script>
const icons=/*ICON_DATA*/[];
const reduced=matchMedia('(prefers-reduced-motion: reduce)');let still=reduced.matches;let demoTimers=[];
const byId=id=>icons.find(i=>i.id===id);const groups=[...new Set(icons.map(i=>i.group))];
const codes=['NAVIGATION','READING','LISTENING','ACTIONS','FILES','SYSTEM'];document.querySelector('#count').textContent=icons.length;
function mark(button,data){const slot=document.createElement('div');slot.className='glyph';slot.innerHTML=data.static;button.prepend(slot);button.dataset.on='false';button.setAttribute('aria-pressed','false');button._slot=slot;button._data=data;button.addEventListener('click',()=>animate(button,true));button.addEventListener('pointerenter',e=>{if(e.pointerType!=='touch'&&!button._running)animate(button,false)});}
function rest(b){b._slot.innerHTML=b.dataset.on==='true'?b._data.on:b._data.static;b._running=false;}
function animate(button,toggle){const data=button._data;const on=button.dataset.on==='true';const next=toggle?!on:on;const frames=toggle?(next?data.onFrames:data.offFrames):(on?data.activeFrames:data.hoverFrames);
  button.dataset.on=String(next);button.setAttribute('aria-pressed',String(next));cancelAnimationFrame(button._raf);if(still){rest(button);return;}
  button._running=true;const start=performance.now();const draw=now=>{const t=Math.min(1,(now-start)/640);button._slot.innerHTML=frames[Math.round(t*(frames.length-1))];if(t<1)button._raf=requestAnimationFrame(draw);else rest(button)};button._raf=requestAnimationFrame(draw);
}
[['discover','拨开书页'],['shelf','抽卷回落'],['folder','纸页探出'],['bookmark','折页回弹'],['play','双页变形'],['sliders','错峰滑动']].forEach(([id,note])=>{const b=document.createElement('button');b.className='feature';b.title=byId(id).label;b.innerHTML=`<span class="name">${byId(id).label}</span><span class="note">${note}</span><div class="mini">${byId(id).static}</div>`;mark(b,byId(id));document.querySelector('.featured').append(b)});
groups.forEach((group,index)=>{const section=document.createElement('section');const h=document.createElement('h2');const code=document.createElement('span');code.className='code';code.textContent=`0${index+1} / ${codes[index]}`;h.append(code,document.createTextNode(group));section.append(h);const grid=document.createElement('div');grid.className='grid';icons.filter(i=>i.group===group).forEach(data=>{const b=document.createElement('button');b.className='tile';b.title=data.id;const text=document.createElement('span');text.textContent=data.label;b.append(text);mark(b,data);grid.append(b)});section.append(grid);document.querySelector('#catalogue').append(section)});
['discover','shelf','folder','profile'].forEach((id,index)=>{const b=document.createElement('button');b.className=index===0?'current':'';b.append(document.createTextNode(['发现','书架','本地','我的'][index]));mark(b,byId(id));b.onclick=()=>{document.querySelectorAll('.dock button').forEach(i=>{i.classList.remove('current');if(i!==b){i.dataset.on='false';i.setAttribute('aria-pressed','false');cancelAnimationFrame(i._raf);rest(i)}});b.classList.add('current')};document.querySelector('.dock').append(b)});
['search','play','bookmark','sliders'].forEach(id=>{const b=document.createElement('button');b.setAttribute('aria-label',byId(id).label);b.title=byId(id).label;mark(b,byId(id));document.querySelector('.actions').append(b)});
const motion=document.querySelector('#motion'), replay=document.querySelector('#replay');function updateMotion(){motion.textContent=still?'动效已关闭':'动效已开启';replay.disabled=still;demoTimers.forEach(clearTimeout);demoTimers=[];document.querySelectorAll('button[data-on]').forEach(b=>{cancelAnimationFrame(b._raf);rest(b)})};motion.onclick=()=>{still=!still;updateMotion()};reduced.onchange=e=>{still=e.matches;updateMotion()};updateMotion();
replay.onclick=()=>{if(still)return;demoTimers.forEach(clearTimeout);demoTimers=[...document.querySelectorAll('.feature')].map((b,i)=>setTimeout(()=>animate(b,true),i*85))};
document.querySelector('#theme').onclick=e=>{const dark=document.documentElement.classList.toggle('dark');e.currentTarget.textContent=dark?'浅色预览':'深色预览'};
</script></html>''';
