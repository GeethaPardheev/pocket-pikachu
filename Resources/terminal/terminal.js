const term = new Terminal({cursorBlink:true,fontSize:13,fontFamily:'Menlo, monospace',scrollback:3000,theme:{background:'#141619',foreground:'#e8e9eb',cursor:'#48cdbb'},allowProposedApi:false});
const fit = new FitAddon.FitAddon(); term.loadAddon(fit); term.open(document.getElementById('terminal'));
const post = data => window.webkit.messageHandlers.terminal.postMessage(data);
term.onData(data => post({kind:'input',data}));
term.onResize(({cols,rows}) => post({kind:'resize',cols,rows}));
window.feed = encoded => new Promise(resolve => {const raw=atob(encoded);const bytes=Uint8Array.from(raw,c=>c.charCodeAt(0));term.write(bytes,resolve);});
window.focusTerminal = () => term.focus();
window.copySelection = () => term.getSelection();
window.pasteText = text => term.paste(text);
new ResizeObserver(()=>fit.fit()).observe(document.getElementById('terminal'));
fit.fit(); post({kind:'ready',cols:term.cols,rows:term.rows}); term.focus();

window.voiceSnapshot = () => {
  const buffer = term.buffer.active;
  const lines = [];
  for (let i = Math.max(0, buffer.length - 60); i < buffer.length; i++) lines.push(buffer.getLine(i)?.translateToString(true) || '');
  return lines.join('\n').slice(-4000);
};
