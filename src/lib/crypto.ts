// Web Crypto API E2EE cryptographic utilities.
// Supporting symmetric key generation, PBKDF2 password derivation, AES-GCM encryption/decryption, and base64 conversions.

export async function generateGroupKey(): Promise<CryptoKey> {
  return window.crypto.subtle.generateKey(
    {
      name: 'AES-GCM',
      length: 256,
    },
    true,
    ['encrypt', 'decrypt']
  );
}

export async function exportKey(key: CryptoKey): Promise<string> {
  const exported = await window.crypto.subtle.exportKey('raw', key);
  const bytes = new Uint8Array(exported);
  let binary = '';
  for (let i = 0; i < bytes.byteLength; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return window.btoa(binary);
}

export async function importKey(base64Key: string): Promise<CryptoKey> {
  const binary = window.atob(base64Key);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return window.crypto.subtle.importKey(
    'raw',
    bytes.buffer,
    'AES-GCM',
    true,
    ['encrypt', 'decrypt']
  );
}

export async function deriveKeyFromPassword(
  password: string,
  saltBytes: Uint8Array
): Promise<CryptoKey> {
  const enc = new TextEncoder();
  const keyMaterial = await window.crypto.subtle.importKey(
    'raw',
    enc.encode(password),
    'PBKDF2',
    false,
    ['deriveBits', 'deriveKey']
  );
  return window.crypto.subtle.deriveKey(
    {
      name: 'PBKDF2',
      salt: saltBytes as BufferSource,
      iterations: 100000,
      hash: 'SHA-256',
    },
    keyMaterial,
    { name: 'AES-GCM', length: 256 },
    true,
    ['encrypt', 'decrypt']
  );
}

export async function encryptText(
  text: string,
  key: CryptoKey
): Promise<{ ciphertext: string; iv: string }> {
  const enc = new TextEncoder();
  const iv = window.crypto.getRandomValues(new Uint8Array(12));
  const ciphertextBuffer = await window.crypto.subtle.encrypt(
    {
      name: 'AES-GCM',
      iv: iv,
    },
    key,
    enc.encode(text)
  );

  const cipherBytes = new Uint8Array(ciphertextBuffer);
  let cipherBinary = '';
  for (let i = 0; i < cipherBytes.byteLength; i++) {
    cipherBinary += String.fromCharCode(cipherBytes[i]);
  }

  let ivBinary = '';
  for (let i = 0; i < iv.byteLength; i++) {
    ivBinary += String.fromCharCode(iv[i]);
  }

  return {
    ciphertext: window.btoa(cipherBinary),
    iv: window.btoa(ivBinary),
  };
}

export async function decryptText(
  ciphertextBase64: string,
  ivBase64: string,
  key: CryptoKey
): Promise<string> {
  const cipherBinary = window.atob(ciphertextBase64);
  const cipherBytes = new Uint8Array(cipherBinary.length);
  for (let i = 0; i < cipherBinary.length; i++) {
    cipherBytes[i] = cipherBinary.charCodeAt(i);
  }

  const ivBinary = window.atob(ivBase64);
  const ivBytes = new Uint8Array(ivBinary.length);
  for (let i = 0; i < ivBinary.length; i++) {
    ivBytes[i] = ivBinary.charCodeAt(i);
  }

  const decryptedBuffer = await window.crypto.subtle.decrypt(
    {
      name: 'AES-GCM',
      iv: ivBytes,
    },
    key,
    cipherBytes.buffer
  );

  const dec = new TextDecoder();
  return dec.decode(decryptedBuffer);
}
