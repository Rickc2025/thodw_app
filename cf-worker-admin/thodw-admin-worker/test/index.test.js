import test from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync } from 'node:crypto';
import { exportJWK } from 'jose';

import { handleRequest } from '../src/index.js';

function firestoreDoc(name, fields) {
  return {
    name,
    fields,
  };
}

function stringField(value) {
  return { stringValue: value };
}

function boolField(value) {
  return { booleanValue: value };
}

function parseBody(body) {
  if (!body) return {};
  if (typeof body === 'string') return JSON.parse(body);
  if (body instanceof URLSearchParams) return Object.fromEntries(body.entries());
  return JSON.parse(String(body));
}

test('worker admin flows stay coherent', async () => {
  const { privateKey, publicKey } = generateKeyPairSync('rsa', {
    modulusLength: 2048,
  });
  const privateKeyPem = privateKey.export({ type: 'pkcs8', format: 'pem' });
  const jwk = await exportJWK(publicKey);
  jwk.kid = 'test-kid';
  jwk.alg = 'RS256';
  jwk.use = 'sig';

  const env = {
    FIREBASE_PROJECT_ID: 'aqx-dive-log',
    GOOGLE_SERVICE_ACCOUNT_EMAIL: 'worker-test@aqx-dive-log.iam.gserviceaccount.com',
    GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY: privateKeyPem,
    TEST_TRUST_BEARER_UID: 'admin-uid',
  };

  const firestoreUsers = new Map([
    ['admin-uid', {
      melcoId: '1015083',
      displayName: 'Ricardo',
      employeeName: 'Ricardo',
      role: 'admin',
      active: true,
      mustChangePassword: false,
      requirePasswordChange: false,
    }],
  ]);
  const authUsers = new Map([
    ['admin-uid', {
      localId: 'admin-uid',
      email: '1015083@hodw.local',
      displayName: 'Ricardo',
      disabled: false,
    }],
  ]);
  const auditLogs = [];

  const originalFetch = global.fetch;
  global.fetch = async (url, init = {}) => {
    const target = typeof url === 'string' ? url : url.toString();
    const method = init.method || 'GET';

    if (target.includes('service_accounts/v1/jwk/securetoken@system.gserviceaccount.com')) {
      return Response.json({ keys: [jwk] });
    }

    if (target === 'https://oauth2.googleapis.com/token') {
      return Response.json({ access_token: 'google-oauth-token', expires_in: 3600 });
    }

    if (target.includes('/documents/users/admin-uid') && method === 'GET') {
      const user = firestoreUsers.get('admin-uid');
      return Response.json(firestoreDoc(
        `projects/${env.FIREBASE_PROJECT_ID}/databases/(default)/documents/users/admin-uid`,
        {
          melcoId: stringField(user.melcoId),
          displayName: stringField(user.displayName),
          employeeName: stringField(user.employeeName),
          role: stringField(user.role),
          active: boolField(user.active),
          mustChangePassword: boolField(user.mustChangePassword),
          requirePasswordChange: boolField(user.requirePasswordChange),
        },
      ));
    }

    if (target.includes('/documents/users?pageSize=500') && method === 'GET') {
      const documents = [...firestoreUsers.entries()].map(([uid, user]) => firestoreDoc(
        `projects/${env.FIREBASE_PROJECT_ID}/databases/(default)/documents/users/${uid}`,
        {
          melcoId: stringField(user.melcoId),
          displayName: stringField(user.displayName),
          employeeName: stringField(user.employeeName),
          role: stringField(user.role),
          active: boolField(user.active),
          mustChangePassword: boolField(user.mustChangePassword),
          requirePasswordChange: boolField(user.requirePasswordChange),
          ...(user.lastPasswordResetAt ? { lastPasswordResetAt: stringField(user.lastPasswordResetAt) } : {}),
        },
      ));
      return Response.json({ documents });
    }

    if (target.includes('/documents/users/') && method === 'PATCH') {
      const uid = target.split('/documents/users/')[1].split('?')[0];
      const body = parseBody(init.body);
      const current = firestoreUsers.get(uid) || {};
      const next = { ...current };
      for (const [key, value] of Object.entries(body.fields || {})) {
        if ('stringValue' in value) next[key] = value.stringValue;
        if ('booleanValue' in value) next[key] = value.booleanValue;
      }
      firestoreUsers.set(uid, next);
      return Response.json(firestoreDoc(
        `projects/${env.FIREBASE_PROJECT_ID}/databases/(default)/documents/users/${uid}`,
        Object.fromEntries(Object.entries(next).map(([key, value]) => [
          key,
          typeof value === 'boolean' ? boolField(value) : stringField(String(value)),
        ])),
      ));
    }

    if (target.includes('/documents/audit_logs?documentId=') && method === 'POST') {
      const body = parseBody(init.body);
      auditLogs.push(body.fields);
      const id = `audit-${auditLogs.length}`;
      return Response.json(firestoreDoc(
        `projects/${env.FIREBASE_PROJECT_ID}/databases/(default)/documents/audit_logs/${id}`,
        body.fields,
      ));
    }

    if (target.endsWith(`/projects/${env.FIREBASE_PROJECT_ID}/accounts:lookup`) && method === 'POST') {
      const body = parseBody(init.body);
      const emails = body.email || [];
      const users = [...authUsers.values()].filter((user) => emails.includes(user.email));
      return Response.json({ users });
    }

    if (target.endsWith('/accounts:signUp') && method === 'POST') {
      const body = parseBody(init.body);
      const localId = 'user-200';
      authUsers.set(localId, {
        localId,
        email: body.email,
        displayName: body.displayName,
        disabled: body.disabled === true,
      });
      return Response.json({ localId, email: body.email, displayName: body.displayName });
    }

    if (target.endsWith(`/projects/${env.FIREBASE_PROJECT_ID}/accounts:update`) && method === 'POST') {
      const body = parseBody(init.body);
      const user = authUsers.get(body.localId);
      if (!user) {
        return Response.json({ error: { message: 'USER_NOT_FOUND' } }, { status: 404 });
      }
      if (Object.prototype.hasOwnProperty.call(body, 'disableUser')) {
        user.disabled = body.disableUser === true;
      }
      if (body.password) {
        user.password = body.password;
      }
      authUsers.set(body.localId, user);
      return Response.json({ localId: user.localId, email: user.email, disabled: user.disabled });
    }

    throw new Error(`Unhandled fetch in test: ${method} ${target}`);
  };

  try {
    const authHeaders = { authorization: 'Bearer test-admin-token' };

    let response = await handleRequest(new Request('https://worker.test/admin/check', { headers: authHeaders }), env);
    let data = await response.json();
    assert.equal(response.status, 200, JSON.stringify(data));
    assert.equal(data.ok, true);
    assert.equal(data.role, 'admin');

    response = await handleRequest(new Request('https://worker.test/users', {
      method: 'POST',
      headers: { ...authHeaders, 'content-type': 'application/json' },
      body: JSON.stringify({
        melcoId: '77406',
        displayName: 'Andrew',
        role: 'operator',
        tempPassword: 'Welcome2026',
      }),
    }), env);
    data = await response.json();
    assert.equal(response.status, 201);
    assert.equal(data.user.melcoId, '77406');
    assert.equal(firestoreUsers.get('user-200').mustChangePassword, true);
    assert.equal(firestoreUsers.get('user-200').requirePasswordChange, true);

    response = await handleRequest(new Request('https://worker.test/users/user-200/reset-password', {
      method: 'POST',
      headers: { ...authHeaders, 'content-type': 'application/json' },
      body: JSON.stringify({ tempPassword: 'Welcome2026' }),
    }), env);
    data = await response.json();
    assert.equal(response.status, 200);
    assert.equal(data.ok, true);
    assert.equal(firestoreUsers.get('user-200').mustChangePassword, true);

    response = await handleRequest(new Request('https://worker.test/users/user-200/active', {
      method: 'POST',
      headers: { ...authHeaders, 'content-type': 'application/json' },
      body: JSON.stringify({ active: false }),
    }), env);
    data = await response.json();
    assert.equal(response.status, 200);
    assert.equal(data.active, false);
    assert.equal(firestoreUsers.get('user-200').active, false);
    assert.equal(authUsers.get('user-200').disabled, true);

    response = await handleRequest(new Request('https://worker.test/users/user-200/active', {
      method: 'POST',
      headers: { ...authHeaders, 'content-type': 'application/json' },
      body: JSON.stringify({ active: true }),
    }), env);
    data = await response.json();
    assert.equal(response.status, 200);
    assert.equal(data.active, true);
    assert.equal(firestoreUsers.get('user-200').active, true);
    assert.equal(authUsers.get('user-200').disabled, false);

    response = await handleRequest(new Request('https://worker.test/users', {
      headers: authHeaders,
    }), env);
    data = await response.json();
    assert.equal(response.status, 200);
    assert.equal(data.users.length, 2);
    assert.equal(data.users.find((user) => user.melcoId === '77406').displayName, 'Andrew');

    response = await handleRequest(new Request('https://worker.test/users/force-password-change', {
      method: 'POST',
      headers: { ...authHeaders, 'content-type': 'application/json' },
      body: JSON.stringify({}),
    }), env);
    data = await response.json();
    assert.equal(response.status, 200);
    assert.equal(data.affectedUsers, 2);
    assert.equal(auditLogs.length, 5);
  } finally {
    global.fetch = originalFetch;
  }
});
