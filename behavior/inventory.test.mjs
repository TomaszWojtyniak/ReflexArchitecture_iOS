import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createBehaviorSession, fixture } from './sdk.mjs';

// Every journey starts on the loaded list and opens one product.
async function openInventoryDetail(session, id = 1) {
  await session.precondition('InventoryList', ({ state }) => assert.equal(state.isLoading, false));
  await session.do({
    action: 'SelectProduct',
    payload: { id },
    expectation: ({ name, state }) => {
      assert.equal(name, 'InventoryDetail');
      assert.equal(state.productId, id);
    },
  });
}

test('given save succeeds, the user can adjust the quantity and save it', async (t) => {
  const session = createBehaviorSession({
    fixtures: [fixture('Inventory.stockCount2'), fixture('Inventory.saveSucceeds')],
  });
  t.after(() => session.close());
  await openInventoryDetail(session);

  await session.do({ action: 'Decrement', expectation: ({ state }) => assert.equal(state.stockCount, 1) });
  await session.do({ action: 'Decrement', expectation: ({ state }) => assert.equal(state.stockCount, 0) });
  // Decrement is always listed; the ViewModel decides it does nothing at zero
  await session.do({ action: 'Decrement', expectation: ({ state }) => assert.equal(state.stockCount, 0) });
  await session.do({
    action: 'SetQuantity',
    payload: { quantity: 40 },
    expectation: ({ state }) => assert.equal(state.stockCount, 40),
  });
  await session.do({ action: 'Save', expectation: ({ state }) => assert.equal(state.isSaved, true) });
  // any edit after a save makes the screen unsaved again
  await session.do({
    action: 'Increment',
    expectation: ({ state }) => {
      assert.equal(state.stockCount, 41);
      assert.equal(state.isSaved, false);
    },
  });
  await session.do({ action: 'Save', expectation: ({ state }) => assert.equal(state.isSaved, true) });
  // back on the list, the product shows what was saved
  await session.do({
    action: 'goBack',
    expectation: ({ name, state }) => {
      assert.equal(name, 'InventoryList');
      assert.equal(state.products.find((p) => p.id === 1).stock, 41);
    },
  });
});
