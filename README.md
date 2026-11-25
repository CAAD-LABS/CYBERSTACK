# CyberStack

Stack de agentes de desenvolvimento para o Claude Code, rodando na assinatura Claude. Leva um projeto da preparação inicial até cada feature no ar, com subagentes em paralelo, entrega automática e um relatório único no fim.

Feita para projetos em Python, com banco SQLite3 e front em HTML e JavaScript, rodando como serviço em uma máquina Linux com systemd.

São dois comandos:

| Comando | Quando | O que faz |
|---|---|---|
| `/preparar` | Uma vez por projeto, antes de tudo | Diagnostica o repositório, cria os arquivos base e propõe a limpeza. |
| `/fluxo <pedido>` | A cada feature, e para executar a limpeza aprovada | Planeja, implementa, testa, verifica, integra, documenta, entrega e relata. |

As definições de cada perfil estão em [`.claude/agents/`](.claude/agents) e os dois comandos em [`.claude/skills/`](.claude/skills), neste repositório. Como instalar está [mais abaixo](#instalar).

Situação: desenho fechado e definições escritas. A stack ainda não rodou em um projeto real. Os dois scripts de implantação são exercitados por `testes/implantacao.sh`, com 88 conferências.

## Fluxo completo

Do primeiro comando até o sistema no ar, em um desenho só. As seções seguintes detalham cada parte.

```mermaid
flowchart TD
    U(["Você"])

    subgraph PREP["1. Preparação, uma vez por projeto, com /preparar"]
        INS["Inspetor<br/>diagnóstico com evidência"]
        BASE["Arquivos base<br/>AGENTS.md, projeto.md, deploy, skills"]
        PLIMP["Plano de limpeza<br/>banco, testes, adequação, remoção, estrutura"]
        PROP["Proposta<br/>situação, plano e dúvidas"]
        INS --> BASE
        BASE --> PLIMP
        PLIMP --> PROP
    end

    subgraph FEAT["2. Cada pedido, com /fluxo"]
        SYNC{{"Produção igual à principal?"}}
        PL["Planejador<br/>critérios de aceite e tarefas"]
        G0{{"Gatilho: tarefa sem dependência, com vaga no teto"}}

        subgraph TAR["Uma cópia do código por tarefa, várias em paralelo"]
            IMP["Implementador<br/>escreve e roda o código"]
            GA{{"Gatilho A: pilha existente passou"}}
            TES["Testador<br/>cria e roda testes novos"]
            GB{{"Gatilho B: testes novos passaram"}}
            REV["Revisor<br/>diff e documentação"]
            TEL["Verificador de tela<br/>se toca interface"]
            SEG["Segurança<br/>se toca área sensível"]
            GC{{"Gatilho C: todos aprovaram"}}
            IMP --> GA
            GA --> TES
            TES --> GB
            GB --> REV
            GB --> TEL
            GB --> SEG
            REV --> GC
            TEL --> GC
            SEG --> GC
        end

        REP["Reprovação<br/>soma uma tentativa"]
        BLQ["Tarefa bloqueada<br/>volta para você com perguntas"]
        INT["Integração serial<br/>uma tarefa por vez"]
        DOC["Documentador<br/>documentação compartilhada"]
        GD{{"Gatilho D: só documentação alterada"}}

        SYNC --> PL
        PL --> G0
        G0 --> IMP
        GC --> INT
        INT --> DOC
        DOC --> GD
        GA -.-> REP
        GB -.-> REP
        GC -.-> REP
        REP -.-> IMP
        REP -.-> BLQ
    end

    subgraph ENT["3. Entrega automática"]
        GE{{"Gatilho E: tudo integrado, nada bloqueado"}}
        PR["PR e merge na principal"]
        IMPL["implantar.sh, uma entrega por vez<br/>cópia do banco, código, migração, contas de teste, reinício"]
        VS{{"Serviço ativo e respondendo?"}}
        AR["No ar<br/>produção é onde você testa"]
        VOLTA["Volta ao commit anterior<br/>principal sincronizada depois"]
        GE --> PR
        PR --> IMPL
        IMPL --> VS
        VS -->|"sim"| AR
        VS -.->|"não"| VOLTA
    end

    PONTE["Ponte<br/>relatório com o desenho da execução"]

    U -->|"/preparar"| INS
    PROP -->|"você revisa, faz commit, prepara a produção e roda /fluxo com o plano"| SYNC
    U -->|"/fluxo com o pedido"| SYNC
    GD --> GE
    GE -.->|"gatilho aberto: fica na branch de integração"| PONTE
    AR --> PONTE
    VOLTA --> PONTE
    PONTE -->|"relatório, roteiro de teste e comando de reversão"| U
    U -.->|"reverter.sh, quando você quiser"| VOLTA
    BLQ -.->|"perguntas na hora; a resposta reabre a tarefa"| U
```

Linhas tracejadas são os caminhos de falha, de espera e de reversão.

## Princípios

- **Poucos papéis fixos.** Cada perfil tem uma função, um contexto limpo e permissões próprias.
- **Verificação em vez de instrução.** Teste, lint e conferência de arquivos valem mais do que texto pedindo cuidado.
- **Do mais barato ao mais caro.** Cada etapa só roda se a anterior passou.
- **Testes depois da implementação,** por um agente que parte dos critérios de aceite e não do código.
- **Todos executam, poucos alteram.** Qualquer agente roda a aplicação e os testes na sua cópia do código. A restrição é sobre o que cada um pode modificar.
- **Paralelismo por subagentes.** O orquestrador dispara várias cópias do mesmo perfil, cada uma em sua cópia do código. A integração é serial. Um teto em `projeto.md` diz quantas tarefas andam ao mesmo tempo.
- **Continuidade sem você.** Fim de etapa por condição verificável, limite de tentativas e estado gravado em arquivo.
- **Entrega automática, com volta garantida.** Quando todos os gatilhos passam, o trabalho vai para a principal e para produção sem esperar você. Toda entrega pode ser desfeita com um comando.
- **Um único relatório,** em formato fixo, com o desenho do que aconteceu e as dúvidas numeradas.
- **Orientação em fonte única.** `AGENTS.md` é o arquivo real; `CLAUDE.md` só o importa.
- **Nada se remove sem evidência e sem teste.** Vale para a limpeza inicial e para qualquer feature.

## Preparação do projeto

Antes da primeira feature, o projeto passa por uma etapa própria: entender o que existe, criar os arquivos base e limpar.

```mermaid
flowchart TD
    U["Você<br/>chama /preparar"]
    INS["Inspetor<br/>diagnóstico com evidência"]
    BASE["Arquivos base<br/>AGENTS.md, CLAUDE.md, projeto.md, deploy, skills"]
    PLANO["Plano de limpeza<br/>banco, testes, adequação, remoção, estrutura"]
    PROP["Proposta<br/>situação, plano e dúvidas"]
    AP{{"Você revisa, faz commit<br/>e prepara a produção"}}
    FL["/fluxo executa o plano<br/>mesmo caminho de uma feature"]
    DOC["Documentador<br/>corrige a documentação antiga"]
    REL["Relatório da ponte"]

    U --> INS
    INS --> BASE
    BASE --> PLANO
    PLANO --> PROP
    PROP --> AP
    AP --> FL
    FL --> DOC
    DOC --> REL
```

O `/preparar` não mexe em código. Ele para na proposta e espera você, porque decidir o que é código morto é o tipo de escolha que pode ir para os dois lados.

**Diagnóstico.** O inspetor roda os comandos do projeto e anota o resultado real, mapeia as pastas, levanta que áreas têm teste, classifica cada documento como correto, desatualizado ou órfão, e procura código morto, problemas de estrutura, o que falta e segredos versionados.

**Código morto exige três verificações.** Nenhuma referência no repositório, não é ponto de entrada e não é carregado de forma dinâmica. Faltou uma, o item é "suspeito": não entra no plano e vira dúvida para você.

**Arquivos base.** `AGENTS.md`, `CLAUDE.md`, `.cyberstack/projeto.md`, as skills locais de teste e de tela, a pasta `deploy/` com os scripts de implantação e a unidade do serviço, e as linhas do `.gitignore`. Só entra o que o diagnóstico confirmou; o resto fica em branco. É o único momento em que um agente escreve os arquivos de orientação, e nada vai para commit sem você.

**Plano de limpeza,** nesta ordem:

1. Banco fora do alcance: se o código abre o banco por um caminho fixo, a adequação desse caminho é a primeira tarefa, sozinha, e todo o resto depende dela. É a única mudança feita sem rede de segurança, porque um teste gravando no banco de produção é pior que uma mudança pequena sem teste.
2. Rede de segurança: testes que registram o comportamento atual das áreas sem teste que serão tocadas.
3. Adequação à entrega: o que mais estiver fora do padrão, como banco fora do modo WAL ou falta do endereço de verificação.
4. Remoção de código morto, em grupos coesos, cada tarefa com a lista exata do que sai.
5. Estrutura: movimentos e junções de arquivos.
6. Documentação: corrigida no fim pelo documentador, a partir do diagnóstico.

Toda tarefa de limpeza tem três critérios fixos: a pilha de testes dá o mesmo resultado de antes, nenhum comportamento observável muda e nenhum arquivo fora da lista é alterado. Remoção, adequação e estrutura dependem das tarefas de teste da mesma área, para a rede de segurança existir antes da mudança.

**Execução.** Depois de revisar, fazer commit dos arquivos base, criar a pasta de produção e instalar o serviço, você roda `/fluxo executar o plano em .cyberstack/preparacao/plano.md`. A limpeza percorre o mesmo caminho de uma feature, com os mesmos gatilhos.

## Visão geral de uma feature

```mermaid
flowchart TD
    U["Você<br/>pede, responde, testa e aprova"]
    P["Perfil ponte<br/>relatório com o desenho do fluxo"]
    O["Orquestrador<br/>comando /fluxo, confere gatilhos"]
    PL["Planejador<br/>critérios de aceite e tarefas"]
    T["Tarefas em paralelo<br/>ver o diagrama de gatilhos"]
    I["Integração serial<br/>uma tarefa por vez"]
    D["Documentador<br/>documentação compartilhada"]
    E["Entrega automática<br/>PR, merge e implantação"]
    A["Produção<br/>o mesmo ambiente do seu teste"]

    U -->|pedido e respostas| P
    P -->|relatório| U
    P --> O
    O --> PL
    PL --> T
    T --> I
    I --> D
    D --> E
    E --> A
    A -->|estado final em arquivo| P
    T -.->|tarefa bloqueada: perguntas na hora| U
```

No Claude Code, quem conversa com você é sempre a sessão principal, que faz o papel de orquestrador. A ponte é um subagente que escreve o relatório lendo só os artefatos, e o orquestrador repassa o texto sem alterar.

## Gatilhos de disparo

```mermaid
flowchart TD
    O["Orquestrador<br/>lê o plano"]
    G0{{"Gatilho: tarefa sem dependência<br/>e com vaga no teto"}}
    TA["Tarefa A<br/>cópia própria do código"]
    TB["Tarefa B<br/>cópia própria do código"]
    TC["Tarefa C<br/>cópia própria do código"]

    O --> G0
    G0 --> TA
    G0 --> TB
    G0 --> TC
    TB --> IMP

    subgraph CADA["Dentro de cada tarefa"]
        IMP["Implementador<br/>escreve e roda o código"]
        GA{{"Gatilho A: pilha existente passou"}}
        TES["Testador<br/>cria e roda testes novos"]
        GB{{"Gatilho B: testes novos passaram"}}
        REV["Revisor<br/>diff e documentação"]
        TEL["Verificador de tela<br/>se toca interface"]
        SEG["Segurança<br/>se toca área sensível"]
        GC{{"Gatilho C: todos aprovaram"}}
        REP["Reprovação<br/>soma uma tentativa"]
        ARB["Revisor arbitra<br/>uma vez por teste"]

        IMP --> GA
        GA --> TES
        TES --> GB
        GB --> REV
        GB --> TEL
        GB --> SEG
        REV --> GC
        TEL --> GC
        SEG --> GC
        GA -.->|não passou| REP
        GB -.->|não passou| REP
        GC -.->|alguém reprovou| REP
        REP -.->|até a segunda| IMP
        IMP -.->|contesta um teste| ARB
        ARB -.->|teste errado| TES
        ARB -.->|teste certo| IMP
    end

    GC --> INT["Integração serial<br/>uma tarefa por vez"]
    REP -.->|terceira tentativa| BLQ["Tarefa bloqueada<br/>volta para você com perguntas"]
    BLQ -.->|sua resposta reabre a tarefa| IMP
```

Há dois pontos de disparo em leque: o orquestrador abre um implementador por tarefa independente, e o Gatilho B abre revisor, verificador de tela e segurança ao mesmo tempo sobre o mesmo diff. Entre eles o disparo é em série. Os três usam a mesma cópia do código, mas cada um sobe a aplicação com banco de exemplo e porta próprios, em uma pasta temporária fora dela, para um não interferir no outro.

O que o orquestrador confere em cada gatilho:

| Gatilho | Dispara | Condição |
|---|---|---|
| Tarefa liberada | Um implementador por tarefa, em paralelo | A tarefa não depende de outra ainda pendente e há vaga no teto de tarefas ao mesmo tempo. |
| A | Testador | O implementador respondeu PRONTO e a pilha existente passa quando o orquestrador roda o comando. |
| B | Revisor, verificador de tela, segurança | O testador aprovou, a pilha completa passa e ele só alterou arquivos nas pastas de teste. |
| C | Integração | Todos os disparados aprovaram e nenhum deles alterou o código. |
| D | Entrega | O documentador só alterou as pastas de documentação compartilhada. |
| E | PR, merge e implantação | Todas as tarefas integradas ou retiradas por você, nenhuma bloqueada, pilha completa passando na integração e entrega automática ligada. |

O orquestrador não aceita relato: ele mesmo roda o comando de teste e olha a lista de arquivos de cada commit. "A pilha passa" quer dizer que não há falha além das que já existiam antes da execução, medidas por ele na branch de integração. Tela e segurança são disparadas pelo que o diff toca, não só pelo que o plano previu.

Tarefa marcada como `Tipo: testes`, usada na rede de segurança da limpeza, não passa pelo implementador: começa direto no testador. Tarefa `Tipo: banco`, que tira do código o caminho fixo do banco, vai sozinha antes de todas, e nada roda antes dela.

## Perfis

| Perfil | Modelo | Esforço | Altera | Quando entra |
|---|---|---|---|---|
| Orquestrador (`/fluxo` e `/preparar`) | opus | high | Artefatos; no `/preparar`, os arquivos base; a orientação, só com proposta que você aprovou | Sempre. É a sessão principal. |
| inspetor | opus | high | Nada | Uma vez por projeto, no `/preparar`. |
| planejador | opus | high | Nada | No início de cada feature, dispensado em pedido pequeno. E quando uma tarefa bloqueia. |
| implementador | opus | medium | Código e documentação junto do código | Um por tarefa. |
| testador | sonnet | high | Só as pastas de teste | Depois do Gatilho A. |
| revisor | opus | high | Nada | Depois do Gatilho B, sempre. E como árbitro de teste contestado. |
| verificador-tela | sonnet | medium | Nada | Depois do Gatilho B, se a tarefa toca interface. |
| seguranca | opus | xhigh | Nada | Depois do Gatilho B, se a tarefa toca área sensível. |
| documentador | sonnet | medium | Só a documentação compartilhada | Uma vez, depois da integração. |
| ponte | sonnet | medium | Nada | Uma vez, no fim. |

Todos podem executar código na sua cópia. Nenhum subagente faz nada com efeito fora dela: banco de produção, envio real de mensagem, cobrança, push ou implantação. Merge e implantação são feitos só pelo orquestrador, na entrega, pelos scripts do projeto.

Se o limite da assinatura apertar, o primeiro ajuste é o implementador para `sonnet` com esforço `high`, e depois o orquestrador para esforço `medium`.

O modelo e o esforço escritos no cabeçalho de `/fluxo` e de `/preparar` valem só no turno em que o comando é digitado. Os subagentes rodam em segundo plano, e cada retorno abre um turno novo, que usa o modelo e o esforço da sessão. Para o orquestrador rodar como na tabela do começo ao fim, abra a sessão já em `opus` com esforço `high`. É também na sessão que se baixa o esforço dele.

### O que cada um faz

- **Inspetor.** Examina o repositório inteiro e entrega o diagnóstico. Comando que ele não rodou não entra como confirmado. Não roda nada que aponte para o banco ou para as integrações de produção.
- **Planejador.** Lê o código, roda o sistema se precisar, escreve os critérios de aceite e divide em tarefas. Duas tarefas só são independentes se não tocam os mesmos arquivos. Quando uma tarefa bloqueia, analisa o bloqueio e escreve as perguntas para você.
- **Implementador.** Roda a pilha antes de começar para ter a linha de base, implementa executando e só entrega com a pilha passando. Não altera teste existente para fazê-lo passar e não escreve os testes da feature. Pode contestar um teste do testador que considere errado.
- **Testador.** Lê os critérios de aceite antes do diff e escreve pelo menos um teste por critério. Se acha defeito, reprova com o teste que falha; não conserta o código.
- **Revisor.** Procura critério não atendido, defeito, teste que só confirma a implementação, código desnecessário, documentação de módulo desatualizada e alteração indevida nos arquivos de orientação. Todo bloqueante tem arquivo, linha e cenário. Também arbitra teste contestado.
- **Verificador de tela.** Sobe a aplicação da tarefa em uma porta temporária e a usa pelo navegador, como uma pessoa, com as contas de teste. Tira uma captura por passo e tenta também os caminhos errados. Não consulta banco, API nem código.
- **Segurança.** Segue o dado da entrada até o uso. Só bloqueia com caminho de exploração.
- **Documentador.** Lê o diff integrado e corrige a documentação compartilhada. Na limpeza, corrige também o que o diagnóstico apontou. Se um arquivo de orientação ficou desatualizado, propõe a mudança em vez de fazer.
- **Ponte.** Relata o que os artefatos dizem, sem interpretar nem suavizar. Falha aparece primeiro.

## Reprovação e bloqueio

1. Qualquer gatilho que falhe soma uma tentativa e é anotado no registro de aprendizado.
2. A tarefa volta ao implementador com o motivo e nada mais.
3. O caminho é refeito desde o Gatilho A.
4. Na terceira tentativa a tarefa é marcada como bloqueada. As outras continuam, menos as que dependem dela, que ficam bloqueadas também.

**Teste contestado.** O implementador não mexe em teste, mas pode contestar um teste do testador que considere errado. O revisor arbitra, uma vez por teste, com o critério de aceite como régua. Teste errado volta ao testador para correção, e a reprovação que ele causou deixa de contar. Teste certo volta ao implementador, sem nova contestação. Se o critério não decide, a tarefa bloqueia e a pergunta vai para você.

**Tarefa bloqueada volta para você, na hora.** O planejador analisa o bloqueio e escreve o que travou e a sequência de perguntas necessárias para prosseguir ou para chegar a outra solução. O orquestrador faz essas perguntas a você, uma por vez, sem parar as outras tarefas. Com as respostas, a tarefa é reaberta com tentativas novas, reescrita pelo planejador ou retirada do pedido. Se a execução terminar antes de você responder, as perguntas vão no relatório e nada é entregue até lá.

Se a pilha falhar depois de um merge na integração, o merge é desfeito e a tarefa é tratada como reprovada. O mesmo vale para conflito de merge. Nos dois casos, a tarefa volta ao implementador já com o código das outras tarefas integradas.

## Entrega automática e reversão

O sistema em produção é também o ambiente em que você testa. Por isso, sucesso nos gatilhos significa entrega completa, sem esperar verificação humana, e toda entrega precisa poder ser desfeita.

```mermaid
flowchart TD
    GE{{"Gatilho E: tudo integrado e passando"}}
    PR["PR e merge na principal"]
    FI["Fila<br/>uma implantação por vez"]
    BK["Cópia do banco"]
    IM["Código, dependências, migração<br/>e contas de teste"]
    RS["Reinício do serviço"]
    VS{{"Verificação: serviço ativo e respondendo,<br/>duas vezes seguidas"}}
    OK["No ar<br/>commit e cópia registrados"]
    VA["Volta sozinha ao commit anterior"]
    SY["Principal sincronizada<br/>commit novo com o conteúdo que está no ar"]
    FA["Produção fora do ar<br/>para tudo e avisa você"]
    NE["Nada mudou em produção<br/>tenta de novo e relata"]

    GE --> PR
    PR --> FI
    FI --> BK
    BK --> IM
    IM --> RS
    RS --> VS
    VS -->|passou| OK
    VS -.->|falhou| VA
    VA -->|voltou| SY
    VA -.->|não voltou| FA
    BK -.->|parou antes de trocar o código| NE
```

**Quando entrega.** O Gatilho E fecha quando todas as tarefas foram integradas, nenhuma ficou bloqueada, a pilha completa passa na integração e a entrega automática está ligada em `projeto.md`. Com qualquer tarefa bloqueada, nada é entregue: o trabalho fica na branch de integração e o relatório diz por quê. Quando você responde às perguntas dela, a execução segue de onde parou.

**Como entrega.** O orquestrador abre o pull request com o resumo do plano e os vereditos e faz o merge. Em repositório sem pull request, avança a principal direto. Se o merge for recusado por conflito ou por regra do repositório, ele não força. Em seguida roda `deploy/implantar.sh` na pasta de produção, que:

1. copia o banco SQLite, pela API de cópia do próprio SQLite, segura com o sistema no ar;
2. coloca o código do commit e, com a configuração desse commit, instala dependências e roda a migração;
3. reinicia o serviço;
4. verifica, duas vezes seguidas, que o serviço está ativo e que o endereço de verificação responde;
5. registra a implantação: data, commit, cópia do banco e resultado.

Na primeira implantação, o registro ganha também o commit que já estava no ar, para a primeira entrega ter para onde voltar.

Só uma implantação roda por vez em cada pasta de produção. Se duas entregas do mesmo projeto chegarem juntas, a segunda espera a primeira acabar e parte do que ela deixou no ar. A reversão entra na mesma fila.

**Se a verificação falha,** o script volta sozinho ao commit que estava no ar e reinicia, sem rodar migração de novo. O orquestrador então devolve à principal o conteúdo que está no ar, com um commit novo, para ela não ficar com código que falhou.

**Se o script para antes de trocar o código,** por falha de rede ou da cópia do banco, o orquestrador tenta mais uma vez. Se repetir, relata como não entregue e a principal fica à frente da produção até a próxima entrega.

**Voltar uma versão quando você quiser.** Na pasta de produção:

| Comando | Efeito |
|---|---|
| `deploy/reverter.sh` | Volta para a implantação bem-sucedida anterior. Rodar de novo volta mais uma. |
| `deploy/reverter.sh <commit>` | Volta para um commit específico. |
| `deploy/reverter.sh --listar` | Mostra as implantações registradas. |
| `deploy/reverter.sh --restaurar-banco <cópia>` | Restaura o banco de uma cópia e reinicia. |

A volta funciona mesmo sem acesso ao remoto, porque o commit já está na pasta de produção.

Voltar o código não volta o banco. Restaurar a cópia apagaria tudo o que foi gravado depois dela, então isso só acontece quando você pede. O que torna isso seguro é a regra de migração do `AGENTS.md`: migração só acrescenta, de modo que a versão anterior do código funciona com o banco novo.

**Depois de uma reversão,** a principal ainda contém o código que saiu do ar. No início do próximo `/fluxo`, o orquestrador compara o commit em produção com a ponta da principal e consulta o registro de implantações. Se a ponta da principal já esteve em produção, ele cria um commit que devolve à principal o conteúdo exato do que está no ar e confere que ficou idêntico. Só então começa a feature nova.

**Commit seu direto na principal,** que nunca foi implantado, não é reversão: nada é desfeito, e ele vai ao ar com a próxima entrega.

**Queda de máquina.** O serviço roda como unidade systemd com `Restart=always`, habilitada na inicialização: volta se o processo cair e sobe sozinho quando a máquina liga. O banco em modo WAL resiste a desligamento abrupto. Se o sistema roda em máquina virtual, falta configurar no hospedeiro o início automático da própria máquina virtual.

**O que foi testado.** Os dois scripts rodam em simulação, com um serviço Python e banco SQLite: implantação boa com migração, implantação quebrada com volta automática, reversão manual com o banco preservado, restauração de banco e falha total. A simulação está em `testes/implantacao.sh`. A unidade systemd passa no `systemd-analyze verify`, mas a instalação dela e os comandos com sudo não foram testados em uma máquina real.

**O risco que fica.** Sem ambiente separado, um defeito que passe por todos os gatilhos chega aos usuários antes de você ver. Para sistemas que cobram ou enviam mensagens a clientes, `projeto.md` tem a opção de segurar a entrega quando a execução toca área sensível. Ela vem desligada.

## Estado e artefatos

Tudo o que acontece fica em arquivo, para a execução poder ser retomada e para a ponte ter de onde ler.

```
.cyberstack/
  projeto.md                     configuração do fluxo
  preparacao/
    diagnostico.md               saída do inspetor
    plano.md                     plano de limpeza
  execucoes/<data>-<pedido>/
    pedido.md                    o pedido, como foi escrito
    plano.md                     critérios de aceite e tarefas
    linha-de-base.md             resultado da pilha antes de qualquer tarefa
    decisoes.md                  o que foi decidido sem perguntar
    aprendizado.md               reprovações e propostas de correção
    documentacao.md              saída do documentador
    entrega.md                   resultado da entrega e comando de reversão
    relatorio.md                 relatório da ponte, com o desenho
    <tarefa>/
      estado.json                estado, tentativas e número da volta
      entrega-<volta>.md         saída do implementador
      testes-<volta>.md          saída do testador
      revisao-<volta>.md         saída do revisor
      tela-<volta>.md            saída do verificador de tela
      seguranca-<volta>.md       saída do revisor de segurança
      capturas-<volta>/          uma imagem por passo do roteiro
      arbitragem-<volta>.md      decisão do árbitro, se um teste for contestado
      bloqueio-<volta>.md        o que travou e as perguntas para você, se a tarefa bloquear
      respostas-<volta>.md       o que você respondeu
.claude/worktrees/
  <data>-<pedido>-integracao/    cópia do código da integração
  <data>-<pedido>-<tarefa>/      cópia do código de cada tarefa
```

A pasta da execução leva a data e o pedido em poucas palavras, como `2026-01-31-exportar-relatorio`, e guarda o pedido como foi escrito: é por ele que uma execução interrompida é reconhecida e retomada. Cada volta de uma tarefa grava as suas saídas com o número da volta. Nada é sobrescrito, e a retomada sabe qual saída vale.

Estados de uma tarefa: `implementando`, `testando`, `verificando`, `aprovada`, `integrada`, `bloqueada`, `retirada`.

A pasta em que você trabalha não é tocada pelo `/fluxo`. Com o Gatilho E fechado, o resultado vai para a branch principal e para produção; caso contrário, fica na branch `fluxo/<data>-<pedido>/integracao`.

## Relatório da ponte

Formato fixo, sempre com as mesmas nove seções:

1. **Situação:** concluído, concluído com ressalvas ou bloqueado, e o estado da entrega: no ar, não entregue, ou voltou sozinha à versão anterior.
2. **O que foi entregue,** em linguagem simples, e o que não foi.
3. **Como foi a execução:** o caminho que as tarefas percorreram.
4. **Evidência:** testes, revisão, tela, segurança e documentação, com os números copiados dos artefatos.
5. **Decisões tomadas por você:** o que os agentes escolheram sozinhos nos pontos ambíguos.
6. **Dúvidas:** numeradas, com opções, a recomendada e o que fica parado. Respondíveis com algo como "1B, 2A".
7. **Próximo passo:** o que acontece se você não fizer nada, e o comando para voltar à versão anterior.
8. **Como testar:** endereço do sistema e roteiro guiado.
9. **Propostas de melhoria permanente:** para aprovar ou recusar.

### O desenho do fluxo no relatório

A seção 3 se ajusta à complexidade do que aconteceu:

- **Sempre:** uma linha por tarefa, legível em qualquer tela, com as etapas percorridas e o número de tentativas.
- **Com duas ou mais tarefas, alguma reprovação ou algum bloqueio:** também um desenho em Mermaid, com um nó por tarefa, quais partiram juntas, quais dependiam de outras, quantas tentativas cada uma levou e o que ficou bloqueado.

O desenho mostra só o que está nos artefatos. Um exemplo com três tarefas, em que a T3 dependia da T1 e a T2 foi bloqueada:

```mermaid
flowchart LR
    P["Plano<br/>3 tarefas"]
    T1["T1 login<br/>1 tentativa"]
    T2["T2 exportação<br/>3 tentativas"]
    T3["T3 painel<br/>2 tentativas"]
    B["Bloqueada<br/>teste de exportação falha"]
    I["Integração"]
    D["Documentação"]
    A["Não entregue<br/>fica na branch de integração"]
    P --> T1
    P --> T2
    T1 --> T3
    T1 --> I
    T3 --> I
    T2 -.-> B
    I --> D
    D --> A
```

No terminal o Mermaid aparece como texto. O relatório fica salvo em `relatorio.md`, na pasta da execução, para abrir em um visualizador de Markdown e ver o desenho.

Dúvidas comuns chegam juntas no relatório, enquanto os agentes seguem com a melhor suposição. Interrupção no meio só em dois casos: ação irreversível ou todas as tarefas bloqueadas. As perguntas de uma tarefa bloqueada chegam na hora, uma por vez, mas não interrompem nada: as outras tarefas seguem.

## Seu teste

- **Você testa em produção,** depois da entrega, seguindo o roteiro guiado do relatório.
- **Roteiro guiado:** nasce dos critérios de aceite e já foi percorrido pelo verificador de tela antes da entrega.
- **Não gostou do que viu:** o relatório traz o comando de reversão, ou você pede a correção em um novo `/fluxo`.
- **Contas de teste em produção:** uma para cada perfil de usuário, para você testar o fluxo de qualquer categoria e não só a sua. Quem cria é um comando do projeto, rodado pela implantação depois da migração: ele cria as que faltam e não mexe nas que já existem. As credenciais ficam guardadas em um arquivo fora do repositório, para reuso, e o relatório diz em cada passo com a conta de qual perfil entrar. Perfil novo ganha a conta na mesma entrega em que nasce.
- **Os agentes nunca tocam o banco de produção.** Cada cópia de trabalho sobe a aplicação em uma porta temporária, com banco próprio criado pelos dados de exemplo e com contas de teste.
- **Integrações externas** ficam em modo de teste nas cópias de trabalho: pagamento e envio de mensagem simulados ou em sandbox.

Cada roteiro percorrido com sucesso pode virar um teste automatizado de navegador, para proteger o fluxo de tela contra regressão sem gastar com agente.

## Orientação dos agentes

| O quê | Onde | Quando entra no contexto |
|---|---|---|
| Comandos, mapa do projeto, regras de "nunca faça" | `AGENTS.md`, abaixo de 200 linhas | Em toda sessão e todo subagente |
| Convenções de uma área do código | `.claude/rules/` | Quando o agente mexe em arquivo daquela área |
| Procedimento passo a passo | Skill em `.claude/skills/` | Quando acionada |
| Explicação do sistema | `docs/`, com ponteiro no `AGENTS.md` | Quando o agente abre |
| Configuração do fluxo e da entrega | `.cyberstack/projeto.md` | Durante o `/fluxo` |

- **Fonte única.** `CLAUDE.md` contém só `@AGENTS.md`. O revisor reprova qualquer conteúdo a mais.
- **Skills locais.** Depois das duas criadas na preparação, uma skill nova só nasce quando um agente errou o mesmo procedimento duas vezes. Se o procedimento cabe em um script, a skill apenas manda rodá-lo.
- **Documentação em dia.** A que fica junto do código é atualizada pelo implementador e cobrada pelo revisor. A compartilhada é atualizada pelo documentador, uma vez, depois da integração, para tarefas paralelas não conflitarem no mesmo arquivo.
- **Aprendizado.** Motivo de reprovação repetido em duas tarefas vira proposta de correção, nesta ordem de preferência: checagem automática, skill, linha no `AGENTS.md`.
- **Ninguém edita a orientação sozinho.** Fora do `/preparar`, `AGENTS.md`, `CLAUDE.md`, regras e skills só mudam com a sua aprovação, pela seção de propostas do relatório. A proposta traz o texto exato, e quem aplica a que você aprovou é o orquestrador, em um commit próprio, sem implementador nem revisor. Proposta de checagem automática aprovada vira tarefa comum.

## O que continua com você

- Aprovar a proposta de preparação e fazer commit dos arquivos base.
- Instalar o serviço na máquina, uma vez, com sudo.
- Decidir voltar uma versão. O relatório traz o comando.
- Restaurar o banco de uma cópia, que apaga o que foi gravado depois dela.
- Qualquer ação irreversível fora da entrega: exclusão de dados, envio a cliente.
- Segredos versionados que o diagnóstico encontrar. Trocar credencial é com você.
- Responder às perguntas das tarefas bloqueadas, e decidir os suspeitos de código morto.
- O teste de uso. O agente julga bem "funciona" e "está quebrado", e pior "está agradável".
- Aprovar ou recusar as propostas de melhoria.

## Primeiro uso em um projeto

- [ ] Stack instalada: `.claude/agents/` e `.claude/skills/` no projeto ou em `~/.claude/`.
- [ ] Permissões do Claude Code liberando os comandos de teste, lint e execução.
- [ ] Sessão aberta em `opus` com esforço `high`, o modelo e o esforço do orquestrador.
- [ ] Ferramenta de navegador configurada, se for usar o verificador de tela.
- [ ] `/preparar`, depois revisar os arquivos base e fazer commit.
- [ ] Pasta de produção clonada do repositório, com `.venv` e o banco no caminho de `deploy/config.env`.
- [ ] Serviço instalado e habilitado com os comandos do topo de `deploy/<serviço>.service`.
- [ ] `/fluxo executar o plano em .cyberstack/preparacao/plano.md`, para a limpeza.
- [ ] Primeira feature pequena, de uma tarefa só, para calibrar os tetos de turnos.

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

## O que tem neste repositório

| Caminho | O que é |
|---|---|
| [`.claude/agents/`](.claude/agents) | Os nove perfis de subagente: inspetor, planejador, implementador, testador, revisor, verificador de tela, segurança, documentador e ponte. |
| [`.claude/skills/preparar/`](.claude/skills/preparar) | O comando `/preparar` e os modelos dos arquivos base que ele cria no projeto, incluindo os scripts de implantação e de reversão. |
| [`.claude/skills/fluxo/`](.claude/skills/fluxo) | O comando `/fluxo`, que é o orquestrador. |
| [`instalar.sh`](instalar.sh) | Instala a stack em um projeto ou na pasta pessoal e confere os arquivos. |
| [`SHA256SUMS`](SHA256SUMS) | O SHA-256 de cada arquivo da stack. |
| [`testes/implantacao.sh`](testes/implantacao.sh) | Teste dos scripts de implantação e de reversão em um projeto de brinquedo. |

Os caminhos dentro de `.claude/` são os mesmos em que os arquivos ficam depois de instalados.

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
3. atualize este README, inclusive os fluxogramas, se o comportamento mudou.

Um projeto que já tem a stack instalada só recebe a mudança quando o `instalar.sh` roda de novo nele.
