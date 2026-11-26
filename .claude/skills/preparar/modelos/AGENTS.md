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
- Um comando do projeto cria uma conta de teste para cada perfil de usuário e não mexe nas que já existem. Perfil novo entra nesse comando na mesma tarefa em que nasce.

## Banco de dados

- Migração só acrescenta: tabela nova, coluna nova com valor padrão, índice novo. Assim a versão anterior do código continua funcionando se for preciso voltar.
- Remover ou renomear tabela ou coluna leva duas entregas: primeiro o código deixa de usar, depois a migração remove.
- Toda migração pode rodar duas vezes sem erro.
- Consultas sempre com parâmetros, nunca montando SQL com texto vindo de fora.

## Slop

Slop é código ou arquivo que não muda o que o sistema faz e só deixa o repositório maior e mais difícil de ler. A lista é fechada: o que não está aqui não é slop, e estilo ou preferência de nome não entram.

1. Comentário que repete o que a linha já diz, ou que narra a mudança, como "agora usa X" ou "corrigido".
2. Função, classe ou bloco que duplica outro que já existe, com outro nome.
3. Abstração com um uso só: classe, wrapper, fábrica ou parâmetro de configuração sem segunda implementação nem segundo chamador.
4. Defesa contra o que não acontece: checagem de nulo ou de tipo para um valor que todo chamador fornece, ou `try` em volta de código que não levanta erro.
5. Erro engolido: `except` que ignora o erro, ou só registra e segue como se nada tivesse acontecido, sem um comentário dizendo por que ele pode ser ignorado.
6. Código de depuração esquecido: `print` ou log de depuração, e trecho de código comentado.
7. Arquivo de trabalho de agente versionado: relatório, plano, notas ou script de uso único, sem referência no código e fora da documentação.

Não escreva nada desta lista.

## Nunca faça

- Não altere nem apague teste existente para fazê-lo passar.
- Não escreva orientação geral em `CLAUDE.md`. Ele só importa este arquivo.
- Não altere este arquivo, as regras ou as skills por conta própria. Proponha a mudança e espere aprovação.
- Não abra, copie nem altere o banco de produção. Testes e cópias de trabalho usam banco próprio, criado pelos dados de exemplo.
- Não implante nem reinicie o serviço fora de `deploy/implantar.sh` e `deploy/reverter.sh`.
- <outras regras do projeto>

## Documentação

- `docs/<arquivo>`: <o que explica>
