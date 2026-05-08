const PROJECT_ID = 'aqx-dive-log';
const FIRESTORE_BASE = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents`;
const IDENTITY_BASE = `https://identitytoolkit.googleapis.com/v1/projects/${PROJECT_ID}`;
const MELCO_DOMAIN = '@hodw.local';
const DEFAULT_PASSWORD = 'Welcome2026';
const BOOTSTRAP_ADMIN_MELCO_ID = '1015083';
const ALLOWED_ROLES = new Set(['admin', 'operator']);

export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: corsHeaders() });
    }

    try {
      const url = new URL(request.url);

      if (request.method === 'GET') {
        return json({
          ok: true,
          service: 'thodw-auth-provisioner',
          status: 'ready',
          endpoints: ['POST /bootstrap-admin', 'POST /users'],
          note: 'Open in browser = health check only. This worker expects POST for provisioning calls.',
        });
      }

      if (request.method !== 'POST') {
        return json({ error: 'Method not allowed.' }, 405);
      }

      const body = await request.json().catch(() => ({}));

      if (url.pathname === '/bootstrap-admin') {
        return await handleBootstrapAdmin(body, env);
      }
      if (url.pathname === '/users') {
        return await handleCreateUser(body, env, request);
      }

      return json({ error: 'Not found.' }, 404);
    } catch (error) {
      return json({ error: error.message || 'Unexpected server error.' }, 500);
    }
  },
};

async function handleBootstrapAdmin(body, env) {
  requireSecret(env, 'BOOTSTRAP_TOKEN');
  assertToken(body?.bootstrapToken, env.BOOTSTRAP_TOKEN);

  const melcoId = normalizeMelcoId(body?.melcoId);
  const displayName = String(body?.displayName || 'Ricardo').trim();
  const role = normalizeRole(body?.role || 'admin');

  if (melcoId !== BOOTSTRAP_ADMIN_MELCO_ID) {
    throw new Error('Bootstrap is only allowed for the configured first admin Melco ID.');
  }
  if (role !== 'admin') {
    throw new Error('Bootstrap admin must use admin role.');
  }

  const accessToken = await getGoogleAccessToken(env.GCP_SERVICE_ACCOUNT_JSON);
  const email = melcoToEmail(melcoId);
  let authUser = await lookupUserByEmail(accessToken, email);
  let created = false;
  let updated = false;

  if (!authUser) {
    authUser = await createAuthUser(accessToken, env, {
      melcoId,
      email,
      password: DEFAULT_PASSWORD,
      displayName,
      role,
    });
    created = true;
  }

  await upsertFirestoreUser(accessToken, authUser.localId, {
    melcoId,
    role,
    displayName,
    requirePasswordChange: true,
    bootstrapAdmin: true,
  });
  updated = true;

  return json({
    email,
    password: DEFAULT_PASSWORD,
    role,
    displayName,
    created,
    updated,
  });
}

async function handleCreateUser(body, env, request) {
  const authHeader = request.headers.get('Authorization') || '';
  const accessToken = await getGoogleAccessToken(env.GCP_SERVICE_ACCOUNT_JSON);
  const firebaseUser = await verifyFirebaseIdToken(authHeader, env, accessToken);
  const callerProfile = await getFirestoreUserProfile(accessToken, firebaseUser.user_id);
  if (!callerProfile || callerProfile.role !== 'admin') {
    throw new Error('Only admins can create login users.');
  }

  const melcoId = normalizeMelcoId(body?.melcoId);
  const displayName = String(body?.displayName || '').trim();
  const role = normalizeRole(body?.role || 'operator');

  if (!melcoId) {
    throw new Error('Melco ID is required.');
  }
  if (!displayName) {
    throw new Error('Display name is required.');
  }

  const email = melcoToEmail(melcoId);
  let authUser = await lookupUserByEmail(accessToken, email);
  let created = false;
  let updated = false;

  if (!authUser) {
    authUser = await createAuthUser(accessToken, env, {
      melcoId,
      email,
      password: DEFAULT_PASSWORD,
      displayName,
      role,
    });
    created = true;
  } else {
    await updateAuthUser(accessToken, authUser.localId, {
      email,
      displayName,
      password: DEFAULT_PASSWORD,
    });
    updated = true;
  }

  await upsertFirestoreUser(accessToken, authUser.localId, {
    melcoId,
    role,
    displayName,
    requirePasswordChange: true,
  });
  updated = true;

  return json({
    email,
    password: DEFAULT_PASSWORD,
    role,
    displayName,
    created,
    updated,
  });
}

function requireSecret(env, key) {
  if (!env[key]) {
    throw new Error(`${key} is not configured on the worker.`);
  }
}

function assertToken(actual, expected) {
  if (!actual || actual !== expected) {
    throw new Error('Unauthorized request.');
  }
}

function normalizeMelcoId(value) {
  return String(value || '').replace(/\D/g, '');
}

function melcoToEmail(melcoId) {
  return `${melcoId}${MELCO_DOMAIN}`;
}

function normalizeRole(value) {
  const role = String(value || 'operator').trim().toLowerCase();
  if (!ALLOWED_ROLES.has(role)) {
    throw new Error('Role must be admin or operator.');
  }
  return role;
}

function corsHeaders() {
  return {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
  };
}

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      'Content-Type': 'application/json',
      ...corsHeaders(),
    },
  });
}

async function verifyFirebaseIdToken(authHeader, env, accessToken) {
  const token = extractBearerToken(authHeader);
  if (!token) {
    throw new Error('Missing Firebase ID token.');
  }

  const apiKey = env.FIREBASE_WEB_API_KEY;
  if (!apiKey) {
    throw new Error('FIREBASE_WEB_API_KEY is not configured on the worker.');
  }

  const response = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=${encodeURIComponent(apiKey)}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ idToken: token }),
    },
  );

  const data = await response.json().catch(() => ({}));
  if (!response.ok || !data.users?.length) {
    throw new Error(data?.error?.message || 'Could not verify Firebase ID token.');
  }

  return {
    user_id: data.users[0].localId,
    email: data.users[0].email,
  };
}

function extractBearerToken(authHeader) {
  if (!authHeader || !authHeader.startsWith('Bearer ')) return '';
  return authHeader.slice('Bearer '.length).trim();
}

async function getFirestoreUserProfile(accessToken, uid) {
  try {
    const data = await authorizedFetch(`${FIRESTORE_BASE}/users/${encodeURIComponent(uid)}`, accessToken, {
      method: 'GET',
    });
    return decodeFirestoreFields(data.fields || {});
  } catch (error) {
    if (error.status === 404) return null;
    return null;
  }
}

function decodeFirestoreFields(fields) {
  const result = {};
  for (const [key, value] of Object.entries(fields)) {
    if ('stringValue' in value) result[key] = value.stringValue;
    else if ('booleanValue' in value) result[key] = value.booleanValue;
    else if ('integerValue' in value) result[key] = Number(value.integerValue);
    else if ('timestampValue' in value) result[key] = value.timestampValue;
  }
  return result;
}

async function getGoogleAccessToken(serviceAccountJson) {
  if (!serviceAccountJson) {
    throw new Error('GCP_SERVICE_ACCOUNT_JSON is not configured on the worker.');
  }

  const serviceAccount = typeof serviceAccountJson === 'string'
    ? JSON.parse(serviceAccountJson)
    : serviceAccountJson;

  const now = Math.floor(Date.now() / 1000);
  const jwtHeader = base64UrlEncode(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const jwtClaim = base64UrlEncode(JSON.stringify({
    iss: serviceAccount.client_email,
    scope: 'https://www.googleapis.com/auth/cloud-platform https://www.googleapis.com/auth/datastore https://www.googleapis.com/auth/identitytoolkit',
    aud: serviceAccount.token_uri,
    iat: now,
    exp: now + 3600,
  }));
  const unsignedJwt = `${jwtHeader}.${jwtClaim}`;
  const signature = await signJwt(unsignedJwt, serviceAccount.private_key);
  const jwt = `${unsignedJwt}.${signature}`;

  const response = await fetch(serviceAccount.token_uri, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  });

  const data = await response.json();
  if (!response.ok || !data.access_token) {
    throw new Error(data.error_description || data.error || 'Could not obtain Google access token.');
  }
  return data.access_token;
}

async function signJwt(input, privateKeyPem) {
  const keyData = pemToArrayBuffer(privateKeyPem);
  const key = await crypto.subtle.importKey(
    'pkcs8',
    keyData,
    {
      name: 'RSASSA-PKCS1-v1_5',
      hash: 'SHA-256',
    },
    false,
    ['sign'],
  );

  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(input),
  );
  return arrayBufferToBase64Url(signature);
}

function pemToArrayBuffer(pem) {
  const base64 = pem
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replace(/\s+/g, '');
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes.buffer;
}

function base64UrlEncode(value) {
  const encoded = btoa(unescape(encodeURIComponent(value)));
  return encoded.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}

function arrayBufferToBase64Url(buffer) {
  const bytes = new Uint8Array(buffer);
  let binary = '';
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}

async function authorizedFetch(url, accessToken, options = {}) {
  const response = await fetch(url, {
    ...options,
    headers: {
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
      ...(options.headers || {}),
    },
  });

  const text = await response.text();
  let data = {};
  if (text) {
    try {
      data = JSON.parse(text);
    } catch {
      data = { raw: text };
    }
  }

  if (!response.ok) {
    const message = data?.error?.message || data?.error || `Google API request failed (${response.status}).`;
    const error = new Error(message);
    error.status = response.status;
    error.data = data;
    throw error;
  }

  return data;
}

async function lookupUserByEmail(accessToken, email) {
  try {
    const data = await authorizedFetch(`${IDENTITY_BASE}/accounts:lookup`, accessToken, {
      method: 'POST',
      body: JSON.stringify({ email: [email] }),
    });
    return data.users?.[0] || null;
  } catch (error) {
    if (error.status === 404) return null;
    if (String(error.message || '').includes('USER_NOT_FOUND')) return null;
    return null;
  }
}

async function createAuthUser(accessToken, env, { email, password, displayName }) {
  const apiKey = env.FIREBASE_WEB_API_KEY;
  if (!apiKey) {
    throw new Error('FIREBASE_WEB_API_KEY is not configured on the worker.');
  }

  const signUpUrl = `https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${encodeURIComponent(apiKey)}`;
  const response = await fetch(signUpUrl, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      email,
      password,
      returnSecureToken: false,
    }),
  });

  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    const message = data?.error?.message || 'Failed to create Firebase Auth user.';
    throw new Error(message);
  }

  const localId = data.localId;
  if (!localId) {
    throw new Error('Firebase Auth did not return a local user ID.');
  }

  await updateAuthUser(accessToken, localId, {
    email,
    password,
    displayName,
  });

  const user = await lookupUserByEmail(accessToken, email);
  if (!user) {
    throw new Error('User was not created in Firebase Auth.');
  }
  return user;
}

async function updateAuthUser(accessToken, localId, { email, password, displayName }) {
  await authorizedFetch(`${IDENTITY_BASE}/accounts:update`, accessToken, {
    method: 'POST',
    body: JSON.stringify({
      localId,
      email,
      password,
      displayName,
      emailVerified: true,
    }),
  });
}

async function upsertFirestoreUser(accessToken, uid, profile) {
  const url = `${FIRESTORE_BASE}/users/${encodeURIComponent(uid)}?updateMask.fieldPaths=melcoId&updateMask.fieldPaths=role&updateMask.fieldPaths=displayName&updateMask.fieldPaths=requirePasswordChange&updateMask.fieldPaths=bootstrapAdmin&updateMask.fieldPaths=updatedAt&updateMask.fieldPaths=createdAt`;
  const now = new Date().toISOString();

  const fields = {
    melcoId: { stringValue: profile.melcoId },
    role: { stringValue: profile.role },
    displayName: { stringValue: profile.displayName },
    requirePasswordChange: { booleanValue: profile.requirePasswordChange !== false },
    updatedAt: { timestampValue: now },
    createdAt: { timestampValue: now },
  };

  if (profile.bootstrapAdmin === true) {
    fields.bootstrapAdmin = { booleanValue: true };
  }

  await authorizedFetch(url, accessToken, {
    method: 'PATCH',
    body: JSON.stringify({ fields }),
  });
}
