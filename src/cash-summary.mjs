// Cash is accumulated from confirmed cash movements, independently of report dates.
export function cashSummary(rows, through) {
 let incoming = 0, outgoing = 0;
 for (const row of rows) {
  if (!row.dia || row.dia > through) continue;
  incoming += Math.round(Number(row.entradas || 0) * 100);
  outgoing += Math.round(Number(row.salidas || 0) * 100);
 }
 return {incoming: incoming / 100, outgoing: outgoing / 100, balance: (incoming - outgoing) / 100};
}
