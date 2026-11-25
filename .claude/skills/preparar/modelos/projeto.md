# Configuração do fluxo

Só o que o `/fluxo` precisa. Comandos e padrões do projeto ficam em `AGENTS.md`.

## Pastas de teste

As únicas que o testador pode alterar.

-

## Documentação compartilhada

As únicas que o documentador pode alterar: índice, registro de mudanças, guias gerais.

-

## Áreas sensíveis

Tarefas que tocam estes pontos disparam o revisor de segurança.

- Autenticação e permissões:
- Pagamento e cobrança:
- Dados de cliente:
- Exposição de rede:

## Entrega

O sistema em produção é também o ambiente em que o usuário testa. Quando todos os gatilhos passam, a entrega é automática.

- Entrega automática: sim
- Segurar para aprovação quando a execução toca área sensível: não
- Branch principal: main
- Como levar à principal: PR
- Pasta de produção:
- Comando de implantação, que recebe o commit: cd <pasta de produção> && deploy/implantar.sh
- Comando de reversão: cd <pasta de produção> && deploy/reverter.sh
- Endereço do sistema:

## Cópias de trabalho

Cada tarefa em andamento tem a sua cópia do código, instala o ambiente e roda a pilha inteira. O teto abaixo diz quantas andam juntas; as outras esperam na fila.

- Arquivo com as contas de teste usadas nas cópias de trabalho:
- Tarefas ao mesmo tempo: 4

## Interface

- Verificar também em tela pequena: sim | não
