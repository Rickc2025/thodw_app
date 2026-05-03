const admin = require('firebase-admin');
const { onCall, HttpsError } = require('firebase-functions/v2/https');

admin.initializeApp();

function assertAdmin(auth) {
  if (!auth) throw new HttpsError('unauthenticated', 'Authentication required.');
  return admin.firestore().collection('users').doc(auth.uid).get().then((doc) => {
    if (!doc.exists || doc.data().active !== true || doc.data().role !== 'admin') {
      throw new HttpsError('permission-denied', 'Admin access required.');
    }
    return doc.data();
  });
}

const DEFAULT_TEMP_PASSWORD = 'Welcome2026';

function melcoIdToEmail(melcoId) {
  return `${String(melcoId).trim()}@thodw.local`;
}

function isStrongPassword(password) {
  const value = String(password || '');
  return value.length >= 8 && /[A-Za-z]/.test(value) && /\d/.test(value);
}

exports.createUserByAdmin = onCall(async (request) => {
  await assertAdmin(request.auth);
  const { melcoId, displayName, role, tempPassword } = request.data || {};
  if (!melcoId || !/^\d+$/.test(String(melcoId))) {
    throw new HttpsError('invalid-argument', 'Valid numeric Melco ID required.');
  }
  const passwordToSet = tempPassword == null || String(tempPassword).trim() === ''
    ? DEFAULT_TEMP_PASSWORD
    : String(tempPassword);
  if (!isStrongPassword(passwordToSet)) {
    throw new HttpsError('invalid-argument', 'Temporary password must be at least 8 characters and contain at least one letter and one number.');
  }
  const normalizedRole = role === 'admin' ? 'admin' : 'operator';
  const email = melcoIdToEmail(melcoId);

  let userRecord;
  try {
    userRecord = await admin.auth().createUser({
      email,
      password: passwordToSet,
      displayName: displayName || String(melcoId),
    });
  } catch (e) {
    if (e.code === 'auth/email-already-exists') {
      throw new HttpsError('already-exists', 'User already exists.');
    }
    throw new HttpsError('internal', e.message || 'Failed to create user.');
  }

  await admin.firestore().collection('users').doc(userRecord.uid).set({
    melcoId: String(melcoId),
    displayName: displayName || String(melcoId),
    role: normalizedRole,
    active: true,
    mustChangePassword: true,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    createdBy: request.auth.uid,
  }, { merge: true });

  await admin.firestore().collection('audit_logs').add({
    action: 'create_user',
    byUid: request.auth.uid,
    targetUid: userRecord.uid,
    melcoId: String(melcoId),
    role: normalizedRole,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return { ok: true, uid: userRecord.uid };
});

exports.resetUserPasswordByAdmin = onCall(async (request) => {
  await assertAdmin(request.auth);
  const { uid, tempPassword } = request.data || {};
  if (!uid) throw new HttpsError('invalid-argument', 'uid is required.');
  const passwordToSet = tempPassword == null || String(tempPassword).trim() === ''
    ? DEFAULT_TEMP_PASSWORD
    : String(tempPassword);
  if (!isStrongPassword(passwordToSet)) {
    throw new HttpsError('invalid-argument', 'Temporary password must be at least 8 characters and contain at least one letter and one number.');
  }

  await admin.auth().updateUser(String(uid), {
    password: passwordToSet,
  });

  await admin.firestore().collection('users').doc(String(uid)).set({
    mustChangePassword: true,
    lastPasswordResetAt: admin.firestore.FieldValue.serverTimestamp(),
    lastPasswordResetBy: request.auth.uid,
  }, { merge: true });

  await admin.firestore().collection('audit_logs').add({
    action: 'reset_password',
    byUid: request.auth.uid,
    targetUid: String(uid),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return { ok: true };
});

exports.forcePasswordChangeForAllUsers = onCall(async (request) => {
  await assertAdmin(request.auth);

  const usersSnap = await admin.firestore().collection('users').where('active', '==', true).get();
  const batch = admin.firestore().batch();
  let count = 0;

  usersSnap.forEach((doc) => {
    batch.set(doc.ref, {
      mustChangePassword: true,
      lastPasswordResetAt: admin.firestore.FieldValue.serverTimestamp(),
      lastPasswordResetBy: request.auth.uid,
    }, { merge: true });
    count += 1;
  });

  if (count > 0) {
    await batch.commit();
  }

  await admin.firestore().collection('audit_logs').add({
    action: 'force_password_change_all',
    byUid: request.auth.uid,
    affectedUsers: count,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return { ok: true, affectedUsers: count };
});

exports.setUserActiveStateByAdmin = onCall(async (request) => {
  await assertAdmin(request.auth);
  const { uid, active } = request.data || {};
  if (!uid || typeof active !== 'boolean') {
    throw new HttpsError('invalid-argument', 'uid and boolean active are required.');
  }

  await admin.firestore().collection('users').doc(String(uid)).set({ active }, { merge: true });

  await admin.firestore().collection('audit_logs').add({
    action: active ? 'activate_user' : 'deactivate_user',
    byUid: request.auth.uid,
    targetUid: String(uid),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return { ok: true };
});
