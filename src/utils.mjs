export const money=v=>new Intl.NumberFormat('es-EC',{style:'currency',currency:'USD'}).format(Number(v||0));
export const num=v=>new Intl.NumberFormat('es-EC',{maximumFractionDigits:3}).format(Number(v||0));
export const today=()=>new Intl.DateTimeFormat('en-CA',{timeZone:'America/Guayaquil',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
export const stamp=d=>`${d}T12:00:00-05:00`;
export const human=s=>String(s??'').replaceAll('_',' ').replace(/^./,c=>c.toUpperCase());
export const csvCell=v=>{let s=String(v??'');if(/^[=+@\-\t\r]/.test(s))s="'"+s;return '"'+s.replaceAll('"','""')+'"';};
export const csvText=rows=>{if(!rows.length)return '';const cols=Object.keys(rows[0]);return '\uFEFF'+[cols.map(csvCell).join(','),...rows.map(r=>cols.map(k=>csvCell(typeof r[k]==='object'?JSON.stringify(r[k]):r[k])).join(','))].join('\r\n');};
export function downloadCSV(rows,name){const url=URL.createObjectURL(new Blob([csvText(rows)],{type:'text/csv;charset=utf-8;'}));const a=document.createElement('a');a.href=url;a.download=name+'.csv';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);}
export const totals=series=>series.reduce((a,r)=>{for(const k of ['ventas','costos','resultado','margen','gastos','cobros','pagos','regalos'])a[k]=(a[k]||0)+Number(r[k]||0);a.provisional||=r.definitivo===false;return a;},{ventas:0,costos:0,resultado:0,margen:0,gastos:0,cobros:0,pagos:0,regalos:0,provisional:false});
export function previousPeriod(from,to){const a=new Date(from+'T12:00:00Z'),b=new Date(to+'T12:00:00Z');const days=Math.round((b-a)/86400000)+1;return [new Date(+a-days*86400000).toISOString().slice(0,10),new Date(+a-86400000).toISOString().slice(0,10)];}
