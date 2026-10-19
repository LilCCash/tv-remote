import Foundation
import Security

/// Modulo ed esponente di una chiave pubblica RSA (big-endian, senza zeri iniziali).
struct RSAKeyParams: Equatable {
    let modulus: [UInt8]
    let exponent: [UInt8]
}

/// Minimo indispensabile di DER: costruzione del certificato self-signed del client
/// e lettura di una chiave pubblica RSA PKCS#1.
enum DER {
    static let null: [UInt8] = [0x05, 0x00]
    static let sha256WithRSA: [UInt8] = [0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x0B]
    static let rsaEncryption: [UInt8] = [0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01]
    static let commonName: [UInt8] = [0x06, 0x03, 0x55, 0x04, 0x03]

    static func length(_ n: Int) -> [UInt8] {
        if n < 0x80 { return [UInt8(n)] }
        var bytes: [UInt8] = []
        var v = n
        while v > 0 {
            bytes.insert(UInt8(v & 0xFF), at: 0)
            v >>= 8
        }
        return [0x80 | UInt8(bytes.count)] + bytes
    }

    static func tlv(_ tag: UInt8, _ content: [UInt8]) -> [UInt8] {
        [tag] + length(content.count) + content
    }

    static func sequence(_ parts: [UInt8]...) -> [UInt8] { tlv(0x30, parts.flatMap { $0 }) }
    static func set(_ content: [UInt8]) -> [UInt8] { tlv(0x31, content) }
    static func bitString(_ bytes: [UInt8]) -> [UInt8] { tlv(0x03, [0x00] + bytes) }
    static func utf8(_ text: String) -> [UInt8] { tlv(0x0C, Array(text.utf8)) }

    /// INTEGER positivo da byte big-endian.
    static func integer(_ bytes: [UInt8]) -> [UInt8] {
        var v = Array(bytes.drop(while: { $0 == 0 }))
        if v.isEmpty { v = [0] }
        if v[0] & 0x80 != 0 { v.insert(0, at: 0) }
        return tlv(0x02, v)
    }

    static func utcTime(_ date: Date) -> [UInt8] {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyMMddHHmmss'Z'"
        return tlv(0x17, Array(f.string(from: date).utf8))
    }

    // MARK: Lettura

    static func readTLV(_ b: [UInt8], at i: Int) -> (tag: UInt8, content: [UInt8], next: Int)? {
        guard i + 2 <= b.count else { return nil }
        let tag = b[i]
        var j = i + 1
        var len = Int(b[j])
        j += 1
        if len & 0x80 != 0 {
            let n = len & 0x7F
            guard n > 0, n <= 4, j + n <= b.count else { return nil }
            len = 0
            for k in 0..<n { len = (len << 8) | Int(b[j + k]) }
            j += n
        }
        guard j + len <= b.count else { return nil }
        return (tag, Array(b[j..<j + len]), j + len)
    }

    /// RSAPublicKey ::= SEQUENCE { modulus INTEGER, publicExponent INTEGER }
    static func parseRSAPublicKey(_ pkcs1: [UInt8]) -> RSAKeyParams? {
        guard let outer = readTLV(pkcs1, at: 0), outer.tag == 0x30,
              let n = readTLV(outer.content, at: 0), n.tag == 0x02,
              let e = readTLV(outer.content, at: n.next), e.tag == 0x02 else { return nil }
        return RSAKeyParams(modulus: Array(n.content.drop(while: { $0 == 0 })),
                            exponent: Array(e.content.drop(while: { $0 == 0 })))
    }
}

/// Genera (una sola volta) e conserva nel Keychain l'identità TLS del client.
/// La TV riconosce l'iPhone proprio da questo certificato dopo il pairing.
enum CertificateManager {
    private static let label = "it.example.xiaomiremote.client-identity"

    static func loadOrCreateIdentity() throws -> SecIdentity {
        if let id = findIdentity() { return id }
        try createIdentity()
        guard let id = findIdentity() else {
            throw TVError.identity("identità non trovata dopo la creazione")
        }
        return id
    }

    /// Cancella l'identità (utile se si vuole ripartire da zero).
    static func resetIdentity() {
        for cls in [kSecClassIdentity, kSecClassCertificate, kSecClassKey] {
            SecItemDelete([kSecClass as String: cls, kSecAttrLabel as String: label] as CFDictionary)
        }
    }

    static func publicKeyParams(of identity: SecIdentity) throws -> RSAKeyParams {
        var cert: SecCertificate?
        guard SecIdentityCopyCertificate(identity, &cert) == errSecSuccess, let c = cert else {
            throw TVError.identity("certificato non leggibile")
        }
        return try publicKeyParams(ofCertificate: c)
    }

    static func publicKeyParams(ofCertificate cert: SecCertificate) throws -> RSAKeyParams {
        guard let key = SecCertificateCopyKey(cert),
              let data = SecKeyCopyExternalRepresentation(key, nil) as Data?,
              let params = DER.parseRSAPublicKey(Array(data)) else {
            throw TVError.identity("chiave RSA non leggibile")
        }
        return params
    }

    // MARK: Privati

    private static func findIdentity() -> SecIdentity? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecAttrLabel as String: label,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var ref: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &ref) == errSecSuccess, let r = ref else { return nil }
        return (r as! SecIdentity)
    }

    private static func createIdentity() throws {
        let privateAttrs: [String: Any] = [
            kSecAttrIsPermanent as String: true,
            kSecAttrApplicationTag as String: Data(label.utf8),
            kSecAttrLabel as String: label,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let attrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
            kSecPrivateKeyAttrs as String: privateAttrs
        ]
        var error: Unmanaged<CFError>?
        guard let priv = SecKeyCreateRandomKey(attrs as CFDictionary, &error),
              let pub = SecKeyCopyPublicKey(priv),
              let pubData = SecKeyCopyExternalRepresentation(pub, &error) as Data? else {
            throw TVError.identity("generazione chiave fallita")
        }

        let now = Date()
        let name = DER.sequence(DER.set(DER.sequence(DER.commonName, DER.utf8("atvremote-ios"))))
        let algorithm = DER.sequence(DER.sha256WithRSA, DER.null)
        let spki = DER.sequence(DER.sequence(DER.rsaEncryption, DER.null), DER.bitString(Array(pubData)))
        var serial = (0..<8).map { _ in UInt8.random(in: 0...255) }
        serial[0] &= 0x7F
        if serial[0] == 0 { serial[0] = 1 }

        let tbs = DER.sequence(
            DER.tlv(0xA0, DER.integer([2])),                       // version: v3
            DER.integer(serial),
            algorithm,
            name,                                                  // issuer
            DER.sequence(DER.utcTime(now.addingTimeInterval(-86_400)),
                         DER.utcTime(now.addingTimeInterval(20 * 365 * 86_400))),
            name,                                                  // subject
            spki
        )

        guard let signature = SecKeyCreateSignature(priv, .rsaSignatureMessagePKCS1v15SHA256,
                                                    Data(tbs) as CFData, &error) as Data? else {
            throw TVError.identity("firma del certificato fallita")
        }
        let certDER = DER.sequence(tbs, algorithm, DER.bitString(Array(signature)))
        guard let cert = SecCertificateCreateWithData(nil, Data(certDER) as CFData) else {
            throw TVError.identity("certificato non valido")
        }
        let add: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecValueRef as String: cert,
            kSecAttrLabel as String: label,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            throw TVError.identity("salvataggio nel Keychain fallito (\(status))")
        }
    }
}
