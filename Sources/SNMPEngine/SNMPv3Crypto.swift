import Foundation
import CryptoKit
import CommonCrypto

public enum SNMPv3AuthProtocol: String, Codable, Sendable, CaseIterable, Identifiable {
    case none = "None"
    case md5 = "HMAC-MD5"
    case sha1 = "HMAC-SHA1"
    case sha256 = "HMAC-SHA256"
    case sha384 = "HMAC-SHA384"
    case sha512 = "HMAC-SHA512"

    public var id: String { rawValue }

    public var digestLength: Int {
        switch self {
        case .none: return 0
        case .md5: return 16
        case .sha1: return 20
        case .sha256: return 32
        case .sha384: return 48
        case .sha512: return 64
        }
    }

    public var truncatedAuthLength: Int {
        switch self {
        case .none: return 0
        case .md5, .sha1: return 12
        case .sha256: return 16
        case .sha384: return 24
        case .sha512: return 32
        }
    }
}

public enum SNMPv3PrivProtocol: String, Codable, Sendable, CaseIterable, Identifiable {
    case none = "None"
    case aes128 = "AES-128 (CFB)"
    case aes256 = "AES-256 (CFB)"

    public var id: String { rawValue }
    public var keyLength: Int {
        switch self {
        case .none: return 0
        case .aes128: return 16
        case .aes256: return 32
        }
    }
}

public enum SNMPv3SecurityLevel: String, Codable, Sendable, CaseIterable, Identifiable {
    case noAuthNoPriv = "noAuthNoPriv"
    case authNoPriv = "authNoPriv"
    case authPriv = "authPriv"

    public var id: String { rawValue }

    public var flags: UInt8 {
        switch self {
        case .noAuthNoPriv: return 0x00
        case .authNoPriv: return 0x01
        case .authPriv: return 0x03
        }
    }
}

/// Cryptographic helper for SNMPv3 User-based Security Model (RFC 3414 & RFC 7860)
public enum SNMPv3Crypto {

    /// RFC 3414 & RFC 7860 Password-to-Key Localization Algorithm
    /// Converts a human passphrase into a localized key for a specific authoritative engineID.
    public static func passwordToKey(
        password: String,
        engineID: Data,
        protocol authProto: SNMPv3AuthProtocol
    ) -> Data {
        guard let passwordData = password.data(using: .utf8), !passwordData.isEmpty else {
            return Data()
        }

        let targetLength = 1048576
        var count = 0
        var passwordIndex = 0
        let pBytes = [UInt8](passwordData)
        let pLen = pBytes.count

        switch authProto {
        case .none:
            return Data()

        case .md5:
            var context = CC_MD5_CTX()
            CC_MD5_Init(&context)
            var buffer = [UInt8](repeating: 0, count: 64)

            while count < targetLength {
                for i in 0..<64 {
                    buffer[i] = pBytes[passwordIndex]
                    passwordIndex = (passwordIndex + 1) % pLen
                }
                CC_MD5_Update(&context, buffer, 64)
                count += 64
            }

            var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
            CC_MD5_Final(&digest, &context)

            var locContext = CC_MD5_CTX()
            CC_MD5_Init(&locContext)
            CC_MD5_Update(&locContext, digest, CC_LONG(digest.count))
            CC_MD5_Update(&locContext, [UInt8](engineID), CC_LONG(engineID.count))
            CC_MD5_Update(&locContext, digest, CC_LONG(digest.count))

            var localized = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
            CC_MD5_Final(&localized, &locContext)
            return Data(localized)

        case .sha1:
            var context = CC_SHA1_CTX()
            CC_SHA1_Init(&context)
            var buffer = [UInt8](repeating: 0, count: 64)

            while count < targetLength {
                for i in 0..<64 {
                    buffer[i] = pBytes[passwordIndex]
                    passwordIndex = (passwordIndex + 1) % pLen
                }
                CC_SHA1_Update(&context, buffer, 64)
                count += 64
            }

            var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
            CC_SHA1_Final(&digest, &context)

            var locContext = CC_SHA1_CTX()
            CC_SHA1_Init(&locContext)
            CC_SHA1_Update(&locContext, digest, CC_LONG(digest.count))
            CC_SHA1_Update(&locContext, [UInt8](engineID), CC_LONG(engineID.count))
            CC_SHA1_Update(&locContext, digest, CC_LONG(digest.count))

            var localized = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
            CC_SHA1_Final(&localized, &locContext)
            return Data(localized)

        case .sha256:
            var context = CC_SHA256_CTX()
            CC_SHA256_Init(&context)
            var buffer = [UInt8](repeating: 0, count: 64)

            while count < targetLength {
                for i in 0..<64 {
                    buffer[i] = pBytes[passwordIndex]
                    passwordIndex = (passwordIndex + 1) % pLen
                }
                CC_SHA256_Update(&context, buffer, 64)
                count += 64
            }

            var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
            CC_SHA256_Final(&digest, &context)

            var locContext = CC_SHA256_CTX()
            CC_SHA256_Init(&locContext)
            CC_SHA256_Update(&locContext, digest, CC_LONG(digest.count))
            CC_SHA256_Update(&locContext, [UInt8](engineID), CC_LONG(engineID.count))
            CC_SHA256_Update(&locContext, digest, CC_LONG(digest.count))

            var localized = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
            CC_SHA256_Final(&localized, &locContext)
            return Data(localized)

        case .sha384:
            // RFC 7860 Section 3: block size is 128 octets
            var context = CC_SHA512_CTX()
            CC_SHA384_Init(&context)
            var buffer = [UInt8](repeating: 0, count: 128)

            while count < targetLength {
                for i in 0..<128 {
                    buffer[i] = pBytes[passwordIndex]
                    passwordIndex = (passwordIndex + 1) % pLen
                }
                CC_SHA384_Update(&context, buffer, 128)
                count += 128
            }

            var digest = [UInt8](repeating: 0, count: Int(CC_SHA384_DIGEST_LENGTH))
            CC_SHA384_Final(&digest, &context)

            var locContext = CC_SHA512_CTX()
            CC_SHA384_Init(&locContext)
            CC_SHA384_Update(&locContext, digest, CC_LONG(digest.count))
            CC_SHA384_Update(&locContext, [UInt8](engineID), CC_LONG(engineID.count))
            CC_SHA384_Update(&locContext, digest, CC_LONG(digest.count))

            var localized = [UInt8](repeating: 0, count: Int(CC_SHA384_DIGEST_LENGTH))
            CC_SHA384_Final(&localized, &locContext)
            return Data(localized)

        case .sha512:
            // RFC 7860 Section 3: block size is 128 octets
            var context = CC_SHA512_CTX()
            CC_SHA512_Init(&context)
            var buffer = [UInt8](repeating: 0, count: 128)

            while count < targetLength {
                for i in 0..<128 {
                    buffer[i] = pBytes[passwordIndex]
                    passwordIndex = (passwordIndex + 1) % pLen
                }
                CC_SHA512_Update(&context, buffer, 128)
                count += 128
            }

            var digest = [UInt8](repeating: 0, count: Int(CC_SHA512_DIGEST_LENGTH))
            CC_SHA512_Final(&digest, &context)

            var locContext = CC_SHA512_CTX()
            CC_SHA512_Init(&locContext)
            CC_SHA512_Update(&locContext, digest, CC_LONG(digest.count))
            CC_SHA512_Update(&locContext, [UInt8](engineID), CC_LONG(engineID.count))
            CC_SHA512_Update(&locContext, digest, CC_LONG(digest.count))

            var localized = [UInt8](repeating: 0, count: Int(CC_SHA512_DIGEST_LENGTH))
            CC_SHA512_Final(&localized, &locContext)
            return Data(localized)
        }
    }

    /// Calculate HMAC authentication signature and truncate to required USM length
    public static func computeAuthHMAC(
        data: Data,
        authKey: Data,
        protocol authProto: SNMPv3AuthProtocol
    ) -> Data {
        guard !authKey.isEmpty else { return Data() }

        switch authProto {
        case .none:
            return Data()

        case .md5:
            var mac = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
            data.withUnsafeBytes { dataBuf in
                authKey.withUnsafeBytes { keyBuf in
                    CCHmac(
                        CCHmacAlgorithm(kCCHmacAlgMD5),
                        keyBuf.baseAddress,
                        keyBuf.count,
                        dataBuf.baseAddress,
                        dataBuf.count,
                        &mac
                    )
                }
            }
            return Data(mac.prefix(12))

        case .sha1:
            var mac = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
            data.withUnsafeBytes { dataBuf in
                authKey.withUnsafeBytes { keyBuf in
                    CCHmac(
                        CCHmacAlgorithm(kCCHmacAlgSHA1),
                        keyBuf.baseAddress,
                        keyBuf.count,
                        dataBuf.baseAddress,
                        dataBuf.count,
                        &mac
                    )
                }
            }
            return Data(mac.prefix(12))

        case .sha256:
            var mac = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
            data.withUnsafeBytes { dataBuf in
                authKey.withUnsafeBytes { keyBuf in
                    CCHmac(
                        CCHmacAlgorithm(kCCHmacAlgSHA256),
                        keyBuf.baseAddress,
                        keyBuf.count,
                        dataBuf.baseAddress,
                        dataBuf.count,
                        &mac
                    )
                }
            }
            return Data(mac.prefix(16))

        case .sha384:
            var mac = [UInt8](repeating: 0, count: Int(CC_SHA384_DIGEST_LENGTH))
            data.withUnsafeBytes { dataBuf in
                authKey.withUnsafeBytes { keyBuf in
                    CCHmac(
                        CCHmacAlgorithm(kCCHmacAlgSHA384),
                        keyBuf.baseAddress,
                        keyBuf.count,
                        dataBuf.baseAddress,
                        dataBuf.count,
                        &mac
                    )
                }
            }
            // RFC 7860 Section 4: truncate to 24 bytes
            return Data(mac.prefix(24))

        case .sha512:
            var mac = [UInt8](repeating: 0, count: Int(CC_SHA512_DIGEST_LENGTH))
            data.withUnsafeBytes { dataBuf in
                authKey.withUnsafeBytes { keyBuf in
                    CCHmac(
                        CCHmacAlgorithm(kCCHmacAlgSHA512),
                        keyBuf.baseAddress,
                        keyBuf.count,
                        dataBuf.baseAddress,
                        dataBuf.count,
                        &mac
                    )
                }
            }
            // RFC 7860 Section 4: truncate to 32 bytes
            return Data(mac.prefix(32))
        }
    }

    /// Encrypt ScopedPDU payload using AES-128 or AES-256 CFB mode (RFC 3826 & RFC 7860)
    public static func encryptAES(
        payload: Data,
        privKey: Data,
        privProtocol: SNMPv3PrivProtocol = .aes128,
        engineBoots: Int32,
        engineTime: Int32,
        salt: UInt64 = UInt64.random(in: 1...UInt64.max)
    ) throws -> (ciphertext: Data, privParams: Data) {
        let neededKeyLen = privProtocol == .aes256 ? 32 : 16
        guard privKey.count >= neededKeyLen else {
            throw NSError(domain: "SNMPv3Crypto", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid \(privProtocol.rawValue) key length (expected >= \(neededKeyLen) bytes, got \(privKey.count))"])
        }
        let key = [UInt8](privKey.prefix(neededKeyLen))

        // RFC 3826 Section 3.1.2.1: IV = engineBoots (4 bytes) || engineTime (4 bytes) || salt (8 bytes)
        var iv = Data()
        var bootsBE = engineBoots.bigEndian
        var timeBE = engineTime.bigEndian
        var saltBE = salt.bigEndian

        iv.append(Data(bytes: &bootsBE, count: 4))
        iv.append(Data(bytes: &timeBE, count: 4))
        iv.append(Data(bytes: &saltBE, count: 8))

        let privParams = Data(bytes: &saltBE, count: 8)
        let ciphertext = try cryptAESCFB(data: payload, key: Data(key), iv: iv, operation: CCOperation(kCCEncrypt))
        return (ciphertext, privParams)
    }

    /// Decrypt ScopedPDU payload using AES-128 or AES-256 CFB mode
    public static func decryptAES(
        ciphertext: Data,
        privKey: Data,
        privProtocol: SNMPv3PrivProtocol = .aes128,
        engineBoots: Int32,
        engineTime: Int32,
        privParams: Data
    ) throws -> Data {
        let neededKeyLen = privProtocol == .aes256 ? 32 : 16
        guard privKey.count >= neededKeyLen else {
            throw NSError(domain: "SNMPv3Crypto", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid \(privProtocol.rawValue) key length"])
        }
        guard privParams.count >= 8 else {
            throw NSError(domain: "SNMPv3Crypto", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid privParams length (expected >= 8 bytes)"])
        }
        let key = [UInt8](privKey.prefix(neededKeyLen))

        var iv = Data()
        var bootsBE = engineBoots.bigEndian
        var timeBE = engineTime.bigEndian
        iv.append(Data(bytes: &bootsBE, count: 4))
        iv.append(Data(bytes: &timeBE, count: 4))
        iv.append(privParams.prefix(8))

        return try cryptAESCFB(data: ciphertext, key: Data(key), iv: iv, operation: CCOperation(kCCDecrypt))
    }

    /// Backward compatibility wrapper for AES-128 CFB encryption
    public static func encryptAES128(
        payload: Data,
        privKey: Data,
        engineBoots: Int32,
        engineTime: Int32,
        salt: UInt64 = UInt64.random(in: 1...UInt64.max)
    ) throws -> (ciphertext: Data, privParams: Data) {
        try encryptAES(payload: payload, privKey: privKey, privProtocol: .aes128, engineBoots: engineBoots, engineTime: engineTime, salt: salt)
    }

    /// Backward compatibility wrapper for AES-128 CFB decryption
    public static func decryptAES128(
        ciphertext: Data,
        privKey: Data,
        engineBoots: Int32,
        engineTime: Int32,
        privParams: Data
    ) throws -> Data {
        try decryptAES(ciphertext: ciphertext, privKey: privKey, privProtocol: .aes128, engineBoots: engineBoots, engineTime: engineTime, privParams: privParams)
    }

    private static func cryptAESCFB(
        data: Data,
        key: Data,
        iv: Data,
        operation: CCOperation
    ) throws -> Data {
        var cryptor: CCCryptorRef?
        let mode = CCMode(kCCModeCFB)

        let status = key.withUnsafeBytes { keyBuf in
            iv.withUnsafeBytes { ivBuf in
                CCCryptorCreateWithMode(
                    operation,
                    mode,
                    CCAlgorithm(kCCAlgorithmAES),
                    CCPadding(ccNoPadding),
                    ivBuf.baseAddress,
                    keyBuf.baseAddress,
                    key.count,
                    nil,
                    0,
                    0,
                    0,
                    &cryptor
                )
            }
        }

        guard status == kCCSuccess, let cryptorRef = cryptor else {
            throw NSError(domain: "SNMPv3Crypto", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Failed to initialize AES-CFB cryptor (status: \(status))"])
        }

        defer { CCCryptorRelease(cryptorRef) }

        var output = Data(count: data.count + 16)
        var outLength = 0

        let updateStatus = data.withUnsafeBytes { dataBuf in
            output.withUnsafeMutableBytes { outBuf in
                CCCryptorUpdate(
                    cryptorRef,
                    dataBuf.baseAddress,
                    dataBuf.count,
                    outBuf.baseAddress,
                    outBuf.count,
                    &outLength
                )
            }
        }

        guard updateStatus == kCCSuccess else {
            throw NSError(domain: "SNMPv3Crypto", code: Int(updateStatus), userInfo: [NSLocalizedDescriptionKey: "AES-CFB update failed (status: \(updateStatus))"])
        }

        var finalLength = 0
        let finalStatus = output.withUnsafeMutableBytes { outBuf in
            CCCryptorFinal(
                cryptorRef,
                outBuf.baseAddress?.advanced(by: outLength),
                outBuf.count - outLength,
                &finalLength
            )
        }

        guard finalStatus == kCCSuccess else {
            throw NSError(domain: "SNMPv3Crypto", code: Int(finalStatus), userInfo: [NSLocalizedDescriptionKey: "AES-CFB final failed (status: \(finalStatus))"])
        }

        return output.prefix(outLength + finalLength)
    }
}
