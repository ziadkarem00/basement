import assert from 'node:assert';

const BASE_URL = process.env.TEST_URL || 'http://127.0.0.1:8787';
const WS_BASE_URL = BASE_URL.replace(/^http/, 'ws');

const SAMPLE_JPEG = '/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////wgALCAABAAEBAREA/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPxA=';

function delay(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

function randomCode() {
  return String(Math.floor(10000 + Math.random() * 89000));
}

function createClient(roomCode, name, id, isCreate = false, deviceId = '', platform = 'web') {
  let url = `${WS_BASE_URL}/room/${roomCode}/ws?name=${encodeURIComponent(name)}&id=${encodeURIComponent(id)}`;
  if (isCreate) url += '&create=1';
  if (deviceId) url += `&deviceId=${encodeURIComponent(deviceId)}`;
  if (platform) url += `&platform=${encodeURIComponent(platform)}`;

  const ws = new WebSocket(url);
  const messages = [];
  const liveMessages = [];
  const events = [];
  let inHistory = false;
  let closed = false;
  let closeCode = null;

  const openPromise = new Promise((resolve, reject) => {
    ws.onopen = () => resolve();
    ws.onerror = (e) => reject(e);
  });

  const closePromise = new Promise((resolve) => {
    ws.onclose = (event) => {
      closed = true;
      closeCode = event.code;
      resolve(event);
    };
  });

  ws.onmessage = (event) => {
    try {
      const data = JSON.parse(event.data);
      events.push(data);
      if (data.type === 'history_start') {
        inHistory = true;
      } else if (data.type === 'history_end') {
        inHistory = false;
      } else if (data.type === 'msg') {
        messages.push(data);
        if (!inHistory) {
          liveMessages.push(data);
        }
      }
    } catch (e) {
      console.error('Test parse error:', e);
    }
  };

  async function waitForEvent(predicate, timeout = 7000) {
    const start = Date.now();
    while (Date.now() - start < timeout) {
      const found = events.find(predicate);
      if (found) return found;
      await delay(50);
    }
    throw new Error(`Timeout waiting for event matching predicate after ${timeout}ms. Received: ${JSON.stringify(events)}`);
  }

  async function waitForMsg(predicate, timeout = 7000) {
    const start = Date.now();
    while (Date.now() - start < timeout) {
      const found = messages.find(predicate);
      if (found) return found;
      await delay(50);
    }
    throw new Error(`Timeout waiting for msg matching predicate after ${timeout}ms. Received: ${JSON.stringify(messages)}`);
  }

  return {
    ws,
    events,
    messages,
    liveMessages,
    openPromise,
    closePromise,
    get isClosed() {
      return closed;
    },
    get closeCode() {
      return closeCode;
    },
    waitForEvent,
    waitForMsg,
    send(obj) {
      ws.send(JSON.stringify(obj));
    },
    close(code = 1000, reason = '') {
      ws.close(code, reason);
    },
  };
}

async function run() {
  console.log(`Starting Basement test suite against ${BASE_URL}...`);

  // =========================================================================
  // TEST 1: Delete Message + Host Delete + Permissions
  // =========================================================================
  console.log('\n--- Test 1: Delete Message, Host Delete, and Permissions ---');
  const code1 = randomCode();
  const a1 = createClient(code1, 'Alice', 'id_alice', true);
  await a1.openPromise;
  await a1.waitForEvent((e) => e.type === 'welcome');

  const b1 = createClient(code1, 'Bob', 'id_bob', false);
  await b1.openPromise;
  await b1.waitForEvent((e) => e.type === 'welcome');

  const c1 = createClient(code1, 'Charlie', 'id_charlie', false);
  await c1.openPromise;
  await c1.waitForEvent((e) => e.type === 'welcome');

  // Bob sends text message
  b1.send({ type: 'text', clientId: 'c_b1', text: 'Hello from Bob' });
  const bMsg = await a1.waitForMsg((m) => m.clientId === 'c_b1');
  assert.ok(bMsg.id, 'Server returned message id');

  // Bob sends image message
  b1.send({ type: 'image', clientId: 'c_b_img', image: SAMPLE_JPEG });
  const bImgMsg = await a1.waitForMsg((m) => m.clientId === 'c_b_img');
  assert.ok(bImgMsg.id, 'Server returned image message id');

  // Charlie tries to delete Bob's text message -> REJECTED (error event, no deletion)
  c1.send({ type: 'delete', id: bMsg.id });
  const cErr = await c1.waitForEvent((e) => e.type === 'error');
  assert.ok(cErr, 'Charlie received error trying to delete Bob message');
  assert.strictEqual(b1.events.filter((e) => e.type === 'deleted').length, 0);

  // Bob deletes his own text message with the server id
  b1.send({ type: 'delete', id: bMsg.id });
  const delA = await a1.waitForEvent((e) => e.type === 'deleted' && e.id === bMsg.id);
  const delB = await b1.waitForEvent((e) => e.type === 'deleted' && e.id === bMsg.id);
  const delC = await c1.waitForEvent((e) => e.type === 'deleted' && e.id === bMsg.id);
  assert.ok(delA && delB && delC, 'Everyone got deleted event');

  // Deleting twice is harmless
  b1.send({ type: 'delete', id: bMsg.id });
  await delay(200);

  // Bob deletes his image message
  b1.send({ type: 'delete', id: bImgMsg.id });
  await a1.waitForEvent((e) => e.type === 'deleted' && e.id === bImgMsg.id);

  // Charlie sends a message, and Host Alice deletes Charlie's message
  c1.send({ type: 'text', clientId: 'c_c1', text: 'Charlie message' });
  const cMsg = await a1.waitForMsg((m) => m.clientId === 'c_c1');
  a1.send({ type: 'delete', id: cMsg.id });
  const delHost = await c1.waitForEvent((e) => e.type === 'deleted' && e.id === cMsg.id);
  assert.ok(delHost, 'Host deleted Charlie message');

  // Alice deletes Alice's own message
  a1.send({ type: 'text', clientId: 'c_a1', text: 'Alice message' });
  const aMsg = await b1.waitForMsg((m) => m.clientId === 'c_a1');
  a1.send({ type: 'delete', id: aMsg.id });
  await b1.waitForEvent((e) => e.type === 'deleted' && e.id === aMsg.id);

  // Nobody can delete system lines
  const sysMsg = a1.messages.find((m) => m.kind === 'system');
  if (sysMsg) {
    a1.send({ type: 'delete', id: sysMsg.id });
    const sysErr = await a1.waitForEvent((e) => e.type === 'error');
    assert.ok(sysErr);
  }

  // New client D joins: history replay shows tombstones with deleted:true and no text/image
  const d1 = createClient(code1, 'Dave', 'id_dave', false);
  await d1.openPromise;
  await d1.waitForEvent((e) => e.type === 'history_end');

  const bTombstone = d1.messages.find((m) => m.id === bMsg.id);
  assert.ok(bTombstone, 'Tombstone exists in history');
  assert.strictEqual(bTombstone.deleted, true);
  assert.strictEqual(bTombstone.text, undefined);
  assert.strictEqual(bTombstone.image, undefined);

  // Dave can still delete a message sent before reconnect
  d1.send({ type: 'text', clientId: 'c_d1', text: 'Dave initial message' });
  const dMsg = await a1.waitForMsg((m) => m.clientId === 'c_d1');

  d1.close();
  await delay(200);

  // Dave reconnects with same ID
  const d1Rejoin = createClient(code1, 'Dave', 'id_dave', false);
  await d1Rejoin.openPromise;
  await d1Rejoin.waitForEvent((e) => e.type === 'history_end');

  // Dave deletes message from history
  d1Rejoin.send({ type: 'delete', id: dMsg.id });
  await a1.waitForEvent((e) => e.type === 'deleted' && e.id === dMsg.id);

  a1.close();
  b1.close();
  c1.close();
  d1Rejoin.close();
  console.log('✓ Test 1 passed!');

  // =========================================================================
  // TEST 2: View-Once Photos
  // =========================================================================
  console.log('\n--- Test 2: View-Once Photos ---');
  const code2 = randomCode();
  const a2 = createClient(code2, 'Alice', 'id_alice', true);
  await a2.openPromise;
  await a2.waitForEvent((e) => e.type === 'welcome');

  // Trying to send viewOnce when alone -> error "No one else is here"
  a2.send({ type: 'image', clientId: 'c_solo_vo', image: SAMPLE_JPEG, viewOnce: true });
  const errSolo = await a2.waitForEvent((e) => e.type === 'error');
  assert.strictEqual(errSolo.reason, 'No one else is here');

  const b2 = createClient(code2, 'Bob', 'id_bob', false);
  await b2.openPromise;
  await b2.waitForEvent((e) => e.type === 'welcome');

  const c2 = createClient(code2, 'Charlie', 'id_charlie', false);
  await c2.openPromise;
  await c2.waitForEvent((e) => e.type === 'welcome');

  // Alice sends view-once image
  await delay(3100); // Respect image rate limit
  a2.send({ type: 'image', clientId: 'c_vo1', image: SAMPLE_JPEG, viewOnce: true });

  // Broadcast to B and C must contain viewOnce:true and NO image data
  const voMsgB = await b2.waitForMsg((m) => m.clientId === 'c_vo1');
  const voMsgC = await c2.waitForMsg((m) => m.clientId === 'c_vo1');
  assert.strictEqual(voMsgB.viewOnce, true);
  assert.strictEqual(voMsgB.image, undefined, 'Broadcast has no image data');
  assert.strictEqual(voMsgC.image, undefined, 'Broadcast has no image data');

  // Sender Alice cannot view her own view-once image
  a2.send({ type: 'view', id: voMsgB.id });
  const errA = await a2.waitForEvent((e) => e.type === 'error');
  assert.ok(errA);

  // Bob views photo
  b2.send({ type: 'view', id: voMsgB.id });
  const viewDataB = await b2.waitForEvent((e) => e.type === 'view_data' && e.id === voMsgB.id);
  assert.ok(viewDataB.image, 'Bob received view_data with image');
  assert.ok(viewDataB.image.startsWith('/9j/'));

  // Everyone receives "viewed"
  const viewedA = await a2.waitForEvent((e) => e.type === 'viewed' && e.id === voMsgB.id);
  assert.strictEqual(viewedA.name, 'Bob');

  // Bob viewing twice is rejected
  b2.send({ type: 'view', id: voMsgB.id });
  const errB2 = await b2.waitForEvent((e) => e.type === 'error');
  assert.ok(errB2);

  // Dave joins AFTER message was sent -> Dave is not a recipient and cannot view
  const d2 = createClient(code2, 'Dave', 'id_dave', false);
  await d2.openPromise;
  await d2.waitForEvent((e) => e.type === 'history_end');
  d2.send({ type: 'view', id: voMsgB.id });
  const errD = await d2.waitForEvent((e) => e.type === 'error');
  assert.strictEqual(errD.reason, 'Photo no longer available');

  // Charlie views photo (final recipient)
  c2.send({ type: 'view', id: voMsgB.id });
  const viewDataC = await c2.waitForEvent((e) => e.type === 'view_data');
  assert.ok(viewDataC.image);

  // Now all recipients opened it -> image deleted and consumed
  await delay(300);
  const e2 = createClient(code2, 'Eve', 'id_eve', false);
  await e2.openPromise;
  await e2.waitForEvent((e) => e.type === 'history_end');

  const replayedVO = e2.messages.find((m) => m.id === voMsgB.id);
  assert.ok(replayedVO);
  assert.strictEqual(replayedVO.consumed, true, 'Replay shows consumed');
  assert.strictEqual(replayedVO.image, undefined, 'Storage has no image data');

  a2.close();
  b2.close();
  c2.close();
  d2.close();
  e2.close();
  console.log('✓ Test 2 passed!');

  // =========================================================================
  // TEST 3: Rate Limiting
  // =========================================================================
  console.log('\n--- Test 3: Rate Limiting ---');
  const code3 = randomCode();
  const a3 = createClient(code3, 'Alice', 'id_alice', true);
  await a3.openPromise;
  await a3.waitForEvent((e) => e.type === 'welcome');

  const b3 = createClient(code3, 'Bob', 'id_bob', false);
  await b3.openPromise;
  await b3.waitForEvent((e) => e.type === 'welcome');

  // Send 10 text messages in rapid succession
  console.log('  Sending 10 rapid text messages (limit: 6 per 5s)...');
  for (let i = 0; i < 10; i++) {
    b3.send({ type: 'text', clientId: `c_burst_${i}`, text: `Msg ${i}` });
  }

  await delay(3000);

  const errors = b3.events.filter((e) => e.type === 'error' && e.reason === 'slow_down');
  assert.strictEqual(errors.length, 4, '4 out of 10 messages were rate-limited');
  assert.ok(errors[0].retryAfterMs > 0, 'Error carries retryAfterMs');

  // Verify only 6 messages reached Alice
  const receivedCount = a3.messages.filter((m) => m.clientId && m.clientId.startsWith('c_burst_')).length;
  assert.strictEqual(receivedCount, 6, 'Only 6 messages stored/broadcast');
  assert.strictEqual(b3.isClosed, false, 'Socket remained open');

  // Test image rate limiting (max 1 per 3s)
  console.log('  Testing image rate limiting (max 1 per 3s)...');
  b3.send({ type: 'image', clientId: 'c_img_1', image: SAMPLE_JPEG });
  await a3.waitForMsg((m) => m.clientId === 'c_img_1');

  // Immediately send second image -> must get slow_down
  b3.send({ type: 'image', clientId: 'c_img_2', image: SAMPLE_JPEG });
  const imgErr = await b3.waitForEvent((e) => e.clientId === 'c_img_2' && e.reason === 'slow_down');
  assert.ok(imgErr, 'Second rapid image was rate limited');

  a3.close();
  b3.close();
  console.log('✓ Test 3 passed!');

  // =========================================================================
  // TEST 4: Forced View-Once & "mine" Field Calculation (including Duplicate Names & Replay)
  // =========================================================================
  console.log('\n--- Test 4: Forced View-Once and "mine" Field Calculation ---');
  const code4 = randomCode();
  const host = createClient(code4, 'Alex', 'id_alex_host', true);
  await host.openPromise;
  await host.waitForEvent((e) => e.type === 'welcome');

  // Solo image send (without viewOnce flag) MUST fail with "No one else is here"
  host.send({ type: 'image', clientId: 'c_solo_plain_img', image: SAMPLE_JPEG });
  const soloErr = await host.waitForEvent((e) => e.type === 'error' && e.clientId === 'c_solo_plain_img');
  assert.strictEqual(soloErr.reason, 'No one else is here', 'Solo image was rejected because no recipients exist');

  // Second user joins: Bob
  const bob = createClient(code4, 'Bob', 'id_bob_4', false);
  await bob.openPromise;
  await bob.waitForEvent((e) => e.type === 'welcome');

  // Third user joins with duplicate name 'Bob' but different member id
  const bob2 = createClient(code4, 'Bob', 'id_bob_duplicate', false);
  await bob2.openPromise;
  await bob2.waitForEvent((e) => e.type === 'welcome');

  // Host sends text message
  host.send({ type: 'text', clientId: 'c_alex_msg', text: 'Hello from host' });
  const echoHost = await host.waitForMsg((m) => m.clientId === 'c_alex_msg');
  assert.strictEqual(echoHost.mine, true, 'Sender echo has mine: true');

  const bobReceived = await bob.waitForMsg((m) => m.clientId === 'c_alex_msg');
  assert.strictEqual(bobReceived.mine, false, 'Other recipient has mine: false');

  const bob2Received = await bob2.waitForMsg((m) => m.clientId === 'c_alex_msg');
  assert.strictEqual(bob2Received.mine, false, 'Duplicate name recipient has mine: false');

  // First Bob sends message: Bob1 must receive mine: true; Bob2 (duplicate name) must receive mine: false
  bob.send({ type: 'text', clientId: 'c_bob1_msg', text: 'Message from Bob 1' });
  const echoBob1 = await bob.waitForMsg((m) => m.clientId === 'c_bob1_msg');
  assert.strictEqual(echoBob1.mine, true, 'Bob 1 echo has mine: true');

  const bob2FromBob1 = await bob2.waitForMsg((m) => m.clientId === 'c_bob1_msg');
  assert.strictEqual(bob2FromBob1.mine, false, 'Bob 2 (same name Bob) receives Bob 1 message as mine: false');

  // Forced View-Once: Bob sends image WITHOUT viewOnce: true
  await delay(3100);
  bob.send({ type: 'image', clientId: 'c_bob_plain_img', image: SAMPLE_JPEG }); // no viewOnce passed!

  const hostImg = await host.waitForMsg((m) => m.clientId === 'c_bob_plain_img');
  assert.strictEqual(hostImg.viewOnce, true, 'Server forced viewOnce: true');
  assert.strictEqual(hostImg.image, undefined, 'Server omitted image payload from broadcast');
  assert.strictEqual(hostImg.mine, false, 'Host received Bob image with mine: false');

  const bobEchoImg = await bob.waitForMsg((m) => m.clientId === 'c_bob_plain_img');
  assert.strictEqual(bobEchoImg.viewOnce, true, 'Echo has viewOnce: true');
  assert.strictEqual(bobEchoImg.image, undefined, 'Echo has no image data');
  assert.strictEqual(bobEchoImg.mine, true, 'Echo has mine: true');

  // Test History Replay calculates mine per socket:
  // Disconnect Bob and reconnect him with the same member id 'id_bob_4'
  bob.close();
  await delay(200);

  const bobReconnected = createClient(code4, 'Bob', 'id_bob_4', false);
  await bobReconnected.openPromise;
  await bobReconnected.waitForEvent((e) => e.type === 'history_end');

  const replayedAlexMsg = bobReconnected.messages.find((m) => m.clientId === 'c_alex_msg');
  assert.ok(replayedAlexMsg, 'Replayed Alex message found');
  assert.strictEqual(replayedAlexMsg.mine, false, 'Replayed other message has mine: false');

  const replayedBobMsg = bobReconnected.messages.find((m) => m.clientId === 'c_bob1_msg');
  assert.ok(replayedBobMsg, 'Replayed Bob message found');
  assert.strictEqual(replayedBobMsg.mine, true, 'Replayed own message has mine: true on reconnect');

  const replayedImg = bobReconnected.messages.find((m) => m.clientId === 'c_bob_plain_img');
  assert.ok(replayedImg, 'Replayed image message found');
  assert.strictEqual(replayedImg.viewOnce, true, 'Replayed image is viewOnce: true');
  assert.strictEqual(replayedImg.mine, true, 'Replayed image sent by Bob has mine: true');

  host.close();
  bob2.close();
  bobReconnected.close();
  console.log('✓ Test 4 passed!');

  console.log('\n======================================================');
  console.log('ALL TESTS PASSED CLEANLY (ALL 4 ITEMS VERIFIED)!');
  console.log('======================================================\n');
}

run().catch((err) => {
  console.error('\n❌ Test failed with error:', err);
  process.exit(1);
});
