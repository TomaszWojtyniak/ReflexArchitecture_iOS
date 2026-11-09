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

test('given save fails, the quantity stays unsaved', async (t) => {
  const session = createBehaviorSession({
    fixtures: [fixture('Inventory.stockCount2'), fixture('Inventory.saveFails')],
  });
  t.after(() => session.close());
  await openInventoryDetail(session);
  await session.do({
    action: 'Save',
    expectation: ({ state }) => {
      assert.equal(state.isSaving, false);
      assert.equal(state.isSaved, false);
      assert.equal(state.error, "Couldn't save");
    },
  });
});

test('given the list fails to load, the user sees an error', async (t) => {
  const session = createBehaviorSession({ fixtures: [fixture('Inventory.listFails')] });
  t.after(() => session.close());
  await session.precondition('InventoryList', ({ state }) => {
    assert.equal(state.isLoading, false);
    assert.equal(state.error, "Couldn't load products");
    assert.deepEqual(state.products, []);
  });
});

test('actions that make no sense change nothing', async (t) => {
  const session = createBehaviorSession({ fixtures: [fixture('Inventory.stockCount2')] });
  t.after(() => session.close());
  await session.precondition('InventoryList', ({ state }) => assert.equal(state.isLoading, false));
  await session.do({ action: 'goBack', expectation: ({ name }) => assert.equal(name, 'InventoryList') });
  await session.do({
    action: 'SelectProduct',
    payload: { id: 999 },
    expectation: ({ name }) => assert.equal(name, 'InventoryList'),
  });

  await openInventoryDetail(session);
  for (const quantity of [-5, 1_000_000]) {
    await session.do({ action: 'SetQuantity', payload: { quantity }, expectation: ({ state }) => assert.equal(state.stockCount, 2) });
  }
  await session.do({ action: 'SetQuantity', payload: { quantity: 999_999 }, expectation: ({ state }) => assert.equal(state.stockCount, 999_999) });
  await session.do({ action: 'Increment', expectation: ({ state }) => assert.equal(state.stockCount, 999_999) });
  // malformed input never reaches the ViewModel
  for (const quantity of ['many', 1.5]) {
    await assert.rejects(session.do({ action: 'SetQuantity', payload: { quantity } }), /SetQuantity expects \{quantity\}/);
  }
  // what isn't on screen can't be done
  await assert.rejects(session.do({ action: 'SelectProduct', payload: { id: 1 } }), /unknown action "SelectProduct"/);
});

test('a request without a fixture fails the session', async (t) => {
  const session = createBehaviorSession({ fixtures: [fixture('Inventory.stockCount2')] });
  t.after(() => session.close());
  await openInventoryDetail(session);
  await assert.rejects(
    session.do({ action: 'Save', expectation: ({ state }) => assert.equal(state.isSaved, true) }),
    /network violation: missing fixture: PUT \/products\/1/,
  );
});

test('edits while a save is in flight change nothing', async (t) => {
  const session = createBehaviorSession({
    fixtures: [fixture('Inventory.stockCount2'), fixture('Inventory.saveSlow')],
  });
  t.after(() => session.close());
  await openInventoryDetail(session);
  await session.do({ action: 'Save', expectation: ({ state }) => assert.equal(state.isSaving, true) });
  await session.do({ action: 'Increment', expectation: ({ state }) => assert.equal(state.stockCount, 2) });
  // a second Save is ignored too; the first one lands with the original quantity
  await session.do({
    action: 'Save',
    expectation: ({ state }) => {
      assert.equal(state.isSaved, true);
      assert.equal(state.stockCount, 2);
    },
  });
});
