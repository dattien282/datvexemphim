const express = require('express');
const cors = require('cors');
const { startCronJobs } = require('./jobs/cron');

const app = express();
app.use(cors());
app.use(express.json());

app.get('/', (req, res) => {
  res.send('✅ Stella Cinema PayOS Backend is running!');
});

app.use(require('./routes/auth.routes'));
app.use(require('./routes/payment.routes'));
app.use(require('./routes/seats.routes'));
app.use(require('./routes/showtime.routes'));
app.use(require('./routes/ticket.routes'));
app.use(require('./routes/cloudinary.routes'));
app.use(require('./routes/chat.routes'));
app.use(require('./routes/notification.routes'));
app.use(require('./routes/movies.routes'));

startCronJobs();

module.exports = app;
