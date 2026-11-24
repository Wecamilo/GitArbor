import Foundation

/// Explicações simples dos conceitos do Git e do GitHub, usadas na aba Aprender
/// e nos botões “?” espalhados pelo app.
public struct Lesson: Sendable, Hashable, Identifiable {
    public enum Diagram: Sendable, Hashable {
        case repository, commits, sync, branches, pullRequest, merge, issues, clone, release, actions, none
    }

    public let id: String
    public let title: String
    /// Nome em inglês, como aparece no site do GitHub.
    public let term: String
    public let symbol: String
    public let summary: String
    public let explanation: String
    public let analogy: String
    public let diagram: Diagram
}

public enum Glossary {
    public static let lessons: [Lesson] = [
        Lesson(id: "repository", title: "Repositório", term: "Repository", symbol: "shippingbox.fill",
               summary: "A pasta de um projeto, com memória de tudo o que já mudou.",
               explanation: "Um repositório guarda os arquivos de um projeto e todo o histórico de mudanças. Ele pode existir no seu Mac (local) e no GitHub (na nuvem). Os dois ficam sincronizados quando você envia e baixa as mudanças.",
               analogy: "É como uma pasta que tira fotos de si mesma sempre que você pede — e guarda todas as fotos.",
               diagram: .repository),
        Lesson(id: "commit", title: "Salvar uma versão", term: "Commit", symbol: "camera.fill",
               summary: "Uma “foto” do projeto num momento, com uma frase dizendo o que mudou.",
               explanation: "Cada commit registra exatamente quais arquivos mudaram e quem mudou. Em conjunto, os commits formam o histórico do projeto: dá para ver, comparar ou voltar a qualquer um deles.",
               analogy: "É o “salvar como versão” de um documento: cada foto tem data, autor e legenda.",
               diagram: .commits),
        Lesson(id: "push", title: "Enviar e baixar", term: "Push / Pull", symbol: "arrow.up.arrow.down.circle.fill",
               summary: "Enviar (push) manda suas versões para o GitHub. Baixar (pull) traz as de lá.",
               explanation: "Quando você salva (commit), a versão fica só no Mac. Para guardar na nuvem, é preciso enviar (push). Se algo mudou no GitHub — por outro computador ou alguém da equipe — você baixa (pull) para o Mac ficar igual.",
               analogy: "Como sincronizar fotos com o iCloud: tirar a foto é o commit; subir para a nuvem é o push.",
               diagram: .sync),
        Lesson(id: "autopush", title: "Envio automático", term: "post-commit hook", symbol: "bolt.horizontal.circle.fill",
               summary: "Depois de cada versão salva (commit), o projeto se envia sozinho ao GitHub.",
               explanation: "Um “hook” é um pequeno roteiro que o Git roda sozinho em certos momentos. O hook post-commit roda logo depois de cada commit; o do Git Arbor faz o push em segundo plano e anota o resultado. Se a internet cair, o próximo commit envia tudo o que ficou pendente.",
               analogy: "Como o iCloud de fotos: tirou a foto, ela já sobe para a nuvem sem você pedir.",
               diagram: .sync),
        Lesson(id: "branch", title: "Ramo", term: "Branch", symbol: "arrow.triangle.branch",
               summary: "Um caminho paralelo para experimentar sem mexer na versão principal.",
               explanation: "O ramo principal (geralmente “main”) é a versão oficial. Ao criar um ramo, você trabalha numa cópia do histórico; se der certo, junta de volta no principal. Se não der, é só apagar o ramo.",
               analogy: "Como os galhos de uma árvore: saem do tronco, crescem separados e podem voltar a se juntar.",
               diagram: .branches),
        Lesson(id: "pullRequest", title: "Pedido de mudança", term: "Pull request", symbol: "arrow.triangle.pull",
               summary: "Um pedido para juntar um ramo no principal, com espaço para revisar.",
               explanation: "O pull request mostra tudo o que mudou num ramo e permite comentar antes de aceitar. Quando aprovado, você faz o “merge”: as mudanças entram no ramo principal.",
               analogy: "É como enviar um documento com controle de alterações para alguém aprovar.",
               diagram: .pullRequest),
        Lesson(id: "merge", title: "Juntar", term: "Merge", symbol: "arrow.triangle.merge",
               summary: "Unir as mudanças de um ramo em outro.",
               explanation: "O merge pega os commits de um ramo e os aplica em outro. Se as mesmas linhas foram mudadas nos dois lados, aparece um conflito, e é preciso escolher qual versão fica.",
               analogy: "Dois galhos que voltam a virar um só tronco.",
               diagram: .merge),
        Lesson(id: "conflict", title: "Conflito", term: "Merge conflict", symbol: "exclamationmark.triangle.fill",
               summary: "Quando a mesma parte de um arquivo mudou nos dois lados e o Git não sabe qual fica.",
               explanation: "Ao juntar dois ramos (ou baixar do GitHub algo que também mudou no Mac), o Git junta sozinho tudo o que não se sobrepõe. Se as mesmas linhas foram mudadas dos dois lados, ele para e marca o trecho no arquivo. Você escolhe: a sua versão, a outra ou as duas. Nada se perde enquanto você decide — e dá para desistir e voltar como estava.",
               analogy: "Duas pessoas editaram a mesma frase do mesmo documento: alguém precisa decidir qual frase fica.",
               diagram: .merge),
        Lesson(id: "timeline", title: "Voltar no tempo", term: "Revert / Restore", symbol: "clock.arrow.circlepath",
               summary: "Desfazer uma versão salva, ou deixar o projeto como estava num momento anterior.",
               explanation: "Cada versão salva fica guardada para sempre. “Desfazer esta versão” (revert) cria uma versão nova que faz o contrário daquela — o histórico não é apagado, então é seguro mesmo depois de enviar. “Voltar o projeto para cá” deixa todos os arquivos como estavam naquele momento, também como uma versão nova. Já “desfazer a última versão” só existe enquanto ela não foi enviada: as mudanças voltam a ficar não salvas.",
               analogy: "Como o histórico de versões de um documento: você volta a uma versão antiga sem jogar fora as outras.",
               diagram: .commits),
        Lesson(id: "stash", title: "Guardar para depois", term: "Stash", symbol: "tray.and.arrow.down.fill",
               summary: "Tira as mudanças não salvas da pasta e guarda numa gaveta, para trazer de volta depois.",
               explanation: "Às vezes você precisa da pasta limpa — para baixar novidades ou trocar de ramo — mas ainda não quer salvar uma versão. O stash guarda as mudanças (inclusive arquivos novos) e deixa a pasta como na última versão. Quando quiser, traga de volta.",
               analogy: "Tirar os papéis da mesa e guardar na gaveta para usar a mesa para outra coisa.",
               diagram: .none),
        Lesson(id: "security", title: "Alertas de segurança", term: "Dependabot", symbol: "shield.lefthalf.filled",
               summary: "Avisos do GitHub quando uma biblioteca que o projeto usa tem uma falha conhecida.",
               explanation: "Projetos usam pacotes feitos por outras pessoas (dependências). Quando alguém descobre uma falha num deles, o GitHub avisa os projetos que usam aquela versão e, se quiser, abre sozinho um pedido de mudança para atualizar. Também vale conferir se nenhuma senha ou chave foi parar no histórico.",
               analogy: "Um recall: o fabricante avisa que uma peça tem defeito e indica a troca.",
               diagram: .none),
        Lesson(id: "issue", title: "Tarefa", term: "Issue", symbol: "smallcircle.filled.circle",
               summary: "Uma anotação de problema, ideia ou tarefa do projeto.",
               explanation: "Issues funcionam como uma lista de afazeres do repositório. Cada uma tem título, descrição, comentários e pode ser fechada quando resolvida.",
               analogy: "Post-its no quadro do projeto: abertos (a fazer) e fechados (feitos).",
               diagram: .issues),
        Lesson(id: "clone", title: "Clonar", term: "Clone", symbol: "square.and.arrow.down.on.square.fill",
               summary: "Baixar um repositório inteiro do GitHub para o Mac, com histórico.",
               explanation: "Clonar cria no seu Mac uma pasta ligada ao repositório do GitHub. A partir daí você pode editar, salvar versões e enviar de volta.",
               analogy: "É como baixar um álbum completo, já ligado à nuvem para sincronizar.",
               diagram: .clone),
        Lesson(id: "release", title: "Versão publicada", term: "Release / Tag", symbol: "tag.fill",
               summary: "Um marco do projeto, como “1.0”, com notas do que mudou.",
               explanation: "Uma tag marca um commit específico com um nome. A release usa essa tag para publicar uma versão com notas e, se quiser, arquivos para baixar.",
               analogy: "A edição oficial de um livro: “2ª edição, revisada”.",
               diagram: .release),
        Lesson(id: "reach", title: "Alcance", term: "Insights / Traffic", symbol: "chart.line.uptrend.xyaxis",
               summary: "Quantas pessoas visitaram, copiaram (clone) e baixaram o seu projeto.",
               explanation: "O GitHub conta as visitas à página do repositório, as cópias feitas com clone e os downloads dos arquivos das versões publicadas. Ele mostra também de onde as pessoas vieram (Google, outro site, o próprio GitHub). Visitas e clones ficam disponíveis só por 14 dias e só para quem pode mudar o repositório; por isso o Git Arbor guarda cada dia no seu Mac. “Pessoas” conta cada visitante uma vez, mesmo que ele volte várias vezes.",
               analogy: "É o contador de público de uma vitrine: quantos pararam para olhar, quantos levaram um folheto e de que rua vieram.",
               diagram: .none),
        Lesson(id: "actions", title: "Automações", term: "Actions", symbol: "gearshape.2.fill",
               summary: "Tarefas que o GitHub roda sozinho, como testar o código a cada envio.",
               explanation: "As Actions são robôs configurados no repositório. Elas podem testar, compilar ou publicar o projeto automaticamente. Verde quer dizer que deu certo; vermelho, que algo falhou.",
               analogy: "Um assistente que confere o trabalho toda vez que você entrega algo.",
               diagram: .actions),
        Lesson(id: "fork", title: "Cópia própria", term: "Fork", symbol: "tuningfork",
               summary: "Uma cópia de um repositório de outra pessoa na sua conta.",
               explanation: "Com um fork você pode mudar à vontade o projeto de alguém sem afetar o original. Se quiser, depois propõe as mudanças com um pull request.",
               analogy: "Fotocopiar a receita de alguém para adaptar do seu jeito.",
               diagram: .none),
        Lesson(id: "star", title: "Estrela", term: "Star", symbol: "star.fill",
               summary: "Um “curtir” que também serve para guardar repositórios favoritos.",
               explanation: "Dar estrela mostra apreço pelo projeto e deixa ele fácil de achar depois na sua lista de estrelas.",
               analogy: "Como favoritar um site.",
               diagram: .none),
        Lesson(id: "readme", title: "Leia-me", term: "README", symbol: "doc.text.fill",
               summary: "O arquivo de apresentação do projeto.",
               explanation: "O README.md aparece na página inicial do repositório. Ele costuma explicar o que é o projeto, como instalar e como usar.",
               analogy: "A contracapa do livro.",
               diagram: .none),
        Lesson(id: "gitignore", title: "Lista de ignorados", term: ".gitignore", symbol: "eye.slash.fill",
               summary: "Arquivos que o Git deve fingir que não existem.",
               explanation: "O .gitignore lista arquivos que não devem ir para o histórico, como senhas, arquivos temporários e pastas de build.",
               analogy: "Uma placa de “não fotografar” para certas coisas da pasta.",
               diagram: .none),
        Lesson(id: "visibility", title: "Público ou privado", term: "Visibility", symbol: "lock.fill",
               summary: "Quem pode ver o repositório.",
               explanation: "Repositórios públicos podem ser vistos por qualquer pessoa na internet (mas só você e convidados alteram). Privados ficam visíveis só para você e quem você convidar.",
               analogy: "Diário trancado (privado) ou vitrine de loja (público).",
               diagram: .none)
    ]

    public static func lesson(_ id: String) -> Lesson? { lessons.first { $0.id == id } }
}
