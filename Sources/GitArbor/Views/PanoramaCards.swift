import Charts
import GitArborCore
import SwiftUI

// Painéis extras do Panorama: sequência, maré de código, relógio, termômetro, mapa de tamanho,
// crescimento, tipos de atividade, envio automático, mudanças pendentes e público × privado.

// MARK: - Sequência atual × recorde

struct StreakCard: View {
    let calendar: ContributionCalendar?
    let shown: Bool

    private var record: Int {
        var best = 0, run = 0
        for day in PanoramaView.days(calendar) {
            run = day.contributionCount > 0 ? run + 1 : 0
            best = max(best, run)
        }
        return best
    }

    var body: some View {
        let now = calendar?.currentStreak ?? 0
        let best = max(record, now)
        Card {
            VStack(alignment: .leading, spacing: 14) {
                CardTitle(title: "Sequência", subtitle: "Dias seguidos com trabalho: agora e o seu recorde no ano.")
                HStack(alignment: .bottom, spacing: 0) {
                    flame(now, of: best, label: "agora", tint: .orange)
                    flame(best, of: best, label: "recorde", tint: Theme.danger)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Text(now >= best && best > 0 ? "Você está no seu recorde. Continue!"
                     : best > 0 ? "Faltam \(best - now + 1) dias para bater o recorde." : "Comece hoje uma sequência nova.")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func flame(_ value: Int, of best: Int, label: String, tint: Color) -> some View {
        let ratio = best == 0 ? 0.3 : 0.35 + 0.65 * Double(value) / Double(best)
        return VStack(spacing: 4) {
            Image(systemName: "flame.fill")
                .font(.system(size: 64))
                .scaleEffect(shown ? ratio : 0.2, anchor: .bottom)
                .foregroundStyle(LinearGradient(colors: [.yellow, tint], startPoint: .top, endPoint: .bottom))
                .shadow(color: tint.opacity(0.4), radius: 8, y: 2)
                .frame(height: 70, alignment: .bottom)
            CountingText(value: Double(shown ? value : 0)).font(.system(size: 26, weight: .bold, design: .rounded))
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Maré de código

struct CodeTideCard: View {
    let weeks: [CodeWeek]
    let loading: Bool
    let shown: Bool
    /// Os dados chegam depois do resto do Panorama: o gráfico cresce quando aparece.
    @ViewState private var grown = false

    var body: some View {
        let adds = weeks.map(\.additions).reduce(0, +)
        let dels = weeks.map(\.deletions).reduce(0, +)
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    CardTitle(title: "Maré de código", subtitle: "Linhas adicionadas (para cima) e removidas (para baixo) por semana, em todos os repositórios.")
                    Spacer()
                    // Fica sempre no lugar (invisível até os dados chegarem): se aparecesse depois,
                    // o título quebraria em mais linhas e a linha de cartões mudaria de altura.
                    VStack(alignment: .trailing, spacing: 1) {
                        // Quando a atualização chega, os totais contam até o número novo.
                        CountingText(value: Double(adds), prefix: "+").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(Theme.open)
                        CountingText(value: Double(dels), prefix: "−").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(Theme.danger)
                    }
                    .animation(.smooth(duration: 0.9), value: adds)
                    .animation(.smooth(duration: 0.9), value: dels)
                    .frame(minWidth: 86, alignment: .trailing)
                    .opacity(weeks.isEmpty ? 0 : 1)
                    .animation(.easeOut(duration: 0.3), value: weeks.isEmpty)
                }
                if weeks.isEmpty {
                    HStack(spacing: 8) {
                        if loading { ProgressView().controlSize(.small) }
                        Text(loading ? "Perguntando ao GitHub…" : "O GitHub ainda está calculando. Volte em instantes.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 190, maxHeight: .infinity)
                } else {
                    TideBars(weeks: weeks, shown: shown && grown)
                    .frame(minHeight: 190, maxHeight: .infinity)
                    .onAppear { grown = true }
                    .onDisappear { grown = false }
                }
            }
        }
    }
}

/// Maré desenhada à mão em duas faixas, cada uma com a sua escala: em cima as linhas
/// adicionadas, embaixo as removidas. Como costuma se tirar bem menos do que se escreve,
/// a faixa de baixo usa uma escala menor — assim as remoções pequenas continuam visíveis.
private struct TideBars: View {
    let weeks: [CodeWeek]
    let shown: Bool
    @ViewState private var hovered: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let axisWidth: CGFloat = 52
    private let monthsHeight: CGFloat = 20
    private let gap: CGFloat = 2

    private var topMax: Double { ChartScale.nice(Double(weeks.map(\.additions).max() ?? 0)) }
    private var bottomMax: Double { ChartScale.nice(Double(weeks.map(\.deletions).max() ?? 0)) }
    /// Parte da altura para as adições (o resto fica para as remoções).
    private var topShare: CGFloat { weeks.contains { $0.deletions > 0 } ? 0.64 : 0.86 }

    private static let pt = Locale(identifier: "pt_BR")
    private static let monthFormat = Date.FormatStyle.dateTime.month(.abbreviated).locale(pt)
    private static let dayFormat = Date.FormatStyle.dateTime.day().month(.abbreviated).locale(pt)

    private static func compact(_ v: Double) -> String {
        Int(v.rounded()).formatted(.number.notation(.compactName).locale(pt))
    }

    var body: some View {
        GeometryReader { geo in
            let plotWidth = max(0, geo.size.width - axisWidth - 8)
            let plotHeight = max(0, geo.size.height - monthsHeight)
            let upHeight = plotHeight * topShare
            let downHeight = plotHeight - upHeight - gap
            let base = upHeight
            let slot = weeks.isEmpty ? 0 : plotWidth / CGFloat(weeks.count)
            let barWidth = max(2, slot * 0.7)

            ZStack(alignment: .topLeading) {
                // Faixa de cima: 0, metade, topo.
                ForEach([0.5, 1.0], id: \.self) { f in
                    gridLine(y: base - upHeight * CGFloat(f), width: plotWidth, label: Self.compact(topMax * f), color: Theme.open)
                }
                // Faixa de baixo, com a escala dela.
                if downHeight > 20 {
                    Rectangle().fill(Theme.danger.opacity(0.05))
                        .frame(width: plotWidth, height: downHeight)
                        .offset(y: base + gap)
                    ForEach([0.5, 1.0], id: \.self) { f in
                        gridLine(y: base + gap + downHeight * CGFloat(f), width: plotWidth, label: "−" + Self.compact(bottomMax * f), color: Theme.danger)
                    }
                }
                // Linha do zero.
                Rectangle().fill(Color.primary.opacity(0.22)).frame(width: plotWidth, height: 1).offset(y: base)
                Text("0").font(.system(size: 10)).foregroundStyle(.secondary).offset(x: plotWidth + 8, y: base - 6)

                ForEach(Array(weeks.enumerated()), id: \.element.id) { index, week in
                    let x = slot * CGFloat(index) + (slot - barWidth) / 2
                    let up = upHeight * CGFloat(Double(week.additions) / topMax)
                    let down = downHeight * CGFloat(Double(week.deletions) / bottomMax)
                    let animation: Animation = reduceMotion ? .easeOut(duration: 0.2)
                        : .smooth(duration: 0.7).delay(Double(index) * 0.015)
                    let dim = hovered != nil && hovered != index

                    UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3, style: .continuous)
                        .fill(LinearGradient(colors: [Theme.open.opacity(0.75), Theme.open], startPoint: .top, endPoint: .bottom))
                        .frame(width: barWidth, height: week.additions > 0 ? max(1.5, up) : 0)
                        .scaleEffect(x: 1, y: shown ? 1 : 0.001, anchor: .bottom)
                        .animation(animation, value: shown)
                        .offset(x: x, y: base - (week.additions > 0 ? max(1.5, up) : 0))
                        .opacity(dim ? 0.5 : 1)
                        // Dados novos do GitHub: a barra vai até o tamanho novo.
                        .animation(.smooth(duration: 0.9), value: up)
                    UnevenRoundedRectangle(bottomLeadingRadius: 3, bottomTrailingRadius: 3, style: .continuous)
                        .fill(LinearGradient(colors: [Theme.danger, Theme.danger.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                        .frame(width: barWidth, height: week.deletions > 0 ? max(1.5, down) : 0)
                        .scaleEffect(x: 1, y: shown ? 1 : 0.001, anchor: .top)
                        .animation(animation.delay(0.08), value: shown)
                        .offset(x: x, y: base + gap)
                        .opacity(dim ? 0.5 : 1)
                        .animation(.smooth(duration: 0.9), value: down)
                    // Área de passar o mouse: a coluna inteira da semana.
                    Color.clear
                        .frame(width: slot, height: plotHeight)
                        .contentShape(Rectangle())
                        .offset(x: slot * CGFloat(index))
                        .onHover { inside in
                            if inside { hovered = index } else if hovered == index { hovered = nil }
                        }
                }

                if let hovered, weeks.indices.contains(hovered) {
                    let week = weeks[hovered]
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Semana de \(week.id.formatted(Self.dayFormat))").font(.system(size: 11, weight: .semibold))
                        Text("+\(week.additions.formatted()) linhas").font(.system(size: 11)).foregroundStyle(Theme.open)
                        Text("−\(week.deletions.formatted()) linhas").font(.system(size: 11)).foregroundStyle(Theme.danger)
                    }
                    .padding(.horizontal, 9).padding(.vertical, 6)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.09)))
                    .fixedSize()
                    .offset(x: min(max(0, slot * CGFloat(hovered) - 40), max(0, plotWidth - 150)), y: 4)
                    .allowsHitTesting(false)
                }

                // Meses, embaixo da primeira semana de cada um.
                ForEach(Array(weeks.enumerated()), id: \.element.id) { index, week in
                    if index > 0, Calendar.current.component(.month, from: week.id) != Calendar.current.component(.month, from: weeks[index - 1].id) {
                        Text(week.id.formatted(Self.monthFormat))
                            .font(.system(size: 10.5)).foregroundStyle(.secondary)
                            .fixedSize()
                            .offset(x: slot * CGFloat(index), y: plotHeight + 5)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Maré de código")
        .accessibilityValue(weeks.map { "\($0.id.formatted(Self.dayFormat)): mais \($0.additions), menos \($0.deletions)" }.joined(separator: "; "))
    }

    private func gridLine(y: CGFloat, width: CGFloat, label: String, color: Color) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(Color.primary.opacity(0.07)).frame(width: width, height: 1).offset(y: y)
            Text(label).font(.system(size: 10)).foregroundStyle(color.opacity(0.85))
                .fixedSize()
                .offset(x: width + 8, y: y - 6)
        }
    }
}

// MARK: - Relógio de trabalho

struct WorkClockCard: View {
    let events: [GHEvent]
    let shown: Bool

    private var hours: [Int] {
        var h = Array(repeating: 0, count: 24)
        for e in events { h[Calendar.current.component(.hour, from: e.createdAt)] += 1 }
        return h
    }

    var body: some View {
        let h = hours
        let total = h.reduce(0, +)
        let peak = h.indices.max { h[$0] < h[$1] } ?? 0
        let maxV = max(1, h.max() ?? 1)
        let periods: [(String, Range<Int>, Color)] = [("Madrugada", 0..<6, .indigo), ("Manhã", 6..<12, .orange),
                                                       ("Tarde", 12..<18, Theme.accent), ("Noite", 18..<24, .purple)]
        Card {
            VStack(alignment: .leading, spacing: 14) {
                CardTitle(title: "Relógio de trabalho", subtitle: "Horário dos eventos recentes do GitHub (até 40).")
                ZStack {
                    Circle().stroke(Color.primary.opacity(0.06), lineWidth: 1).frame(width: 96, height: 96)
                    ForEach(0..<24, id: \.self) { i in
                        let len = 8 + 62 * (shown ? Double(h[i]) / Double(maxV) : 0)
                        Capsule()
                            .fill(color(i, periods).gradient)
                            .opacity(h[i] == 0 ? 0.25 : 1)
                            .frame(width: 7, height: len)
                            .offset(y: -(50 + len / 2))
                            .rotationEffect(.degrees(Double(i) / 24 * 360))
                            .animation(.spring(response: 0.8, dampingFraction: 0.7).delay(Double(i) * 0.02), value: shown)
                            .help("\(i)h: \(h[i]) \(h[i] == 1 ? "atividade" : "atividades")")
                    }
                    ForEach([0, 6, 12, 18], id: \.self) { i in
                        Text("\(i)h").font(.system(size: 9.5, weight: .semibold)).foregroundStyle(.secondary)
                            .offset(y: -38).rotationEffect(.degrees(Double(i) / 24 * 360))
                            .rotationEffect(.degrees(0))
                    }
                    VStack(spacing: 0) {
                        Text(total == 0 ? "—" : "\(peak)h").font(.system(size: 22, weight: .bold, design: .rounded))
                        Text("pico").font(.system(size: 10.5)).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 250, height: 250)
                .frame(maxWidth: .infinity)
                HStack(spacing: 0) {
                    ForEach(periods, id: \.0) { name, range, tint in
                        let n = range.map { h[$0] }.reduce(0, +)
                        VStack(spacing: 2) {
                            Text(total == 0 ? "0%" : "\(Int((Double(n) / Double(total) * 100).rounded()))%")
                                .font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(tint)
                            Text(name).font(.system(size: 10.5)).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func color(_ hour: Int, _ periods: [(String, Range<Int>, Color)]) -> Color {
        periods.first { $0.1.contains(hour) }?.2 ?? Theme.accent
    }
}

// MARK: - Termômetro

struct ThermometerCard: View {
    let repos: [GHRepo]
    let shown: Bool

    private enum AgeBand: CaseIterable {
        case day, week, month, quarter, older

        init(seconds: TimeInterval) {
            switch seconds {
            case ..<86_400: self = .day
            case ..<604_800: self = .week
            case ..<2_592_000: self = .month
            case ..<7_776_000: self = .quarter
            default: self = .older
            }
        }

        var color: Color {
            switch self {
            case .day: Color(red: 0.93, green: 0.30, blue: 0.22)
            case .week: .orange
            case .month: Color(red: 0.92, green: 0.75, blue: 0.15)
            case .quarter: .teal
            case .older: .blue
            }
        }

        var label: String {
            switch self {
            case .day: "Até 24 h"
            case .week: "Até 7 d"
            case .month: "Até 30 d"
            case .quarter: "Até 90 d"
            case .older: "90 d ou mais"
            }
        }
    }

    private struct Reading {
        let timestamp: Date?
        let now: Date

        var seconds: TimeInterval? { timestamp.map { max(0, now.timeIntervalSince($0)) } }
        var band: AgeBand? { seconds.map { AgeBand(seconds: $0) } }

        var heat: Double {
            guard let seconds else { return 0 }
            // Uma escala logarítmica mantém visíveis tanto as horas recentes quanto os meses.
            return max(0.06, 1 - log1p(seconds / 900) / log1p(31_536_000.0 / 900))
        }

        var label: String {
            guard let seconds else { return "Sem registro" }
            let minutes = Int(seconds / 60)
            switch minutes {
            case 0: return "Agora"
            case ..<60: return "há \(minutes) min"
            case ..<1440: return "há \(minutes / 60) h"
            default: return "há \(minutes / 1440) d"
            }
        }
    }

    var body: some View {
        let sorted = repos.sorted {
            let left = $0.lastActivity ?? .distantPast
            let right = $1.lastActivity ?? .distantPast
            if left != right { return left > right }
            return $0.fullName.localizedStandardCompare($1.fullName) == .orderedAscending
        }

        TimelineView(.periodic(from: .now, by: 60)) { context in
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    CardTitle(title: "Termômetro", subtitle: "Última atividade no GitHub.")
                    if sorted.isEmpty {
                        Text("Nenhum repositório para mostrar.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 88)
                    } else {
                        // A altura do cartão é a do Relógio de trabalho, ao lado. Se os projetos não
                        // couberem, a lista vira páginas, como um letreiro de aeroporto.
                        FlipBoard(items: sorted, rowHeight: 17, spacing: 5) { repo, width in
                            let reading = Reading(timestamp: repo.lastActivity, now: context.date)
                            activityRow(repo, reading: reading, nameWidth: min(164, width * 0.42))
                        }
                        .frame(minHeight: min(CGFloat(sorted.count) * 22 - 5, 3 * 22), maxHeight: .infinity)

                        FlowRow(spacing: 10) {
                            ForEach(AgeBand.allCases, id: \.self) { band in
                                HStack(spacing: 4) {
                                    Circle().fill(band.color).frame(width: 7, height: 7)
                                        .accessibilityHidden(true)
                                    Text(band.label)
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private func activityRow(_ repo: GHRepo, reading: Reading, nameWidth: CGFloat) -> some View {
        HStack(spacing: 9) {
            Text(repo.name)
                .font(.system(size: 11.5, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: nameWidth, alignment: .leading)
                .help(repo.fullName)

            // A barra cresce quando a linha aparece (também ao virar a página).
            GrowOnAppear(delay: 0.25) { grown in
                GeometryReader { geometry in
                    Capsule()
                        .fill(Color.primary.opacity(0.07))
                        .overlay(alignment: .leading) {
                            if let band = reading.band {
                                Capsule()
                                    .fill(LinearGradient(colors: [band.color.opacity(0.58), band.color],
                                                         startPoint: .leading, endPoint: .trailing))
                                    .frame(width: geometry.size.width * (shown && grown ? reading.heat : 0))
                            }
                        }
                }
            }
            .frame(height: 6)

            Text(reading.label)
                .font(.system(size: 10.5).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 66, alignment: .trailing)
                .help(reading.timestamp?.formatted(date: .abbreviated, time: .shortened) ?? reading.label)
        }
        .frame(height: 17)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(repo.fullName)
        .accessibilityValue(reading.label)
    }
}

// MARK: - Mapa de tamanho

struct SizeMapCard: View {
    @Environment(AppModel.self) private var model
    let repos: [GHRepo]
    let shown: Bool

    @ViewState private var mode: Mode = .size
    @ViewState private var activity: [String: RepositoryActivity] = [:]
    @ViewState private var loaded: [Revision]?
    @ViewState private var expiresAt: Date?
    @ViewState private var activityFailed = false
    @ViewState private var retry = 0

    private enum Mode: String, CaseIterable, Hashable {
        case size = "Tamanho"
        case language = "Linguagens"
        case commits = "Commits"
        case time = "Tempo estimado"

        var needsHistory: Bool { self == .commits || self == .time }

        var title: String {
            switch self {
            case .size: "Mapa de tamanho"
            case .language: "Mapa de linguagens"
            case .commits: "Mapa de commits"
            case .time: "Mapa de tempo estimado"
            }
        }

        var symbol: String {
            switch self {
            case .size: "internaldrive"
            case .language: "chevron.left.forwardslash.chevron.right"
            case .commits: "arrow.triangle.branch"
            case .time: "clock"
            }
        }

        var subtitle: String {
            switch self {
            case .size: "Espaço ocupado por repositório no GitHub. A cor indica a linguagem principal."
            case .language: "Volume de código por linguagem, somado em todos os repositórios exibidos."
            case .commits: "Todos os commits que fazem parte do ramo principal de cada repositório."
            case .time: "Estimativa por projeto a partir dos seus commits no ramo principal, nos últimos 30 dias."
            }
        }
    }

    private struct Revision: Hashable {
        let name: String
        let pushedAt: Date?
        let branch: String
    }

    private struct HistoryRequest: Equatable {
        let repos: [Revision]
        let retry: Int
    }

    private struct Entry: Identifiable {
        let id: String
        let name: String
        let detailName: String
        let language: String?
        let value: Int
    }

    private struct Tile: Identifiable {
        let entry: Entry
        let rect: CGRect
        let index: Int
        let valueLabel: String

        var id: String { entry.id }
        var metadata: String {
            valueLabel + (entry.language.flatMap { $0 == entry.detailName ? nil : " · \($0)" } ?? "")
        }
    }

    var body: some View {
        let request = mode.needsHistory ? HistoryRequest(repos: revisions, retry: retry) : nil
        let items = entries
        let total = items.reduce(0) { $0 + $1.value }
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    CardTitle(title: mode.title, subtitle: mode.subtitle)
                    Spacer(minLength: 12)
                    if !items.isEmpty {
                        Text(Self.label(total, for: mode))
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.accent)
                            .fixedSize()
                    }
                }

                FilterChips(selection: $mode, options: Mode.allCases.map {
                    ChipOption(value: $0, title: $0.rawValue, symbol: $0.symbol)
                })
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Métrica do mapa")

                if items.isEmpty {
                    emptyMap.frame(maxWidth: .infinity)
                        .frame(height: 260)
                } else {
                    GeometryReader { geometry in
                        Tiles(tiles: Self.layout(items, mode: mode, in: geometry.size), size: geometry.size, shown: shown)
                            .id(mode)
                    }
                    .frame(height: 260)
                }

                if mode == .time && !items.isEmpty {
                    Text("Cada sessão começa com 15 min. Intervalos de até 1 h entre commits da sessão entram na soma.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }

                if let coverage, coverage < repos.count, !items.isEmpty {
                    Text("Dados disponíveis para \(coverage) de \(repos.count) repositórios.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task(id: request) {
            if let request { await loadHistory(request.repos) }
        }
    }

    private var revisions: [Revision] {
        repos.map { Revision(name: $0.fullName, pushedAt: $0.pushedAt, branch: $0.branch) }
            .sorted { $0.name < $1.name }
    }

    private var entries: [Entry] {
        if mode == .language {
            return model.languageBytes.compactMap { language, bytes in
                guard bytes > 0 else { return nil }
                return Entry(id: language, name: language, detailName: language, language: language, value: bytes)
            }
        }
        return repos.compactMap { repo in
            let value: Int?
            switch mode {
            case .size: value = (repo.size ?? 0) * 1024
            case .commits: value = activity[repo.fullName]?.commits
            case .time: value = activity[repo.fullName]?.estimatedMinutes
            case .language: value = nil
            }
            guard let value, mode == .size || value > 0 else { return nil }
            return Entry(id: repo.fullName, name: repo.name, detailName: repo.fullName, language: repo.language, value: value)
        }
    }

    private var coverage: Int? {
        switch mode {
        case .size: nil
        case .language: model.languageRepositoryCount
        case .commits: repos.count { activity[$0.fullName] != nil }
        case .time: repos.count { activity[$0.fullName]?.estimatedMinutes != nil }
        }
    }

    @ViewBuilder private var emptyMap: some View {
        if mode.needsHistory && !repos.isEmpty && loaded == nil && !activityFailed
            || mode == .language && model.isLoadingLanguages {
            ProgressView("Consultando o GitHub…").controlSize(.small)
        } else if mode.needsHistory && activityFailed {
            VStack(spacing: 8) {
                Text("Não consegui consultar o histórico dos repositórios.")
                Button("Tentar novamente") { retry += 1 }.controlSize(.small)
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        } else {
            let message: String = switch mode {
            case .size: "Nenhum repositório para mostrar."
            case .language: "Nenhum volume de código disponível."
            case .commits: activity.isEmpty ? "Histórico indisponível para estes repositórios." : "Nenhum commit no ramo principal."
            case .time: (coverage ?? 0) == 0 ? "Histórico indisponível para estimar o tempo." : "Nenhum commit seu no ramo principal nos últimos 30 dias."
            }
            Text(message).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }

    private func loadHistory(_ revisions: [Revision]) async {
        guard !revisions.isEmpty, let client = model.client else { return }
        let now = Date()
        if loaded == revisions, let expiresAt, expiresAt > now { return }
        let names = revisions.map(\.name)
        activityFailed = false
        if loaded != revisions {
            activity = [:]
            loaded = nil
        }
        do {
            let window = now.addingTimeInterval(-30 * 86_400)
            let incoming = try await client.repositoryActivity(names, from: window, through: now)
            guard !Task.isCancelled, model.client?.responses === client.responses else { return }
            activity = incoming
            loaded = revisions
            expiresAt = Date().addingTimeInterval(300)
        } catch {
            guard !Task.isCancelled, model.client?.responses === client.responses else { return }
            activityFailed = true
            loaded = nil
        }
    }

    // A posição dos blocos depende dos dados e da largura. O hover atualiza só esta camada.
    private struct Tiles: View {
        let tiles: [Tile]
        let size: CGSize
        let shown: Bool

        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @ViewState private var hoveredID: String?

        var body: some View {
            let hovered = shown ? tiles.first { $0.id == hoveredID } : nil
            let stagger = min(0.04, 0.32 / Double(max(1, tiles.count - 1)))
            return ZStack {
                ForEach(tiles) { tile in
                    block(tile, highlighted: tile.id == hovered?.id, dimmed: hovered != nil && tile.id != hovered?.id)
                        .scaleEffect(shown || reduceMotion ? 1 : 0.92)
                        .opacity(shown ? 1 : 0)
                        .animation(reduceMotion ? nil : .smooth(duration: 0.55).delay(Double(tile.index) * stagger * 0.5),
                                   value: shown)
                        .frame(width: tile.rect.width, height: tile.rect.height)
                        .contentShape(Rectangle())
                        .onHover { inside in
                            if inside { hoveredID = tile.id }
                            else if hoveredID == tile.id { hoveredID = nil }
                        }
                        .position(x: tile.rect.midX, y: tile.rect.midY)
                        .zIndex(tile.id == hovered?.id ? 1 : 0)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .topLeading) {
                if let hovered {
                    details(for: hovered, in: size)
                        .id(hovered.id)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: hoveredID)
        }

        private func block(_ tile: Tile, highlighted: Bool, dimmed: Bool) -> some View {
            let tint = Color.language(tile.entry.language)
            let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
            let width = max(0, tile.rect.width - 4)
            let height = max(0, tile.rect.height - 4)
            return shape
                .fill(LinearGradient(colors: [tint.opacity(0.75), tint], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: width, height: height)
                .overlay {
                    Group {
                        if width > 66 && height > 30 {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(tile.entry.name).font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
                                Text(tile.valueLabel).font(.system(size: 10)).opacity(0.85)
                            }
                            .padding(7)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        } else if width >= 18 && height >= 48 && height > width * 1.35 {
                            Text(tile.entry.name)
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .minimumScaleFactor(0.82)
                                .frame(width: height - 12)
                                .rotationEffect(.degrees(-90))
                        }
                    }
                    .foregroundStyle(Color.onLanguage(tile.entry.language))
                    .shadow(color: .black.opacity(Color.isLight(hex: Languages.hex(tile.entry.language)) ? 0 : 0.25), radius: 1)
                }
                .overlay { shape.strokeBorder(.white.opacity(highlighted ? 0.78 : 0), lineWidth: 1.5) }
                .scaleEffect(highlighted && !reduceMotion ? 1.025 : 1)
                .shadow(color: .black.opacity(highlighted ? 0.2 : 0), radius: 7, y: 3)
                .opacity(dimmed ? 0.84 : 1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(tile.entry.detailName)
                .accessibilityValue(tile.metadata)
        }

        private func details(for tile: Tile, in size: CGSize) -> some View {
            let width = max(0, min(252, size.width - 16))
            let x = min(max(8, tile.rect.midX - width / 2), max(8, size.width - width - 8))
            let alignment: Alignment = tile.rect.midY < size.height / 2 ? .bottomLeading : .topLeading
            return VStack(alignment: .leading, spacing: 4) {
                Text(tile.entry.detailName)
                    .font(.system(size: 12, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(tile.metadata)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .frame(width: width, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.09)) }
            .shadow(color: .black.opacity(0.14), radius: 9, y: 3)
            .frame(height: max(0, size.height - 16), alignment: alignment)
            .offset(x: x, y: 8)
        }

    }

    private static func label(_ value: Int, for mode: Mode) -> String {
        switch mode {
        case .size, .language:
            ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file)
        case .commits:
            "\(value.formatted()) \(value == 1 ? "commit" : "commits")"
        case .time:
            value < 60 ? "\(value) min" : "\((value / 60).formatted()) h \(value % 60) min"
        }
    }

    /// Divide o retângulo em dois grupos de peso parecido pelo lado mais comprido.
    private static func layout(_ entries: [Entry], mode: Mode, in size: CGSize) -> [Tile] {
        let total = entries.reduce(0.0) { $0 + Double($1.value) }
        let floor = mode == .size ? max(1024, total * 0.015) : 1
        var items: [(Entry, Double)] = entries.map { ($0, max(floor, Double($0.value))) }
        items.sort { left, right in
            if left.1 == right.1 { return left.0.id < right.0.id }
            return left.1 > right.1
        }
        var out: [Tile] = []
        func split(_ list: ArraySlice<(Entry, Double)>, _ rect: CGRect) {
            guard let first = list.first else { return }
            if list.count == 1 {
                out.append(Tile(entry: first.0, rect: rect, index: out.count, valueLabel: label(first.0.value, for: mode)))
                return
            }
            let sum = list.map(\.1).reduce(0, +)
            var acc = 0.0
            var cut = list.startIndex
            for i in list.indices {
                acc += list[i].1
                cut = i + 1
                if acc >= sum / 2 { break }
            }
            if cut == list.endIndex { cut = list.endIndex - 1; acc = sum - list[cut].1 }
            let ratio = CGFloat(acc / sum)
            let a: CGRect, b: CGRect
            if rect.width >= rect.height {
                a = CGRect(x: rect.minX, y: rect.minY, width: rect.width * ratio, height: rect.height)
                b = CGRect(x: rect.minX + rect.width * ratio, y: rect.minY, width: rect.width * (1 - ratio), height: rect.height)
            } else {
                a = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * ratio)
                b = CGRect(x: rect.minX, y: rect.minY + rect.height * ratio, width: rect.width, height: rect.height * (1 - ratio))
            }
            split(list[list.startIndex..<cut], a)
            split(list[cut..<list.endIndex], b)
        }
        split(items[...], CGRect(origin: .zero, size: size))
        return out
    }
}

// MARK: - Crescimento

struct GrowthCard: View {
    let repos: [GHRepo]
    let since: Date?
    let shown: Bool

    private struct Point: Identifiable { let id: Int; let date: Date; let total: Int }

    private var points: [Point] {
        let dates = repos.compactMap(\.createdAt).sorted()
        var pts: [Point] = []
        if let start = since ?? dates.first { pts.append(Point(id: -1, date: start, total: 0)) }
        for (i, d) in dates.enumerated() { pts.append(Point(id: i, date: d, total: i + 1)) }
        if let last = pts.last { pts.append(Point(id: dates.count, date: Date(), total: last.total)) }
        return pts
    }

    var body: some View {
        let data = points
        let thisYear = repos.filter { ($0.createdAt ?? .distantPast) > Calendar.current.date(byAdding: .year, value: -1, to: Date())! }.count
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    CardTitle(title: "Crescimento", subtitle: "Quantos repositórios você tinha ao longo do tempo.")
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("+\(thisYear)").font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(.teal)
                        Text("no último ano").font(.system(size: 10.5)).foregroundStyle(.secondary)
                    }
                }
                Growing(progress: shown ? 1 : 0) { k in
                Chart(data) { p in
                    AreaMark(x: .value("Data", p.date), y: .value("Repositórios", Double(p.total) * k))
                        .interpolationMethod(.stepEnd)
                        .foregroundStyle(LinearGradient(colors: [.teal.opacity(0.35), .teal.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Data", p.date), y: .value("Repositórios", Double(p.total) * k))
                        .interpolationMethod(.stepEnd)
                        .foregroundStyle(.teal)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                }
                .chartYScale(domain: 0...ChartScale.nice(Double(data.last?.total ?? 0)))
                }
                .frame(minHeight: 190, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - Tipos de atividade

struct ActivityTypesCard: View {
    let events: [GHEvent]
    let shown: Bool

    private struct Slice: Identifiable { let id: String; let count: Int; let color: Color }

    private static func kind(_ type: String) -> (String, Color) {
        switch type {
        case "PushEvent": ("Envios de código", Theme.accent)
        case "PullRequestEvent", "PullRequestReviewEvent", "PullRequestReviewCommentEvent": ("Pedidos de mudança", Theme.closed)
        case "IssuesEvent": ("Tarefas", Theme.open)
        case "IssueCommentEvent", "CommitCommentEvent": ("Comentários", .orange)
        case "CreateEvent": ("Ramos e repositórios criados", .teal)
        case "DeleteEvent": ("Ramos apagados", .gray)
        case "ReleaseEvent": ("Lançamentos", .pink)
        case "WatchEvent": ("Estrelas dadas", .yellow)
        case "ForkEvent": ("Cópias (forks)", .brown)
        default: ("Outros", .secondary)
        }
    }

    private var slices: [Slice] {
        Dictionary(grouping: events, by: { Self.kind($0.type).0 })
            .map { Slice(id: $0.key, count: $0.value.count, color: Self.kind($0.value[0].type).1) }
            .sorted { $0.count > $1.count }
    }

    var body: some View {
        let data = slices
        Card {
            VStack(alignment: .leading, spacing: 14) {
                CardTitle(title: "Tipos de atividade", subtitle: "Tipos de eventos recentes do GitHub (até 40).")
                if data.isEmpty {
                    Text("Nenhuma atividade recente.").font(.system(size: 12)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 150, maxHeight: .infinity)
                } else {
                    ZStack {
                        Growing(progress: shown ? 1 : 0) { p in
                        Chart(data) { s in
                            SectorMark(angle: .value("Quantidade", Double(s.count) * p + (s.id == data.first?.id ? 1 - p : 0)),
                                       innerRadius: .ratio(0.62), angularInset: 1.5)
                                .cornerRadius(4)
                                .foregroundStyle(s.color)
                        }
                        .chartLegend(.hidden)
                        }
                        VStack(spacing: 0) {
                            Text("\(events.count)").font(.system(size: 24, weight: .bold, design: .rounded))
                            Text("atividades").font(.system(size: 10.5)).foregroundStyle(.secondary)
                        }
                    }
                    .frame(minHeight: 150, maxHeight: .infinity)
                    VStack(spacing: 5) {
                        ForEach(data) { s in
                            HStack(spacing: 8) {
                                Circle().fill(s.color).frame(width: 9, height: 9)
                                Text(s.id).font(.system(size: 12))
                                Spacer()
                                Text("\(s.count)").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Envio automático

struct AutoPushCard: View {
    let repos: [LocalRepoStatus]
    let shown: Bool

    private struct Status: Identifiable {
        let id: String
        let count: Int
        let tint: Color
    }

    var body: some View {
        let linked = repos.filter { $0.gitHubFullName != nil }
        let enabled = linked.filter(\.autoPush.enabled)
        let attention = enabled.filter { $0.upstream == nil || $0.autoPushNeedsAttention }.count
        let statuses = [
            Status(id: "Ligado", count: enabled.count - attention, tint: Theme.open),
            Status(id: "Atenção", count: attention, tint: .orange),
            Status(id: "Desligado", count: linked.count - enabled.count, tint: .gray)
        ]

        Card {
            VStack(alignment: .leading, spacing: 14) {
                CardTitle(title: "Envio automático", subtitle: "Situação do envio ao GitHub após cada commit.")
                if linked.isEmpty {
                    Text("Nenhum projeto ligado ao GitHub.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 58, maxHeight: .infinity)
                } else {
                    GeometryReader { geometry in
                        Capsule()
                            .fill(Color.primary.opacity(0.07))
                            .overlay(alignment: .leading) {
                                HStack(spacing: 0) {
                                    ForEach(statuses.filter { $0.count > 0 }) { status in
                                        Rectangle()
                                            .fill(status.tint.gradient)
                                            .frame(width: shown ? geometry.size.width * CGFloat(status.count) / CGFloat(linked.count) : 0)
                                    }
                                }
                            }
                            .clipShape(Capsule())
                    }
                    .frame(height: 16)
                    .accessibilityHidden(true)

                    HStack(spacing: 8) {
                        ForEach(statuses) { status in
                            VStack(alignment: .leading, spacing: 3) {
                                CountingText(value: Double(shown ? status.count : 0))
                                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                                HStack(spacing: 5) {
                                    Circle().fill(status.tint).frame(width: 7, height: 7)
                                        .accessibilityHidden(true)
                                    Text(status.id).font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

// MARK: - Mudanças pendentes

struct PendingChangesCard: View {
    let repos: [LocalRepoStatus]
    let shown: Bool

    private struct Part: Identifiable { let id: String; let count: Int; let color: Color }

    private var parts: [Part] {
        let all = repos.flatMap(\.changes)
        let colors: [String: Color] = ["Alterado": .orange, "Novo": Theme.open, "Apagado": Theme.danger, "Renomeado": .blue, "Conflito": .purple]
        return Dictionary(grouping: all, by: { $0.kind.label })
            .map { Part(id: $0.key, count: $0.value.count, color: colors[$0.key] ?? .gray) }
            .sorted { $0.count > $1.count }
    }

    var body: some View {
        let data = parts
        let total = data.map(\.count).reduce(0, +)
        let projects = repos.filter { !$0.changes.isEmpty }.count
        Card {
            VStack(alignment: .leading, spacing: 14) {
                CardTitle(title: "Mudanças não salvas", subtitle: total == 0 ? "Nada esperando: tudo já virou versão."
                          : "\(total) \(total == 1 ? "arquivo" : "arquivos") em \(projects) \(projects == 1 ? "projeto" : "projetos"), por tipo.")
                if total == 0 {
                    HStack {
                        Image(systemName: "checkmark.seal.fill").font(.system(size: 34)).foregroundStyle(Theme.open)
                            .scaleEffect(shown ? 1 : 0.3)
                        Text("Tudo salvo").font(.system(size: 15, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 74, maxHeight: .infinity)
                } else {
                    GeometryReader { geo in
                        HStack(spacing: 2) {
                            ForEach(data) { p in
                                p.color.frame(width: max(4, (geo.size.width - CGFloat(data.count * 2)) * CGFloat(p.count) / CGFloat(total)))
                            }
                        }
                        .frame(width: shown ? geo.size.width : 0, alignment: .leading)
                        .clipShape(Capsule())
                    }
                    .frame(height: 16)
                    VStack(spacing: 5) {
                        ForEach(data) { p in
                            HStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 2).fill(p.color).frame(width: 10, height: 10)
                                Text(p.id).font(.system(size: 12))
                                Spacer()
                                Text("\(p.count)").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

// MARK: - Público × privado e tarefas abertas

struct VisibilityIssuesCard: View {
    let repos: [GHRepo]
    let shown: Bool

    var body: some View {
        let priv = repos.filter(\.isPrivate).count
        let pub = repos.count - priv
        let withIssues = repos.filter { $0.openIssuesCount > 0 }.sorted { $0.openIssuesCount > $1.openIssuesCount }.prefix(5)
        Card {
            VStack(alignment: .leading, spacing: 14) {
                CardTitle(title: "Público × privado", subtitle: "Quem pode ver os seus repositórios.")
                GeometryReader { geo in
                    let w = geo.size.width
                    let ratio = repos.isEmpty ? 0.5 : CGFloat(priv) / CGFloat(repos.count)
                    HStack(spacing: 2) {
                        Theme.closed.frame(width: max(0, (shown ? ratio : 0.5) * w - 1))
                        Theme.open.frame(maxWidth: .infinity)
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 16)
                HStack {
                    Label("\(priv) privados", systemImage: "lock.fill").foregroundStyle(Theme.closed)
                    Spacer()
                    Label("\(pub) públicos", systemImage: "globe").foregroundStyle(Theme.open)
                }
                .font(.system(size: 12, weight: .semibold))

                Divider()
                Text("Tarefas abertas").font(.system(size: 13, weight: .semibold))
                if withIssues.isEmpty {
                    Text("Nenhuma tarefa aberta nos repositórios.").font(.system(size: 12)).foregroundStyle(.secondary)
                } else {
                    Growing(progress: shown ? 1 : 0) { p in
                    Chart(Array(withIssues)) { r in
                        BarMark(x: .value("Abertas", Double(r.openIssuesCount) * p), y: .value("Repositório", r.name))
                            .foregroundStyle(Color.orange.gradient)
                            .cornerRadius(4)
                            .annotation(position: .trailing) {
                                Text("\(r.openIssuesCount)").font(.system(size: 10.5)).foregroundStyle(.secondary)
                            }
                    }
                    .chartXAxis(.hidden)
                    .chartXScale(domain: 0...ChartScale.nice(Double(withIssues.map(\.openIssuesCount).max() ?? 0) * 1.15))
                    }
                    .frame(height: CGFloat(withIssues.count) * 24 + 6)
                }
            }
        }
    }
}


/// Lista em páginas que viram como um letreiro de aeroporto: mostra as linhas que cabem,
/// espera alguns segundos e vira linha por linha, de cima para baixo, revelando a próxima página.
/// Depois da última, volta à primeira. Com o mouse em cima, fica parada.
struct FlipBoard<Item: Identifiable, Row: View>: View {
    let items: [Item]
    var rowHeight: CGFloat = 17
    var spacing: CGFloat = 5
    /// Segundos em cada página.
    var interval: Double = 5.5
    @ViewBuilder let row: (Item, CGFloat) -> Row

    @ViewState private var page = 0
    @ViewState private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let dotsHeight: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            let fitsAll = CGFloat(items.count) * (rowHeight + spacing) - spacing <= geo.size.height
            let usable = fitsAll ? geo.size.height : geo.size.height - dotsHeight - 4
            let perPage = max(1, Int((usable + spacing) / (rowHeight + spacing)))
            let pageCount = max(1, Int((Double(items.count) / Double(perPage)).rounded(.up)))
            let current = min(page, pageCount - 1)

            VStack(alignment: .leading, spacing: spacing) {
                ForEach(0..<perPage, id: \.self) { slot in
                    let index = current * perPage + slot
                    ZStack {
                        if index < items.count {
                            row(items[index], geo.size.width)
                                .id(items[index].id)
                                .transition(reduceMotion ? .opacity : Self.flip)
                        }
                    }
                    .frame(height: rowHeight)
                    .animation(reduceMotion ? .easeInOut(duration: 0.3)
                               : .spring(response: 0.55, dampingFraction: 0.82).delay(Double(slot) * 0.075),
                               value: current)
                }
                if pageCount > 1 {
                    Spacer(minLength: 0)
                    HStack(spacing: 5) {
                        Spacer()
                        ForEach(0..<pageCount, id: \.self) { i in
                            Capsule()
                                .fill(i == current ? Theme.accent : Color.primary.opacity(0.18))
                                .frame(width: i == current ? 14 : 5, height: 5)
                                .onTapGesture { page = i }
                        }
                    }
                    .frame(height: dotsHeight)
                    .animation(.smooth(duration: 0.35), value: current)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Página \(current + 1) de \(pageCount)")
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            .task(id: pageCount) {
                if page >= pageCount { page = 0 }
                guard pageCount > 1 else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(interval))
                    if Task.isCancelled { return }
                    if !hovering { page = (page + 1) % pageCount }
                }
            }
        }
        .onHover { hovering = $0 }
    }

    /// A linha antiga tomba para trás e a nova desce virando, como uma plaqueta do letreiro.
    static var flip: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: FlipEffect(angle: -90), identity: FlipEffect(angle: 0)),
            removal: .modifier(active: FlipEffect(angle: 90), identity: FlipEffect(angle: 0))
        )
    }
}

private struct FlipEffect: ViewModifier {
    let angle: Double

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(angle), axis: (x: 1, y: 0, z: 0), anchor: .center, perspective: 0.55)
            .opacity(angle == 0 ? 1 : 0)
    }
}

/// Dá ao conteúdo um “apareceu” que vira verdadeiro logo depois de ele surgir na tela.
struct GrowOnAppear<Content: View>: View {
    var delay: Double = 0
    @ViewBuilder let content: (Bool) -> Content
    @ViewState private var grown = false

    var body: some View {
        content(grown)
            .onAppear {
                withAnimation(.spring(response: 0.8, dampingFraction: 0.86).delay(delay)) { grown = true }
            }
    }
}
