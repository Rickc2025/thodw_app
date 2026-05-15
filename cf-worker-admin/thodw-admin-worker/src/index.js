import { createRemoteJWKSet, SignJWT, jwtVerify, importPKCS8 } from 'jose';

const GOOGLE_JWKS = createRemoteJWKSet(
  new URL('https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com'),
);

const FIRESTORE_BASE = 'https://firestore.googleapis.com/v1';
const IDENTITY_TOOLKIT_BASE = 'https://identitytoolkit.googleapis.com/v1';
const OAUTH_TOKEN_URL = 'https://oauth2.googleapis.com/token';
const DEFAULT_TEMP_PASSWORD = 'Welcome2026';
const ACCESS_TOKEN_SCOPE = 'https://www.googleapis.com/auth/cloud-platform';

let cachedAccessToken = null;

function corsHeaders() {
  return {
    'access-control-allow-origin': '*',
    'access-control-allow-methods': 'GET,POST,OPTIONS',
    'access-control-allow-headers': 'authorization,content-type',
  };
}

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      ...corsHeaders(),
    },
  });
}

function errorResponse(status, error, detail) {
  return json({ error, ...(detail ? { detail } : {}) }, status);
}

function melcoIdToEmail(melcoId) {
  return `${String(melcoId).trim()}@hodw.local`;
}

function sanitizeRole(role) {
  return role === 'admin' ? 'admin' : 'operator';
}

function isStrongPassword(password) {
  const value = String(password || '');
  return value.length >= 8 && /[A-Za-z]/.test(value) && /\d/.test(value);
}

function nowIso() {
  return new Date().toISOString();
}

function decodeBase64Url(value) {
  const normalized = value.replace(/-/g, '+').replace(/_/g, '/');
  const padded = normalized + '='.repeat((4 - (normalized.length % 4 || 4)) % 4);
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) {
    bytes[i] = binary.charCodeAt(i);
  }
  return new TextDecoder().decode(bytes);
}

function parseJsonBody(request) {
  return request.json().catch(() => ({}));
}

function extractBearer(request) {
  const auth = request.headers.get('authorization') || '';
  const match = auth.match(/^Bearer\s+(.+)$/i);
  return match?.[1] || null;
}

async function verifyFirebaseToken(idToken, projectId) {
  const { payload } = await jwtVerify(idToken, GOOGLE_JWKS, {
    issuer: `https://securetoken.google.com/${projectId}`,
    audience: projectId,
  });
  return payload;
}

async function fetchJson(url, init = {}) {
  const response = await fetch(url, init);
  const text = await response.text();
  let body = null;
  if (text) {
    try {
      body = JSON.parse(text);
    } catch {
      body = { raw: text };
    }
  }
  if (!response.ok) {
    const error = new Error(body?.error?.message || body?.error || `HTTP ${response.status}`);
    error.status = response.status;
    error.body = body;
    throw error;
  }
  return body;
}

async function getGoogleAccessToken(env) {
  const now = Math.floor(Date.now() / 1000);
  if (cachedAccessToken && cachedAccessToken.expiresAt > now + 60) {
    return cachedAccessToken.token;
  }

  if (!env.GOOGLE_SERVICE_ACCOUNT_EMAIL || !env.GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY) {
    throw new Error('Worker missing Google service-account secrets.');
  }

  const key = await importPKCS8(String(env.GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY), 'RS256');

  const assertion = await new SignJWT({
    scope: ACCESS_TOKEN_SCOPE,
  })
    .setProtectedHeader({ alg: 'RS256', typ: 'JWT' })
    .setIssuer(env.GOOGLE_SERVICE_ACCOUNT_EMAIL)
    .setSubject(env.GOOGLE_SERVICE_ACCOUNT_EMAIL)
    .setAudience(OAUTH_TOKEN_URL)
    .setIssuedAt(now)
    .setExpirationTime(now + 3600)
    .sign(key);

  const tokenBody = await fetchJson(OAUTH_TOKEN_URL, {
    method: 'POST',
    headers: {
      'content-type': 'application/x-www-form-urlencoded',
    },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
  });

  cachedAccessToken = {
    token: tokenBody.access_token,
    expiresAt: now + Number(tokenBody.expires_in || 3600),
  };

  return cachedAccessToken.token;
}

async function googleApiJson(env, url, init = {}) {
  const accessToken = await getGoogleAccessToken(env);
  const headers = new Headers(init.headers || {});
  headers.set('authorization', `Bearer ${accessToken}`);
  if (!headers.has('content-type') && init.body != null) {
    headers.set('content-type', 'application/json');
  }
  return fetchJson(url, {
    ...init,
    headers,
  });
}

function toFirestoreFields(data) {
  const fields = {};
  for (const [key, value] of Object.entries(data)) {
    if (value === undefined) continue;
    if (value === null) {
      fields[key] = { nullValue: null };
    } else if (typeof value === 'string') {
      fields[key] = { stringValue: value };
    } else if (typeof value === 'boolean') {
      fields[key] = { booleanValue: value };
    } else if (typeof value === 'number') {
      if (Number.isInteger(value)) {
        fields[key] = { integerValue: String(value) };
      } else {
        fields[key] = { doubleValue: value };
      }
    } else if (Array.isArray(value)) {
      fields[key] = {
        arrayValue: {
          values: value.map((item) => toFirestoreValue(item)),
        },
      };
    } else if (typeof value === 'object') {
      fields[key] = {
        mapValue: {
          fields: toFirestoreFields(value),
        },
      };
    }
  }
  return fields;
}

function toFirestoreValue(value) {
  if (value === null) return { nullValue: null };
  if (typeof value === 'string') return { stringValue: value };
  if (typeof value === 'boolean') return { booleanValue: value };
  if (typeof value === 'number') {
    return Number.isInteger(value)
      ? { integerValue: String(value) }
      : { doubleValue: value };
  }
  if (Array.isArray(value)) {
    return {
      arrayValue: {
        values: value.map((item) => toFirestoreValue(item)),
      },
    };
  }
  return {
    mapValue: {
      fields: toFirestoreFields(value),
    },
  };
}

function fromFirestoreValue(value) {
  if ('stringValue' in value) return value.stringValue;
  if ('booleanValue' in value) return value.booleanValue;
  if ('integerValue' in value) return Number(value.integerValue);
  if ('doubleValue' in value) return value.doubleValue;
  if ('nullValue' in value) return null;
  if ('arrayValue' in value) return (value.arrayValue.values || []).map(fromFirestoreValue);
  if ('mapValue' in value) return fromFirestoreFields(value.mapValue.fields || {});
  return null;
}

function fromFirestoreFields(fields = {}) {
  const data = {};
  for (const [key, value] of Object.entries(fields)) {
    data[key] = fromFirestoreValue(value);
  }
  return data;
}

function firestoreDocUrl(env, collection, docId) {
  return `${FIRESTORE_BASE}/projects/${env.FIREBASE_PROJECT_ID}/databases/(default)/documents/${collection}/${docId}`;
}

function firestoreCollectionUrl(env, collection) {
  return `${FIRESTORE_BASE}/projects/${env.FIREBASE_PROJECT_ID}/databases/(default)/documents/${collection}`;
}

async function readFirestoreDoc(env, collection, docId) {
  try {
    const doc = await googleApiJson(env, firestoreDocUrl(env, collection, docId), {
      method: 'GET',
    });
    return {
      id: doc.name.split('/').pop(),
      ...fromFirestoreFields(doc.fields || {}),
    };
  } catch (error) {
    if (error.status === 404) return null;
    throw error;
  }
}

async function patchFirestoreDoc(env, collection, docId, data) {
  const url = new URL(firestoreDocUrl(env, collection, docId));
  for (const key of Object.keys(data).filter((key) => data[key] !== undefined)) {
    url.searchParams.append('updateMask.fieldPaths', key);
  }
  const doc = await googleApiJson(env, url.toString(), {
    method: 'PATCH',
    body: JSON.stringify({ fields: toFirestoreFields(data) }),
  });
  return {
    id: doc.name.split('/').pop(),
    ...fromFirestoreFields(doc.fields || {}),
  };
}

async function listFirestoreDocs(env, collection) {
  const body = await googleApiJson(env, `${firestoreCollectionUrl(env, collection)}?pageSize=500`, {
    method: 'GET',
  });
  return (body.documents || []).map((doc) => ({
    id: doc.name.split('/').pop(),
    ...fromFirestoreFields(doc.fields || {}),
  }));
}

async function createFirestoreDoc(env, collection, data, docId = crypto.randomUUID()) {
  const doc = await googleApiJson(env, `${firestoreCollectionUrl(env, collection)}?documentId=${encodeURIComponent(docId)}`, {
    method: 'POST',
    body: JSON.stringify({ fields: toFirestoreFields(data) }),
  });
  return {
    id: doc.name.split('/').pop(),
    ...fromFirestoreFields(doc.fields || {}),
  };
}

async function authSignUp(env, payload) {
  return googleApiJson(env, `${IDENTITY_TOOLKIT_BASE}/accounts:signUp`, {
    method: 'POST',
    body: JSON.stringify({
      ...payload,
      targetProjectId: env.FIREBASE_PROJECT_ID,
    }),
  });
}

async function authUpdate(env, payload) {
  return googleApiJson(env, `${IDENTITY_TOOLKIT_BASE}/projects/${env.FIREBASE_PROJECT_ID}/accounts:update`, {
    method: 'POST',
    body: JSON.stringify(payload),
  });
}

async function authLookup(env, identifiers) {
  return googleApiJson(env, `${IDENTITY_TOOLKIT_BASE}/projects/${env.FIREBASE_PROJECT_ID}/accounts:lookup`, {
    method: 'POST',
    body: JSON.stringify(identifiers),
  });
}

async function readAdminRecord(env, uid) {
  return readFirestoreDoc(env, 'users', uid);
}

async function requireAdmin(request, env) {
  const idToken = extractBearer(request);
  if (!idToken) {
    return { error: errorResponse(401, 'Missing bearer token') };
  }

  let payload;
  if (env.TEST_TRUST_BEARER_UID) {
    payload = { user_id: env.TEST_TRUST_BEARER_UID };
  } else {
    try {
      payload = await verifyFirebaseToken(idToken, env.FIREBASE_PROJECT_ID);
    } catch (error) {
      return {
        error: errorResponse(401, 'Invalid Firebase token', String(error?.message || error)),
      };
    }
  }

  const adminUser = await readAdminRecord(env, payload.user_id);
  if (!adminUser || adminUser.active !== true || adminUser.role !== 'admin') {
    return { error: errorResponse(403, 'Admin access required') };
  }

  return { payload, adminUser };
}

async function writeAudit(env, data) {
  return createFirestoreDoc(env, 'audit_logs', {
    ...data,
    createdAt: nowIso(),
  });
}

function normalizeManagedUser(authUser, profile) {
  const email = authUser?.email || profile?.email || '';
  const melcoId = profile?.melcoId || (email.endsWith('@hodw.local') ? email.replace(/@hodw\.local$/i, '') : null);
  return {
    uid: authUser?.localId || profile?.id,
    melcoId,
    displayName: profile?.displayName || authUser?.displayName || melcoId || '',
    role: sanitizeRole(profile?.role),
    active: profile?.active !== false && authUser?.disabled !== true,
    mustChangePassword: profile?.mustChangePassword === true || profile?.requirePasswordChange === true,
    requirePasswordChange: profile?.requirePasswordChange === true || profile?.mustChangePassword === true,
    disabledInAuth: authUser?.disabled === true,
    createdAt: profile?.createdAt || null,
    updatedAt: profile?.updatedAt || null,
    lastPasswordResetAt: profile?.lastPasswordResetAt || null,
    email,
  };
}

async function listManagedUsers(env) {
  const firestoreUsers = await listFirestoreDocs(env, 'users');

  return firestoreUsers
    .filter((user) => !!user.melcoId)
    .map((user) => normalizeManagedUser(null, user))
    .sort((a, b) => {
      const nameA = `${a.displayName} ${a.melcoId}`.toLowerCase();
      const nameB = `${b.displayName} ${b.melcoId}`.toLowerCase();
      return nameA.localeCompare(nameB);
    });
}

async function handleAdminCheck(request, env) {
  const auth = await requireAdmin(request, env);
  if (auth.error) return auth.error;

  return json({
    ok: true,
    backend: 'cloudflare-worker',
    uid: auth.payload.user_id,
    melcoId: auth.adminUser.melcoId || null,
    role: auth.adminUser.role,
  });
}

async function handleListUsers(request, env) {
  const auth = await requireAdmin(request, env);
  if (auth.error) return auth.error;

  const users = await listManagedUsers(env);
  return json({ ok: true, users });
}

async function handleCreateUser(request, env) {
  const auth = await requireAdmin(request, env);
  if (auth.error) return auth.error;

  const body = await parseJsonBody(request);
  const melcoId = String(body.melcoId || '').trim();
  const displayName = String(body.displayName || '').trim();
  const tempPassword = String(body.tempPassword || DEFAULT_TEMP_PASSWORD).trim();
  const role = sanitizeRole(body.role);

  if (!/^\d+$/.test(melcoId)) {
    return errorResponse(400, 'Valid numeric Melco ID required.');
  }
  if (!displayName) {
    return errorResponse(400, 'Display name is required.');
  }
  if (!isStrongPassword(tempPassword)) {
    return errorResponse(400, 'Temporary password must be at least 8 characters and contain at least one letter and one number.');
  }

  const email = melcoIdToEmail(melcoId);

  try {
    const lookup = await authLookup(env, { email: [email] });
    if ((lookup.users || []).length > 0) {
      return errorResponse(409, 'User already exists.');
    }

    const created = await authSignUp(env, {
      email,
      password: tempPassword,
      displayName,
      disabled: false,
    });

    const timestamp = nowIso();
    await patchFirestoreDoc(env, 'users', created.localId, {
      melcoId,
      displayName,
      employeeName: displayName,
      role,
      active: true,
      mustChangePassword: true,
      requirePasswordChange: true,
      createdAt: timestamp,
      updatedAt: timestamp,
      createdBy: auth.payload.user_id,
    });

    await writeAudit(env, {
      action: 'create_user',
      byUid: auth.payload.user_id,
      targetUid: created.localId,
      melcoId,
      displayName,
      role,
    });

    return json({
      ok: true,
      user: {
        uid: created.localId,
        melcoId,
        displayName,
        role,
        active: true,
        mustChangePassword: true,
      },
    }, 201);
  } catch (error) {
    const detail = String(error?.body?.error?.message || error?.message || error);
    if (detail.includes('EMAIL_EXISTS')) {
      return errorResponse(409, 'User already exists.');
    }
    return errorResponse(500, 'Failed to create user.', detail);
  }
}

async function handleResetPassword(request, env, uid) {
  const auth = await requireAdmin(request, env);
  if (auth.error) return auth.error;

  const body = await parseJsonBody(request);
  const tempPassword = String(body.tempPassword || DEFAULT_TEMP_PASSWORD).trim();
  if (!uid) return errorResponse(400, 'uid is required.');
  if (!isStrongPassword(tempPassword)) {
    return errorResponse(400, 'Temporary password must be at least 8 characters and contain at least one letter and one number.');
  }

  try {
    await authUpdate(env, {
      localId: uid,
      password: tempPassword,
    });

    await patchFirestoreDoc(env, 'users', uid, {
      mustChangePassword: true,
      requirePasswordChange: true,
      lastPasswordResetAt: nowIso(),
      lastPasswordResetBy: auth.payload.user_id,
      updatedAt: nowIso(),
    });

    await writeAudit(env, {
      action: 'reset_password',
      byUid: auth.payload.user_id,
      targetUid: uid,
    });

    return json({ ok: true, uid, tempPassword: DEFAULT_TEMP_PASSWORD === tempPassword ? DEFAULT_TEMP_PASSWORD : undefined });
  } catch (error) {
    return errorResponse(500, 'Failed to reset password.', String(error?.body?.error?.message || error?.message || error));
  }
}

async function handleSetActive(request, env, uid) {
  const auth = await requireAdmin(request, env);
  if (auth.error) return auth.error;

  const body = await parseJsonBody(request);
  const active = body.active;
  if (!uid || typeof active !== 'boolean') {
    return errorResponse(400, 'uid and boolean active are required.');
  }

  try {
    await authUpdate(env, {
      localId: uid,
      disableUser: !active,
    });

    await patchFirestoreDoc(env, 'users', uid, {
      active,
      updatedAt: nowIso(),
    });

    await writeAudit(env, {
      action: active ? 'activate_user' : 'deactivate_user',
      byUid: auth.payload.user_id,
      targetUid: uid,
    });

    return json({ ok: true, uid, active });
  } catch (error) {
    return errorResponse(500, 'Failed to update user state.', String(error?.body?.error?.message || error?.message || error));
  }
}

async function handleForcePasswordChange(request, env) {
  const auth = await requireAdmin(request, env);
  if (auth.error) return auth.error;

  try {
    const users = await listFirestoreDocs(env, 'users');
    const managedUsers = users.filter((user) => user.active === true && !!user.melcoId);
    await Promise.all(
      managedUsers.map((user) => patchFirestoreDoc(env, 'users', user.id, {
        mustChangePassword: true,
        requirePasswordChange: true,
        lastPasswordResetAt: nowIso(),
        lastPasswordResetBy: auth.payload.user_id,
        updatedAt: nowIso(),
      })),
    );

    await writeAudit(env, {
      action: 'force_password_change_all',
      byUid: auth.payload.user_id,
      affectedUsers: managedUsers.length,
    });

    return json({ ok: true, affectedUsers: managedUsers.length });
  } catch (error) {
    return errorResponse(500, 'Failed to force password change.', String(error?.body?.error?.message || error?.message || error));
  }
}

export async function handleRequest(request, env) {
  if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: corsHeaders() });

  const url = new URL(request.url);
  const pathname = url.pathname.replace(/\/+$/, '') || '/';

  if (pathname === '/health' && request.method === 'GET') {
    return json({ ok: true, service: 'thodw-admin-worker', backend: 'cloudflare-worker' });
  }

  if (pathname === '/admin/check' && request.method === 'GET') {
    return handleAdminCheck(request, env);
  }

  if (pathname === '/users' && request.method === 'GET') {
    return handleListUsers(request, env);
  }

  if (pathname === '/users' && request.method === 'POST') {
    return handleCreateUser(request, env);
  }

  const resetMatch = pathname.match(/^\/users\/([^/]+)\/reset-password$/);
  if (resetMatch && request.method === 'POST') {
    return handleResetPassword(request, env, decodeURIComponent(resetMatch[1]));
  }

  const activeMatch = pathname.match(/^\/users\/([^/]+)\/active$/);
  if (activeMatch && request.method === 'POST') {
    return handleSetActive(request, env, decodeURIComponent(activeMatch[1]));
  }

  if (pathname === '/users/force-password-change' && request.method === 'POST') {
    return handleForcePasswordChange(request, env);
  }

  return errorResponse(404, 'Not found');
}

export default {
  async fetch(request, env) {
    try {
      return await handleRequest(request, env);
    } catch (error) {
      return errorResponse(500, 'Unhandled worker failure.', String(error?.message || error));
    }
  },
};
