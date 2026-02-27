const crypto = require('crypto')

function generateToken({ accessKey, productId }) {

  const version = '2018-10-31'
  const method = 'sha1'
  const res = `products/${productId}`
  const et = Math.floor(Date.now() / 1000) + 3600

  const stringForSign = `${et}\n${method}\n${res}\n${version}`

  const key = Buffer.from(accessKey, 'base64')

  const sign = crypto
    .createHmac('sha1', key)
    .update(stringForSign)
    .digest()

  const signB64 = Buffer.from(sign).toString('base64')
  const signEncoded = encodeURIComponent(signB64)

  return `version=${version}&res=${encodeURIComponent(res)}&et=${et}&method=${method}&sign=${signEncoded}`
}

module.exports = { generateToken }
