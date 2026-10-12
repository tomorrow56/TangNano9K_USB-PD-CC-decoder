import assert from 'node:assert/strict';import fs from 'node:fs';
import {StreamParser,crc16,crc32,makeRecord,demoRecords} from '../web/dist/protocol.mjs';
assert.equal(crc16(Buffer.from('123456789')),0x29b1);assert.equal(crc32(Buffer.from('123456789')),0xcbf43926);
const expected=JSON.parse(fs.readFileSync(new URL('../build/expected.json',import.meta.url)));
const bytes=fs.readFileSync(new URL('../build/uart.bin',import.meta.url));
for(const size of [1,7,51,52,91,1024]) {const actual=[];const p=new StreamParser(x=>actual.push(x));for(let i=0;i<bytes.length;i+=size)p.feed(bytes.slice(i,i+size));assert.equal(actual.length,expected.length);actual.forEach((r,i)=>{assert.equal(r.kind,expected[i].kind);assert.equal(r.flags,expected[i].flags);assert.deepEqual(r.raw,expected[i].raw);assert.equal(r.seq,i);assert.equal(r.dropped,0);if(expected[i].flags===1)assert.equal(r.ok,true);if([0,2,4,9].includes(expected[i].flags)&&r.kind<5)assert.equal(r.ok,false);});}
const out=[],p=new StreamParser(x=>out.push(x));const good=demoRecords()[0], bad=good.slice();bad[22]^=1;
p.feed([1,2,3,0xa5]);p.feed(bad);p.feed(good.slice(0,19));p.feed(good.slice(19));assert.equal(out.length,1);assert.equal(p.errors,1);assert.equal(out[0].name,'Source_Capabilities');assert.match(out[0].objects[0].detail,/5 V \/ 3 A/);
for(let cut=1;cut<52;cut++){const a=[],p=new StreamParser(r=>a.push(r));p.feed([...good.slice(0,cut),...good,...good]);assert.equal(a.length,2);}
for(const r of demoRecords()){const a=[],p=new StreamParser(x=>a.push(x));p.feed(r);assert.equal(a[0].ok,true);}
const a=[],q=new StreamParser(r=>a.push(r));q.feed(makeRecord({kind:5,flags:0}));assert.equal(a[0].name,'Hard Reset');assert.equal(a[0].ok,true);
console.log(`PASS ${expected.length} RTL→UART→JS records; chunk boundaries, corruption, byte loss, CRC, PDO, demos`);
const ov=[],op=new StreamParser(r=>ov.push(r));op.feed(fs.readFileSync(new URL('../build/overflow.bin',import.meta.url)));assert.equal(ov.length,10);assert.deepEqual(ov.map(r=>r.seq),[0,1,2,3,4,5,6,7,8,20]);assert.equal(ov.at(-1).dropped,11);assert.equal(ov.at(-1).ticks,20);console.log('PASS overflow wire records: sequence gaps and cumulative drops');
