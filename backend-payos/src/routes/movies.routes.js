const express = require('express');
const { requireAuth } = require('../middleware/auth.middleware');

const router = express.Router();

// API: Tra cứu thông tin phim từ TMDB theo id để admin điền nhanh form thêm
// phim (admin_movies_screen.dart) - không có TMDB_API_KEY thì trả về dữ liệu
// mẫu (mock) để vẫn kiểm thử được luồng nhập liệu.
router.post('/api/movies/import-tmdb', requireAuth, async (req, res) => {
  try {
    const { tmdbId } = req.body;
    if (!tmdbId) {
      return res.status(400).json({ success: false, message: 'Thiếu tmdbId' });
    }

    const tmdbApiKey = process.env.TMDB_API_KEY;

    // Nếu không có API Key, sử dụng mock data để dễ kiểm thử
    if (!tmdbApiKey) {
      console.log('[TMDB] Không tìm thấy TMDB_API_KEY trong .env, sử dụng Mock Fallback.');

      const mocks = {
        '533535': {
          title: 'Deadpool & Wolverine',
          genre: 'Hành Động, Hài Hước, Khoa Học Viễn Tưởng',
          rating: '9.0',
          posterUrl: 'https://upload.wikimedia.org/wikipedia/en/4/4c/Deadpool_%26_Wolverine_poster.jpg',
          trailerUrl: 'https://www.youtube.com/watch?v=73_1biulkYw',
          director: 'Shawn Levy',
          cast: 'Ryan Reynolds, Hugh Jackman, Emma Corrin',
          duration: '127 phút',
          releaseDate: '26/07/2024',
          description: 'Deadpool bị lôi kéo vào hàng ngũ TVA và buộc phải hợp tác với một Wolverine bất đắc dĩ từ vũ trụ khác để cứu lấy dòng thời gian của mình.',
          country: 'Mỹ',
          ageRating: 'T18'
        },
        '950396': {
          title: 'Avatar: Fire and Ash',
          genre: 'Khoa Học Viễn Tưởng, Hành Động, Phiêu Lưu',
          rating: '9.5',
          posterUrl: 'https://upload.wikimedia.org/wikipedia/vi/3/37/Avatar_Fire_and_Ash_logo.jpg',
          trailerUrl: 'https://www.youtube.com/watch?v=Way9Dexny3w',
          director: 'James Cameron',
          cast: 'Sam Worthington, Zoe Saldana, Sigourney Weaver',
          duration: '180 phút',
          releaseDate: '19/12/2025',
          description: 'Jake Sully và Neytiri đối đầu với một tộc Na\'vi hung bạo sống ở vùng núi lửa (Người Tro), khám phá những góc tối nguy hiểm chưa từng có của Pandora.',
          country: 'Mỹ',
          ageRating: 'T13'
        },
        '1022789': {
          title: 'Inside Out 2: Những Mảnh Ghép Cảm Xúc 2',
          genre: 'Hoạt Hình, Hài Hước, Gia Đình',
          rating: '8.8',
          posterUrl: 'https://upload.wikimedia.org/wikipedia/en/f/f7/Inside_Out_2_poster.jpg',
          trailerUrl: 'https://www.youtube.com/watch?v=LEjhY15eCx0',
          director: 'Kelsey Mann',
          cast: 'Amy Poehler, Maya Hawke, Kensington Tallman',
          duration: '96 phút',
          releaseDate: '14/06/2024',
          description: 'Riley bước vào tuổi dậy thì và tâm trí cô đón nhận những cảm xúc mới tinh tinh bao gồm Lo Âu, Ghen Tị, Xấu Hổ và Chán Nản.',
          country: 'Mỹ',
          ageRating: 'P'
        }
      };

      const mock = mocks[String(tmdbId)];
      if (mock) {
        return res.json({ success: true, isMock: true, data: mock });
      }

      // Trả về mock mặc định nếu không khớp ID cụ thể để test bất kỳ ID nào
      return res.json({
        success: true,
        isMock: true,
        data: {
          title: `Phim Mẫu TMDB #${tmdbId}`,
          genre: 'Hành Động, Phiêu Lưu',
          rating: '8.5',
          posterUrl: 'https://upload.wikimedia.org/wikipedia/en/3/36/Mai_2024_poster.jpg',
          trailerUrl: 'https://www.youtube.com/watch?v=HKm5rF2L31Y',
          director: 'Đạo diễn Mẫu',
          cast: 'Diễn viên A, Diễn viên B, Diễn viên C',
          duration: '120 phút',
          releaseDate: '20/07/2026',
          description: 'Mô tả tóm tắt nội dung của phim mẫu được tải từ hệ thống fallback của CinemaHub.',
          country: 'Mỹ',
          ageRating: 'T16'
        }
      });
    }

    // Nếu có API Key, tiến hành call API của TMDB
    const url = `https://api.themoviedb.org/3/movie/${tmdbId}?api_key=${tmdbApiKey}&language=vi-VN&append_to_response=videos,credits`;
    const response = await fetch(url);
    if (!response.ok) {
      return res.status(response.status).json({ success: false, message: `Lỗi kết nối TMDB: Status ${response.status}` });
    }
    const movie = await response.json();

    let director = '';
    if (movie.credits && movie.credits.crew) {
      const dirObj = movie.credits.crew.find(c => c.job === 'Director');
      if (dirObj) director = dirObj.name;
    }

    let cast = '';
    if (movie.credits && movie.credits.cast) {
      cast = movie.credits.cast.slice(0, 4).map(c => c.name).join(', ');
    }

    let trailerUrl = '';
    if (movie.videos && movie.videos.results) {
      const trailerObj = movie.videos.results.find(v => v.type === 'Trailer' && v.site === 'YouTube');
      if (trailerObj) {
        trailerUrl = `https://www.youtube.com/watch?v=${trailerObj.key}`;
      }
    }

    let country = '';
    if (movie.production_countries && movie.production_countries.length > 0) {
      country = movie.production_countries[0].name;
    }

    let genre = '';
    if (movie.genres && movie.genres.length > 0) {
      genre = movie.genres.map(g => g.name).join(', ');
    }

    // Định dạng releaseDate (yyyy-MM-dd -> dd/MM/yyyy)
    let releaseDate = movie.release_date || '';
    if (releaseDate.includes('-')) {
      const parts = releaseDate.split('-');
      if (parts.length === 3) {
        releaseDate = `${parts[2]}/${parts[1]}/${parts[0]}`;
      }
    }

    const formattedData = {
      title: movie.title || movie.original_title || '',
      genre: genre,
      rating: movie.vote_average ? movie.vote_average.toFixed(1) : '0.0',
      posterUrl: movie.poster_path ? `https://image.tmdb.org/t/p/w500${movie.poster_path}` : '',
      trailerUrl: trailerUrl,
      director: director,
      cast: cast,
      duration: movie.runtime ? `${movie.runtime} phút` : '',
      releaseDate: releaseDate,
      description: movie.overview || '',
      country: country,
      ageRating: movie.adult ? 'T18' : 'P'
    };

    return res.json({ success: true, isMock: false, data: formattedData });
  } catch (error) {
    console.error('Lỗi import-tmdb:', error.message);
    return res.status(500).json({ success: false, message: 'Lỗi máy chủ khi kết nối TMDB' });
  }
});

module.exports = router;
