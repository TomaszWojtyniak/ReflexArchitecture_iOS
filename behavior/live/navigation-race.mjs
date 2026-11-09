// Manual check against the Debug app in the simulator (not part of ./test):
//   node behavior/live/navigation-race.mjs [runs]
// Drives open → edit → back at machine speed over localhost:7777. SwiftUI writes back the
// stack it displays when a transition ends; if RootView took that stale write as a user pop,
// a fresh push would vanish and the journey would find itself back on the list.
import net from 'node:net';
import { createInterface } from 'node:readline';

const runs = Number(process.argv[2] ?? 120);
const socket = net.connect(7777, '127.0.0.1');
await new Promise((resolve, reject) => socket.once('connect', resolve).once('error', reject));
const waiting = [];
createInterface({ input: socket }).on('line', (line) => waiting.shift()?.(JSON.parse(line)));
const send = (body) =>
  new Promise((resolve) => {
    waiting.push(resolve);
    socket.write(JSON.stringify(body) + '\n');
  });

const list = await send({ cmd: 'ls' });
if (list.name !== 'InventoryList' || list.state.isLoading) throw new Error('start on the loaded list');

const steps = [
  { cmd: 'do', action: 'SelectProduct', payload: { id: list.state.products[0].id } },
  { cmd: 'do', action: 'Increment' },
  { cmd: 'do', action: 'SetQuantity', payload: { quantity: 10 } },
  { cmd: 'do', action: 'goBack' },
];
let lost = 0;
for (let run = 0; run < runs; run++) {
  for (const step of steps) {
    const answer = await send(step);
    const { name } = await send({ cmd: 'ls' });
    const expected = step.action === 'goBack' ? 'InventoryList' : 'InventoryDetail';
    if (answer.error || name !== expected) {
      lost++;
      if (name !== 'InventoryList') await send({ cmd: 'do', action: 'goBack' });
      break;
    }
  }
}
socket.end();
console.log(`${lost}/${runs} journeys lost their push`);
process.exitCode = lost ? 1 : 0;
