import test from 'node:test';
import assert from 'node:assert/strict';
import {cashSummary} from '../src/cash-summary.mjs';
test('saldo acumula caja histórica, descuenta pagos y reembolsos y excluye movimientos futuros',()=>{
 const rows=[{dia:'2026-09-04',entradas:'0.00',salidas:'0.00'}, {dia:'2026-10-25',entradas:'44.00',salidas:0}, {dia:'2026-10-26',entradas:'44',salidas:'5.20'}, {dia:'2026-10-28',entradas:'0',salidas:'12.80'}, {dia:'2026-11-01',entradas:'500',salidas:0}];
 assert.deepEqual(cashSummary(rows,'2026-10-30'),{incoming:88,outgoing:18,balance:70});
 assert.deepEqual(cashSummary(rows,'2026-10-25'),{incoming:44,outgoing:0,balance:44});
 assert.deepEqual(cashSummary([],'2026-10-30'),{incoming:0,outgoing:0,balance:0});
 assert.equal(cashSummary([{dia:'2026-10-01',entradas:'.10',salidas:'.30'},{dia:'2026-10-02',entradas:'.20',salidas:0}],'2026-10-30').balance,0);
 assert.equal(cashSummary([{dia:'2026-10-01',entradas:0,salidas:8}],'2026-10-30').balance,-8);
});
