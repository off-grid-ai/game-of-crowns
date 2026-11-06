import json, html
S='/private/tmp/claude-501/-Users-user-wednesday-civilization/d6afc56d-5455-4288-8689-768b695dcaf3/scratchpad/'
d=json.load(open(S+'data.json'))
E=html.escape
def copyblock(label, text, id_):
    return f'''<div class="copy"><div class="copy-h"><span class="lbl">{E(label)}</span><button class="cbtn" data-copy="{id_}">Copy</button></div><pre id="{id_}">{E(text)}</pre></div>'''
def step(id_, time, title, body):
    return f'''<li class="step" id="s-{id_}"><label class="chk"><input type="checkbox" id="c-{id_}" data-k="{id_}"><span class="box" aria-hidden="true"></span></label><div class="step-main"><div class="step-h"><span class="time">{E(time)}</span><h3>{title}</h3></div>{body}</div></li>'''
steps=[]
steps.append(step('itch','Now','Publish the itch page', '''<p>Done. It's live at <a href="https://alichherawalla.itch.io/game-of-crowns" target="_blank" rel="noopener">alichherawalla.itch.io/game-of-crowns</a> with your copy and the 0.5 download.</p>'''))
steps.append(step('devlog','Now','Publish the launch devlog', '''<p>Done. <a href="https://alichherawalla.itch.io/game-of-crowns/devlog" target="_blank" rel="noopener">"0.5 is out"</a> is live, and the tags now include choices-matter, politics and fantasy.</p>'''))
steps.append(step('test','Now','Download it once, the way a stranger would', '''<p>Open <a href="https://alichherawalla.itch.io/game-of-crowns" target="_blank" rel="noopener">alichherawalla.itch.io/game-of-crowns</a> in a private window, download, open the dmg, and launch it. If anything stops you, tell me before posting.</p>'''))
mt="History names you the Golden, the Bloody or the Deposed in the free kingdom game I built on my Mac"
mb="""Game of Crowns is a medieval kingdom sim. You're the king, and seven great houses want your throne. You hold it with grain, gold, marriages and your rulings at court. Side against a house in a war, and ten years later its lord stands up at court to remind you. When your reign ends, history names you: the Golden, the Bloody, or the Deposed.

I wanted my own Game of Thrones story, so I built one where you can rename anyone, rewrite their past and pick the story that comes for your throne. A season passes every 20 seconds, so a whole reign fits in an evening.

With an optional local model, you can answer petitioners in your own words instead of picking from a list, and it can write you a new story for your next reign.

It's free and open source on Apple Silicon Macs, with Windows next. I built it with Claude on top of Freeciv, and I'm happy to go into how any of it works.

https://alichherawalla.itch.io/game-of-crowns (signed and notarised, macOS 12 or later, a 2 GB download)

I'm in the comments tonight. How does it run on your Mac?"""
ai="""Partly. The paintings in the trailer and on the game's intro screens were made with AI. In the game, if you also run Off Grid AI, another app I make, the lords speak in their own words through a small model on your own Mac. Nothing goes online, and without it the game runs on its own rules."""
steps.append(step('mac','Now, before 10:30pm','Post on r/macgaming', f'''<p>Make a <b>video post</b> and upload <code>docs/buzz/video/game-of-crowns-launch-16x9.mp4</code> to Reddit itself, not a YouTube link. Flair: <b>Self promotion</b>. Post it once; if it sinks, don't repost.</p>{copyblock('Title',mt,'mac-t')}{copyblock('Body',mb,'mac-b')}{copyblock('If someone asks "is it AI?"',ai,'mac-ai')}<p class="note">Then stay and reply to everything tonight, bug reports first. Developers whose posts did well replied to around 16 comments; the ones that sank replied to none.</p>'''))
cards=[]
for i,e in enumerate(d['emails']):
    to_is_form=e['to'].startswith('Contact form')
    to_html = f'<a href="{E(e["to"].split(": ",1)[1])}" target="_blank" rel="noopener">{E(e["to"])}</a>' if to_is_form else copyblock('To', e['to'], f'em{i}-to')
    cards.append(f'''<details class="email"><summary><label class="mini" onclick="event.stopPropagation()"><input type="checkbox" id="c-em{i}" data-k="em{i}"><span class="box" aria-hidden="true"></span></label><span class="ename">{E(e["name"])}</span><span class="esubs">{E(e["subs"])}</span></summary><div class="ebody">{to_html}{copyblock('Subject',e['subject'],f'em{i}-s')}{copyblock('Email',e['body'],f'em{i}-b')}</div></details>''')
steps.append(step('emails','Right after r/macgaming','Send the eight creator emails', '<p>From your own email. Each links the 33-second launch film. Each one names a real video of theirs. One follow-up in a week at most, never more.</p><div class="emails">'+''.join(cards)+'</div>'))
t,b=d['god']
steps.append(step('godot','An hour after r/macgaming','Post on r/godot', f'''<p>Video post with the same film. Flair: <b>selfpromo (games)</b>. Their rule: you stay and answer questions.</p>{copyblock('Title',t,'god-t')}{copyblock('Body',b,'god-b')}'''))
t,b=d['ig']
steps.append(step('ig','On hold','r/IndieGaming', f'''<p><b>Hold this one.</b> r/IndieGaming removes AI-generated content, and the launch film is AI paintings. A real-gameplay post is being written for it separately; skip it tonight.</p>{copyblock('Title',t,'ig-t')}{copyblock('Body',b,'ig-b')}'''))
steps.append(step('reply','All evening','Reply to every comment', '<p>Answer what was asked, plainly. If someone hits a bug, thank them and tell me; I\'ll get it into 0.5.1.</p>'))
later=[('Sat 7 Nov','Post the vertical clip on Shorts, TikTok and Reels','<code>docs/buzz/video/game-of-crowns-launch-9x16.mp4</code>. Upload it to each one separately so there are no watermarks.'),
('Sat 7 Nov','Put the trailer on YouTube and send me the link','itch\'s trailer slot only takes a YouTube or Vimeo link. I\'ll add it.'),
('This week','Make an AppleGamingWiki page marked native','It needs an account, so it has to be you. <a href="https://applegamingwiki.com" target="_blank" rel="noopener">applegamingwiki.com</a>'),
('Mon 9 Nov','Send 15 more creator emails','Strategy and sim channels, in docs/buzz/creators.md under Batch 2.'),
('Mon 9 Nov','Post on r/SimulationGames','Ready in docs/buzz/channel-04-simulationgames.md.'),
('Fri 13 Nov','Post the week-one devlog','"The realms you made", with players\' screenshots.'),
('Wed 18 Nov','Update 0.6, the second beat','A new feature, a new clip, an email to every creator who covered it.')]
lat=''.join(step(f'l{i}',w,E(t),f'<p>{b}</p>') for i,(w,t,b) in enumerate(later))
out=f'''<title>Launch Night Checklist</title>
<meta name="claude:viewport-fit-sides" content="cover">
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Cinzel:wght@500;700&family=Source+Sans+3:wght@400;600;700&family=JetBrains+Mono:wght@400&display=swap">
<style>
/* Layout: one column of timed steps, a progress seal on top; copy blocks sit inside the step they belong to */
:root{{--bg:#f3f4f6;--panel:#ffffff;--ink:#1c2230;--muted:#5b6475;--line:#dde1e8;--gold:#8a6420;--gold-soft:#f3e9d4;--done:#2f7d4f;
--display:"Cinzel",Georgia,serif;--body:"Source Sans 3",system-ui,sans-serif;--mono:"JetBrains Mono",ui-monospace,Menlo,monospace}}
@media (prefers-color-scheme:dark){{:root:not([data-theme="light"]){{--bg:#12151c;--panel:#1a1f29;--ink:#e6e8ee;--muted:#9aa3b5;--line:#2b3240;--gold:#d6aa5c;--gold-soft:#2e2717;--done:#5fbf86;color-scheme:dark}}}}
:root[data-theme="dark"]{{--bg:#12151c;--panel:#1a1f29;--ink:#e6e8ee;--muted:#9aa3b5;--line:#2b3240;--gold:#d6aa5c;--gold-soft:#2e2717;--done:#5fbf86;color-scheme:dark}}
body{{background:var(--bg);color:var(--ink);font:16px/1.55 var(--body);padding-left:max(16px,env(safe-area-inset-left,0px));padding-right:max(16px,env(safe-area-inset-right,0px));padding-block:28px 64px}}
.wrap{{max-width:760px;margin:0 auto;display:grid;gap:28px}}
header{{display:grid;gap:10px}}
.eyebrow{{font:600 12px/1 var(--body);letter-spacing:.14em;text-transform:uppercase;color:var(--gold)}}
h1{{font:700 clamp(28px,6vw,40px)/1.1 var(--display);margin:0;text-wrap:balance;letter-spacing:.01em}}
.lede{{color:var(--muted);margin:0;max-width:62ch}}
.hook{{font-family:var(--display);font-size:18px;color:var(--ink);border-left:3px solid var(--gold);padding:6px 0 6px 14px;margin:0}}
.progress{{display:flex;align-items:center;gap:12px;font-variant-numeric:tabular-nums;color:var(--muted);font-size:14px}}
.bar{{flex:1;height:6px;background:var(--line);border-radius:3px;overflow:hidden}}.bar i{{display:block;height:100%;width:0;background:var(--gold);transition:width .3s}}
h2{{font:600 13px/1 var(--body);letter-spacing:.14em;text-transform:uppercase;color:var(--muted);margin:8px 0 0}}
ol{{list-style:none;margin:0;padding:0;display:grid;gap:12px}}
.step{{display:grid;grid-template-columns:28px minmax(0,1fr);gap:14px;background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:16px 18px}}
.step.is-done{{opacity:.6}}.step.is-done h3{{text-decoration:line-through;text-decoration-color:var(--muted)}}
.step-main{{min-width:0;display:grid;gap:10px}}
.step-h{{display:flex;flex-wrap:wrap;align-items:baseline;gap:4px 12px}}
.time{{font:600 13px/1 var(--mono);color:var(--gold);white-space:nowrap}}
h3{{margin:0;font:700 18px/1.3 var(--body)}}
.step p{{margin:0;color:var(--ink)}}.note{{color:var(--muted)!important;font-size:14px}}
a{{color:var(--gold);text-underline-offset:2px}}
code{{font:13px var(--mono);background:var(--gold-soft);padding:1px 5px;border-radius:4px;word-break:break-all}}
.chk,.mini{{position:relative;display:inline-flex;cursor:pointer}}.chk{{margin-top:2px}}
.chk input,.mini input{{position:absolute;opacity:0;width:100%;height:100%;margin:0;cursor:pointer}}
.box{{width:22px;height:22px;border:2px solid var(--line);border-radius:6px;display:grid;place-items:center;background:var(--panel)}}
.mini .box{{width:18px;height:18px}}
input:checked+.box{{background:var(--done);border-color:var(--done)}}
input:checked+.box::after{{content:"";width:6px;height:11px;border:solid #fff;border-width:0 2px 2px 0;transform:rotate(45deg) translate(-1px,-1px)}}
input:focus-visible+.box{{outline:2px solid var(--gold);outline-offset:2px}}
.copy{{border:1px solid var(--line);border-radius:8px;overflow:hidden;background:var(--bg)}}
.copy-h{{display:flex;justify-content:space-between;align-items:center;padding:6px 8px 6px 12px;border-bottom:1px solid var(--line)}}
.lbl{{font:600 12px/1 var(--body);letter-spacing:.1em;text-transform:uppercase;color:var(--muted)}}
.cbtn{{font:600 13px var(--body);color:var(--ink);background:var(--panel);border:1px solid var(--line);border-radius:6px;padding:4px 12px;cursor:pointer}}
.cbtn:hover{{border-color:var(--gold)}}.cbtn.ok{{color:var(--done);border-color:var(--done)}}
.cbtn:focus-visible{{outline:2px solid var(--gold);outline-offset:2px}}
pre{{margin:0;padding:12px;font:14px/1.55 var(--body);white-space:pre-wrap;word-wrap:break-word;max-height:none}}
.emails{{display:grid;gap:8px}}
details.email{{border:1px solid var(--line);border-radius:8px;background:var(--bg)}}
details.email summary{{display:flex;align-items:center;gap:12px;padding:10px 12px;cursor:pointer;list-style:none}}
details.email summary::-webkit-details-marker{{display:none}}
details.email summary::after{{content:"Open";margin-left:auto;font-size:13px;color:var(--gold)}}
details.email[open] summary::after{{content:"Close"}}
.ename{{font-weight:700}}.esubs{{color:var(--muted);font-size:14px;font-variant-numeric:tabular-nums}}
.ebody{{display:grid;gap:8px;padding:0 12px 12px}}
@media (prefers-reduced-motion:reduce){{.bar i{{transition:none}}}}
</style>
<div class="wrap">
<header>
<span class="eyebrow">Game of Crowns 0.5 · Friday 6 November</span>
<h1>Launch night</h1>
<p class="lede">Everything only you can do tonight, in order, with every post and email ready to copy. Tick things off as you go; the ticks stay in this browser.</p>
<p class="hook">Find out what kind of king you'd be.</p>
<div class="progress"><div class="bar"><i id="bar"></i></div><span id="count">0 of 0 done</span></div>
</header>
<section><h2>Tonight</h2><ol>{''.join(steps)}</ol></section>
<section><h2>Next two weeks</h2><ol>{lat}</ol></section>
</div>
<script>
(function(){{
 const boxes=[...document.querySelectorAll('input[type=checkbox][data-k]')];
 let st={{itch:true,devlog:true}}; try{{st=Object.assign(st,JSON.parse(localStorage.getItem('goc-launch')||'{{}}'))}}catch(e){{}}
 function save(){{try{{localStorage.setItem('goc-launch',JSON.stringify(st))}}catch(e){{}}}}
 function paint(){{
  boxes.forEach(b=>{{b.checked=!!st[b.dataset.k];const s=document.getElementById('s-'+b.dataset.k);if(s)s.classList.toggle('is-done',b.checked)}});
  const main=boxes.filter(b=>!b.dataset.k.startsWith('em'));const n=main.filter(b=>b.checked).length;
  document.getElementById('bar').style.width=(100*n/main.length)+'%';document.getElementById('count').textContent=n+' of '+main.length+' done';
 }}
 boxes.forEach(b=>b.addEventListener('change',()=>{{st[b.dataset.k]=b.checked;
  if(b.dataset.k.startsWith('em')){{const all=boxes.filter(x=>x.dataset.k.startsWith('em'));if(all.every(x=>x.checked||x===b&&b.checked)&&all.every(x=>x.checked))st['emails']=true}}
  save();paint()}}));
 document.querySelectorAll('.cbtn').forEach(btn=>btn.addEventListener('click',()=>{{
  const el=document.getElementById(btn.dataset.copy);const txt=el.textContent;
  const done=()=>{{btn.textContent='Copied';btn.classList.add('ok');setTimeout(()=>{{btn.textContent='Copy';btn.classList.remove('ok')}},1600)}};
  const sel=()=>{{const r=document.createRange();r.selectNodeContents(el);const s=getSelection();s.removeAllRanges();s.addRange(r);btn.textContent='Selected, press ⌘C'}};
  try{{navigator.clipboard.writeText(txt).then(done,sel)}}catch(e){{sel()}}
 }}));
 paint();
}})();
</script>'''
open('/Users/user/wednesday/civilization/docs/buzz/artifact/launch-night.html','w').write(out)
print(len(out))
