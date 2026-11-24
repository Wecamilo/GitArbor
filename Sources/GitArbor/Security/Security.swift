import AppKit
import Foundation
import GitArborCore
import LocalAuthentication
import Security

/// Touch ID: a entrada rápida usa só a digital (sem Apple Watch nem senha do Mac).
enum TouchIDAuthentication {
    /// Há sensor e digital cadastrada neste Mac.
    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    /// Contexto que só aceita a digital: sem o botão "usar senha".
    static func context() -> LAContext {
        let context = LAContext()
        context.localizedFallbackTitle = ""
        context.localizedCancelTitle = "Cancelar"
        return context
    }

    static func verify(_ context: LAContext = context(), reason: String) async throws {
        _ = try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
    }

    /// Senha do Mac (ou digital, se houver): para quem não usa Touch ID.
    static func verifyOwner(reason: String) async throws {
        let context = LAContext()
        context.localizedCancelTitle = "Cancelar"
        _ = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
    }

    static func message(for error: Error) -> String? {
        guard let la = error as? LAError else { return error.localizedDescription }
        switch la.code {
        case .userCancel, .appCancel, .systemCancel, .userFallback: return nil
        case .authenticationFailed: return "Digital não reconhecida."
        case .biometryNotAvailable: return "O Touch ID não está disponível agora. Entre com a senha do Mac."
        case .biometryNotEnrolled: return "Cadastre uma digital nos Ajustes do Sistema para usar o Touch ID."
        case .biometryLockout: return "O Touch ID foi bloqueado após várias tentativas. Entre com a senha do Mac."
        case .passcodeNotSet: return "Defina uma senha no Mac para usar este modo."
        default: return la.localizedDescription
        }
    }
}

struct KeychainError: LocalizedError {
    let status: OSStatus
    var errorDescription: String? {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "código \(status)"
        return "Chaves do macOS: \(message)"
    }
}

/// Chave de acesso ao GitHub colada pelo usuário, guardada no app Chaves do macOS.
enum TokenStore {
    static let service = "io.github.gitarbor.GitArbor.github-token"
    static let account = "github"

    static func save(_ token: String) throws {
        delete()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrLabel as String: "Git Arbor — chave do GitHub",
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: Data(token.utf8)
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    static func load() throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data, let token = String(data: data, encoding: .utf8) else {
            throw KeychainError(status: status)
        }
        return token
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// O GitHub CLI (`gh`) já conectado neste Mac: o app pega a chave dele na hora de entrar.
enum GitHubCLI {
    static let candidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]

    static var path: String? { candidates.first { FileManager.default.isExecutableFile(atPath: $0) } }
    static var isInstalled: Bool { path != nil }

    struct NotConnected: LocalizedError {
        var errorDescription: String? {
            "O GitHub CLI não está conectado. Abra o Terminal, rode “gh auth login” e siga os passos. Depois volte aqui."
        }
    }

    static func token() async throws -> String {
        guard let path else { throw NotConnected() }
        do {
            let output = try await LocalGit.runProcess(path, ["auth", "token"], in: nil)
            let token = output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty, !token.contains(" ") else { throw NotConnected() }
            return token
        } catch is GitFailure {
            throw NotConnected()
        }
    }
}
