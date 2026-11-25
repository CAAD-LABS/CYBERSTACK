# CyberStack

Stack de agentes de desenvolvimento para o Claude Code, rodando na assinatura Claude. Leva um projeto da preparação inicial até cada feature no ar, com subagentes em paralelo, entrega automática e um relatório único no fim.

Feita para projetos em Python, com banco SQLite3 e front em HTML e JavaScript, rodando como serviço em uma máquina Linux com systemd.

| Comando | Quando | O que faz |
|---|---|---|
| `/preparar` | Uma vez por projeto, antes de tudo | Diagnostica o repositório, cria os arquivos base e propõe a limpeza. |
| `/fluxo <pedido>` | A cada feature, e para executar a limpeza aprovada | Planeja, implementa, testa, verifica, integra, documenta, entrega e relata. |

O desenho completo, com os diagramas do fluxo, dos gatilhos e da entrega, está em [docs/desenho.md](docs/desenho.md).

Situação: desenho fechado e definições escritas. A stack ainda não rodou em um projeto real. Os dois scripts de implantação são exercitados por `testes/implantacao.sh`.

## O que tem aqui

| Caminho | O que é |
|---|---|
| [`.claude/agents/`](.claude/agents) | Os nove perfis de subagente: inspetor, planejador, implementador, testador, revisor, verificador de tela, segurança, documentador e ponte. |
| [`.claude/skills/preparar/`](.claude/skills/preparar) | O comando `/preparar` e os modelos dos arquivos base que ele cria no projeto, incluindo os scripts de implantação e de reversão. |
| [`.claude/skills/fluxo/`](.claude/skills/fluxo) | O comando `/fluxo`, que é o orquestrador. |
| [`docs/desenho.md`](docs/desenho.md) | O desenho da stack. |
| [`instalar.sh`](instalar.sh) | Instala a stack em um projeto ou na pasta pessoal e confere os arquivos. |
| [`SHA256SUMS`](SHA256SUMS) | O SHA-256 de cada arquivo da stack. |
| [`testes/implantacao.sh`](testes/implantacao.sh) | Teste dos scripts de implantação e de reversão em um projeto de brinquedo. |

Os caminhos dentro de `.claude/` são os mesmos em que os arquivos ficam depois de instalados.

## Instalar

Requisitos: Claude Code 2.1.271 ou mais novo, git, python3 e curl. A entrega automática usa systemd e, quando leva o trabalho à principal por pull request, o `gh`. O verificador de tela precisa de uma ferramenta de navegador na sessão.

```bash
git clone git@github.com:CAAD-LABS/CYBERSTACK.git
cd CYBERSTACK
./instalar.sh /caminho/do/projeto   # só nesse projeto
./instalar.sh --global              # em ~/.claude, para todos os projetos
```

O instalador copia os 19 arquivos para `.claude/agents/` e `.claude/skills/` do destino e confere cada um pelo SHA-256. Arquivo que já existe no destino e está diferente é mantido, a não ser com `--sobrescrever`. Ele não cria `AGENTS.md`, `CLAUDE.md` nem `.cyberstack/projeto.md`, que nascem no `/preparar`, e não faz commit.

Se você é um agente instalando a stack: use o `instalar.sh` em vez de copiar os arquivos à mão; se o usuário não disse, pergunte se a instalação é no projeto ou para todos os projetos; não crie os arquivos base, não faça commit e termine dizendo ao usuário para abrir uma sessão nova na raiz do projeto e rodar `/preparar`.

## Usar

1. Abra uma sessão nova do Claude Code na raiz do projeto e rode `/preparar`.
2. Revise os arquivos base e o plano de limpeza, faça commit e instale o serviço.
3. Rode `/fluxo executar o plano em .cyberstack/preparacao/plano.md` para a limpeza.
4. Daí em diante, `/fluxo <pedido>` a cada feature.

A lista completa do primeiro uso está em [docs/desenho.md](docs/desenho.md#primeiro-uso-em-um-projeto).

## Conferir e testar

```bash
./instalar.sh --conferir                       # os arquivos daqui batem com o SHA256SUMS?
./instalar.sh --conferir /caminho/do/projeto   # e os instalados naquele projeto?
testes/implantacao.sh                          # exercita implantar.sh e reverter.sh
```

## Mudar a stack

Os arquivos de `.claude/` deste repositório são a fonte. Depois de mudar um deles:

1. rode `./instalar.sh --somas`, que regrava o `SHA256SUMS`;
2. rode `testes/implantacao.sh`, se mexeu nos scripts;
3. atualize `docs/desenho.md`, se o comportamento mudou.

Um projeto que já tem a stack instalada só recebe a mudança quando o `instalar.sh` roda de novo nele.
