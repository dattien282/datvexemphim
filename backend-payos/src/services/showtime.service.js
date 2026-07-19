// Port của models/session_type.dart detectSessionType/parseReleaseDate -
// PHẢI khớp tuyệt đối logic Dart vì đây chính là bản xác thực authoritative
// thay cho suy luận phía client.
function parseReleaseDateJs(releaseDate) {
  if (!releaseDate) return null;
  const m = /^(\d{1,2})\/(\d{1,2})\/(\d{4})$/.exec(String(releaseDate).trim());
  if (!m) return null;
  return new Date(parseInt(m[3], 10), parseInt(m[2], 10) - 1, parseInt(m[1], 10));
}
function detectSessionTypeJs(showAt, movieReleaseDate) {
  if (movieReleaseDate) {
    const showDate = new Date(showAt.getFullYear(), showAt.getMonth(), showAt.getDate());
    const releaseDate = new Date(movieReleaseDate.getFullYear(), movieReleaseDate.getMonth(), movieReleaseDate.getDate());
    if (showDate.getTime() < releaseDate.getTime()) return 'Sneak Show';
    if (showDate.getTime() === releaseDate.getTime()) return 'First Day';
  }
  const hour = showAt.getHours();
  if (hour < 7) return 'Midnight';
  if (hour < 10) return 'Morning';
  if (hour < 12) return 'Late Morning';
  if (hour < 17) return 'Afternoon';
  if (hour < 21) return 'Prime Time';
  return 'Evening';
}

// Port của models/showtime.dart contentStartAt/contentEndAt/roomReleaseAt
// (Giai đoạn G) - khoảng phòng bị chiếm = showAt + advertisingMinutes (chưa
// vào phim, đang chiếu trailer/quảng cáo) -> + thời lượng phim -> +
// exitBufferMinutes/cleaningMinutes (khách ra về + dọn phòng). Mặc định
// (0, 10, 0) khớp CHÍNH XÁC công thức cứng cũ "+10 phút" để không đổi kết quả
// của suất chiếu đã tồn tại chưa có 3 field này.
const FALLBACK_SHOWTIME_DURATION_MS = 150 * 60 * 1000;
function roomReleaseAtJs(showAt, movieDurationMs, advertisingMin, exitBufferMin, cleaningMin) {
  return new Date(showAt.getTime() + (advertisingMin || 0) * 60000 + movieDurationMs + ((exitBufferMin ?? 10) + (cleaningMin || 0)) * 60000);
}
// [a]/[b] là { showAt, advertisingMinutes, exitBufferMinutes, cleaningMinutes }
// - mỗi suất chiếu dùng ĐÚNG buffer của chính nó, không dùng chung 1 buffer
// cho tất cả (khớp tinh thần "Default operational durations... may be
// overridden by a specific Showtime").
function overlapsWindowJs(a, b, movieDurationMs) {
  const aEnd = roomReleaseAtJs(a.showAt, movieDurationMs, a.advertisingMinutes, a.exitBufferMinutes, a.cleaningMinutes);
  const bEnd = roomReleaseAtJs(b.showAt, movieDurationMs, b.advertisingMinutes, b.exitBufferMinutes, b.cleaningMinutes);
  return a.showAt.getTime() < bEnd.getTime() && b.showAt.getTime() < aEnd.getTime();
}

// Port tối giản của Showtime.isoDate/Showtime.hhmm (models/showtime.dart) -
// chỉ dùng để ghi lại 2 field hiển thị 'date'/'time' cho tương thích ngược
// với các màn hình cũ còn đọc trực tiếp 2 field string này thay vì 'showAt'.
function Showtime_isoDate(d) {
  const pad = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}
function Showtime_hhmm(d) {
  const pad = (n) => String(n).padStart(2, '0');
  return `${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

// Parse các định dạng ngày đang tồn tại trong app: "yyyy-MM-dd" (từ showtimes
// do theater_manager tạo) hoặc "Hôm nay (dd/MM)" / "Thứ Hai (dd/MM)" (từ
// showtime_selection_screen.dart). Trả về null nếu không parse được -
// verify-checkin sẽ bỏ qua kiểm tra khung giờ trong trường hợp đó.
function parseShowDateTime(showDate, showTime) {
  try {
    const [hh, mm] = showTime.split(':').map((s) => parseInt(s, 10));
    const isoMatch = showDate.match(/^(\d{4})-(\d{2})-(\d{2})$/);
    if (isoMatch) {
      return new Date(Number(isoMatch[1]), Number(isoMatch[2]) - 1, Number(isoMatch[3]), hh, mm);
    }
    const ddmmMatch = showDate.match(/\((\d{2})\/(\d{2})\)/);
    if (ddmmMatch) {
      const now = new Date();
      return new Date(now.getFullYear(), Number(ddmmMatch[2]) - 1, Number(ddmmMatch[1]), hh, mm);
    }
    return null;
  } catch (e) {
    return null;
  }
}

// Layout phòng mặc định - phải khớp với seat_booking_screen.dart khi chưa
// tìm thấy room doc thật (showtime cũ/dự phòng chưa gắn phòng cụ thể).
const DEFAULT_ROOM = { standardRows: 3, vipRows: 5, sweetboxRows: 2, seatsPerRow: 10 };

module.exports = {
  FALLBACK_SHOWTIME_DURATION_MS,
  DEFAULT_ROOM,
  parseReleaseDateJs,
  detectSessionTypeJs,
  roomReleaseAtJs,
  overlapsWindowJs,
  Showtime_isoDate,
  Showtime_hhmm,
  parseShowDateTime,
};
