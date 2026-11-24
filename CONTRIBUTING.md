# Como contribuir

Obrigado pelo interesse no Git Arbor!

## Antes de começar

- **Erros e ideias:** abra uma *issue* usando um dos modelos. Para mudanças grandes, converse numa issue antes de escrever o código.
- **Idioma:** o app é todo em português do Brasil, e issues, commits e pull requests também podem ser em português.

## Princípios do app

1. **Para quem está começando.** Cada tela explica o que está acontecendo, sem jargão. Quando um termo técnico for inevitável, ele aparece no Glossário (`Sources/GitArborCore/Glossary.swift`).
2. **Tudo local.** Nada de servidores próprios, telemetria ou coleta de dados. O app fala só com o Git do Mac e a API do GitHub.
3. **Visual próprio e nativo.** SwiftUI/AppKit, sem dependências externas.

## Passo a passo

1. Faça um *fork* e crie um ramo: `git switch -c minha-melhoria`.
2. Rode os testes: `swift test`. Lógica nova no núcleo (`GitArborCore`) deve vir com teste.
3. Para ver o app: `./build_app.sh`.
4. Abra o *pull request* explicando **o que** muda e **por quê**, com um print se mexer na interface.

## Publicar uma versão (mantenedores)

Altere `VERSION` se for o caso, crie a etiqueta e envie:

```bash
git tag v1.0.0
git push origin v1.0.0
```

A automação **Versão** compila, testa, gera o `GitArbor-1.0.0.zip` e cria a versão no GitHub.
