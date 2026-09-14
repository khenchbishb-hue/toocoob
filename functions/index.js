const crypto = require('crypto');
const admin = require('firebase-admin');
const functions = require('firebase-functions');

admin.initializeApp();
const db = admin.firestore();
const maxRegistrars = 5;

// The e-mail is configured only in the Functions runtime, never in Flutter or
// Firestore.  This callable may be invoked by any signed-in account, but only
// the verified account matching that private value can receive the claim.
exports.bootstrapSystemAdmin = functions.https.onCall(async (_data, context) => {
  const uid = authUid(context);
  const configuredEmail = String(
    functions.config().system_admin?.email || process.env.SYSTEM_ADMIN_EMAIL || '',
  ).trim().toLowerCase();
  const callerEmail = String(context.auth.token.email || '').trim().toLowerCase();

  if (!configuredEmail) {
    throw new functions.https.HttpsError(
      'failed-precondition',
      'System Admin и-мэйл серверт тохируулагдаагүй байна.',
    );
  }
  if (callerEmail !== configuredEmail) {
    throw new functions.https.HttpsError('permission-denied', 'System Admin эрхгүй байна.');
  }

  // Trust the Auth record, rather than a token supplied by the web client.
  const account = await admin.auth().getUser(uid);
  if (!account.emailVerified) {
    throw new functions.https.HttpsError(
      'failed-precondition',
      'System Admin account и-мэйлээ баталгаажуулах ёстой.',
    );
  }

  const adminRef = db.collection('_system').doc('admin');
  await db.runTransaction(async transaction => {
    const existing = await transaction.get(adminRef);
    if (existing.exists && existing.data().uid !== uid) {
      throw new functions.https.HttpsError(
        'permission-denied',
        'System Admin аль хэдийн өөр account-д оноогдсон байна.',
      );
    }
    transaction.set(adminRef, {
      uid,
      email: configuredEmail,
      assignedAt: existing.data()?.assignedAt || admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
  });

  // Preserve any future custom claims while adding the single admin flag.
  await admin.auth().setCustomUserClaims(uid, {
    ...(account.customClaims || {}),
    systemAdmin: true,
  });
  return {systemAdmin: true};
});

const text = (value, label, max = 160) => {
  const result = String(value || '').trim();
  if (!result || result.length > max) throw new functions.https.HttpsError('invalid-argument', `${label} буруу байна.`);
  return result;
};
const phone = value => String(value || '').replace(/[^0-9+]/g, '');
const authUid = context => {
  if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Нэвтэрнэ үү.');
  return context.auth.uid;
};
async function owner(groupId, uid) {
  const group = await db.collection('groups').doc(groupId).get();
  if (!group.exists || group.data().ownerUid !== uid) throw new functions.https.HttpsError('permission-denied', 'Зөвхөн бүлэг үүсгэгч энэ үйлдлийг хийнэ.');
  return group;
}

exports.initializeAccount = functions.https.onCall(async (data, context) => {
  const uid = authUid(context);
  const fullName = text(data.fullName, 'Нэр');
  const normalizedPhone = phone(data.phone);
  if (normalizedPhone.length < 8 || normalizedPhone.length > 20) throw new functions.https.HttpsError('invalid-argument', 'Утасны дугаар буруу байна.');
  await db.collection('users').doc(uid).set({
    fullName, displayName: fullName, username: fullName, phone: normalizedPhone,
    email: text(context.auth.token.email, 'И-мэйл', 254).toLowerCase(), role: 'user',
    createdAt: admin.firestore.FieldValue.serverTimestamp(), updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});
  return {ok: true};
});

exports.createGroup = functions.https.onCall(async (data, context) => {
  const uid = authUid(context);
  const groupRef = db.collection('groups').doc();
  const batch = db.batch();
  batch.set(groupRef, {
    name: text(data.name, 'Бүлгийн нэр'), description: String(data.description || '').trim().slice(0, 300),
    ownerUid: uid, isDiscoverable: data.isDiscoverable !== false, memberUids: [uid], registrarLimit: maxRegistrars,
    createdAt: admin.firestore.FieldValue.serverTimestamp(), updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  batch.set(groupRef.collection('members').doc(uid), {uid, role: 'owner', canManageGames: true, joinedAt: admin.firestore.FieldValue.serverTimestamp()});
  await batch.commit();
  return {groupId: groupRef.id};
});

exports.requestJoinGroup = functions.https.onCall(async (data, context) => {
  const uid = authUid(context); const groupId = text(data.groupId, 'Бүлэг'); const groupRef = db.collection('groups').doc(groupId);
  const group = await groupRef.get();
  if (!group.exists || group.data().isDiscoverable !== true) throw new functions.https.HttpsError('not-found', 'Бүлэг олдсонгүй.');
  if ((group.data().memberUids || []).includes(uid)) return {status: 'member'};
  await groupRef.collection('joinRequests').doc(uid).set({uid, status: 'pending', requestedAt: admin.firestore.FieldValue.serverTimestamp()}, {merge: true});
  return {status: 'pending'};
});

exports.reviewJoinRequest = functions.https.onCall(async (data, context) => {
  const ownerUid = authUid(context); const groupId = text(data.groupId, 'Бүлэг'); const memberUid = text(data.memberUid, 'Хэрэглэгч'); const approved = data.approved === true;
  const groupRef = db.collection('groups').doc(groupId); await owner(groupId, ownerUid);
  const batch = db.batch();
  batch.set(groupRef.collection('joinRequests').doc(memberUid), {status: approved ? 'approved' : 'rejected', decidedAt: admin.firestore.FieldValue.serverTimestamp(), decidedBy: ownerUid}, {merge: true});
  if (approved) {
    batch.update(groupRef, {memberUids: admin.firestore.FieldValue.arrayUnion(memberUid), updatedAt: admin.firestore.FieldValue.serverTimestamp()});
    batch.set(groupRef.collection('members').doc(memberUid), {uid: memberUid, role: 'member', canManageGames: false, joinedAt: admin.firestore.FieldValue.serverTimestamp()});
  }
  await batch.commit(); return {ok: true};
});

exports.setRegistrarPermission = functions.https.onCall(async (data, context) => {
  const ownerUid = authUid(context); const groupId = text(data.groupId, 'Бүлэг'); const memberUid = text(data.memberUid, 'Хэрэглэгч'); const enabled = data.enabled === true;
  const groupRef = db.collection('groups').doc(groupId); await owner(groupId, ownerUid);
  const memberRef = groupRef.collection('members').doc(memberUid); const member = await memberRef.get();
  if (!member.exists) throw new functions.https.HttpsError('not-found', 'Гишүүн олдсонгүй.');
  if (enabled && member.data().canManageGames !== true) {
    const registrars = await groupRef.collection('members').where('canManageGames', '==', true).get();
    if (registrars.size >= maxRegistrars) throw new functions.https.HttpsError('failed-precondition', 'Бүртгэл хөтлөгчийн дээд тоо 5.');
  }
  await memberRef.update({canManageGames: enabled, updatedAt: admin.firestore.FieldValue.serverTimestamp()});
  return {ok: true};
});

exports.createPendingMember = functions.https.onCall(async (data, context) => {
  const ownerUid = authUid(context); const groupId = text(data.groupId, 'Бүлэг'); await owner(groupId, ownerUid);
  const normalizedPhone = phone(data.phone); if (normalizedPhone.length < 8 || normalizedPhone.length > 20) throw new functions.https.HttpsError('invalid-argument', 'Утасны дугаар буруу байна.');
  const code = crypto.randomBytes(9).toString('base64url').toUpperCase();
  const pending = db.collection('groups').doc(groupId).collection('pendingMembers').doc();
  await pending.set({fullName: text(data.fullName, 'Нэр'), nickname: text(data.nickname, 'Хоч'), phone: normalizedPhone, codeHash: crypto.createHash('sha256').update(code).digest('hex'), status: 'pending', createdBy: ownerUid, createdAt: admin.firestore.FieldValue.serverTimestamp()});
  return {pendingId: pending.id, activationCode: code};
});

exports.claimPendingMember = functions.https.onCall(async (data, context) => {
  const uid = authUid(context); const groupId = text(data.groupId, 'Бүлэг'); const code = text(data.activationCode, 'Идэвхжүүлэх код', 64).toUpperCase();
  const groupRef = db.collection('groups').doc(groupId); const hash = crypto.createHash('sha256').update(code).digest('hex');
  const found = await groupRef.collection('pendingMembers').where('codeHash', '==', hash).where('status', '==', 'pending').limit(1).get();
  if (found.empty) throw new functions.https.HttpsError('not-found', 'Код буруу эсвэл ашиглагдсан байна.');
  const pending = found.docs[0]; const pendingData = pending.data(); const batch = db.batch();
  batch.update(pending.ref, {status: 'claimed', claimedBy: uid, claimedAt: admin.firestore.FieldValue.serverTimestamp()});
  batch.update(groupRef, {memberUids: admin.firestore.FieldValue.arrayUnion(uid), updatedAt: admin.firestore.FieldValue.serverTimestamp()});
  batch.set(groupRef.collection('members').doc(uid), {uid, role: 'member', nickname: pendingData.nickname, canManageGames: false, joinedAt: admin.firestore.FieldValue.serverTimestamp()});
  batch.set(db.collection('users').doc(uid), {fullName: pendingData.fullName, displayName: pendingData.nickname, phone: pendingData.phone, updatedAt: admin.firestore.FieldValue.serverTimestamp()}, {merge: true});
  await batch.commit(); return {nickname: pendingData.nickname};
});

// Profile uploads stay server-side so the GitHub token is never shipped to Web clients.
exports.uploadProfileImage = functions.region('us-central1').https.onRequest(async (req, res) => {
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Headers', 'Content-Type');
  res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  if (req.method === 'OPTIONS') return res.status(204).send('');
  if (req.method !== 'POST') return res.status(405).json({error: 'Method not allowed'});
  try {
    const github = functions.config().github || {};
    if (!github.owner || !github.repo || !github.token) return res.status(500).json({error: 'GitHub config is missing on server'});
    const username = String(req.body?.username || 'player').trim().replace(/[^a-zA-Z0-9_-]/g, '_') || 'player';
    const content = String(req.body?.contentBase64 || '').trim();
    if (!content) return res.status(400).json({error: 'contentBase64 is required'});
    const branch = github.branch || 'main'; const folder = github.folder || 'player_profiles'; const path = `${folder}/${username}_${Date.now()}.jpg`;
    const result = await fetch(`https://api.github.com/repos/${github.owner}/${github.repo}/contents/${path}`, {method: 'PUT', headers: {'Authorization': `Bearer ${github.token}`, 'Accept': 'application/vnd.github+json', 'Content-Type': 'application/json', 'X-GitHub-Api-Version': '2022-11-28'}, body: JSON.stringify({message: `upload profile image for ${username}`, branch, content})});
    if (!result.ok) return res.status(result.status).json({error: 'GitHub upload failed'});
    return res.status(200).json({url: `https://raw.githubusercontent.com/${github.owner}/${github.repo}/${branch}/${path}`});
  } catch (error) { return res.status(500).json({error: 'Unexpected server error', detail: String(error)}); }
});
