const crypto = require('crypto');
const { TICKET_SIGNING_SECRET } = require('../config/firebase');

function signTicket(ticketId, orderCode, paymentStatus) {
  const payload = `${ticketId}:${orderCode || ''}:${paymentStatus}`;
  return crypto.createHmac('sha256', TICKET_SIGNING_SECRET).update(payload).digest('hex');
}

module.exports = { signTicket };
