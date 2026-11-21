package com.focusdns.engine.crypto

import android.content.Context
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.Signature
import java.security.interfaces.ECPublicKey
import java.security.spec.ECGenParameterSpec

/**
 * AndroidKeyStoreManager provides hardware-backed NIST P-256 (secp256r1) keypair generation and signing.
 * Utilizes StrongBox Keymaster when available, otherwise standard hardware-backed TEE.
 */
class AndroidKeyStoreManager(private val context: Context? = null) {

    companion object {
        const val ANDROID_KEYSTORE = "AndroidKeyStore"
        const val DEFAULT_ALIAS = "focusdns_device_key_p256"

        @Volatile
        private var instance: AndroidKeyStoreManager? = null

        fun getInstance(context: Context? = null): AndroidKeyStoreManager {
            return instance ?: synchronized(this) {
                instance ?: AndroidKeyStoreManager(context?.applicationContext).also { instance = it }
            }
        }
    }

    private val keyStore: KeyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }

    /**
     * Retrieves or generates a hardware-backed NIST P-256 keypair.
     */
    @Synchronized
    fun getOrCreateDeviceKeyPair(alias: String = DEFAULT_ALIAS): KeyPair {
        if (keyStore.containsAlias(alias)) {
            val entry = keyStore.getEntry(alias, null) as? KeyStore.PrivateKeyEntry
            if (entry != null) {
                return KeyPair(entry.certificate.publicKey, entry.privateKey)
            }
        }
        return generateP256KeyPair(alias)
    }

    /**
     * Returns the 65-byte uncompressed EC public key (0x04 || X || Y) in hex.
     */
    @Synchronized
    fun getDevicePublicKeyHex(alias: String = DEFAULT_ALIAS): String {
        val keyPair = getOrCreateDeviceKeyPair(alias)
        val ecPubKey = keyPair.public as? ECPublicKey
            ?: throw IllegalStateException("Key is not an ECPublicKey")

        val x = ecPubKey.w.affineX.toByteArray().stripLeadingZero()
        val y = ecPubKey.w.affineY.toByteArray().stripLeadingZero()

        val raw = ByteArray(65)
        raw[0] = 0x04
        System.arraycopy(x, 0, raw, 1 + (32 - x.size), x.size)
        System.arraycopy(y, 0, raw, 33 + (32 - y.size), y.size)

        return raw.joinToString("") { "%02x".format(it) }
    }

    /**
     * Signs a challenge nonce using SHA256withECDSA.
     * Returns DER-encoded signature in hex.
     */
    @Synchronized
    fun signChallengeNonceHex(nonceHex: String, alias: String = DEFAULT_ALIAS): String {
        val nonceBytes = hexToBytes(nonceHex)
        val keyPair = getOrCreateDeviceKeyPair(alias)

        val signer = Signature.getInstance("SHA256withECDSA")
        signer.initSign(keyPair.private)
        signer.update(nonceBytes)
        val signatureBytes = signer.sign()

        return signatureBytes.joinToString("") { "%02x".format(it) }
    }

    private fun generateP256KeyPair(alias: String): KeyPair {
        val kpg = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, ANDROID_KEYSTORE)

        val builder = KeyGenParameterSpec.Builder(
            alias,
            KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY
        )
            .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
            .setDigests(KeyProperties.DIGEST_SHA256, KeyProperties.DIGEST_SHA512)

        // Attempt StrongBox if supported on Android 9.0+
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            try {
                builder.setIsStrongBoxBacked(true)
                kpg.initialize(builder.build())
                return kpg.generateKeyPair()
            } catch (e: Exception) {
                // StrongBox unavailable on this SoC; fall back to TEE Keymaster
                builder.setIsStrongBoxBacked(false)
            }
        }

        kpg.initialize(builder.build())
        return kpg.generateKeyPair()
    }

    private fun ByteArray.stripLeadingZero(): ByteArray {
        return if (this.size == 33 && this[0] == 0.toByte()) {
            this.copyOfRange(1, 33)
        } else {
            this
        }
    }

    private fun hexToBytes(hex: String): ByteArray {
        val len = hex.length
        val data = ByteArray(len / 2)
        var i = 0
        while (i < len) {
            data[i / 2] = ((Character.digit(hex[i], 16) shl 4) + Character.digit(hex[i + 1], 16)).toByte()
            i += 2
        }
        return data
    }
}
