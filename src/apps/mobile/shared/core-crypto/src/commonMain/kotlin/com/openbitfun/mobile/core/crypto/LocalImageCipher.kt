package com.openbitfun.mobile.core.crypto

import dev.whyoleg.cryptography.algorithms.SHA256

/** Independent, one-transfer key. Every authenticated record has a fresh IV. */
public object LocalImageCipher {
    public const val OVERHEAD: Int = GCM_NONCE_SIZE + GCM_TAG_SIZE

    public fun newKey(): ByteArray = DeviceIdentity.generateSecret()

    public suspend fun pairingDigest(bytes: ByteArray): ByteArray =
        relayCryptographyProvider.get(SHA256).hasher().hash(bytes)

    public suspend fun seal(key: ByteArray, value: ByteArray): ByteArray {
        val nonce = DeviceIdentity.randomBytes(GCM_NONCE_SIZE)
        return nonce + AesGcmCipher().encrypt(value, key, nonce)
    }

    public suspend fun open(key: ByteArray, record: ByteArray): ByteArray {
        require(record.size >= OVERHEAD)
        val nonce = record.copyOfRange(0, GCM_NONCE_SIZE)
        return AesGcmCipher().decrypt(record.copyOfRange(GCM_NONCE_SIZE, record.size), key, nonce)
    }
}
