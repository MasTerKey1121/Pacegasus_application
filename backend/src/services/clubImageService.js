const fs = require('node:fs/promises');
const path = require('node:path');
const { randomUUID } = require('node:crypto');
const ApiError = require('../utils/ApiError');

const MAX_IMAGE_BYTES = 2 * 1024 * 1024;
const imageDirectory = path.resolve(process.env.CLUB_IMAGE_DIR || path.join(__dirname, '../../uploads/club-images'));

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

async function saveImage(encoded, directory = imageDirectory) {
  const { bytes, extension } = decodeImage(encoded);
  const filename = `${randomUUID()}.${extension}`;
  await fs.mkdir(directory, { recursive: true });
  await fs.writeFile(path.join(directory, filename), bytes, { flag: 'wx' });
  return filename;
}

module.exports = { MAX_IMAGE_BYTES, imageDirectory, decodeImage, saveImage };
