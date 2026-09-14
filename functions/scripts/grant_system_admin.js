/*
 * One-time, local System Admin assignment.
 *
 * Run this only from a trusted computer after setting
 * GOOGLE_APPLICATION_CREDENTIALS to a Firebase service-account key kept
 * outside this repository. The key is never read by Flutter or deployed.
 *
 * Usage (from functions/):
 *   node scripts/grant_system_admin.js "verified-account@example.com"
 */
const admin = require('firebase-admin');

const email = String(process.argv[2] || '').trim().toLowerCase();
if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
  console.error('Usage: node scripts/grant_system_admin.js "verified-account@example.com"');
  process.exit(1);
}

if (!process.env.GOOGLE_APPLICATION_CREDENTIALS) {
  console.error('GOOGLE_APPLICATION_CREDENTIALS тохируулаагүй байна.');
  process.exit(1);
}

admin.initializeApp({credential: admin.credential.applicationDefault()});
const db = admin.firestore();

async function grantSystemAdmin() {
  const account = await admin.auth().getUserByEmail(email);
  if (!account.emailVerified) {
    throw new Error('Энэ account и-мэйлээ хараахан баталгаажуулаагүй байна.');
  }

  const adminRef = db.collection('_system').doc('admin');
  await db.runTransaction(async transaction => {
    const existing = await transaction.get(adminRef);
    if (existing.exists && existing.data().uid !== account.uid) {
      throw new Error('System Admin аль хэдийн өөр account-д оноогдсон байна.');
    }
    transaction.set(adminRef, {
      uid: account.uid,
      email,
      assignedAt: existing.data()?.assignedAt || admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
  });

  await admin.auth().setCustomUserClaims(account.uid, {
    ...(account.customClaims || {}),
    systemAdmin: true,
  });
  console.log(`System Admin эрх ${email} account-д амжилттай оноогдлоо.`);
}

grantSystemAdmin().catch(error => {
  console.error(`System Admin эрх оноож чадсангүй: ${error.message}`);
  process.exitCode = 1;
});
