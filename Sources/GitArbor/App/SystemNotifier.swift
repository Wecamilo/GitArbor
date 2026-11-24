import AppKit
import GitArborCore
import UserNotifications

/// Avisos na Central de Notificações do macOS: novidades do GitHub e envio automático que falhou.
/// Clicar no aviso abre o app na seção certa.
final class SystemNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = SystemNotifier()
    /// O app, para abrir a seção certa quando o aviso é clicado.
    weak var model: AppModel?

    private var center: UNUserNotificationCenter { .current() }

    /// Pede permissão (o macOS só pergunta uma vez) e passa a receber os cliques.
    func activate(model: AppModel) {
        self.model = model
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func post(id: String, title: String, body: String, section: AppSection, folder: URL? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = section.rawValue
        var info: [String: String] = ["section": section.rawValue]
        if let folder { info["folder"] = folder.path }
        content.userInfo = info
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    // Com o app na frente, o aviso fica só na Central (o app já mostra a novidade).
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        await MainActor.run { NSApp.isActive } ? [.list] : [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let section = (info["section"] as? String).flatMap(AppSection.init(rawValue:))
        let folder = (info["folder"] as? String).map { URL(fileURLWithPath: $0) }
        await MainActor.run {
            NSApp.activate()
            NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("main") == true || $0.title == "Git Arbor" }?.makeKeyAndOrderFront(nil)
            guard let model = SystemNotifier.shared.model, model.phase == .unlocked, let section else { return }
            model.section = section
            if section == .repos { model.repoPath = [] }
            if let folder {
                Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    NotificationCenter.default.post(name: .openLocalProject, object: ProjectSheetRequest(folder: folder, tab: .timeline))
                }
            }
        }
    }

    /// Nome em português do tipo de aviso do GitHub.
    static func kind(_ type: String) -> String {
        switch type {
        case "PullRequest": "Pedido de mudança"
        case "Issue": "Tarefa"
        case "Release": "Versão publicada"
        case "CheckSuite", "WorkflowRun": "Automação"
        case "Discussion": "Conversa"
        case "Commit": "Versão salva"
        case "RepositoryVulnerabilityAlert", "RepositoryDependabotAlertsThread": "Alerta de segurança"
        default: "Aviso"
        }
    }
}
