import GitArborCore
import SwiftUI

/// Início: cumprimento, números principais, quadradinhos de atividade, o que pede atenção e o que aconteceu.
struct HomeView: View {
    @Environment(AppModel.self) private var model

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let part = hour < 12 ? "Bom dia" : hour < 18 ? "Boa tarde" : "Boa noite"
        return "\(part), \(model.user?.firstName ?? "")"
    }

    private var publicCount: Int { model.repos.filter { !$0.isPrivate }.count }
    private var privateCount: Int { model.repos.filter(\.isPrivate).count }
    private var stars: Int { model.repos.reduce(0) { $0 + $1.stargazersCount } }
    private var needsAttention: [LocalRepoStatus] {
        model.localRepos.filter { [.unsaved, .toSend, .toReceive, .diverged, .conflict, .noUpstream].contains($0.state) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack(spacing: 16) {
                    Avatar(url: model.user?.avatarUrl, size: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(greeting).font(.system(size: 28, weight: .bold))
                        Text("Este é o resumo do seu GitHub. Clique em qualquer cartão para ver mais.")
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if model.isRefreshing || model.isScanningLocal {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text("Atualizando…").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        .transition(.opacity)
                    } else if let date = model.lastRefresh {
                        Text("Atualizado \(Phrases.relative(date))")
                            .font(.system(size: 11)).foregroundStyle(.tertiary)
                            .transition(.opacity)
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 14)], spacing: 14) {
                    Button { model.section = .repos } label: {
                        StatTile(value: "\(model.repos.count)", label: "Repositórios",
                                 symbol: "shippingbox.fill", tint: .blue,
                                 hint: "\(publicCount) públicos · \(privateCount) privados")
                    }.buttonStyle(.plain)
                    Button { model.section = .local } label: {
                        StatTile(value: "\(model.localRepos.count)", label: "Projetos no Mac",
                                 symbol: "laptopcomputer", tint: .indigo,
                                 hint: needsAttention.isEmpty ? "Tudo em dia" : "\(needsAttention.count) pedem atenção")
                    }.buttonStyle(.plain)
                    Button { model.section = .notifications } label: {
                        StatTile(value: "\(model.unreadCount)", label: "Notificações",
                                 symbol: "bell.fill", tint: .orange, hint: "Avisos ainda não lidos")
                    }.buttonStyle(.plain)
                    StatTile(value: "\(stars)", label: "Estrelas recebidas", symbol: "star.fill", tint: .yellow,
                             hint: "Quantas pessoas “curtiram” seus projetos")
                    StatTile(value: "\(model.user?.followers ?? 0)", label: "Seguidores", symbol: "person.2.fill", tint: .teal,
                             hint: "Pessoas que acompanham você")
                }

                if let calendar = model.calendar {
                    ActivityCard(calendar: calendar)
                }

                if !needsAttention.isEmpty {
                    AttentionCard(items: needsAttention)
                }

                HStack(alignment: .top, spacing: 18) {
                    RecentReposCard()
                    ActivityTimeline()
                }
            }
            .padding(28)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}

/// Quadradinhos do último ano: cada um é um dia; mais escuro = mais atividade.
private struct ActivityCard: View {
    @Environment(AppModel.self) private var model
    let calendar: ContributionCalendar
    @ViewState private var hoveredDate: String?

    var body: some View {
        let labels = model.activityLabels
        let maxCount = calendar.maxCount
        Card(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Sua atividade no último ano").font(.system(size: 15, weight: .semibold))
                        Text("Cada quadradinho é um dia. Quanto mais escuro, mais coisas você fez (commits, tarefas, pedidos).")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    HStack(spacing: 18) {
                        metric("\(calendar.totalContributions)", "contribuições")
                        metric("\(calendar.currentStreak)", calendar.currentStreak == 1 ? "dia seguido" : "dias seguidos")
                    }
                }

                GeometryReader { geo in
                    let weeks = calendar.weeks.count
                    let cell = max(6, min(16, (geo.size.width - CGFloat(weeks - 1) * 3) / CGFloat(max(weeks, 1))))
                    HStack(alignment: .top, spacing: 3) {
                        ForEach(Array(calendar.weeks.enumerated()), id: \.offset) { _, week in
                            VStack(spacing: 3) {
                                ForEach(week.contributionDays, id: \.date) { day in
                                    RoundedRectangle(cornerRadius: cell * 0.22)
                                        .fill(color(day.contributionCount, max: maxCount))
                                        .frame(width: cell, height: cell)
                                        .onHover { inside in
                                            if inside { hoveredDate = day.date }
                                            else if hoveredDate == day.date { hoveredDate = nil }
                                        }
                                        .help(labels[day.date] ?? day.date)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .frame(height: 7 * 16 + 6 * 3)
                .accessibilityLabel("Gráfico de atividade: \(calendar.totalContributions) contribuições no último ano")

                HStack {
                    Text(hoveredDate.flatMap { labels[$0] } ?? "Passe o mouse num quadradinho para ver o dia.")
                        .font(.system(size: 11.5)).foregroundStyle(.secondary)
                    Spacer()
                    HStack(spacing: 4) {
                        Text("Menos").font(.system(size: 10.5)).foregroundStyle(.tertiary)
                        ForEach([0, 1, 3, 6, 10], id: \.self) { n in
                            RoundedRectangle(cornerRadius: 2.5).fill(color(n, max: 10)).frame(width: 11, height: 11)
                        }
                        Text("Mais").font(.system(size: 10.5)).foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(value).font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(Theme.accent)
            Text(label).font(.system(size: 10.5)).foregroundStyle(.secondary)
        }
    }

    private func color(_ count: Int, max: Int) -> Color {
        if count == 0 { return Color.primary.opacity(0.07) }
        let top = Double(Swift.max(max, 1))
        let level = Swift.min(1, 0.25 + 0.75 * Double(count) / top)
        return Theme.accent.opacity(level)
    }
}

/// Projetos do Mac com algo pendente.
private struct AttentionCard: View {
    @Environment(AppModel.self) private var model
    let items: [LocalRepoStatus]

    var body: some View {
        Card(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Pedem atenção no seu Mac", systemImage: "exclamationmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("Ver todos") { model.section = .local }.buttonStyle(ActionButtonStyle(tint: .indigo))
                }
                ForEach(items.prefix(5)) { repo in
                    HStack(spacing: 10) {
                        LocalStateBadge(state: repo.state)
                        Text(repo.name).font(.system(size: 13, weight: .medium))
                        Text(LocalStateBadge.sentence(for: repo)).font(.system(size: 12)).foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
        }
    }
}

private struct RecentReposCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Card(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Mexidos recentemente").font(.system(size: 15, weight: .semibold))
                if model.repos.isEmpty {
                    LoadingRow()
                } else {
                    ForEach(model.repos.sorted { ($0.lastActivity ?? .distantPast) > ($1.lastActivity ?? .distantPast) }.prefix(6)) { repo in
                        Button { model.open(repo) } label: {
                            HStack(spacing: 10) {
                                RoundedRectangle(cornerRadius: 6).fill(Color.language(repo.language).gradient)
                                    .frame(width: 30, height: 30)
                                    .overlay(Image(systemName: repo.isPrivate ? "lock.fill" : "globe").font(.system(size: 12, weight: .bold)).foregroundStyle(.white))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(repo.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                    Text(Phrases.relative(repo.lastActivity)).font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: 380)
    }
}

/// Linha do tempo do que aconteceu na conta.
private struct ActivityTimeline: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Card(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("O que aconteceu").font(.system(size: 15, weight: .semibold))
                if model.events.isEmpty {
                    EmptyState(symbol: "clock", title: "Nada por aqui ainda", message: "Quando você enviar mudanças, criar tarefas ou repositórios, isso aparece aqui.")
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(model.events.prefix(14).enumerated()), id: \.element.id) { index, event in
                            let info = Phrases.event(event)
                            HStack(alignment: .top, spacing: 12) {
                                VStack(spacing: 0) {
                                    Image(systemName: info.symbol)
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 24, height: 24)
                                        .background(Theme.accent.gradient, in: Circle())
                                    if index < min(model.events.count, 14) - 1 {
                                        Rectangle().fill(Color.primary.opacity(0.1)).frame(width: 2).frame(maxHeight: .infinity)
                                    }
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(info.text).font(.system(size: 12.5)).fixedSize(horizontal: false, vertical: true)
                                    Text(Phrases.relative(event.createdAt)).font(.system(size: 11)).foregroundStyle(.tertiary)
                                }
                                .padding(.bottom, 14)
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { model.open(fullName: event.repo.name) }
                        }
                    }
                }
            }
        }
    }
}
