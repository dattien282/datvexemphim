const { firestore, auth } = require('../config/firebase');

async function requireStaffAuth(req, res, next) {
  if (!firestore || !auth) {
    return res.status(503).json({ success: false, message: 'Server chưa cấu hình Firebase Admin SDK' });
  }
  const authHeader = req.headers.authorization || '';
  const idToken = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : null;
  if (!idToken) {
    return res.status(401).json({ success: false, message: 'Thiếu token xác thực' });
  }
  try {
    const decoded = await auth.verifyIdToken(idToken);
    const userDoc = await firestore.collection('users').doc(decoded.uid).get();
    const userData = userDoc.data() || {};
    const role = userData.role;
    const hasStaffAccess = role === 'staff' || role === 'theater_manager' || role === 'admin' || userData.isAdmin === true;
    if (!hasStaffAccess) {
      return res.status(403).json({ success: false, message: 'Tài khoản không có quyền soát vé' });
    }
    req.staffUid = decoded.uid;
    req.staffEmail = decoded.email || null;
    req.staffTheater = userData.assignedTheater || null;
    req.staffIsAdmin = role === 'admin' || userData.isAdmin === true;
    next();
  } catch (e) {
    return res.status(401).json({ success: false, message: 'Token không hợp lệ' });
  }
}

async function requireAuth(req, res, next) {
  if (!firestore || !auth) {
    return res.status(503).json({ success: false, message: 'Server chưa cấu hình Firebase Admin SDK' });
  }
  const authHeader = req.headers.authorization || '';
  const idToken = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : null;
  if (!idToken) {
    return res.status(401).json({ success: false, message: 'Thiếu token xác thực' });
  }
  try {
    const decoded = await auth.verifyIdToken(idToken);
    req.userUid = decoded.uid;
    req.userEmail = decoded.email || null;
    next();
  } catch (e) {
    return res.status(401).json({ success: false, message: 'Token không hợp lệ' });
  }
}

async function requireManagerAuth(req, res, next) {
  if (!firestore || !auth) {
    return res.status(503).json({ success: false, message: 'Server chưa cấu hình Firebase Admin SDK' });
  }
  const authHeader = req.headers.authorization || '';
  const idToken = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : null;
  if (!idToken) {
    return res.status(401).json({ success: false, message: 'Thiếu token xác thực' });
  }
  try {
    const decoded = await auth.verifyIdToken(idToken);
    const userDoc = await firestore.collection('users').doc(decoded.uid).get();
    const userData = userDoc.data() || {};
    const isAdminUser = userData.role === 'admin' || userData.isAdmin === true;
    const isManager = userData.role === 'theater_manager';
    if (!isAdminUser && !isManager) {
      return res.status(403).json({ success: false, message: 'Chỉ quản lý rạp hoặc admin được thao tác suất chiếu' });
    }
    req.staffUid = decoded.uid;
    req.staffIsAdmin = isAdminUser;
    req.staffTheater = userData.assignedTheater || null;
    next();
  } catch (e) {
    return res.status(401).json({ success: false, message: 'Token không hợp lệ' });
  }
}

module.exports = {
  requireAuth,
  requireStaffAuth,
  requireManagerAuth
};
