const { randomUUID } = require('node:crypto');
const ApiError = require('../utils/ApiError');
const db = require('../config/db');

const MAX_IMAGE_BYTES = 2 * 1024 * 1024;
const MIME_BY_EXTENSION = { png: 'image/png', jpg: 'image/jpeg', webp: 'image/webp' };

function decodeImage(encoded) {
  if (typeof encoded !== 'string' || encoded.length === 0 ||
      encoded.length > Math.ceil(MAX_IMAGE_BYTES / 3) * 4 ||
      !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(encoded)) {
    throw new ApiError(400, 'กรุณาเลือกรูป JPG, PNG หรือ WebP ขนาดไม่เกิน 2 MB');
  }
  const bytes = Buffer.from(encoded, 'base64');
  if (bytes.length > MAX_IMAGE_BYTES || bytes.toString('base64') !== encoded) {
    throw new ApiError(400, 'รูปภาพไม่ถูกต้องหรือมีขนาดเกิน 2 MB');
  }
  let extension;
  if (bytes.length >= 24 && bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])) && bytes.toString('ascii', 12, 16) === 'IHDR') extension = 'png';
  else if (bytes.length >= 4 && bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255) extension = 'jpg';
  else if (bytes.length >= 20 && bytes.toString('ascii', 0, 4) === 'RIFF' && bytes.toString('ascii', 8, 12) === 'WEBP') extension = 'webp';
  else throw new ApiError(400, 'รองรับรูป JPG, PNG หรือ WebP เท่านั้น');
  return { bytes, extension };
}

async function saveImage(encoded) {
  const { bytes, extension } = decodeImage(encoded);
  const id = randomUUID();
  await db.query(
    'INSERT INTO club_images (id, content_type, image_data) VALUES ($1, $2, $3)',
    [id, MIME_BY_EXTENSION[extension], bytes]
  );
  return id;
}

async function getImage(id) {
  const { rows } = await db.query(
    'SELECT content_type, image_data FROM club_images WHERE id = $1', [id]
  );
  if (!rows[0]) throw new ApiError(404, 'ไม่พบรูปคลับ');
  return rows[0];
}

module.exports = { MAX_IMAGE_BYTES, decodeImage, saveImage, getImage };
