import Toybox.Lang;
import Toybox.StringUtil;
import Toybox.Cryptography;

//! Privacy transport primitives used by the background fetch path.
//! Implements HKDF-style key derivation from APP_AUTH_SECRET, AES-256-CBC
//! encryption with PKCS#7 padding, HMAC-SHA256, length-prefixed canonical
//! byte assembly, and Base64URL (padding-free) encoding.
//! See the privacy transport design document for the wire format.
(:background)
module WindForceCrypto {

    const ENC_LABEL = "wf-enc-v1";
    const MAC_LABEL = "wf-mac-v1";
    const AUTH_LABEL = "wf-auth-v1";

    //! HMAC-SHA256. Returns a 32-byte ByteArray.
    function hmacSha256(key as ByteArray, data as ByteArray) as ByteArray {
        var h = new Cryptography.HashBasedMessageAuthenticationCode({
            :algorithm => Cryptography.HASH_SHA256,
            :key => key
        });
        h.update(data);
        return h.digest();
    }

    //! UTF-8 byte representation of a String.
    function utf8(s as String) as ByteArray {
        return StringUtil.convertEncodedString(s, {
            :fromRepresentation => StringUtil.REPRESENTATION_STRING_PLAIN_TEXT,
            :toRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY
        }) as ByteArray;
    }

    //! Decode standard Base64 text to raw bytes.
    function base64Decode(s as String) as ByteArray {
        return StringUtil.convertEncodedString(s, {
            :fromRepresentation => StringUtil.REPRESENTATION_STRING_BASE64,
            :toRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY
        }) as ByteArray;
    }

    //! Encode raw bytes as standard Base64 text.
    function base64Encode(b as ByteArray) as String {
        return StringUtil.convertEncodedString(b, {
            :fromRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY,
            :toRepresentation => StringUtil.REPRESENTATION_STRING_BASE64
        }) as String;
    }

    //! Encode as Base64URL without padding (RFC 4648 §5).
    //! Mutates the ASCII byte representation of the standard-Base64 form in
    //! place so the URL-safe string is materialized with O(1) String
    //! allocations rather than one per character.
    function base64urlEncode(b as ByteArray) as String {
        var ascii = StringUtil.convertEncodedString(base64Encode(b), {
            :fromRepresentation => StringUtil.REPRESENTATION_STRING_PLAIN_TEXT,
            :toRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY
        }) as ByteArray;
        var n = ascii.size();
        // Drop trailing '=' padding (0x3d). Standard Base64 has at most two.
        while (n > 0 && ascii[n - 1] == 0x3d) {
            n -= 1;
        }
        // Replace '+' (0x2b) → '-' (0x2d) and '/' (0x2f) → '_' (0x5f).
        for (var i = 0; i < n; i++) {
            var c = ascii[i];
            if (c == 0x2b) {
                ascii[i] = 0x2d;
            } else if (c == 0x2f) {
                ascii[i] = 0x5f;
            }
        }
        return StringUtil.convertEncodedString(ascii.slice(0, n), {
            :fromRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY,
            :toRepresentation => StringUtil.REPRESENTATION_STRING_PLAIN_TEXT
        }) as String;
    }

    //! Derive enc/mac/auth keys from the standard-Base64 APP_AUTH_SECRET text.
    //! Returns a Dictionary with keys :encKey, :macKey, :authKey, each a
    //! 32-byte ByteArray.
    function deriveKeys(appAuthSecret as String) as Dictionary {
        var ikm = base64Decode(appAuthSecret);
        var zero32 = new [32]b;
        // initialize to zero
        for (var i = 0; i < 32; i++) {
            zero32[i] = 0;
        }
        var prk = hmacSha256(zero32, ikm);

        var encInfo = utf8(ENC_LABEL);
        encInfo.add(0x01);
        var macInfo = utf8(MAC_LABEL);
        macInfo.add(0x01);
        var authInfo = utf8(AUTH_LABEL);
        authInfo.add(0x01);

        return {
            :encKey => hmacSha256(prk, encInfo),
            :macKey => hmacSha256(prk, macInfo),
            :authKey => hmacSha256(prk, authInfo)
        };
    }

    //! Append PKCS#7 padding to a 16-byte block size. Always adds 1-16 bytes.
    function pkcs7Pad(bytes as ByteArray) as ByteArray {
        var padLen = 16 - (bytes.size() % 16);
        var padded = new [bytes.size() + padLen]b;
        for (var i = 0; i < bytes.size(); i++) {
            padded[i] = bytes[i];
        }
        for (var i = bytes.size(); i < padded.size(); i++) {
            padded[i] = padLen;
        }
        return padded;
    }

    //! Encrypt plaintext under enc_key with AES-256-CBC + PKCS#7.
    //! Returns Base64URL-encoded `iv || ciphertext || mac` ready to be sent
    //! as the `q` query parameter.
    function encryptPayload(plaintext as String, encKey as ByteArray, macKey as ByteArray) as String {
        var iv = Cryptography.randomBytes(16);
        var padded = pkcs7Pad(utf8(plaintext));
        var cipher = new Cryptography.Cipher({
            :algorithm => Cryptography.CIPHER_AES256,
            :mode => Cryptography.MODE_CBC,
            :key => encKey,
            :iv => iv
        });
        var ct = cipher.encrypt(padded);

        var ivCt = new [iv.size() + ct.size()]b;
        for (var i = 0; i < iv.size(); i++) { ivCt[i] = iv[i]; }
        for (var i = 0; i < ct.size(); i++) { ivCt[iv.size() + i] = ct[i]; }

        var mac = hmacSha256(macKey, ivCt);

        var envelope = new [ivCt.size() + mac.size()]b;
        for (var i = 0; i < ivCt.size(); i++) { envelope[i] = ivCt[i]; }
        for (var i = 0; i < mac.size(); i++) { envelope[ivCt.size() + i] = mac[i]; }

        return base64urlEncode(envelope);
    }

    //! Append `u16be(len(s_utf8)) || s_utf8` to `out`.
    function appendLp(out as ByteArray, s as String) as Void {
        var b = utf8(s);
        var n = b.size();
        out.add((n >> 8) & 0xff);
        out.add(n & 0xff);
        out.addAll(b);
    }

    //! Build the canonical X-WF-App-Mac input bytes in the fixed order:
    //!   method || path || q || ts || app || app_id || app_ver
    //! Each field is length-prefixed with a u16be of its UTF-8 byte length.
    function canonicalizeMacInput(
        method as String, path as String, q as String,
        ts as String, app as String, appId as String, appVer as String
    ) as ByteArray {
        var out = []b;
        appendLp(out, method);
        appendLp(out, path);
        appendLp(out, q);
        appendLp(out, ts);
        appendLp(out, app);
        appendLp(out, appId);
        appendLp(out, appVer);
        return out;
    }

    //! Build the small fixed-schema plaintext JSON string.
    //! The schema is intentionally tiny; no JSON library is needed.
    function buildPlaintextJson(
        lat as String, lon as String,
        units as String, slots as String, ts as Number
    ) as String {
        return "{\"lat\":\"" + lat + "\",\"lon\":\"" + lon
            + "\",\"units\":\"" + units + "\",\"slots\":\""
            + slots + "\",\"ts\":" + ts.toString() + "}";
    }

}
