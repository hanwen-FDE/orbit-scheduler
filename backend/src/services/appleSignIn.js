// Apple identityToken 使用 Apple 公钥验签；不能只在客户端“相信”一个 user id。
const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const config = require('../config');
const { ApiError } = require('../middleware/errorHandler');

let cachedKeys = [];
let cachedUntil = 0;

async function appleKeys() {
  if (cachedKeys.length && Date.now() < cachedUntil) return cachedKeys;
  let response;
  try {
    response = await fetch('https://appleid.apple.com/auth/keys');
  } catch {
    throw new ApiError('APPLE_AUTH_UNAVAILABLE', '暂时无法验证 Apple 登录，请稍后重试。', 503);
  }
  if (!response.ok) throw new ApiError('APPLE_AUTH_UNAVAILABLE', '暂时无法验证 Apple 登录，请稍后重试。', 503);
  const payload = await response.json();
  cachedKeys = Array.isArray(payload.keys) ? payload.keys : [];
  cachedUntil = Date.now() + 6 * 60 * 60 * 1000;
  return cachedKeys;
}

async function verifyIdentityToken(identityToken) {
  if (typeof identityToken !== 'string' || identityToken.length < 100) {
    throw new ApiError('APPLE_TOKEN_INVALID', 'Apple 登录凭证无效，请重试。', 401);
  }
  const decoded = jwt.decode(identityToken, { complete: true });
  if (!decoded || decoded.header?.alg !== 'RS256' || !decoded.header?.kid) {
    throw new ApiError('APPLE_TOKEN_INVALID', 'Apple 登录凭证格式无效，请重试。', 401);
  }
  const key = (await appleKeys()).find((item) => item.kid === decoded.header.kid && item.kty === 'RSA');
  if (!key) throw new ApiError('APPLE_TOKEN_INVALID', 'Apple 登录凭证已更新，请重试。', 401);
  try {
    const publicKey = crypto.createPublicKey({ key, format: 'jwk' });
    const claims = jwt.verify(identityToken, publicKey, {
      algorithms: ['RS256'],
      issuer: 'https://appleid.apple.com',
      audience: config.apple.bundleId,
    });
    if (!claims.sub) throw new Error('missing sub');
    return claims;
  } catch {
    throw new ApiError('APPLE_TOKEN_INVALID', 'Apple 登录验证失败，请重试。', 401);
  }
}

module.exports = { verifyIdentityToken };
