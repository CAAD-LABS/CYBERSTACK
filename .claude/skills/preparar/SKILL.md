---
name: preparar
description: Prepara um projeto para a CyberStack. Diagnostica o repositório, cria os arquivos base, monta o plano de limpeza, leva os arquivos base à principal e cria a pasta de produção.
argument-hint: [observações]
disable-model-invocation: true
model: opus
effort: high
---

Observações do usuário, se houver: $ARGUMENTS

Você prepara este repositório para trabalhar com a CyberStack. Esta etapa roda uma vez por projeto, antes do primeiro `/fluxo`.

Você diagnostica, cria os arquivos base, propõe a limpeza, leva os arquivos base à principal e cria a pasta de produção. Você não remove, não move e não reescreve código: isso acontece depois, pelo `/fluxo`, com o plano.

Os modelos dos arquivos base estão em `${CLAUDE_SKILL_DIR}/modelos/`.

## 1. Diagnóstico

Dispare o `inspetor`, com o caminho do modelo `AGENTS.md`, onde está a lista de slop, e grave a saída em `.cyberstack/preparacao/diagnostico.md`.

## 2. Arquivos base

Crie na pasta de trabalho, a partir dos modelos e do diagnóstico:

- `AGENTS.md`, do modelo `AGENTS.md`. Se já existir `AGENTS.md` ou `CLAUDE.md` com conteúdo, aproveite o que continua verdadeiro, descarte o que o diagnóstico marcou como desatualizado e anote o que descartou.
- `CLAUDE.md`, contendo apenas a linha `@AGENTS.md`.
- `.cyberstack/projeto.md`, do modelo `projeto.md`.
- `.claude/skills/rodar-testes/SKILL.md`, do modelo `rodar-testes.md`.
- `.claude/skills/verificar-tela/SKILL.md`, do modelo `verificar-tela.md`, somente se o projeto tem interface.
- A pasta `deploy/`, dos modelos em `modelos/deploy/`. Copie `implantar.sh` e `reverter.sh` sem alterar, com permissão de execução. Preencha `config.env` e a unidade do serviço, salva como `deploy/<nome do serviço>.service`.
- No `.gitignore`, as linhas `.cyberstack/execucoes/` e `.claude/worktrees/`.

Regras:

- Escreva somente o que o diagnóstico confirmou. Comando que o inspetor não rodou com sucesso fica em branco.
- As seções "Stack", "Banco de dados" e "Slop" do modelo de `AGENTS.md` são o padrão da CyberStack e entram como estão. Onde o projeto não segue o padrão, não mude o texto: a diferença vira tarefa de adequação no plano.
- Você não mexe em permissões do sistema. A unidade do serviço só é instalada nas condições da seção 6.
- Uma skill só é criada se todos os campos do modelo puderem ser preenchidos. Se faltar algum, não crie e diga qual faltou.
- Este é o único momento em que um agente escreve os arquivos de orientação, porque o usuário pediu ao chamar este comando. Eles vão à principal depois das perguntas da seção 4, sem esperar outra aprovação.

## 3. Plano de limpeza

Escreva `.cyberstack/preparacao/plano.md` no mesmo formato de plano do `planejador`, com critérios de aceite e tarefas, nesta ordem:

1. **Banco fora do alcance.** Se o diagnóstico mostra o caminho do banco fixo no código, ou outro caminho pelo qual um teste ou uma cópia de trabalho abriria o banco de produção, a adequação que resolve isso é a primeira tarefa do plano, sozinha, com a linha `- Tipo: banco`, e todas as outras dependem dela. É a única mudança feita sem rede de segurança: um teste gravando no banco de produção é pior que uma mudança pequena sem teste. Ela muda só o necessário, e os critérios dela são: o caminho do banco vem da variável `BANCO`; sem a variável, a aplicação para com erro e não abre banco nenhum; os testes passam a rodar em banco próprio.
2. **Rede de segurança.** Para cada área sem teste que a limpeza vai tocar, uma tarefa com a linha `- Tipo: testes`, que registra o comportamento atual, certo ou errado. Nada é removido de uma área sem teste.
3. **Adequação à entrega.** Uma tarefa para cada um dos outros itens que o diagnóstico marcou como fora do padrão na seção "Entrega": banco fora do modo WAL, falta do endereço de verificação, migração que não pode rodar duas vezes, falta do comando de contas de teste. O comando de contas de teste cria uma conta para cada perfil de usuário, com nome que deixa claro que é de teste e senha forte gerada na hora; não mexe em conta que já existe; grava as credenciais no arquivo de `CONTAS_ARQUIVO`, fora do repositório e legível só pelo dono; e pode rodar duas vezes. A tarefa que o cria preenche `CONTAS_DE_TESTE` em `deploy/config.env`.
4. **Remoção de código morto.** Somente os itens de "Candidatos à remoção". Uma tarefa por grupo coeso. Cada tarefa lista exatamente o que sai.
5. **Slop.** Somente os itens de "Slop" do diagnóstico, menos os de erro engolido. Uma tarefa por tipo de slop em cada área, com a lista exata de arquivo e linha. Duplicação vira uma só, com os chamadores apontando para a que fica; abstração de um uso volta para dentro do chamador.
6. **Estrutura.** Uma tarefa por movimento ou junção, com a lista de arquivos e as referências a atualizar.
7. **Documentação.** A documentação desatualizada ou órfã não vira tarefa: o documentador corrige no fim, a partir do diagnóstico.

Todo plano de limpeza tem estes critérios de aceite, além dos específicos:

- a pilha de testes dá o mesmo resultado de antes da tarefa;
- nenhum comportamento observável muda;
- nenhum arquivo fora da lista da tarefa é alterado.

O primeiro e o terceiro são critérios de processo: quem confere é o orquestrador, pela pilha e pela lista de arquivos do commit, e eles não pedem teste novo. A tarefa `Tipo: banco` não tem o primeiro: a pilha não roda antes dela.

Tarefas que tocam os mesmos arquivos dependem uma da outra. Fora a `Tipo: banco`, que vem antes de tudo, toda tarefa de adequação, remoção, slop ou estrutura depende das tarefas `Tipo: testes` da área que ela toca, menos as de slop que só tiram comentário ou arquivo de trabalho de agente, porque não mexem em código que roda: a ordem acima não basta, porque o `/fluxo` dispara junto tudo o que não tem dependência. Remoções em áreas distintas podem ser independentes entre si.

Fica fora do plano: os "Suspeitos", que viram dúvida para o usuário, os demais "Riscos", que são dele para resolver, e o erro engolido. Tirar um `except` muda o que o sistema faz quando dá erro, então cada um vira pergunta: o erro deve aparecer, ser tratado de outro jeito ou continuar ignorado de propósito.

## 4. Perguntas

Antes de entregar, faça ao usuário, uma por vez, em texto, só as perguntas que são dele:

- os "Suspeitos" de código morto, cada um com o que falta confirmar;
- cada erro engolido do diagnóstico;
- cada campo em branco dos arquivos base que só ele sabe, como a pasta de produção e o endereço do sistema.

Cada pergunta traz as opções e a recomendada, tirada do diagnóstico. Comando que o inspetor não conseguiu rodar não vira pergunta: fica em branco. Com cada resposta, atualize o arquivo ou o plano na hora. Pergunta que ele pular fica como está e vai para o relatório.

## 5. Entrega dos arquivos base

Leve os arquivos base à principal, pelo caminho de "Como levar à principal" em `projeto.md`:

1. Confira que a pasta está na principal e, se houver remoto, que a principal local é igual à remota depois de buscar. Se não estiver, não entregue: diga o que encontrou.
2. Crie a branch `cyberstack-preparacao` e faça commit somente dos arquivos que você criou ou completou nas seções 2 a 4, do `.gitignore` e de `.cyberstack/preparacao/`. Adicione cada um pelo caminho, nunca a pasta inteira: alteração do usuário em outro arquivo fica fora do commit.
3. Com pull request: envie a branch, abra o PR com o resumo do diagnóstico e do plano e faça o merge. Se o merge for recusado por conflito ou por regra do repositório, não force e diga o motivo. Sem remoto, ou com "Como levar à principal" dizendo direto, faça o commit na própria principal.
4. Volte a pasta para a principal atualizada e apague a branch local.

## 6. Pasta de produção e serviço

Se `projeto.md` tem a pasta de produção e ela ainda não existe, crie: um clone do repositório na principal, com `.venv` e as dependências instaladas pelo comando `INSTALAR` de `deploy/config.env`. Se ela já existe e não é um clone deste repositório, não mexa: diga o que encontrou.

Na pasta de produção você não roda a migração, o comando de contas de teste nem a aplicação, e não cria, copia nem move banco. Isso é da primeira implantação do `/fluxo`. Se o sistema já roda de outra pasta, com banco em uso, a troca para a pasta nova fica com o usuário, e o relatório diz os passos.

Instale a unidade do serviço, com os comandos do topo de `deploy/<serviço>.service`, somente se valem as três: `sudo -n true` funciona, não existe unidade com esse nome e nada escuta na porta do sistema. Faltou uma, o serviço fica com o usuário, e o relatório diz qual faltou.

## 7. Relatório

Mostre ao usuário exatamente isto e pare:

```
# Preparação: <projeto>

## 1. Situação do projeto
<três a cinco linhas: o que roda, o que não roda, estado dos testes e da documentação>

## 2. Arquivos base
- <arquivo>: criado | completado. Em branco: <campos, ou "nada">.
- Não criado: <arquivo e o que faltou>

## 3. Plano de limpeza
- Antes de tudo: <adequação do caminho do banco, ou "não precisa">
- Rede de segurança: <n> tarefas de teste em <áreas>
- Adequação à entrega: <itens>
- Remoção: <n> itens. <os maiores, em uma linha>
- Slop: <n> itens, por tipo
- Estrutura: <movimentos, em uma linha>
- Documentação: <n> a corrigir, <n> a remover

## 4. Fora do plano
- Suspeitos de código morto: <itens e o que falta confirmar>
- Riscos: <arquivo e tipo>

## 5. Respostas
- <pergunta>: <resposta e o que mudou>
- Sem resposta: <perguntas puladas>

## 6. Entrega
- Arquivos base: PR #<n> mesclado em <commit curto> | commit direto na principal <commit curto> | não entregue: <motivo>
- Pasta de produção: criada em <caminho> | já existia | não criada: <motivo>
- Serviço: instalado e ativo | com você: <o que faltou>

## 7. Para continuar
1. <o que ficou com você, se ficou: comandos do serviço, troca da pasta, campos em branco>
2. Rode: /fluxo executar o plano em .cyberstack/preparacao/plano.md
```

Seção sem conteúdo recebe "Nada".
