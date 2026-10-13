const fs = require('fs');
const path = require('path');
const multer = require('multer');
const ApiError = require('../utils/ApiError');

const AVATAR_DIR = path.join(__dirname, '..', '..', 'uploads', 'avatars');
const MAX_SIZE_BYTES = 5 * 1024 * 1024;
const EXT_BY_MIME = { 'image/jpeg': '.jpg', 'image/png': '.png', 'image/webp': '.webp' };

fs.mkdirSync(AVATAR_DIR, { recursive: true });

const upload = multer({
  storage: multer.diskStorage({
    destination: (req, file, cb) => cb(null, AVATAR_DIR),
    filename: (req, file, cb) => cb(null, `${req.user.id}-${Date.now()}${EXT_BY_MIME[file.mimetype]}`),
  }),
  limits: { fileSize: MAX_SIZE_BYTES, files: 1 },
  fileFilter: (req, file, cb) => {
    if (!EXT_BY_MIME[file.mimetype]) {
      return cb(new ApiError(400, 'รองรับเฉพาะไฟล์รูป JPEG, PNG หรือ WebP'));
    }
    return cb(null, true);
  },
}).single('avatar');

// Wraps multer so its errors (size limit, unexpected field) use the standard ApiError shape
function uploadAvatar(req, res, next) {
  upload(req, res, (err) => {
    if (!err) return next();
    if (err instanceof multer.MulterError) {
      const message =
        err.code === 'LIMIT_FILE_SIZE'
          ? `ไฟล์รูปต้องมีขนาดไม่เกิน ${MAX_SIZE_BYTES / 1024 / 1024} MB`
          : 'ส่งไฟล์รูปผ่าน field ชื่อ "avatar" เพียง 1 ไฟล์';
      return next(new ApiError(400, message));
    }
    return next(err);
  });
}

module.exports = { uploadAvatar, AVATAR_DIR };
