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

    const url = new URL(request.url);

    try {
      if (request.method === 'GET') {
        if (url.pathname === '/' || url.pathname === '') {
          return json({
            ok: true,
            service: 'thodw-auth-provisioner',
            status: 'ready',
            endpoints: [
              'GET /users',
              'POST /bootstrap-admin',
              'POST /users',
              'POST /users/reset-password',
              'POST /users/set-disabled',
            ],
            note:
              'Open in browser = health check only. Real provisioning/admin calls use authenticated requests.',
          });
        }

        if (url.pathname === '/users') {
          return await handleListUsers(request, env);
        }

        return json({ error: 'Not found.' }, 404);
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
      if (url.pathname === '/users/reset-password') {
        return await handleResetPassword(body, env, request);
      }
      if (url.pathname === '/users/set-disabled') {
        return await handleSetDisabled(body, env, request);
      }

      return json({ error: 'Not found.' }, 404);
    } catch (error) {
      return json(
        { error: error.message || 'Unexpected server error.' },
        error.status || 500,
      );
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
    throw new Error(
      'Bootstrap is only allowed for the configured first admin Melco ID.',
    );
  }
  if (role !== 'admin') {
    throw new Error('Bootstrap admin must use admin role.');
  }

  const accessToken = await getGoogleAccessToken(env.GCP_SERVICE_ACCOUNT_JSON);
  const email = melcoToEmail(melcoId);
  let authUser = await lookupUserByEmail(accessToken, email);
  let created = false;

  if (!authUser) {
    authUser = await createAuthUser(accessToken, env, {
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
      disableUser: false,
    });
  }

  const existingProfile = await getFirestoreUserProfile(accessToken, authUser.localId);
  await upsertFirestoreUser(accessToken, authUser.localId, {
    melcoId,
    role,
    displayName,
    email,
    requirePasswordChange: true,
    disabled: false,
    bootstrapAdmin: true,
    createdAt: existingProfile?.createdAt,
  });

  await writeAuditLog(accessToken, {
    action: created ? 'bootstrap_admin_created' : 'bootstrap_admin_refreshed',
    actorUid: authUser.localId,
    actorEmail: email,
    targetUid: authUser.localId,
    targetMelcoId: melcoId,
    details: `Bootstrap admin ${created ? 'created' : 'refreshed'} via worker.`,
  });

  return json({
    email,
    password: DEFAULT_PASSWORD,
    role,
    displayName,
    created,
    updated: true,
  });
}

async function handleListUsers(request, env) {
  const { accessToken } = await requireAdminAccess(request, env);
  const users = await listFirestoreUsers(accessToken);
  return json({ users });
}

async function handleCreateUser(body, env, request) {
  const { accessToken, firebaseUser, callerProfile } = await requireAdminAccess(
    request,
    env,
  );

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

  if (!authUser) {
    authUser = await createAuthUser(accessToken, env, {
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
    });
  }

  const existingProfile = await getFirestoreUserProfile(accessToken, authUser.localId);
  await upsertFirestoreUser(accessToken, authUser.localId, {
    melcoId,
    role,
    displayName,
    email,
    requirePasswordChange: true,
    disabled: existingProfile?.disabled === true ? true : false,
    bootstrapAdmin: existingProfile?.bootstrapAdmin === true,
    createdAt: existingProfile?.createdAt,
  });

  await writeAuditLog(accessToken, {
    action: created ? 'login_user_created' : 'login_user_updated',
    actorUid: firebaseUser.user_id,
    actorEmail: firebaseUser.email,
    actorMelcoId: callerProfile.melcoId,
    targetUid: authUser.localId,
    targetMelcoId: melcoId,
    details: `${displayName} (${role}) ${created ? 'created' : 'updated'} by admin.`,
  });

  return json({
    email,
    password: DEFAULT_PASSWORD,
    role,
    displayName,
    created,
    updated: true,
  });
}

async function handleResetPassword(body, env, request) {
  const { accessToken, firebaseUser, callerProfile } = await requireAdminAccess(
    request,
    env,
  );

  const uid = String(body?.uid || '').trim();
  if (!uid) {
    throw new Error('User ID is required.');
  }

  const targetProfile = await getFirestoreUserProfile(accessToken, uid);
  if (!targetProfile) {
    throw new Error('User profile not found.');
  }

  const email = targetProfile.email || melcoToEmail(targetProfile.melcoId);
  try {
    await updateAuthUser(accessToken, uid, {
      email,
      displayName: targetProfile.displayName,
      password: DEFAULT_PASSWORD,
    });
  } catch (error) {
    const message = String(error?.message || '');
    if (message.includes('QUOTA_EXCEEDED')) {
      throw new Error(
        'Firebase Auth temporarily refused the password reset because of a rate/quota limit. Wait a moment and try again.',
      );
    }
    throw error;
  }

  await upsertFirestoreUser(accessToken, uid, {
    melcoId: targetProfile.melcoId,
    role: targetProfile.role,
    displayName: targetProfile.displayName,
    email,
    requirePasswordChange: true,
    disabled: targetProfile.disabled === true,
    bootstrapAdmin: targetProfile.bootstrapAdmin === true,
    createdAt: targetProfile.createdAt,
  });

  await writeAuditLog(accessToken, {
    action: 'login_user_password_reset',
    actorUid: firebaseUser.user_id,
    actorEmail: firebaseUser.email,
    actorMelcoId: callerProfile.melcoId,
    targetUid: uid,
    targetMelcoId: targetProfile.melcoId,
    details: `Password reset to default for ${targetProfile.displayName}.`,
  });

  return json({
    uid,
    melcoId: targetProfile.melcoId,
    displayName: targetProfile.displayName,
    email,
    password: DEFAULT_PASSWORD,
  });
}

async function handleSetDisabled(body, env, request) {
  const { accessToken, firebaseUser, callerProfile } = await requireAdminAccess(
    request,
    env,
  );

  const uid = String(body?.uid || '').trim();
  const disabled = body?.disabled === true;
  if (!uid) {
    throw new Error('User ID is required.');
  }

  const targetProfile = await getFirestoreUserProfile(accessToken, uid);
  if (!targetProfile) {
    throw new Error('User profile not found.');
  }
  if (targetProfile.bootstrapAdmin === true && disabled) {
    throw new Error('Cannot disable the bootstrap admin account.');
  }

  const email = targetProfile.email || melcoToEmail(targetProfile.melcoId);
  await updateAuthUser(accessToken, uid, {
    email,
    displayName: targetProfile.displayName,
    disableUser: disabled,
  });

  await upsertFirestoreUser(accessToken, uid, {
    melcoId: targetProfile.melcoId,
    role: targetProfile.role,
    displayName: targetProfile.displayName,
    email,
    requirePasswordChange: targetProfile.requirePasswordChange === true,
    disabled,
    bootstrapAdmin: targetProfile.bootstrapAdmin === true,
    createdAt: targetProfile.createdAt,
  });

  await writeAuditLog(accessToken, {
    action: disabled ? 'login_user_disabled' : 'login_user_enabled',
    actorUid: firebaseUser.user_id,
    actorEmail: firebaseUser.email,
    actorMelcoId: callerProfile.melcoId,
    targetUid: uid,
    targetMelcoId: targetProfile.melcoId,
    details: `${targetProfile.displayName} was ${disabled ? 'disabled' : 'enabled'} by admin.`,
  });

  return json({
    uid,
    melcoId: targetProfile.melcoId,
    displayName: targetProfile.displayName,
    disabled,
  });
}

async function requireAdminAccess(request, env) {
  const authHeader = request.headers.get('Authorization') || '';
  const accessToken = await getGoogleAccessToken(env.GCP_SERVICE_ACCOUNT_JSON);
  const firebaseUser = await verifyFirebaseIdToken(authHeader, env);
  const callerProfile = await getFirestoreUserProfile(accessToken, firebaseUser.user_id);

  if (!callerProfile || callerProfile.role !== 'admin' || callerProfile.disabled === true) {
    throw new Error('Only active admins can use this endpoint.');
  }

  return { accessToken, firebaseUser, callerProfile };
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
    'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
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

async function verifyFirebaseIdToken(authHeader, env) {
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
    const data = await authorizedFetch(
      `${FIRESTORE_BASE}/users/${encodeURIComponent(uid)}`,
      accessToken,
      { method: 'GET' },
    );
    return {
      uid,
      ...decodeFirestoreFields(data.fields || {}),
    };
  } catch (error) {
    if (error.status === 404) return null;
    throw error;
  }
}

async function listFirestoreUsers(accessToken) {
  const data = await authorizedFetch(`${FIRESTORE_BASE}/users?pageSize=200`, accessToken, {
    method: 'GET',
  });
  const docs = data.documents || [];
  const users = docs.map((doc) => {
    const uid = doc.name.split('/').pop();
    return {
      uid,
      ...decodeFirestoreFields(doc.fields || {}),
    };
  });

  users.sort((a, b) => {
    const aName = (a.displayName || a.melcoId || '').toString().toLowerCase();
    const bName = (b.displayName || b.melcoId || '').toString().toLowerCase();
    return aName.localeCompare(bName);
  });

  return users;
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

  const serviceAccount =
    typeof serviceAccountJson === 'string'
      ? JSON.parse(serviceAccountJson)
      : serviceAccountJson;

  const now = Math.floor(Date.now() / 1000);
  const jwtHeader = base64UrlEncode(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const jwtClaim = base64UrlEncode(
    JSON.stringify({
      iss: serviceAccount.client_email,
      scope:
        'https://www.googleapis.com/auth/cloud-platform https://www.googleapis.com/auth/datastore https://www.googleapis.com/auth/identitytoolkit',
      aud: serviceAccount.token_uri,
      iat: now,
      exp: now + 3600,
    }),
  );
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
    throw new Error(
      data.error_description || data.error || 'Could not obtain Google access token.',
    );
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
  const localId = crypto.randomUUID();

  await authorizedFetch(
    `https://identitytoolkit.googleapis.com/v1/projects/${PROJECT_ID}/accounts:batchCreate`,
    accessToken,
    {
      method: 'POST',
      body: JSON.stringify({
        hashAlgorithm: 'BCRYPT',
        allowOverwrite: false,
        users: [
          {
            localId,
            email,
            passwordHash: btoa(password),
            displayName,
            emailVerified: true,
          },
        ],
      }),
    },
  );

  await updateAuthUser(accessToken, localId, {
    email,
    password,
    displayName,
    disableUser: false,
  });

  const user = await lookupUserByEmail(accessToken, email);
  if (!user) {
    throw new Error('User was not created in Firebase Auth.');
  }
  return user;
}

async function updateAuthUser(
  accessToken,
  localId,
  { email, password, displayName, disableUser },
) {
  const payload = { localId };
  if (email !== undefined) payload.email = email;
  if (password !== undefined) payload.password = password;
  if (displayName !== undefined) payload.displayName = displayName;
  if (typeof disableUser === 'boolean') payload.disableUser = disableUser;
  if (email !== undefined) payload.emailVerified = true;

  await authorizedFetch(`${IDENTITY_BASE}/accounts:update`, accessToken, {
    method: 'POST',
    body: JSON.stringify(payload),
  });
}

async function upsertFirestoreUser(accessToken, uid, profile) {
  const now = new Date().toISOString();
  const createdAt = profile.createdAt || now;
  const fields = {
    melcoId: { stringValue: profile.melcoId },
    role: { stringValue: profile.role },
    displayName: { stringValue: profile.displayName || '' },
    email: { stringValue: profile.email || melcoToEmail(profile.melcoId) },
    requirePasswordChange: {
      booleanValue: profile.requirePasswordChange !== false,
    },
    disabled: { booleanValue: profile.disabled === true },
    updatedAt: { timestampValue: now },
    createdAt: { timestampValue: createdAt },
  };

  if (profile.bootstrapAdmin === true) {
    fields.bootstrapAdmin = { booleanValue: true };
  }

  const updateMask = Object.keys(fields)
    .map((key) => `updateMask.fieldPaths=${encodeURIComponent(key)}`)
    .join('&');
  const url = `${FIRESTORE_BASE}/users/${encodeURIComponent(uid)}?${updateMask}`;

  await authorizedFetch(url, accessToken, {
    method: 'PATCH',
    body: JSON.stringify({ fields }),
  });
}

async function writeAuditLog(accessToken, entry) {
  const now = new Date().toISOString();
  const fields = {
    action: { stringValue: String(entry.action || '') },
    actorUid: { stringValue: String(entry.actorUid || '') },
    actorEmail: { stringValue: String(entry.actorEmail || '') },
    actorMelcoId: { stringValue: String(entry.actorMelcoId || '') },
    targetUid: { stringValue: String(entry.targetUid || '') },
    targetMelcoId: { stringValue: String(entry.targetMelcoId || '') },
    details: { stringValue: String(entry.details || '') },
    timestamp: { timestampValue: now },
  };

  await authorizedFetch(`${FIRESTORE_BASE}/audit_logs`, accessToken, {
    method: 'POST',
    body: JSON.stringify({ fields }),
  });
}
