export const SOP = ['SOP', "SOP′", 'SOP″', 'SOP′ Debug', 'SOP″ Debug', 'Hard Reset', 'Cable Reset'];
const CONTROL = ['Reserved','GoodCRC','GotoMin','Accept','Reject','Ping','PS_RDY','Get_Source_Cap','Get_Sink_Cap','DR_Swap','PR_Swap','VCONN_Swap','Wait','Soft_Reset','Reserved','Reserved','Not_Supported','Get_Source_Cap_Extended','Get_Status','FR_Swap','Get_PPS_Status','Get_Country_Codes','Get_Sink_Cap_Extended','Get_Source_Info','Get_Revision'];
const DATA = {1:'Source_Capabilities',2:'Request',3:'BIST',4:'Sink_Capabilities',5:'Battery_Status',6:'Alert',7:'Get_Country_Info',8:'Enter_USB',9:'EPR_Request',10:'EPR_Mode',11:'Source_Info',12:'Revision',15:'Vendor_Defined'};
export const hex = a => Array.from(a, x=>x.toString(16).padStart(2,'0').toUpperCase()).join(' ');
export function crc16(a) { let c=0xffff; for(const b of a) {c^=b<<8;for(let i=0;i<8;i++) c=((c<<1)^((c&0x8000)?0x1021:0))&0xffff;} return c; }
export function crc32(a) {let c=0xffffffff;for(const b of a) {c^=b;for(let i=0;i<8;i++) c=(c>>>1)^((c&1)?0xedb88320:0);}return (~c)>>>0;}
const u32 = (a,i) => (a[i]|a[i+1]<<8|a[i+2]<<16|a[i+3]<<24)>>>0;
export function decode(r) {
 const a=r.raw, h=a.length>=2?a[0]|a[1]<<8:0, n=(h>>>12)&7, ext=!!(h&0x8000), t=h&31;
 const reset=r.kind>=5;
 const validLength=reset ? a.length===0 : a.length===6+n*4;
 const crcOK=!reset && a.length>=6 && crc32(a.slice(0,-4))===u32(a,a.length-4);
 const problems=[];
 if(!reset && !crcOK) problems.push('CRC32不一致');
 if(!validLength || (r.flags&8)) problems.push('長さ不一致');
 if(r.flags&2) problems.push('4b5bエラー');if(r.flags&4) problems.push('EOP未受信');
 if(!reset && !!(r.flags&1)!==crcOK) problems.push('FPGA/ブラウザCRC判定不一致');
 const objects=[];
 if(!reset && a.length>=6) for(let i=0;i<n && 2+4*(i+1)<=a.length-4;i++) {
  const x=u32(a,2+i*4);let detail='';
  if(!ext && (t===1 || t===4)) {
   const type=x>>>30;
   if(type===0) detail=`Fixed ${((x>>>10)&1023)*0.05} V / ${(x&1023)*0.01} A`;
   else if(type===1) detail=`Battery ${((x>>>10)&1023)*0.05}–${((x>>>20)&1023)*0.05} V / ${(x&1023)*0.25} W`;
   else if(type===2) detail=`Variable ${((x>>>10)&1023)*0.05}–${((x>>>20)&1023)*0.05} V / ${(x&1023)*0.01} A`;
   else if(((x>>>28)&3)===0) detail=`PPS APDO ${((x>>>8)&255)*0.1}–${((x>>>17)&255)*0.1} V / ${(x&127)*0.05} A`;
   else detail='APDO（raw）';
  } else if(!ext && t===2) detail=`RDO object position ${(x>>>28)&15}（電流/電圧の解釈には対応PDOが必要）`;
  objects.push({index:i+1,hex:x.toString(16).padStart(8,'0').toUpperCase(),detail});
 }
 let extended=null;
 if(ext && a.length>=8) {const e=a[2]|a[3]<<8;extended={dataSize:e&511,requestChunk:!!(e&1024),chunkNumber:(e>>>11)&15,chunked:!!(e&32768)};}
 return {...r,sop:SOP[r.kind]??'Unknown',name:reset?SOP[r.kind]:ext?`Extended type ${t}`:n?(DATA[t]??`Data ${t}`):(CONTROL[t]??`Control ${t}`),header:h,n,ext,messageId:(h>>>9)&7,revision:['1.0','2.0','3.x','Reserved'][(h>>>6)&3],role:r.kind===0?`${h&256?'Source':'Sink'} / ${h&32?'DFP':'UFP'}`:'Cable / Debug（役割はraw参照）',validLength,crcOK,problems,objects,extended,ok:problems.length===0};
}
export class StreamParser {
 constructor(onRecord) {this.onRecord=onRecord;this.buffer=[];this.errors=0;}
 feed(chunk) {
  this.buffer.push(...chunk);
  while(this.buffer.length>=52) {
   if(this.buffer[0]!==0xa5 || this.buffer[1]!==0x5a) {this.buffer.shift();continue;}
   const b=this.buffer.slice(0,52);
   if(b[2]!==1 || b[3]>6 || b[5]>34 || crc16(b.slice(2,50))!==(b[50]|b[51]<<8)) {this.errors++;this.buffer.shift();continue;}
   this.buffer.splice(0,52);
   this.onRecord(decode({kind:b[3],flags:b[4],raw:b.slice(16,16+b[5]),seq:b[6]|b[7]<<8,ticks:u32(b,8),dropped:u32(b,12)}));
  }
 }
}
export function makeRecord({kind=0,flags=1,raw=[],seq=0,ticks=0,dropped=0}) {
 const b=new Uint8Array(52),v=new DataView(b.buffer);b.set([0xa5,0x5a,1,kind,flags,raw.length]);v.setUint16(6,seq,true);v.setUint32(8,ticks,true);v.setUint32(12,dropped,true);b.set(raw,16);v.setUint16(50,crc16(b.slice(2,50)),true);return b;
}
export function demoRecords() {
 const defs=[[0x61,0x11,0x2c,0x91,0x01,0x00],[0x42,0x10,0x2c,0xb1,0x04,0x10],[0x63,0x03],[0x66,0x05]];
 return defs.map((a,i)=>{const c=crc32(a);return makeRecord({raw:[...a,c&255,(c>>>8)&255,(c>>>16)&255,c>>>24],seq:i,ticks:2700000+i*540000});});
}
