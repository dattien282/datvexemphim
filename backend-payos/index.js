require('dotenv').config({ quiet: true });

const app = require('./src/app');

const port = process.env.PORT || 3000;

app.listen(port, () => {
  console.log(`Server đang chạy tại http://localhost:${port}`);
  console.log('Hãy sử dụng ngrok để expose port này ra public và cấu hình Webhook trên trang PayOS nhé!');
});
