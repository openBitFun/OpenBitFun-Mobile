package com.openbitfun.mobile.core.crypto

import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertFails
import kotlin.test.assertFalse

class LocalImageCipherTest {
    @Test
    fun authenticatedRecordRejectsOtherKeysAndTampering() = runTest {
        val secret = LocalImageCipher.newKey()
        val image = byteArrayOf(12, 0, -1, 34)
        val encrypted = LocalImageCipher.seal(secret, image)
        assertContentEquals(image, LocalImageCipher.open(secret, encrypted))
        assertFalse(encrypted.contentEquals(LocalImageCipher.seal(secret, image)))
        assertFails { LocalImageCipher.open(LocalImageCipher.newKey(), encrypted) }
        encrypted[encrypted.lastIndex] = (encrypted.last().toInt() xor 1).toByte()
        assertFails { LocalImageCipher.open(secret, encrypted) }
    }
}
