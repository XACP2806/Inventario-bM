import React from 'react';
import {Wallet} from 'lucide-react';
import {all} from './api';
import {useLoad,ErrorBox,Button} from './components';
import {cashSummary} from './cash-summary.mjs';
import {money,today} from './utils.mjs';

export default function CashSummary({refreshKey,onNavigate}) {
 const through=today();
 const state=useLoad(async()=>cashSummary(await all('v_caja_diaria'),through),[refreshKey,through]);
 return <section className="card cash-summary" aria-label="Saldo acumulado de dinero">
  <div className="section-heading"><div><span className="eyebrow">DINERO DE bM · HASTA HOY</span><h2>Saldo de dinero registrado</h2></div><Wallet size={24}/></div>
  <ErrorBox error={state.error}/>
  {state.loading?<p role="status">Calculando saldo…</p>:!state.error&&state.data&&<>
   <div className="cash-summary-values"><strong className="cash-balance">{money(state.data.balance)}</strong><dl><div><dt>Entradas acumuladas</dt><dd>{money(state.data.incoming)}</dd></div><div><dt>Salidas pagadas por bM</dt><dd>{money(state.data.outgoing)}</dd></div></dl></div>
   <p>Desde el primer movimiento hasta hoy. No cambia con el filtro de fechas. Los pagos cubiertos por regalos no restan este saldo.</p>
   <details><summary>¿Qué incluye este saldo?</summary><p>Parte de $0 y suma los cobros registrados, menos pagos y reembolsos confirmados. Incluye efectivo y transferencias juntos. Las compras o gastos pendientes de pago todavía no lo reducen. No es una lectura de tu banco: solo coincide con el dinero real si registras todas las entradas y salidas.</p></details>
   {onNavigate&&<Button variant="ghost" onClick={()=>onNavigate('dinero')}>Ver movimientos de dinero</Button>}
  </>}
 </section>;
}
