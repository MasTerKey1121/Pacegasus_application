const { OAuth2Client } = require('google-auth-library');
const env = require('../config/env');
const ApiError = require('../utils/ApiError');

const client = new OAuth2Client(env.google.clientId);

/**
 * Verifies a Google ID token sent from the frontend (Google Sign-In)
 * and returns the relevant profile fields.
 */
async function verifyGoogleIdToken(idToken) {
  try {
    const ticket = await client.verifyIdToken({
      idToken,
      audience: env.google.clientId,
    });
    const payload = ticket.getPayload();

    if (!payload || !payload.email) {
      throw new Error('Google token payload missing email');
    }

    return {
      googleId: payload.sub,
      email: payload.email.toLowerCase(),
      emailVerified: !!payload.email_verified,
      displayName: payload.name,
      avatarUrl: payload.picture,
    };
  } catch (err) {
    throw new ApiError(401, 'Google idToken ไม่ถูกต้องหรือหมดอายุ');
  }
}

module.exports = { verifyGoogleIdToken };
