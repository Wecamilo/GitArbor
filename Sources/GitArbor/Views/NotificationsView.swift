import AppKit
import GitArborCore
import SwiftUI

struct NotificationsView: View {
    @Environment(AppModel.self) private var model
    @ViewState private var loading = false

    private var grouped: [(String, [GHNotification])] {
        Dictionary(grouping: model.notifications, by: \.repository.fullName)
            .map { ($0.key, $0.value.sorted { $0.updatedAt > $1.updatedAt }) }
            .sorted { ($0.1.first?.updatedAt ?? .distantPast) > ($1.1.first?.updatedAt ?? .distantPast) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ScreenHeader(title: "Notificações", subtitle: "Avisos do GitHub: comentários, menções, automações e pedidos de revisão. Clique para abrir; marque como lido quando resolver.",
                             symbol: "bell.fill", tint: .orange) {
                    HStack {
                        Button { Task { loading = true; await model.refreshNotifications(); loading = false } } label: {
                            if loading { ProgressView().controlSize(.small) } else { Label("Atualizar", systemImage: "arrow.clockwise") }
                        }
                        .buttonStyle(ActionButtonStyle(tint: .orange))
                        Button { Task { await model.markAllRead() } } label: { Label("Marcar tudo como lido", systemImage: "checkmark.circle") }
                            .buttonStyle(ActionButtonStyle(tint: .orange, prominent: true))
                            .disabled(model.notifications.isEmpty)
                    }
                }

                if model.notifications.isEmpty {
                    EmptyState(symbol: "bell.slash", title: "Nenhuma notificação", message: "Você está em dia. Quando alguém comentar, mencionar você ou uma automação terminar, aparece aqui.", tint: .orange)
                } else {
                    ForEach(grouped, id: \.0) { repo, items in
                        Card(padding: 0) {
                            VStack(alignment: .leading, spacing: 0) {
                                Button { model.open(fullName: repo) } label: {
                                    HStack {
                                        Image(systemName: "shippingbox.fill").foregroundStyle(.blue)
                                        Text(repo).font(.system(size: 13, weight: .semibold))
                                        Spacer()
                                        Text(Phrases.plural(items.count, "aviso", "avisos")).font(.system(size: 11)).foregroundStyle(.secondary)
                                    }
                                    .padding(14)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                Divider()
                                ForEach(items) { n in
                                    NotificationRow(notification: n)
                                    if n.id != items.last?.id { Divider().padding(.leading, 56) }
                                }
                            }
                        }
                    }
                }
            }
            .padding(28)
        }
    }
}

private struct NotificationRow: View {
    @Environment(AppModel.self) private var model
    let notification: GHNotification

    private var symbol: (String, Color) {
        switch notification.subject.type {
        case "Issue": ("smallcircle.filled.circle", Theme.open)
        case "PullRequest": ("arrow.triangle.pull", Theme.closed)
        case "Release": ("tag.fill", .pink)
        case "CheckSuite", "WorkflowRun": ("gearshape.2.fill", .orange)
        case "Commit": ("camera.fill", .indigo)
        case "Discussion": ("bubble.left.and.bubble.right.fill", .teal)
        default: ("exclamationmark.shield.fill", .red)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IconTile(symbol: symbol.0, tint: symbol.1, size: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(notification.subject.title).font(.system(size: 13, weight: notification.unread ? .semibold : .regular))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Pill(text: Phrases.notificationReason(notification.reason), tint: symbol.1)
                    Text(Phrases.notificationKind(notification.subject.type)).font(.system(size: 11)).foregroundStyle(.secondary)
                    Text("· \(Phrases.relative(notification.updatedAt))").font(.system(size: 11)).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Button { NSWorkspace.shared.open(notification.webURL ?? URL(string: "https://github.com/notifications")!) } label: {
                Label("Abrir", systemImage: "safari")
            }
            .buttonStyle(ActionButtonStyle(tint: .secondary))
            Button { Task { await model.markRead(notification) } } label: { Image(systemName: "checkmark") }
                .buttonStyle(ActionButtonStyle(tint: Theme.open))
                .help("Marcar como lida")
                .accessibilityLabel("Marcar como lida")
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }
}
