import SwiftUI
import Charts
import GitArborCore

/// Seção “Alcance” da visão geral: visitas, clones, downloads, de onde as pessoas vieram e
/// as páginas mais vistas. O GitHub só mostra 14 dias e só para quem pode mudar o repositório;
/// o histórico mais longo fica guardado no Mac (ReachStore).
struct RepoReachCard: View {
    @Environment(AppModel.self) private var model
    let repo: GHRepo

    private enum Range: Int, CaseIterable, Identifiable {
        case twoWeeks = 14, month = 30, quarter = 90
        var id: Int { rawValue }
        var label: String { "\(rawValue) dias" }
    }

    @ViewState private var history: ReachHistory?
    @ViewState private var views: GHTrafficViews?
    @ViewState private var clones: GHTrafficClones?
    @ViewState private var referrers: [GHReferrer] = []
    @ViewState private var paths: [GHPopularPath] = []
    @ViewState private var downloads: Int?
    @ViewState private var releaseCount = 0
    @ViewState private var loading = true
    @ViewState private var noAccess = false
    @ViewState private var range: Range = .month

    var body: some View {
        // Sem acesso ao tráfego e sem nada guardado: a seção não aparece (repositório de outra pessoa).
        Group {
        if !(noAccess && history == nil) {
            Card(padding: 18) {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if loading && history == nil {
                        LoadingRow(text: "Lendo o alcance no GitHub…")
                    } else {
                        numbers
                        chart
                        if !referrers.isEmpty || !paths.isEmpty { sources }
                        footer
                    }
                }
            }
        }
        }
        .task(id: repo.id) { await load() }
    }

    // MARK: Partes

    private var header: some View {
        HStack(alignment: .top) {
            HStack(spacing: 6) {
                CardTitle(title: "Alcance", subtitle: "Quantas pessoas viram, copiaram e baixaram este projeto.")
                HelpTip(lessonID: "reach")
            }
            Spacer()
            Picker("Período do gráfico", selection: $range) {
                ForEach(Range.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
    }

    private var numbers: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], alignment: .leading, spacing: 12) {
            ReachNumber(value: views?.count, label: "Visitas", symbol: "eye.fill", tint: Theme.accent,
                        detail: views.map { "\(Phrases.plural($0.uniques, "pessoa", "pessoas")) · 14 dias" } ?? "últimos 14 dias")
            ReachNumber(value: clones?.count, label: "Clones", symbol: "square.on.square.fill", tint: .teal,
                        detail: clones.map { "\(Phrases.plural($0.uniques, "pessoa", "pessoas")) · 14 dias" } ?? "últimos 14 dias")
            ReachNumber(value: downloads, label: "Downloads", symbol: "arrow.down.circle.fill", tint: .pink,
                        detail: releaseCount == 0 ? "nenhuma versão publicada" : "somando \(Phrases.plural(releaseCount, "versão", "versões"))")
            ReachNumber(value: history?.totalViews, label: "Visitas guardadas", symbol: "archivebox.fill", tint: .orange,
                        detail: history?.firstDay.map { "desde \(Self.shortDate($0))" } ?? "histórico neste Mac")
        }
    }

    private var chart: some View {
        let data = (history ?? ReachHistory()).series(lastDays: range.rawValue).map {
            ReachPoint(date: $0.date, views: $0.day.views, clones: $0.day.clones)
        }
        let top = ChartScale.nice(Double(data.map { max($0.views, $0.clones) }.max() ?? 0))
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                legend("Visitas", Theme.accent)
                legend("Clones", .teal)
            }
            if data.allSatisfy({ $0.views == 0 && $0.clones == 0 }) {
                Text("Ainda ninguém visitou ou copiou este projeto no período.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Chart(data) { p in
                    AreaMark(x: .value("Dia", p.date, unit: .day), y: .value("Visitas", p.views), series: .value("Tipo", "Visitas"))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(LinearGradient(colors: [Theme.accent.opacity(0.3), Theme.accent.opacity(0.02)],
                                                        startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Dia", p.date, unit: .day), y: .value("Visitas", p.views), series: .value("Tipo", "Visitas"))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(Theme.accent)
                        .lineStyle(StrokeStyle(lineWidth: 2.2))
                    LineMark(x: .value("Dia", p.date, unit: .day), y: .value("Clones", p.clones), series: .value("Tipo", "Clones"))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(.teal)
                        .lineStyle(StrokeStyle(lineWidth: 2.2, dash: [5, 3]))
                }
                .chartYScale(domain: 0...max(top, 1))
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    }
                }
                .environment(\.locale, Locale(identifier: "pt_BR"))
                .frame(height: 170)
                .accessibilityLabel("Gráfico de visitas e clones por dia nos últimos \(range.rawValue) dias")
            }
        }
    }

    private var sources: some View {
        HStack(alignment: .top, spacing: 20) {
            ReachRanking(title: "De onde vieram", symbol: "point.3.connected.trianglepath.dotted",
                         rows: referrers.prefix(5).map { .init(id: $0.referrer, name: Reach.referrerName($0.referrer), count: $0.count, uniques: $0.uniques) },
                         empty: "Nenhum site trouxe visitas nos últimos 14 dias.")
            ReachRanking(title: "Páginas mais vistas", symbol: "doc.text.magnifyingglass",
                         rows: paths.prefix(5).map { .init(id: $0.path, name: $0.shortPath(repoFullName: repo.fullName), count: $0.count, uniques: $0.uniques) },
                         empty: "Nenhuma página vista nos últimos 14 dias.")
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: noAccess ? "exclamationmark.triangle.fill" : "info.circle")
                .foregroundStyle(noAccess ? .orange : .secondary)
            Text(noAccess
                 ? "Não consegui ler o tráfego agora. Mostrando o que está guardado neste Mac."
                 : "O GitHub mostra só os últimos 14 dias. O Git Arbor guarda neste Mac cada dia que vê, para você acompanhar por mais tempo.")
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func legend(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(.system(size: 11.5, weight: .medium)).foregroundStyle(.secondary)
        }
    }

    private static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "pt_BR")))
    }

    // MARK: Dados

    private func load() async {
        if history == nil { history = await ReachStore.load(repoID: repo.id) }
        guard let client = model.client else { loading = false; return }
        let name = repo.fullName
        async let v = try? client.trafficViews(name)
        async let c = try? client.trafficClones(name)
        async let r = try? client.trafficReferrers(name)
        async let p = try? client.trafficPaths(name)
        async let rel = try? client.releases(name)

        if let releases = await rel {
            releaseCount = releases.count
            downloads = Reach.totalDownloads(releases)
        }
        if let views = await v, let clones = await c {
            self.views = views
            self.clones = clones
            var merged = history ?? ReachHistory()
            merged.merge(views: views.views, clones: clones.clones)
            history = merged
            ReachStore.save(merged, repoID: repo.id)
            noAccess = false
        } else {
            noAccess = true
        }
        referrers = await r ?? []
        paths = await p ?? []
        loading = false
    }
}

private struct ReachPoint: Identifiable {
    let date: Date
    let views: Int
    let clones: Int
    var id: Date { date }
}

/// Número do alcance: ícone, valor grande, rótulo e detalhe.
private struct ReachNumber: View {
    let value: Int?
    let label: String
    let symbol: String
    let tint: Color
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            IconTile(symbol: symbol, tint: tint, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(value.map { $0.formatted(.number.locale(Locale(identifier: "pt_BR"))) } ?? "—")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text(label).font(.system(size: 12, weight: .semibold))
                Text(detail).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Lista curta com barras proporcionais (sites de origem, páginas mais vistas).
private struct ReachRanking: View {
    struct Row: Identifiable { let id: String; let name: String; let count: Int; let uniques: Int }
    let title: String
    let symbol: String
    let rows: [Row]
    let empty: String

    var body: some View {
        let top = Double(rows.map(\.count).max() ?? 1)
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol).font(.system(size: 12.5, weight: .semibold))
            if rows.isEmpty {
                Text(empty).font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(row.name).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 8)
                        Text("\(row.count)").font(.system(size: 12, weight: .semibold, design: .rounded))
                        Text("· \(Phrases.plural(row.uniques, "pessoa", "pessoas"))").font(.system(size: 10.5)).foregroundStyle(.secondary)
                    }
                    GeometryReader { geo in
                        Capsule().fill(Theme.accent.opacity(0.55))
                            .frame(width: max(3, geo.size.width * Double(row.count) / max(top, 1)))
                    }
                    .frame(height: 4)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
