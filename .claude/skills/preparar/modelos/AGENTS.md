# <Nome do projeto>

<Uma ou duas frases: o que o sistema faz e para quem.>

Este é o único arquivo de orientação geral do repositório. Mantenha abaixo de 200 linhas. O que for específico de uma área vai para `.claude/rules/`, e procedimento passo a passo vai para uma skill em `.claude/skills/`.

## Comandos

- Instalar dependências:
- Lint e tipos:
- Pilha de testes completa:
- Testes de uma área só:
- Subir a aplicação em uma porta escolhida:
- Carregar os dados de exemplo ou voltar ao estado limpo:

## Mapa do projeto

- `<pasta>`: <o que fica aqui>
- `<pasta>`: <o que fica aqui>

## Padrões

- <organização de pastas e nomes>
- <tratamento de erro>
- <o que usar e o que não usar>

## Stack

- Python, com dependências em `requirements.txt` e ambiente em `.venv`.
- Banco SQLite3 em modo WAL. O caminho do arquivo vem da variável de ambiente `BANCO`, nunca fixo no código.
- Front em HTML e JavaScript, sem etapa de build, servido pela própria aplicação.
- A aplicação responde 200 em `<caminho de verificação>` quando está de pé.

## Banco de dados

- Migração só acrescenta: tabela nova, coluna nova com valor padrão, índice novo. Assim a versão anterior do código continua funcionando se for preciso voltar.
- Remover ou renomear tabela ou coluna leva duas entregas: primeiro o código deixa de usar, depois a migração remove.
- Toda migração pode rodar duas vezes sem erro.
- Consultas sempre com parâmetros, nunca montando SQL com texto vindo de fora.

## Nunca faça

- Não altere nem apague teste existente para fazê-lo passar.
- Não escreva orientação geral em `CLAUDE.md`. Ele só importa este arquivo.
- Não altere este arquivo, as regras ou as skills por conta própria. Proponha a mudança e espere aprovação.
- Não abra, copie nem altere o banco de produção. Testes e cópias de trabalho usam banco próprio, criado pelos dados de exemplo.
- Não implante nem reinicie o serviço fora de `deploy/implantar.sh` e `deploy/reverter.sh`.
- <outras regras do projeto>

## Documentação

- `docs/<arquivo>`: <o que explica>
