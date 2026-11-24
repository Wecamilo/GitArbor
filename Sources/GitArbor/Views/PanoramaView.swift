import Charts
import GitArborCore
import SwiftUI

/// Panorama: só imagens. Anéis de saúde, ritmo das semanas, linguagens, o mapa dos projetos
/// no Mac e a linha do tempo do que aconteceu, tudo animado ao abrir.
struct PanoramaView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ScreenHeader(title: "Panorama", subtitle: "Como vão os seus projetos, em imagens.",
                             symbol: "chart.pie.fill", tint: .teal)

                Reveal { rings($0) }

                PanoramaCardPair(side: .trailing) {
                    Reveal { WeeklyRhythmCard(calendar: model.calendar, shown: $0) }
                    Reveal { LanguagesCard(repos: model.repos, bytes: model.languageBytes, shown: $0) }
                }

                PanoramaCardPair(side: .leading) {
                    Reveal { StreakCard(calendar: model.calendar, shown: $0) }
                    Reveal { CodeTideCard(weeks: model.codeWeeks, loading: model.isLoadingPanorama, shown: $0) }
                }

                Reveal { ProjectsMapCard(repos: model.localRepos, shown: $0) }

                PanoramaCardPair {
                    Reveal { AutoPushCard(repos: model.localRepos, shown: $0) }
                    Reveal { PendingChangesCard(repos: model.localRepos, shown: $0) }
                }

                LeadingHeightPair {
                    Reveal { WorkClockCard(events: model.events, shown: $0) }
                    Reveal { ThermometerCard(repos: model.repos, shown: $0) }
                }

                Reveal { SizeMapCard(repos: model.repos, shown: $0) }

                PanoramaCardPair(side: .trailing) {
                    Reveal { TimelineCard(events: model.events, shown: $0) }
                    Reveal { WeekdayCard(calendar: model.calendar, shown: $0) }
                }

                PanoramaCardPair(side: .trailing) {
                    Reveal { GrowthCard(repos: model.repos, since: model.user?.createdAt, shown: $0) }
                    Reveal { ActivityTypesCard(events: model.events, shown: $0) }
                }

                Reveal { VisibilityIssuesCard(repos: model.repos, shown: $0) }
            }
            .padding(28)
            .frame(maxWidth: 1200)
            .frame(maxWidth: .infinity)
        }
        .task(id: model.repos.map(\.fullName).sorted()) { await model.loadPanoramaExtras() }
    }

    // MARK: Anéis

    private func rings(_ shown: Bool) -> some View {
        let local = model.localRepos
        let clean = local.filter { $0.state == .clean }.count
        let protected = local.filter(\.protected).count
        let activeDays = Self.lastDays(model.calendar, 30).filter { $0.contributionCount > 0 }.count
        let fresh = model.repos.filter { ($0.lastActivity ?? .distantPast) > Date().addingTimeInterval(-30 * 86_400) }.count

        return HStack(spacing: 16) {
            RingTile(value: local.isEmpty ? 0 : Double(clean) / Double(local.count), shown: shown, tint: Theme.open,
                     title: "Em dia", detail: "\(clean) de \(local.count) projetos iguais ao GitHub", symbol: "checkmark")
            RingTile(value: Double(activeDays) / 30, shown: shown, tint: Theme.accent,
                     title: "Dias ativos", detail: "\(activeDays) dos últimos 30 dias com trabalho", symbol: "flame.fill")
            RingTile(value: local.isEmpty ? 0 : Double(protected) / Double(local.count), shown: shown, tint: .indigo,
                     title: "Protegidos", detail: "\(protected) de \(local.count) com a lista de arquivos sensíveis", symbol: "lock.shield.fill")
            RingTile(value: model.repos.isEmpty ? 0 : Double(fresh) / Double(model.repos.count), shown: shown, tint: .orange,
                     title: "Mexidos no mês", detail: "\(fresh) de \(model.repos.count) repositórios mudaram em 30 dias", symbol: "sparkles")
        }
    }

    static func days(_ calendar: ContributionCalendar?) -> [ContributionCalendar.Day] {
        calendar?.weeks.flatMap(\.contributionDays) ?? []
    }

    static func lastDays(_ calendar: ContributionCalendar?, _ n: Int) -> [ContributionCalendar.Day] {
        Array(days(calendar).suffix(n))
    }

    static let dayParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

/// Monta o cartão quando ele entra na tela ao rolar (sobe um pouco, aparece e os gráficos de
/// dentro crescem) e desmonta quando ele sai — nas duas direções. Voltando a rolar, monta de novo.
private struct Reveal<Content: View>: View {
    @ViewBuilder var content: (Bool) -> Content
    @ViewState private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content(shown)
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 10)
            .onScrollVisibilityChange(threshold: 0.12) { visible in
                guard visible != shown else { return }
                // Movimento curto e sem quique: o cartão só desliza um pouco e aparece.
                let animation: Animation = reduceMotion ? .easeOut(duration: 0.2)
                    : visible ? .smooth(duration: 0.6)
                    : .easeOut(duration: 0.3)
                withAnimation(animation) { shown = visible }
            }
    }
}

/// Dois cartões lado a lado com a altura do primeiro (o Relógio de trabalho, de largura fixa).
/// O segundo (Termômetro) se ajusta a essa altura e rola sozinho se não couber.
private struct LeadingHeightPair: Layout {
    private let spacing: CGFloat = 16
    private let leadingWidth: CGFloat = 340

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 900
        let height = subviews[0].sizeThatFits(.init(width: min(leadingWidth, width), height: nil)).height
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let left = min(leadingWidth, bounds.width)
        let right = max(0, bounds.width - left - spacing)
        subviews[0].place(at: bounds.origin, anchor: .topLeading, proposal: .init(width: left, height: bounds.height))
        subviews[1].place(at: CGPoint(x: bounds.minX + left + spacing, y: bounds.minY), anchor: .topLeading,
                          proposal: .init(width: right, height: bounds.height))
    }
}

/// Mede os dois cards com suas larguras reais e propõe a altura do maior para ambos.
private struct PanoramaCardPair: Layout {
    var side: HorizontalEdge? = nil
    private let spacing: CGFloat = 16
    private let sideWidth: CGFloat = 340

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? (subviews[0].sizeThatFits(.unspecified).width
                                       + subviews[1].sizeThatFits(.unspecified).width + spacing)
        let (left, right) = widths(for: width)
        let height = max(subviews[0].sizeThatFits(.init(width: left, height: nil)).height,
                         subviews[1].sizeThatFits(.init(width: right, height: nil)).height)
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (left, right) = widths(for: bounds.width)
        subviews[0].place(at: bounds.origin, anchor: .topLeading, proposal: .init(width: left, height: bounds.height))
        subviews[1].place(at: CGPoint(x: bounds.minX + left + spacing, y: bounds.minY), anchor: .topLeading,
                          proposal: .init(width: right, height: bounds.height))
    }

    private func widths(for width: CGFloat) -> (CGFloat, CGFloat) {
        let available = max(0, width - spacing)
        guard let side else { return (available / 2, available / 2) }
        let narrow = min(sideWidth, available * 0.46)
        let wide = available - narrow
        return side == .leading ? (narrow, wide) : (wide, narrow)
    }
}

// MARK: - Anel

private struct RingTile: View {
    let value: Double
    let shown: Bool
    let tint: Color
    let title: String
    let detail: String
    let symbol: String

    var body: some View {
        Card {
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(tint.opacity(0.14), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: shown ? max(0.001, value) : 0.001)
                        .stroke(AngularGradient(colors: [tint.opacity(0.55), tint], center: .center),
                                style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Image(systemName: symbol).font(.system(size: 11, weight: .bold)).foregroundStyle(tint)
                        CountingText(value: (shown ? value : 0) * 100, suffix: "%")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                    }
                }
                .frame(width: 70, height: 70)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 14, weight: .semibold))
                    Text(detail).font(.system(size: 11.5)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(Int(value * 100)) por cento. \(detail)")
    }
}

struct CardTitle: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(subtitle).font(.system(size: 11.5)).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Ritmo das semanas

private struct WeeklyRhythmCard: View {
    let calendar: ContributionCalendar?
    let shown: Bool

    fileprivate struct Week: Identifiable { let id: Int; let start: Date; let count: Int }

    private var weeks: [Week] {
        let all = calendar?.weeks.suffix(17) ?? []
        return all.enumerated().compactMap { i, w in
            guard let first = w.contributionDays.first, let date = PanoramaView.dayParser.date(from: first.date) else { return nil }
            return Week(id: i, start: date, count: w.contributionDays.map(\.contributionCount).reduce(0, +))
        }
    }

    var body: some View {
        let data = weeks
        let average = data.isEmpty ? 0 : Double(data.map(\.count).reduce(0, +)) / Double(data.count)
        let best = data.max { $0.count < $1.count }
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    CardTitle(title: "Ritmo das semanas", subtitle: "Contribuições por semana nos últimos 4 meses.")
                    Spacer()
                    if let best, best.count > 0 {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("\(best.count)").font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(Theme.accent)
                            Text("melhor semana").font(.system(size: 10.5)).foregroundStyle(.secondary)
                        }
                    }
                }
                if data.isEmpty {
                    Text("Sem dados de contribuições ainda.").font(.system(size: 12)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 180, maxHeight: .infinity)
                } else {
                    WeeklyBars(weeks: data, average: average, shown: shown)
                        .frame(minHeight: 190, maxHeight: .infinity)
                }
            }
        }
    }
}

/// Gráfico de barras desenhado à mão (sem Swift Charts): grade e eixos ficam parados e cada
/// barra cresce de baixo para cima com uma mola, uma depois da outra. Como cada barra é só uma
/// forma com escala animada, nenhuma atualização da tela interrompe o crescimento.
private struct WeeklyBars: View {
    let weeks: [WeeklyRhythmCard.Week]
    let average: Double
    let shown: Bool
    @ViewState private var hovered: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let axisWidth: CGFloat = 30
    private let monthsHeight: CGFloat = 20

    private var top: Double { ChartScale.nice(max(Double(weeks.map(\.count).max() ?? 0), average)) }
    private var ticks: [Double] { (0...4).map { top * Double($0) / 4 } }

    private static let monthFormat = Date.FormatStyle.dateTime.month(.abbreviated).locale(Locale(identifier: "pt_BR"))
    private static let dayFormat = Date.FormatStyle.dateTime.day().month(.abbreviated).locale(Locale(identifier: "pt_BR"))

    var body: some View {
        GeometryReader { geo in
            let plotWidth = max(0, geo.size.width - axisWidth - 8)
            let plotHeight = max(0, geo.size.height - monthsHeight)
            let slot = weeks.isEmpty ? 0 : plotWidth / CGFloat(weeks.count)
            let barWidth = max(2, slot * 0.68)

            ZStack(alignment: .topLeading) {
                // Grade e números do eixo (parados).
                ForEach(ticks, id: \.self) { value in
                    let y = plotHeight * (1 - CGFloat(value / top))
                    Rectangle().fill(Color.primary.opacity(value == 0 ? 0.16 : 0.07))
                        .frame(width: plotWidth, height: 1)
                        .offset(y: y)
                    Text(value.formatted(.number.precision(.fractionLength(0))))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                        .frame(width: axisWidth, alignment: .leading)
                        .offset(x: plotWidth + 8, y: y - 6)
                }

                // Barras.
                ForEach(Array(weeks.enumerated()), id: \.element.id) { index, week in
                    let height = plotHeight * CGFloat(Double(week.count) / top)
                    UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4, style: .continuous)
                        .fill(LinearGradient(colors: [Theme.accentLight, Theme.accent], startPoint: .top, endPoint: .bottom))
                        .opacity(hovered == nil || hovered == index ? 1 : 0.55)
                        .frame(width: barWidth, height: max(0, height))
                        .scaleEffect(x: 1, y: shown ? 1 : 0.001, anchor: .bottom)
                        .animation(reduceMotion ? .easeOut(duration: 0.2)
                                   : .smooth(duration: 0.7).delay(Double(index) * 0.02),
                                   value: shown)
                        .offset(x: slot * CGFloat(index) + (slot - barWidth) / 2, y: plotHeight - height)
                        .onHover { inside in
                            if inside { hovered = index } else if hovered == index { hovered = nil }
                        }
                        .help("Semana de \(week.start.formatted(Self.dayFormat)): \(Phrases.plural(week.count, "contribuição", "contribuições"))")
                }

                // Linha da média: desenha-se da esquerda para a direita.
                if average > 0 {
                    let y = plotHeight * (1 - CGFloat(average / top))
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: plotWidth, y: y))
                    }
                    .trim(from: 0, to: shown ? 1 : 0)
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.9).delay(0.25), value: shown)
                    Text("média \(Int(average.rounded()))")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(.orange)
                        .offset(y: y - 16)
                        .opacity(shown ? 1 : 0)
                        .animation(.easeOut(duration: 0.4).delay(0.6), value: shown)
                }

                // Valor da barra sob o mouse.
                if let hovered, weeks.indices.contains(hovered) {
                    let week = weeks[hovered]
                    let height = plotHeight * CGFloat(Double(week.count) / top)
                    Text("\(week.count)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.accent)
                        .frame(width: max(slot, 30))
                        .offset(x: slot * CGFloat(hovered) + slot / 2 - max(slot, 30) / 2, y: plotHeight - height - 16)
                        .allowsHitTesting(false)
                }

                // Meses, embaixo da primeira semana de cada um.
                ForEach(Array(weeks.enumerated()), id: \.element.id) { index, week in
                    if index > 0, Calendar.current.component(.month, from: week.start) != Calendar.current.component(.month, from: weeks[index - 1].start) {
                        Text(week.start.formatted(Self.monthFormat))
                            .font(.system(size: 10.5)).foregroundStyle(.secondary)
                            .fixedSize()
                            .offset(x: slot * CGFloat(index), y: plotHeight + 5)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ritmo das semanas")
        .accessibilityValue(weeks.map { "\($0.start.formatted(Self.dayFormat)): \($0.count)" }.joined(separator: ", "))
    }
}

// MARK: - Linguagens

private struct LanguagesCard: View {
    let repos: [GHRepo]
    let bytes: [String: Int]
    let shown: Bool
    @ViewState private var byCode = false

    private struct Slice: Identifiable { let id: String; let count: Int }

    private var slices: [Slice] {
        let grouped = (byCode && !bytes.isEmpty
            ? bytes.map { Slice(id: $0.key, count: $0.value) }
            : Dictionary(grouping: repos, by: { $0.language ?? "Outras" }).map { Slice(id: $0.key, count: $0.value.count) })
            .sorted { $0.count > $1.count }
        guard grouped.count > 6 else { return grouped }
        let rest = grouped.dropFirst(5).map(\.count).reduce(0, +)
        return Array(grouped.prefix(5)) + [Slice(id: "Outras", count: rest)]
    }

    var body: some View {
        let data = slices
        Card {
            VStack(alignment: .leading, spacing: 14) {
                CardTitle(title: "Linguagens", subtitle: byCode ? "Quanto código há em cada linguagem, somando tudo." : "A linguagem principal de cada repositório.")
                // As pílulas ficam sempre no lugar (só ativas quando o tamanho do código chega):
                // se aparecessem depois, o cartão cresceria e o Ritmo das semanas, ao lado,
                // daria um salto no meio da animação.
                ViewThatFits(in: .horizontal) {
                    countFilters(repository: "Por repositório", code: "Por código")
                    countFilters(repository: "Repositórios", code: "Código")
                }
                .disabled(bytes.isEmpty)
                .opacity(bytes.isEmpty ? 0.45 : 1)
                .animation(.easeOut(duration: 0.25), value: bytes.isEmpty)
                .help(bytes.isEmpty ? "Somando o código de cada repositório…" : "")
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Contagem de linguagens")
                ZStack {
                    Growing(progress: shown ? 1 : 0) { p in
                    Chart(data) { s in
                        SectorMark(angle: .value("Repositórios", Double(s.count) * p + (s.id == data.first?.id ? 1 - p : 0)),
                                   innerRadius: .ratio(0.62), angularInset: 1.5)
                            .cornerRadius(4)
                            .foregroundStyle(s.id == "Outras" ? Color.gray.opacity(0.5) : Color.language(s.id))
                    }
                    .chartLegend(.hidden)
                    }
                    VStack(spacing: 0) {
                        if byCode && !bytes.isEmpty {
                            Text(ByteCountFormatter.string(fromByteCount: Int64(bytes.values.reduce(0, +)), countStyle: .file))
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                            Text("de código").font(.system(size: 10.5)).foregroundStyle(.secondary)
                        } else {
                            Text("\(repos.count)").font(.system(size: 24, weight: .bold, design: .rounded))
                            Text("repositórios").font(.system(size: 10.5)).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(height: 150)
                VStack(spacing: 5) {
                    ForEach(data) { s in
                        HStack(spacing: 8) {
                            Circle().fill(s.id == "Outras" ? Color.gray.opacity(0.5) : Color.language(s.id)).frame(width: 9, height: 9)
                            Text(s.id).font(.system(size: 12))
                            Spacer()
                            Text(label(s, of: data)).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func countFilters(repository: String, code: String) -> some View {
        FilterChips(selection: $byCode, options: [
            ChipOption(value: false, title: repository, symbol: "shippingbox"),
            ChipOption(value: true, title: code, symbol: "chevron.left.forwardslash.chevron.right")
        ])
    }

    private func label(_ s: Slice, of all: [Slice]) -> String {
        guard byCode && !bytes.isEmpty else { return "\(s.count)" }
        let total = max(1, all.map(\.count).reduce(0, +))
        let pct = Double(s.count) / Double(total) * 100
        return pct < 1 ? "<1%" : "\(Int(pct.rounded()))%"
    }
}

// MARK: - Mapa dos projetos no Mac

private struct ProjectsMapCard: View {
    let repos: [LocalRepoStatus]
    let shown: Bool

    private var states: [(LocalRepoStatus.State, Int)] {
        let order: [LocalRepoStatus.State] = [.clean, .unsaved, .toSend, .toReceive, .diverged, .conflict, .noUpstream, .noRemote]
        return order.compactMap { s in
            let n = repos.filter { $0.state == s }.count
            return n > 0 ? (s, n) : nil
        }
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                CardTitle(title: "Mapa dos projetos no Mac",
                          subtitle: "Cada bolha é um projeto: a cor mostra como ele está, o tamanho mostra quanto mudou. As que pulsam pedem atenção.")
                if repos.isEmpty {
                    Text("Nenhum projeto encontrado na pasta escolhida.").font(.system(size: 12)).foregroundStyle(.secondary)
                } else {
                    // Barra empilhada com a proporção de cada situação.
                    GeometryReader { geo in
                        HStack(spacing: 2) {
                            ForEach(states, id: \.0) { s, n in
                                LocalStateBadge.tint(s)
                                    .frame(width: max(4, (geo.size.width - CGFloat(states.count * 2)) * CGFloat(n) / CGFloat(repos.count)))
                            }
                        }
                        .frame(width: shown ? geo.size.width : 0, alignment: .leading)
                        .clipShape(Capsule())
                    }
                    .frame(height: 10)

                    FlowBubbles(repos: repos, shown: shown)

                    HStack(spacing: 14) {
                        ForEach(states, id: \.0) { s, n in
                            HStack(spacing: 5) {
                                Circle().fill(LocalStateBadge.tint(s)).frame(width: 8, height: 8)
                                Text("\(LocalStateBadge.title(s)) · \(n)").font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct FlowBubbles: View {
    let repos: [LocalRepoStatus]
    let shown: Bool

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
            ForEach(Array(repos.sorted { weight($0) > weight($1) }.enumerated()), id: \.element.id) { i, repo in
                Bubble(repo: repo, size: size(repo), shown: shown, delay: Double(i) * 0.035)
            }
        }
    }

    private func weight(_ r: LocalRepoStatus) -> Int { r.changes.count + r.ahead + r.behind }

    private func size(_ r: LocalRepoStatus) -> CGFloat {
        let w = Double(weight(r))
        return 34 + CGFloat(min(1, log2(w + 1) / 6)) * 40
    }
}

private struct Bubble: View {
    let repo: LocalRepoStatus
    let size: CGFloat
    let shown: Bool
    let delay: Double
    @ViewState private var pulse = false

    private var needsAttention: Bool { ![.clean, .noRemote].contains(repo.state) }
    private var tint: Color { LocalStateBadge.tint(repo.state) }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                if needsAttention {
                    Circle().stroke(tint.opacity(0.5), lineWidth: 2)
                        .frame(width: size, height: size)
                        .scaleEffect(pulse ? 1.35 : 1)
                        .opacity(pulse ? 0 : 0.8)
                }
                Circle()
                    .fill(RadialGradient(colors: [tint.opacity(0.75), tint], center: .topLeading, startRadius: 0, endRadius: size))
                    .frame(width: size, height: size)
                    .shadow(color: tint.opacity(0.35), radius: 6, y: 3)
                Image(systemName: LocalStateBadge.symbol(repo.state))
                    .font(.system(size: size * 0.32, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 80, height: 80)
            .scaleEffect(shown ? 1 : 0.2)
            .opacity(shown ? 1 : 0)
            .animation(.spring(response: 0.6, dampingFraction: 0.6).delay(delay), value: shown)
            Text(repo.name).font(.system(size: 11, weight: .medium)).lineLimit(1).truncationMode(.middle)
        }
        .help("\(repo.name): \(LocalStateBadge.title(repo.state))")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(repo.name): \(LocalStateBadge.title(repo.state))")
        .onAppear {
            guard needsAttention else { return }
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}

// MARK: - Linha do tempo

private struct TimelineCard: View {
    let events: [GHEvent]
    let shown: Bool

    private struct Point: Identifiable { let id: String; let date: Date; let repo: String; let size: Int }

    private var points: [Point] {
        let since = Date().addingTimeInterval(-30 * 86_400)
        let recent = events.filter { $0.createdAt > since }
        let topRepos = Dictionary(grouping: recent, by: { short($0.repo.name) })
            .sorted { $0.value.count > $1.value.count }.prefix(7).map(\.key)
        return recent.filter { topRepos.contains(short($0.repo.name)) }
            .map { Point(id: $0.id, date: $0.createdAt, repo: short($0.repo.name), size: max(1, $0.payload.size ?? $0.payload.commits?.count ?? 1)) }
    }

    private func short(_ name: String) -> String { name.split(separator: "/").last.map(String.init) ?? name }

    var body: some View {
        let data = points
        Card {
            VStack(alignment: .leading, spacing: 14) {
                CardTitle(title: "Linha do tempo", subtitle: "O que aconteceu em cada repositório nos últimos 30 dias. Bolinhas maiores têm mais versões.")
                if data.isEmpty {
                    Text("Nada aconteceu no GitHub nos últimos 30 dias.").font(.system(size: 12)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 160, maxHeight: .infinity)
                } else {
                    Chart(data) { p in
                        PointMark(x: .value("Dia", p.date), y: .value("Repositório", p.repo))
                            .symbolSize(shown ? CGFloat(40 + min(p.size, 10) * 25) : 0)
                            .foregroundStyle(by: .value("Repositório", p.repo))
                            .opacity(0.8)
                    }
                    .chartLegend(.hidden)
                    .chartXScale(domain: Date().addingTimeInterval(-30 * 86_400)...Date())
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                        }
                    }
                    .frame(minHeight: CGFloat(max(3, Set(data.map(\.repo)).count)) * 34 + 30, maxHeight: .infinity)
                }
            }
        }
    }
}

// MARK: - Dia da semana

private struct WeekdayCard: View {
    let calendar: ContributionCalendar?
    let shown: Bool
    @Environment(\.colorScheme) private var scheme

    private static let names = ["Dom", "Seg", "Ter", "Qua", "Qui", "Sex", "Sáb"]
    private static let fullNames = ["aos domingos", "às segundas", "às terças", "às quartas", "às quintas", "às sextas", "aos sábados"]

    private struct Day: Identifiable { let id: Int; let total: Int }

    private var data: [Day] {
        let days = PanoramaView.days(calendar)
        return (0..<7).map { wd in Day(id: wd, total: days.filter { $0.weekday == wd }.map(\.contributionCount).reduce(0, +)) }
    }

    var body: some View {
        let d = data
        let best = d.filter { $0.total > 0 }.max { $0.total < $1.total }
        let subtitle = best.map { "Você trabalha mais \(Self.fullNames[$0.id])." } ?? "Ainda sem contribuições no ano."
        Card {
            VStack(alignment: .leading, spacing: 14) {
                CardTitle(title: "Seu dia mais ativo", subtitle: subtitle)
                Growing(progress: shown ? 1 : 0) { p in
                Chart(d) { day in
                    BarMark(x: .value("Total", Double(day.total) * p), y: .value("Dia", Self.names[day.id]))
                        .foregroundStyle(day.id == best?.id ? Theme.accent : Theme.accent.opacity(scheme == .dark ? 0.55 : 0.35))
                        .cornerRadius(4)
                        .annotation(position: .trailing) {
                            Text("\(day.total)").font(.system(size: 10.5)).foregroundStyle(.secondary)
                        }
                }
                .chartXAxis(.hidden)
                .chartYScale(domain: Self.names)
                .chartXScale(domain: 0...ChartScale.nice(Double(d.map(\.total).max() ?? 0) * 1.12))
                }
                .frame(minHeight: 200, maxHeight: .infinity)
            }
        }
    }
}
