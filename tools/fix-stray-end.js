// fix-stray-end.js <file> [--apply]
// Repairs the one-extra-'end' defect in the tail of findClosestAlly:
//     28sp end / 24sp end / 20sp / 16sp / 12sp / 8sp / 4sp   <- 7 ends, one too many
//     (blank)
//     return closestAlly
//     end
// Deleting the LAST end of the run (the 4sp one) puts `return closestAlly` back inside
// the function and lets the trailing `end` close it.
// Dry-run by default; pass --apply to write. Aborts unless the pattern matches EXACTLY.
const fs = require('fs');

const file = process.argv[2];
const apply = process.argv.includes('--apply');
if (!file) { console.log('usage: node fix-stray-end.js <file> [--apply]'); process.exit(2); }

const raw = fs.readFileSync(file, 'utf8');
const eol = raw.includes('\r\n') ? '\r\n' : '\n';
const lines = raw.split(/\r?\n/);

const hits = [];
lines.forEach((l, i) => { if (l.trim() === 'return closestAlly') hits.push(i); });
if (hits.length !== 1) {
  console.log(`ABORT: expected exactly 1 "return closestAlly" line, found ${hits.length}`);
  process.exit(3);
}
const idx = hits[0]; // 0-based index of the `return closestAlly` line

let ok = true;
if ((lines[idx - 1] || '').trim() !== '') {
  ok = false;
  console.log(`ABORT: line ${idx} (before return) is not blank: ${JSON.stringify(lines[idx - 1])}`);
}
const expect = [4, 8, 12, 16, 20, 24, 28];
for (let k = 0; k < 7; k++) {
  const li = idx - 2 - k;
  const m = (lines[li] || '').match(/^( *)(end)\s*$/);
  if (!m || m[1].length !== expect[k]) {
    ok = false;
    console.log(`ABORT: line ${li + 1} = ${JSON.stringify(lines[li])} (expected ${expect[k]} spaces + end)`);
  }
}
if ((lines[idx + 1] || '').trim() !== 'end') {
  ok = false;
  console.log(`ABORT: expected 'end' immediately after return, got ${JSON.stringify(lines[idx + 1])}`);
}
if (!ok) process.exit(4);

const del = idx - 2; // 0-based index of the 4-space end (closest to the blank line)
console.log(`PATTERN OK: deleting line ${del + 1} (${JSON.stringify(lines[del])})`);
console.log(`  ...run of ends at lines ${del - 5}..${del + 1}`);
if (!apply) { console.log('dry run - pass --apply to write'); process.exit(0); }

lines.splice(del, 1);
fs.writeFileSync(file, lines.join(eol));
console.log(`WROTE ${file}: ${lines.length} lines (was ${raw.split(/\r?\n/).length - 1})`);
