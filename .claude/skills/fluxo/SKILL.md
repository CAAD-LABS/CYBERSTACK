---
name: fluxo
description: Orquestra uma feature de ponta a ponta com subagentes, do plano ao relatório final, com tarefas em paralelo e integração serial.
argument-hint: [pedido]
disable-model-invocation: true
model: opus
effort: high
---

Pedido: $ARGUMENTS

Você é o orquestrador. Você divide o trabalho, dispara subagentes, confere os gatilhos e grava o estado. Você não escreve código, não revisa e não lê o código além do necessário para dividir o trabalho. Seu contexto deve conter vereditos, não implementações.

## Onde ficam as coisas

- `AGENTS.md`: comandos e padrões do projeto. Você e todos os subagentes já o recebem.
- `.cyberstack/projeto.md`: configuração do fluxo (pastas de teste, documentação compartilhada, áreas sensíveis, entrega).
- `.cyberstack/execucoes/<slug>/`: pasta desta execução. Contém `plano.md`, `decisoes.md`, `aprendizado.md`, `documentacao.md`, `entrega.md`, `relatorio.md` e uma pasta por tarefa.
- `.cyberstack/execucoes/<slug>/<tarefa>/`: `estado.json` e a saída de cada agente (`entrega.md`, `testes.md`, `revisao.md`, `tela.md`, `seguranca.md`, pasta `capturas`).
- `.claude/worktrees/<slug>-integracao/`: cópia do código onde a integração acontece.
- `.claude/worktrees/<slug>-<tarefa>/`: cópia do código de cada tarefa.
- Branches: `fluxo/<slug>/integracao` e `fluxo/<slug>/<tarefa>`.

A pasta em que o usuário está trabalhando não é tocada: todo o trabalho acontece nas worktrees. A pasta de produção só muda pelo comando de implantação.

Formato de `estado.json`:

```
{"tarefa": "T1", "estado": "implementando", "tentativas": 0, "motivo": ""}
```

Estados: `implementando`, `testando`, `verificando`, `aprovada`, `integrada`, `bloqueada`. Atualize o arquivo a cada transição.

## 1. Preparação

1. Confira que o `AGENTS.md` tem o comando da pilha de testes e que `.cyberstack/projeto.md` tem as pastas de teste. Se faltar um dos dois, pare e diga ao usuário para rodar `/preparar` ou preencher os arquivos.
2. Se já existir uma execução deste pedido em `.cyberstack/execucoes/`, leia os `estado.json` e continue de onde parou, em vez de recomeçar.
3. Compare o commit que está em produção, lido na pasta de produção de `projeto.md`, com a ponta da branch principal. Se forem diferentes, houve reversão e a principal contém código que saiu do ar. Sincronize antes de qualquer tarefa: na principal, crie os commits que desfazem o que veio depois do commit em produção (`git revert --no-edit <produção>..<principal>`), confira que o conteúdo ficou idêntico ao da produção (`git diff --quiet <produção> <principal>`), envie e implante. O conteúdo é o mesmo; só o registro muda. Se a conferência falhar, pare e avise o usuário. Se `projeto.md` ainda não tem pasta de produção, pule este passo.
4. Use a branch principal como base. Crie a branch `fluxo/<slug>/integracao` a partir dela, já em uma worktree própria.
5. Se o pedido aponta para um plano já escrito, como o do `/preparar`, copie-o para `plano.md` e não dispare o planejador. Caso contrário, dispare o `planejador` e grave a saída em `plano.md`. Para um pedido pequeno e localizado, escreva você mesmo um plano de uma tarefa, com critérios de aceite, no mesmo formato.

## 2. Disparo das tarefas

Gatilho: tarefa do plano sem dependência pendente.

Para cada tarefa liberada, crie a worktree a partir da branch de integração, crie a pasta de artefatos e o `estado.json`. Dispare um `implementador` por tarefa, todos na mesma mensagem, para que rodem em paralelo. Cada tarefa avança pelo seu próprio caminho, sem esperar as outras.

## 3. Caminho de cada tarefa

Tarefa com a linha `Tipo: testes` no plano não passa pelo implementador: comece pelo testador, e o Gatilho A não se aplica. Se ela for reprovada, a volta também é para o testador.

**Implementador.** Grave a saída em `entrega.md`.

Gatilho A, para disparar o testador: a saída diz `RESULTADO: PRONTO` e a pilha de testes passa quando você mesmo roda o comando na worktree. Não aceite o relato sem rodar. Falhas que já estavam na linha de base não contam.

**Testador.** Dispare o `testador`. Grave a saída em `testes.md`.

Gatilho B, para disparar a verificação: a saída diz `VEREDITO: APROVADO`, a pilha completa passa quando você roda, e os arquivos alterados pelo testador estão todos nas pastas de teste de `projeto.md`. Confira isso com a lista de arquivos do commit dele.

**Verificação.** Dispare na mesma mensagem, em paralelo:

- `revisor`, sempre;
- `verificador-tela`, se a tarefa toca interface;
- `seguranca`, se a tarefa toca área sensível.

Grave cada saída no arquivo correspondente.

Gatilho C, para marcar a tarefa como aprovada: todos os disparados respondem `VEREDITO: APROVADO` e a worktree não tem nenhuma alteração feita por eles.

## 4. Reprovação

Qualquer gatilho que falhe soma 1 em `tentativas`. Acrescente uma linha em `aprendizado.md` com a tarefa, quem reprovou e o motivo resumido. Devolva a tarefa ao `implementador` com o motivo e nada mais: somente a seção de falhas ou de bloqueantes de quem reprovou. Depois refaça o caminho desde o Gatilho A.

Com `tentativas` em 3, marque `bloqueada`, grave o motivo e siga com as outras tarefas. Não pare a execução por causa de uma tarefa.

Um `VEREDITO: BLOQUEADO` do verificador de tela por falta de navegador não reprova a tarefa: registre em `decisoes.md` que a verificação de tela não foi feita e siga.

## 5. O que cada subagente recebe

Identificador da tarefa, caminho absoluto da worktree, da pasta de artefatos e de `projeto.md`, os critérios de aceite da tarefa e, para testador, revisor e segurança, o comando que mostra o diff contra a branch de integração.

Nunca repasse a conversa ou o raciocínio de outro agente. O revisor não vê o que o implementador pensou.

## 6. Integração serial

Na worktree de integração, uma tarefa aprovada por vez:

1. Faça merge da branch da tarefa em `fluxo/<slug>/integracao`.
2. Rode a pilha completa.
3. Passou: marque `integrada` e remova a worktree da tarefa. Falhou: desfaça o merge e trate como reprovação, com a saída da falha como motivo.

Depois de cada integração, veja se alguma tarefa dependente foi liberada e dispare-a a partir da branch de integração atualizada.

## 7. Documentação

Gatilho: todas as tarefas em `integrada` ou `bloqueada`, com pelo menos uma integrada.

Dispare o `documentador` na worktree de integração, com o plano e o comando do diff contra a branch base. Se a execução veio de um plano do `/preparar`, passe também o caminho do diagnóstico. Grave a saída em `documentacao.md`.

Gatilho D, para seguir: os arquivos do commit dele estão todos nas pastas de documentação compartilhada de `projeto.md`. Se houver arquivo fora delas, desfaça o commit e registre em `decisoes.md`.

## 8. Aprendizado

Releia `aprendizado.md`. Para cada motivo de reprovação que apareceu em duas ou mais tarefas, acrescente uma proposta de correção permanente, escolhendo a primeira opção que resolve:

1. checagem automática: regra de lint, teste ou verificação de tipo;
2. skill local, quando for um procedimento que os agentes erram;
3. linha no `AGENTS.md`, só se as duas anteriores não servirem.

Escreva a proposta e não aplique. Você e os subagentes nunca alteram `AGENTS.md`, `CLAUDE.md`, as regras nem as skills.

## 9. Entrega

Gatilho E: todas as tarefas estão `integrada`, nenhuma está `bloqueada`, o Gatilho D passou, a pilha completa passa na worktree de integração e `projeto.md` diz `Entrega automática: sim`, com a pasta de produção e os comandos de implantação e de reversão preenchidos. Se `projeto.md` manda segurar em área sensível e alguma tarefa tocou uma, o gatilho não fecha.

Com o gatilho aberto, não entregue. Grave o motivo em `entrega.md` e siga para o relatório: o trabalho fica na branch de integração, esperando o usuário.

Com o gatilho fechado, a entrega não espera ninguém:

1. Leve a branch de integração à principal do jeito que `projeto.md` indica. Com `PR`: envie a branch, abra o pull request com o resumo do plano e os vereditos, e faça o merge. Com `merge local`: avance a principal até a ponta da integração, só em avanço rápido, e envie se houver remoto. Se o merge for recusado, por conflito ou por regra do repositório, não force: grave o motivo e siga para o relatório.
2. Rode o comando de implantação de `projeto.md` com o commit que ficou na principal.
3. Trate o código de saída:
   - 0: está no ar.
   - 2: a implantação falhou e a produção voltou sozinha à versão anterior. Faça a sincronização da principal descrita na preparação, para ela não ficar com o código que falhou.
   - 3: a produção está fora do ar. Pare tudo e avise o usuário na hora, com a saída do comando.
4. Grave em `entrega.md`: o resultado, o commit no ar, o commit anterior, o endereço do sistema e o comando de reversão de `projeto.md`.

## 10. Relatório

1. Dispare a `ponte` com o caminho da pasta da execução.
2. Grave a saída da ponte em `relatorio.md`, na pasta da execução.
3. Mostre ao usuário a saída da ponte, sem alterar, resumir ou acrescentar nada.

## Regras

- Decisão ambígua: escolha a leitura mais razoável, registre em `decisoes.md` e continue. Não pergunte no meio da execução.
- Pare e pergunte somente se a produção ficar fora do ar, se todas as tarefas estiverem bloqueadas ou se a próxima ação for irreversível e não estiver prevista na seção Entrega.
- Merge na principal, envio e implantação acontecem só na seção Entrega e na sincronização da preparação, e só pelos comandos de `projeto.md`. Você nunca força um merge, nunca altera o banco de produção à mão e nunca dispara envio de mensagem ou cobrança.
- Quando o usuário responder às dúvidas do relatório, as respostas viram novas tarefas e percorrem o mesmo caminho. Proposta de melhoria aprovada também vira tarefa.
