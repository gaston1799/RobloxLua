(() => {
  const t = document.body.innerText;
  const enc = new TextEncoder();
  const lines = t.split(/\r?\n/);
  const idx = lines.findIndex(l => l.indexOf('return closestAlly') >= 0);
  const tail = [];
  if (idx >= 0) {
    for (let i = Math.max(0, idx - 7); i <= Math.min(lines.length - 1, idx + 3); i++) {
      tail.push((i + 1) + '| ' + lines[i]);
    }
  }
  return JSON.stringify({
    url: location.href,
    title: document.title,
    notFound404: /404: Not Found/.test(t),
    chars: t.length,
    utf8Bytes: enc.encode(t).length,
    lineCount: lines.length,
    closestAllyReturnLines: lines.map((l, i) => (l.indexOf('return closestAlly') >= 0 ? i + 1 : 0)).filter(Boolean),
    line174: lines[173] || null,
    line756: lines[755] || null,
    tailAroundReturn: tail
  }, null, 1);
})()
