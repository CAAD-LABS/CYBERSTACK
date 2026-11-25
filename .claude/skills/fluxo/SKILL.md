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
- `.cyberstack/execucoes/<slug>/`: pasta desta execução. Contém `plano.md`, `linha-de-base.md`, `decisoes.md`, `aprendizado.md`, `documentacao.md`, `entrega.md`, `relatorio.md` e uma pasta por tarefa.
- `.cyberstack/execucoes/<slug>/<tarefa>/`: `estado.json` e a saída de cada agente (`entrega.md`, `testes.md`, `revisao.md`, `tela.md`, `seguranca.md`, pasta `capturas`). Se a tarefa bloquear, também `bloqueio.md` e `respostas.md`; se um teste for contestado, `arbitragem.md`.
- `.claude/worktrees/<slug>-integracao/`: cópia do código onde a integração acontece.
- `.claude/worktrees/<slug>-<tarefa>/`: cópia do código de cada tarefa.
- Branches: `fluxo/<slug>/integracao` e `fluxo/<slug>/<tarefa>`.

A pasta em que o usuário está trabalhando não é tocada: todo o trabalho acontece nas worktrees. A pasta de produção só muda pelo comando de implantação.

Formato de `estado.json`:

```
{"tarefa": "T1", "estado": "implementando", "tentativas": 0, "motivo": ""}
```

Estados: `implementando`, `testando`, `verificando`, `aprovada`, `integrada`, `bloqueada`, `retirada`. Atualize o arquivo a cada transição.

## 1. Preparação

1. Confira que o `AGENTS.md` tem o comando da pilha de testes e que `.cyberstack/projeto.md` tem as pastas de teste. Se faltar um dos dois, pare e diga ao usuário para rodar `/preparar` ou preencher os arquivos.
2. Se já existir uma execução deste pedido em `.cyberstack/execucoes/`, leia os `estado.json` e continue de onde parou, em vez de recomeçar. Tarefa `bloqueada` que tem `bloqueio.md` e ainda espera resposta: volte a fazer as perguntas ao usuário.
3. Compare o commit que está em produção, lido na pasta de produção de `projeto.md`, com a ponta da branch principal. Se houver remoto, busque antes e use a ponta do remoto. Se `projeto.md` ainda não tem pasta de produção, pule este passo. Se os dois commits forem iguais, siga. Se o commit em produção não estiver no histórico da principal, pare e avise o usuário. Nos demais casos a principal está à frente da produção: descubra o motivo no registro de implantações (`deploy/reverter.sh --listar`, na pasta de produção) antes de mexer em qualquer coisa:
   - A ponta da principal aparece no registro: ela já esteve em produção e saiu, por reversão ou por implantação que falhou. A principal contém código que saiu do ar. Sincronize antes de qualquer tarefa.
   - Nenhum commit à frente da produção aparece no registro: são commits que nunca foram implantados, feitos fora do fluxo. Não desfaça nada. Registre em `decisoes.md` quais são e siga: eles vão ao ar com a próxima entrega.
   - Só parte dos commits à frente aparece no registro: pare e avise o usuário.

   Sincronizar é criar um commit que devolve à principal o conteúdo exato do commit em produção: `git commit-tree <produção>^{tree} -p <principal> -m "Volta a principal ao conteúdo de <produção>"`. Não use `git revert` de um intervalo: ele falha quando há merge no meio, e a integração produz merges. Confira que o conteúdo ficou idêntico (`git diff --quiet <produção> <commit novo>`), leve o commit à principal do jeito que `projeto.md` indica e implante. O conteúdo é o mesmo; só o registro muda. Se a conferência falhar, pare e avise o usuário.

   Grave o commit de sincronização em `decisoes.md`. Se o pedido for corrigir o que saiu do ar, a primeira tarefa do plano desfaz esse commit na integração (`git revert <commit de sincronização>`), para o trabalho recomeçar de onde estava; diga isso ao planejador.
4. Use como base a ponta da principal conferida no passo anterior, a do remoto se houver. Crie a branch `fluxo/<slug>/integracao` a partir dela, já em uma worktree própria. Uma worktree nova não traz o `.venv`: rode nela o comando de instalar dependências do `AGENTS.md`. Depois rode a pilha completa e grave o resultado, com os nomes dos testes que falham, em `linha-de-base.md`. Antes de rodar, veja se o plano do pedido começa por uma tarefa `Tipo: banco`: se começa, não rode nada ainda, porque o código abre o banco de produção, e meça a linha de base quando essa tarefa integrar. Crie também `decisoes.md` e `aprendizado.md`, vazios.
5. Se o pedido aponta para um plano já escrito, como o do `/preparar`, copie-o para `plano.md` e não dispare o planejador. Caso contrário, dispare o `planejador`, com o caminho da worktree de integração, e grave a saída em `plano.md`. Para um pedido pequeno e localizado, escreva você mesmo um plano de uma tarefa, com critérios de aceite, no mesmo formato.

## 2. Disparo das tarefas

Gatilho: tarefa do plano sem dependência pendente.

Para cada tarefa liberada, crie a worktree a partir da branch de integração, instale nela as dependências, crie a pasta de artefatos e o `estado.json`. Dispare um `implementador` por tarefa, todos na mesma mensagem, para que rodem em paralelo. Cada tarefa avança pelo seu próprio caminho, sem esperar as outras.

## 3. Caminho de cada tarefa

Tarefa com a linha `Tipo: testes` no plano não passa pelo implementador: comece pelo testador, e o Gatilho A não se aplica. Se ela for reprovada, a volta também é para o testador.

Tarefa com a linha `Tipo: banco` tira do código o caminho fixo do banco. Ela vai sozinha, antes de todas as outras, e nada roda antes dela: diga ao implementador que não execute a pilha nem a aplicação antes de fazer a mudança. O Gatilho A dela exige `RESULTADO: PRONTO` e a pilha rodando com `BANCO` apontando para um arquivo da worktree; como ainda não há linha de base, falha de teste que já existia não reprova, e quem julga a mudança são o testador e o revisor. Quando ela integrar, rode a pilha na worktree de integração, grave `linha-de-base.md` e só então libere as outras tarefas.

Em todos os gatilhos, "a pilha passa" quer dizer que não há falha além das que estão em `linha-de-base.md`. Vale a linha de base que você mediu, não a do relato de um agente.

**Implementador.** Grave a saída em `entrega.md`.

Gatilho A, para disparar o testador: a saída diz `RESULTADO: PRONTO` e a pilha de testes passa quando você mesmo roda o comando na worktree. Não aceite o relato sem rodar. Falhas que já estavam na linha de base não contam, nem as dos testes que a entrega lista em "Testes obsoletos": esses quem ajusta é o testador. Em tarefa de limpeza, confira também que o commit só altera arquivos da lista da tarefa.

**Testador.** Dispare o `testador`. Grave a saída em `testes.md`.

Gatilho B, para disparar a verificação: a saída diz `VEREDITO: APROVADO`, a pilha completa passa quando você roda, e os arquivos alterados pelo testador estão todos nas pastas de teste de `projeto.md`. Para saber o que ele gravou, anote a ponta da branch antes de disparar e compare depois (`git diff --name-only <antes>..HEAD`).

**Verificação.** Dispare na mesma mensagem, em paralelo:

- `revisor`, sempre;
- `verificador-tela`, se a tarefa toca interface;
- `seguranca`, se a tarefa toca área sensível.

Decida pela lista de arquivos do diff, não só pelo plano. Se o diff toca um caminho das áreas sensíveis de `projeto.md`, a pasta `deploy/` ou o próprio `.cyberstack/projeto.md`, dispare a segurança mesmo que o plano diga não. Se toca HTML, JavaScript ou CSS, dispare o verificador de tela.

Grave cada saída no arquivo correspondente.

Gatilho C, para marcar a tarefa como aprovada: todos os disparados respondem `VEREDITO: APROVADO` e a worktree não tem nenhuma alteração feita por eles.

## 4. Reprovação

Qualquer gatilho que falhe soma 1 em `tentativas`. Acrescente uma linha em `aprendizado.md` com a tarefa, quem reprovou e o motivo resumido. Devolva a tarefa ao `implementador` com o motivo e nada mais: somente a seção de falhas ou de bloqueantes de quem reprovou. Depois refaça o caminho desde o Gatilho A.

Com `tentativas` em 3, marque `bloqueada`, grave o motivo e siga com as outras tarefas. Não pare a execução por causa de uma tarefa. O que fazer com ela está em "Tarefa bloqueada", abaixo. Tarefa que depende de uma bloqueada também é marcada `bloqueada`, com o motivo "depende de <tarefa>", sem ser disparada.

`RESULTADO: BLOQUEADO` do implementador não é reprovação: marque a tarefa como `bloqueada` na hora, com o que ele disse que falta.

Quando quem errou foi o agente e não o código, a tarefa não volta ao implementador. Se o testador alterou arquivo fora das pastas de teste, ou um verificador alterou a worktree, desfaça o que ele gravou e dispare de novo o mesmo perfil, com esse motivo. Conta como tentativa.

Um `VEREDITO: BLOQUEADO` do verificador de tela por falta de navegador não reprova a tarefa: registre em `decisoes.md` que a verificação de tela não foi feita e siga.

Saída sem a linha de `RESULTADO` ou de `VEREDITO` quer dizer que o agente parou no teto de turnos antes de concluir. Isso não é reprovação: retome o mesmo agente para ele terminar. Se depois de duas retomadas a linha ainda não vier, marque a tarefa como `bloqueada`, com esse motivo.

### Teste contestado

O implementador pode responder `RESULTADO: CONTESTADO` quando voltou por um teste do testador que ele considera errado. Isso não é reprovação e não soma tentativa.

1. Dispare o `revisor` como árbitro, com os critérios de aceite, a falha apontada pelo testador, a contestação e o comando do diff, pedindo a arbitragem. Grave a saída em `arbitragem.md`, na pasta da tarefa, e acrescente o resultado em `aprendizado.md`.
2. Teste que o árbitro deu como errado: dispare o `testador` para corrigi-lo, com a decisão do árbitro, e desconte de `tentativas` a reprovação que esse teste causou.
3. Teste que o árbitro deu como certo: devolva a tarefa ao `implementador` com a decisão. Esse teste não pode ser contestado de novo.
4. Critério que não decide: marque a tarefa como `bloqueada`, com a pergunta do árbitro como motivo, e siga por "Tarefa bloqueada".

Se a mesma contestação tiver teste errado e teste certo, o testador corrige os errados primeiro e depois a tarefa volta ao implementador pelos certos. Em qualquer caso, o caminho recomeça do Gatilho A.

### Tarefa bloqueada

Tarefa bloqueada volta ao usuário na hora, com as perguntas de que ela precisa para andar. As outras tarefas seguem.

1. Dispare o `planejador` com o bloco da tarefa, a worktree dela e o motivo de cada reprovação, pedindo a análise do bloqueio. Grave a saída em `bloqueio.md`, na pasta da tarefa. Tarefa bloqueada só por depender de outra não passa por isso: ela espera a outra.
2. Faça ao usuário a primeira pergunta de `bloqueio.md`, em texto, na conversa, dizendo qual é a tarefa e o que travou. Uma pergunta por vez: a resposta de uma decide qual é a próxima, ou dispensa as seguintes. Não use ferramenta que fique esperando a resposta: enquanto ela espera, os gatilhos das outras tarefas param. Com mais de uma tarefa bloqueada, termine as perguntas de uma antes de começar as da outra.
3. Grave cada resposta em `respostas.md`, na pasta da tarefa. Quando as respostas bastarem, siga o caminho que elas apontam:
   - Prosseguir: zere `tentativas`, volte o estado para `implementando` e dispare o `implementador`, ou o `testador` em tarefa `Tipo: testes`, com o bloco da tarefa, o que travou e as respostas. A tarefa refaz o caminho desde o Gatilho A.
   - Outra solução: dispare o `planejador` para reescrever a tarefa no plano, ou trocá-la por outras, a partir das respostas. O que ele escrever percorre o caminho normal.
   - Tirar do pedido: marque a tarefa como `retirada`. Ela deixa de contar para a entrega.
4. Tarefa que estava bloqueada por depender desta volta a esperar quando esta é reaberta ou reescrita, e vai junto ao planejador quando esta é retirada.

Se a execução chegar ao fim antes das respostas, as perguntas que faltam vão no relatório, a tarefa continua `bloqueada` e nada é entregue. Quando o usuário responder, siga daqui.

## 5. O que cada subagente recebe

O bloco inteiro da tarefa, copiado do plano, com o identificador e o tipo; caminho absoluto da worktree, da pasta de artefatos e de `projeto.md`; os critérios de aceite da tarefa; para o testador, a entrega do implementador; e, para testador, revisor e segurança, o comando que mostra o diff contra a branch de integração.

Um subagente começa na pasta do usuário, não na worktree, e o diretório dele não persiste de um comando para o outro. Diga em todo despacho que cada comando começa por `cd <worktree> &&`.

Nunca repasse a conversa ou o raciocínio de outro agente. O revisor não vê o que o implementador pensou.

## 6. Integração serial

Na worktree de integração, uma tarefa aprovada por vez:

1. Faça merge da branch da tarefa em `fluxo/<slug>/integracao`. Se der conflito, aborte o merge e trate como reprovação, com os arquivos em conflito como motivo.
2. Rode a pilha completa.
3. Passou: marque `integrada` e remova a worktree da tarefa. Falhou: desfaça o merge e trate como reprovação, com a saída da falha como motivo.

Uma tarefa reprovada aqui passava sozinha e só falha junto com as outras. Antes de devolvê-la ao implementador, faça na worktree dela o merge da branch de integração atual, para ele trabalhar sobre o código já integrado. Se esse merge der conflito, deixe o conflito na worktree e diga no motivo que resolver é com ele.

Depois de cada integração, veja se alguma tarefa dependente foi liberada e dispare-a a partir da branch de integração atualizada.

## 7. Documentação

Gatilho: todas as tarefas em `integrada`, `retirada` ou `bloqueada`, com pelo menos uma integrada. Se uma tarefa for reaberta depois, este passo roda de novo quando ela chegar ao fim.

Dispare o `documentador` na worktree de integração, com o plano e o comando do diff contra a branch base. Se a execução veio de um plano do `/preparar`, passe também o caminho do diagnóstico. Grave a saída em `documentacao.md`.

Gatilho D, para seguir: os arquivos que ele gravou estão todos nas pastas de documentação compartilhada de `projeto.md`. Confira como no Gatilho B, pela ponta da branch anotada antes do disparo; se ele respondeu `NADA A ATUALIZAR`, não há o que conferir. Se houver arquivo fora delas, desfaça só o que ele gravou e registre em `decisoes.md`: a execução segue sem a atualização da documentação, e o gatilho conta como passado.

## 8. Aprendizado

Releia `aprendizado.md`. Para cada motivo de reprovação que apareceu em duas ou mais tarefas, acrescente uma proposta de correção permanente, escolhendo a primeira opção que resolve:

1. checagem automática: regra de lint, teste ou verificação de tipo;
2. skill local, quando for um procedimento que os agentes erram;
3. linha no `AGENTS.md`, só se as duas anteriores não servirem.

Escreva a proposta e não aplique. Você e os subagentes nunca alteram `AGENTS.md`, `CLAUDE.md`, as regras nem as skills.

## 9. Entrega

Gatilho E: todas as tarefas estão `integrada` ou `retirada`, nenhuma está `bloqueada`, o Gatilho D passou, a pilha completa passa na worktree de integração e `projeto.md` diz `Entrega automática: sim`, com a pasta de produção e os comandos de implantação e de reversão preenchidos. Se `projeto.md` manda segurar em área sensível e alguma tarefa tocou uma, o gatilho não fecha: a entrega espera a aprovação do usuário, pedida no relatório, e acontece quando ele aprovar.

Com o gatilho aberto, não entregue. Grave o motivo em `entrega.md` e siga para o relatório: o trabalho fica na branch de integração, esperando o usuário.

Com o gatilho fechado, a entrega não espera ninguém:

1. Leve a branch de integração à principal do jeito que `projeto.md` indica. Com `PR`: envie a branch, abra o pull request com o resumo do plano e os vereditos, e faça o merge. Com `merge local`: avance a principal até a ponta da integração, só em avanço rápido, e envie se houver remoto. Se o merge for recusado, por conflito ou por regra do repositório, não force: grave o motivo e siga para o relatório.
2. Rode o comando de implantação de `projeto.md` com o commit que ficou na principal.
3. Trate o código de saída:
   - 0: está no ar.
   - 2: a implantação falhou e a produção voltou sozinha à versão anterior. Faça a sincronização da principal descrita na preparação, para ela não ficar com o código que falhou.
   - 3: a produção está fora do ar. Pare tudo e avise o usuário na hora, com a saída do comando.
   - 1: o script parou antes de trocar o código, por falha de rede, commit não encontrado, erro na configuração ou na cópia do banco. Nada mudou em produção. Rode o comando mais uma vez. Se repetir, grave a saída em `entrega.md` e siga para o relatório como não entregue: a principal fica à frente da produção e o trabalho vai ao ar na próxima entrega.
   - Qualquer outro: confira o commit na pasta de produção e se o endereço do sistema responde, grave em `entrega.md` o que encontrou e pare para avisar o usuário.
4. Grave em `entrega.md`: o resultado, o commit no ar, o commit anterior, o endereço do sistema e o comando de reversão de `projeto.md`.

## 10. Relatório

1. Dispare a `ponte` com o caminho da pasta da execução.
2. Grave a saída da ponte em `relatorio.md`, na pasta da execução.
3. Mostre ao usuário a saída da ponte, sem alterar, resumir ou acrescentar nada.
4. Se ficou tarefa bloqueada esperando resposta, a execução não acabou. Quando o usuário responder, siga pela seção 4 e, no fim, faça a entrega e um relatório novo.

## Regras

- Decisão ambígua: escolha a leitura mais razoável, registre em `decisoes.md` e continue. Não pergunte no meio da execução; a exceção é a tarefa bloqueada, na seção 4.
- Comando demorado, como a pilha de testes e a implantação, roda com tempo limite maior que os dois minutos padrão. Nunca interrompa uma implantação no meio.
- Pare e pergunte somente se a produção ficar fora do ar, se todas as tarefas estiverem bloqueadas ou se a próxima ação for irreversível e não estiver prevista na seção Entrega. A pergunta de tarefa bloqueada não é parada: as outras tarefas seguem.
- Merge na principal, envio e implantação acontecem só na seção Entrega e na sincronização da preparação, e só pelos comandos de `projeto.md`. Você nunca força um merge, nunca altera o banco de produção à mão e nunca dispara envio de mensagem ou cobrança.
- Quando o usuário responder às dúvidas do relatório, as respostas viram novas tarefas e percorrem o mesmo caminho. Proposta de melhoria aprovada também vira tarefa. Resposta a pergunta de tarefa bloqueada não vira tarefa nova: reabre, reescreve ou retira a própria tarefa, pela seção 4.
