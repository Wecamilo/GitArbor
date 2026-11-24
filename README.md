# Git Arbor

**Central do GitHub para macOS, pensada para quem está começando: tudo em português, muito visual e com explicações em cada tela.**

[![Testes](../../actions/workflows/ci.yml/badge.svg)](../../actions/workflows/ci.yml)
[![Licença MIT](https://img.shields.io/badge/licen%C3%A7a-MIT-green.svg)](LICENSE)
![macOS 15+](https://img.shields.io/badge/macOS-15%2B-blue.svg)
![Swift 6.2](https://img.shields.io/badge/Swift-6.2-orange.svg)

> *English:* Git Arbor is a native macOS GitHub client for beginners, fully in Brazilian Portuguese, with visual explanations on every screen. MIT licensed.

## O que tem

- **Entrada com Touch ID** (ou senha do Mac), com visual próprio: anel de “commits” em volta da digital.
- **Início**: números da conta, quadradinhos de atividade do último ano, projetos que pedem atenção e linha do tempo.
- **Repositórios**: cartões coloridos, busca, filtros e criação. Em cada um: visão geral (README e linguagens), arquivos, histórico com o que mudou em cada commit, ramos (à frente/atrás), tarefas (issues), pedidos de mudança (pull requests, com juntar/fechar), automações (Actions, com rodar de novo), versões (releases) e ajustes (nome, visibilidade, arquivar, apagar).
- **Projetos no Mac**: situação de cada pasta com Git (não salvo, falta enviar, novidades para baixar), salvar versão com prévia das mudanças, enviar, baixar, publicar no GitHub e começar a usar Git numa pasta.
- **Proteção de senhas e chaves**: avisa quando arquivos que parecem senhas ou chaves estão prestes a ir para o GitHub e procura vazamentos no histórico.
- **Notificações**, **Aprender** (lições ilustradas) e **Conta e ajustes**.

## Instalar

**Requisitos:** macOS 15 (Sequoia) ou mais novo. O [GitHub CLI](https://cli.github.com) (`gh`) é opcional.

1. Baixe o `GitArbor-x.y.z.zip` da [versão mais recente](../../releases/latest).
2. Abra o zip e arraste o **Git Arbor** para a pasta **Aplicativos**.
3. Na primeira vez, o macOS avisa que não pode verificar o desenvolvedor (o app ainda não tem assinatura paga da Apple). Para liberar:
   - abra **Ajustes do Sistema → Privacidade e Segurança**, desça até o aviso do Git Arbor e clique em **Abrir Mesmo Assim**; **ou**
   - no Terminal: `xattr -dr com.apple.quarantine "/Applications/Git Arbor.app"`

Prefere não confiar num binário? Compile você mesmo (veja abaixo): é um comando só.

## Conexão com o GitHub

O Git Arbor usa a conta do GitHub CLI (`gh`) já conectada no Mac **ou** uma chave de acesso (*personal access token*) guardada no app **Chaves** do macOS. A chave fica só no seu Mac e é usada apenas para falar com o GitHub. Não há servidor intermediário, conta própria nem coleta de dados.

## Compilar a partir do código

Precisa das Command Line Tools ou do Xcode com **Swift 6.2** ou mais novo.

```bash
git clone <endereço deste repositório>
cd Git-Arbor
./build_app.sh        # testa, empacota, assina com um certificado local e instala em ~/Applications
```

Outros comandos úteis:

```bash
swift test                              # testes do núcleo
Scripts/package_release.sh 1.0.0        # gera dist/GitArbor-1.0.0.zip (assinatura ad hoc)
swift Scripts/make_icon.swift /tmp/AppIcon.iconset && iconutil -c icns /tmp/AppIcon.iconset -o Resources/AppIcon.icns
```

O `build_app.sh` cria, só no seu Mac, um certificado de assinatura próprio (em `~/Library/Application Support/Git Arbor/Signing`). Assim o app Chaves continua liberando a chave do GitHub depois de cada atualização, sem perguntar de novo.

## Estrutura

| Pasta | O que tem |
| --- | --- |
| `Sources/GitArborCore` | Núcleo sem interface: API do GitHub, Git local, glossário, detecção de senhas e chaves. |
| `Sources/GitArbor` | App SwiftUI/AppKit. |
| `Tests/GitArborCoreTests` | Testes do núcleo (Swift Testing). |
| `Scripts` | Montagem do app, versão para baixar e ícone. |

## Contribuir

Ideias, erros e melhorias são bem-vindos: veja [CONTRIBUTING.md](CONTRIBUTING.md). Problemas de segurança: [SECURITY.md](SECURITY.md).

## Licença

[MIT](LICENSE). O Git Arbor é um projeto independente, sem ligação com o GitHub, Inc.
