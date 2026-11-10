import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createBehaviorSession, fixture } from './sdk.mjs';

// The tab bar lends selectTab to every screen. Home holds the inventory stack; Search,
// Favorites and Profile are placeholders; "report" (Zgłoś) opens a sheet, never a tab.
function startOnHome(t) {
  const session = createBehaviorSession({ fixtures: [fixture('Inventory.stockCount2')] });
  t.after(() => session.close());
  return session;
}

const selectTab = (session, tab, expectation) => session.do({ action: 'selectTab', payload: { tab }, expectation });

async function openProduct(session) {
  await session.precondition('InventoryList', ({ state }) => assert.equal(state.isLoading, false));
  await session.do({
    action: 'SelectProduct',
    payload: { id: 1 },
    expectation: ({ name }) => assert.equal(name, 'InventoryDetail'),
  });
}

test('the app opens on Home, and each tab shows its own screen', async (t) => {
  const session = startOnHome(t);
  await session.precondition('InventoryList', ({ state }) => assert.equal(state.isLoading, false));
  for (const [tab, name] of [['search', 'Search'], ['favorites', 'Favorites'], ['profile', 'Profile']]) {
    await selectTab(session, tab, (node) => {
      assert.equal(node.name, name);
      assert.deepEqual(node.state, { title: name });
    });
  }
  await selectTab(session, 'home', ({ name }) => assert.equal(name, 'InventoryList'));
});

test('switching tabs keeps Home where the user left it', async (t) => {
  const session = startOnHome(t);
  await openProduct(session);
  await session.do({ action: 'Increment', expectation: ({ state }) => assert.equal(state.stockCount, 3) });
  await selectTab(session, 'search', ({ name }) => assert.equal(name, 'Search'));
  await selectTab(session, 'home', ({ name, state }) => {
    assert.equal(name, 'InventoryDetail');
    assert.equal(state.productId, 1);
    // the unsaved edit survived the trip
    assert.equal(state.stockCount, 3);
    assert.equal(state.isSaved, false);
  });
});

test('tapping the selected tab again takes it back to its first screen', async (t) => {
  const session = startOnHome(t);
  await openProduct(session);
  await selectTab(session, 'home', ({ name }) => assert.equal(name, 'InventoryList'));
});

test('Zgłoś opens the report over the current tab, and closing it returns there', async (t) => {
  const session = startOnHome(t);
  await openProduct(session);
  await selectTab(session, 'report', ({ name, state }) => {
    assert.equal(name, 'Report');
    assert.deepEqual(state, { title: 'Zgłoś' });
  });
  await session.do({
    action: 'dismiss',
    expectation: ({ name, state }) => {
      assert.equal(name, 'InventoryDetail');
      assert.equal(state.productId, 1);
    },
  });
  // the same over a placeholder tab
  await selectTab(session, 'profile', ({ name }) => assert.equal(name, 'Profile'));
  await selectTab(session, 'report', ({ name }) => assert.equal(name, 'Report'));
  await session.do({ action: 'dismiss', expectation: ({ name }) => assert.equal(name, 'Profile') });
});

test('tab actions that make no sense change nothing', async (t) => {
  const session = startOnHome(t);
  await session.precondition('InventoryList', ({ state }) => assert.equal(state.isLoading, false));
  await assert.rejects(
    selectTab(session, 'settings'),
    /selectTab expects \{tab\}: unknown tab "settings"; tabs: home, search, favorites, profile, report/,
  );
  // the sheet covers the tab bar, so switching under it does nothing; dismiss shows where we are
  await selectTab(session, 'report', ({ name }) => assert.equal(name, 'Report'));
  await selectTab(session, 'search', ({ name }) => assert.equal(name, 'Report'));
  await session.do({ action: 'dismiss', expectation: ({ name }) => assert.equal(name, 'InventoryList') });
  // with the sheet closed there is nothing to dismiss
  await assert.rejects(session.do({ action: 'dismiss' }), /unknown action "dismiss"/);
});
