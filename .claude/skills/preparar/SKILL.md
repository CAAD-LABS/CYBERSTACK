---
name: preparar
description: Prepara um projeto para a CyberStack. Diagnostica o repositório, cria os arquivos base e monta o plano de limpeza para o usuário aprovar.
argument-hint: [observações]
disable-model-invocation: true
model: opus
effort: high
---

Observações do usuário, se houver: $ARGUMENTS

Você prepara este repositório para trabalhar com a CyberStack. Esta etapa roda uma vez por projeto, antes do primeiro `/fluxo`.

Você diagnostica, cria os arquivos base e propõe a limpeza. Você não remove, não move e não reescreve código: isso acontece depois, pelo `/fluxo`, com o plano que o usuário aprovar. Também não faz commit.

Os modelos dos arquivos base estão em `${CLAUDE_SKILL_DIR}/modelos/`.

## 1. Diagnóstico

Dispare o `inspetor` e grave a saída em `.cyberstack/preparacao/diagnostico.md`.

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
- As seções "Stack" e "Banco de dados" do modelo de `AGENTS.md` são o padrão da CyberStack e entram como estão. Onde o projeto não segue o padrão, não mude o texto: a diferença vira tarefa de adequação no plano.
- Você não instala a unidade do serviço nem mexe em permissões do sistema. Isso exige sudo e fica com o usuário.
- Uma skill só é criada se todos os campos do modelo puderem ser preenchidos. Se faltar algum, não crie e diga qual faltou.
- Este é o único momento em que um agente escreve os arquivos de orientação, porque o usuário pediu ao chamar este comando. Nada vai para commit sem ele.

## 3. Plano de limpeza

Escreva `.cyberstack/preparacao/plano.md` no mesmo formato de plano do `planejador`, com critérios de aceite e tarefas, nesta ordem:

1. **Rede de segurança.** Para cada área sem teste que a limpeza vai tocar, uma tarefa com a linha `- Tipo: testes`, que registra o comportamento atual, certo ou errado. Nada é removido de uma área sem teste.
2. **Adequação à entrega.** Uma tarefa para cada item que o diagnóstico marcou como fora do padrão na seção "Entrega": caminho do banco fixo no código, banco fora do modo WAL, falta do endereço de verificação, migração que não pode rodar duas vezes.
3. **Remoção de código morto.** Somente os itens de "Candidatos à remoção". Uma tarefa por grupo coeso. Cada tarefa lista exatamente o que sai.
4. **Estrutura.** Uma tarefa por movimento ou junção, com a lista de arquivos e as referências a atualizar.
5. **Documentação.** A documentação desatualizada ou órfã não vira tarefa: o documentador corrige no fim, a partir do diagnóstico.

Todo plano de limpeza tem estes critérios de aceite, além dos específicos:

- a pilha de testes dá o mesmo resultado de antes da tarefa;
- nenhum comportamento observável muda;
- nenhum arquivo fora da lista da tarefa é alterado.

Tarefas que tocam os mesmos arquivos dependem uma da outra. Remoções em áreas distintas podem ser independentes.

Fica fora do plano: os "Suspeitos", que viram dúvida para o usuário, e os "Riscos", que são dele para resolver.

## 4. Proposta

Mostre ao usuário exatamente isto e pare:

```
# Preparação: <projeto>

## 1. Situação do projeto
<três a cinco linhas: o que roda, o que não roda, estado dos testes e da documentação>

## 2. Arquivos base
- <arquivo>: criado | completado. Em branco: <campos, ou "nada">.
- Não criado: <arquivo e o que faltou>

## 3. Plano de limpeza
- Rede de segurança: <n> tarefas de teste em <áreas>
- Adequação à entrega: <itens>
- Remoção: <n> itens. <os maiores, em uma linha>
- Estrutura: <movimentos, em uma linha>
- Documentação: <n> a corrigir, <n> a remover

## 4. Fora do plano
- Suspeitos de código morto: <itens e o que falta confirmar>
- Riscos: <arquivo e tipo>

## 5. Dúvidas
1. <pergunta>
   A) <opção>
   B) <opção>
   Recomendada: <A ou B>.

## 6. Para continuar
1. Revise `AGENTS.md`, `.cyberstack/projeto.md` e `deploy/config.env` e complete o que ficou em branco.
2. Ajuste `.cyberstack/preparacao/plano.md` se quiser tirar ou incluir algo.
3. Faça commit dos arquivos base.
4. Instale o serviço, uma vez, com os comandos que estão no topo de `deploy/<serviço>.service`. É isso que faz o sistema subir sozinho quando a máquina liga e voltar se o processo cair.
5. Rode: /fluxo executar o plano em .cyberstack/preparacao/plano.md
```

Seção sem conteúdo recebe "Nada".
