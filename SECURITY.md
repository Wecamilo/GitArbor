# Segurança

O Git Arbor lida com a sua chave de acesso ao GitHub, então levamos falhas de segurança a sério.

## Como relatar

**Não abra uma issue pública.** Use o botão **Report a vulnerability** na aba **Security** deste repositório (relato privado do GitHub). Descreva o problema, como reproduzir e o impacto.

## Como o app protege seus dados

- A chave de acesso fica no app **Chaves** do macOS, guardada só neste Mac e liberada apenas com o Mac desbloqueado.
- O app conversa apenas com o GitHub (a API e as imagens de perfil) e com o Git do seu Mac. Não há servidor próprio nem telemetria.
- O cache local fica em `~/Library/Application Support/Git Arbor/`, legível só pelo seu usuário.
