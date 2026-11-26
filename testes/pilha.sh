#!/usr/bin/env bash
# Exercita pilha.sh, o script que roda a pilha de testes uma vez por código, em um
# repositório de brinquedo montado como o /fluxo monta: uma cópia para a integração e
# uma para a tarefa. A "pilha" é um comando que conta quantas vezes rodou de verdade e
# falha quando o código tem a palavra "defeito". Tudo acontece em uma pasta temporária,
# apagada no fim.
#
# Uso: testes/pilha.sh [caminho do pilha.sh]
#      Sem argumento, testa .claude/skills/fluxo/pilha.sh.
# Saída: 0 se todas as conferências passam, 1 se alguma falha.
set -uo pipefail

# O teste não depende da configuração de git de quem roda.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

AQUI=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT=$(realpath "${1:-$AQUI/.claude/skills/fluxo/pilha.sh}")
[ -f "$SCRIPT" ] || { echo "Não achei $SCRIPT" >&2; exit 1; }

T=$(mktemp -d "${TMPDIR:-/tmp}/cyberstack-pilha.XXXXXX")
P="$T/pilhas"
TAB=$(printf '\t')
feitos=0
falhas=0
codigo=0
saida=""

limpar() {
  pkill -KILL -f -- "--trabalhador $P" 2> /dev/null
  pkill -KILL -f "$P/comando" 2> /dev/null
  if [ -f "$T/sobra.pid" ]; then kill -KILL "$(cat "$T/sobra.pid")" 2> /dev/null; fi
  rm -rf "$T"
}
trap limpar EXIT

# ---------------------------------------------------------------- apoio

G() { git -c user.name=teste -c user.email=teste@exemplo.invalid -c init.defaultBranch=main "$@"; }

caso() { echo; echo "$1"; }

confere() { # confere "<o que se espera>" <comando que devolve 0 quando é verdade>
  feitos=$((feitos + 1))
  if "${@:2}"; then
    echo "  ok      $1"
  else
    echo "  FALHOU  $1"
    falhas=$((falhas + 1))
  fi
}
igual() { [ "$1" = "$2" ]; }
menor() { [ "$1" -lt "$2" ]; }
contem() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac; }
nao_contem() { ! contem "$1" "$2"; }

rodadas() { if [ -f "$T/rodadas" ]; then wc -l < "$T/rodadas"; else echo 0; fi; }
comprovantes() { find "$P" -name '*.txt' ! -name '*anterior*' | wc -l; }
guardados() { find "$P" -name "*.anterior-*.$1" | wc -l; }
sobras_na_pasta() { find "$P" -maxdepth 1 \( -name 'tmp.*' -o -name '*.rodando' -o -name '*.parcial' \) | wc -l; }
objetos_soltos() { G -C "$T/tarefa" count-objects | cut -d' ' -f1; }
situacao() { G -C "$T/tarefa" status --short; }
indice() { echo "$(G -C "$T/tarefa" rev-parse --absolute-git-dir)/index"; }
cara_do_indice() { stat -c '%i-%Y-%s' "$(indice)"; }

pilha() { # pilha [cópia] [opções]: chama o script e guarda a saída e o código
  local copia="${1:-$T/tarefa}"
  saida=$("$SCRIPT" "$P" "$copia" "${@:2}" 2>&1)
  codigo=$?
}

espera_rodadas() { # espera_rodadas <n>: espera a pilha registrar a rodada de número n
  local voltas=0
  until [ "$(rodadas)" -ge "$1" ]; do
    voltas=$((voltas + 1))
    [ "$voltas" -le 600 ] || return 1
    sleep 0.1
  done
}
sessao_vazia() { # sessao_vazia <processo>: não sobrou ninguém da sessão dele
  local voltas=0
  while pgrep -s "$1" > /dev/null; do
    voltas=$((voltas + 1))
    [ "$voltas" -le 50 ] || return 1
    sleep 0.1
  done
}

muda() { # muda <texto>: acrescenta uma linha ao código da tarefa, sem commit
  echo "# $1" >> "$T/tarefa/soma.py"
}
grava() { # grava "<mensagem>" [arquivos]: commit na cópia da tarefa; sem arquivos, de tudo
  if [ "$#" -gt 1 ]; then G -C "$T/tarefa" add "${@:2}"; else G -C "$T/tarefa" add --all; fi
  G -C "$T/tarefa" commit --quiet -m "$1"
}

# ---------------------------------------------------------------- montagem

mkdir -p "$T/origem" "$P"
G -C "$T/origem" init --quiet
cat > "$T/origem/soma.py" << 'EOF'
def soma(a, b):
    return a + b
EOF
echo "ignorado/" > "$T/origem/.gitignore"
G -C "$T/origem" add --all
G -C "$T/origem" commit --quiet -m "base"
G -C "$T/origem" worktree add --quiet -b integracao "$T/integracao" main
G -C "$T/origem" worktree add --quiet -b tarefa "$T/tarefa" integracao

# A pilha de brinquedo. Registra cada rodada de verdade, denuncia quando duas rodam ao
# mesmo tempo e obedece a arquivos de controle: "demora" a faz demorar, "mexe" a faz
# alterar o código no meio, "gera" a faz gravar um relatório na cópia e "sobra" a faz
# deixar um processo para trás.
cat > "$P/comando" << EOF
echo rodou >> "$T/rodadas"
if [ -f "$T/em-uso" ] && kill -0 "\$(cat "$T/em-uso")" 2> /dev/null; then echo simultaneas >> "$T/simultaneas"; fi
echo \$\$ > "$T/em-uso"
if [ -f "$T/demora" ]; then sleep "\$(cat "$T/demora")"; fi
if [ -f "$T/mexe" ]; then echo "# mexido pela pilha" >> soma.py; fi
if [ -f "$T/gera" ]; then echo "cobertura: 100%" > relatorio.txt; fi
if [ -f "$T/sobra" ]; then (sleep 20 > /dev/null 2>&1 & echo \$! > "$T/sobra.pid"); fi
if grep -q defeito soma.py; then echo "FAILED teste_soma"; echo "1 failed, 1 passed"; exit 1; fi
echo "2 passed"
EOF

# ---------------------------------------------------------------- cenários

caso "1. A primeira chamada roda e grava o comprovante"
pilha "$T/integracao"
confere "sai com código 0" igual "$codigo" 0
confere "a pilha rodou uma vez" igual "$(rodadas)" 1
confere "diz que rodou agora" contem "$saida" "rodou agora"
confere "o comprovante diz que passou" contem "$saida" "resultado: passou"
confere "mostra o resumo da pilha" contem "$saida" "resumo: 2 passed"
confere "há um comprovante na pasta" igual "$(comprovantes)" 1

caso "2. Pedir de novo sobre o mesmo código não roda"
pilha "$T/integracao"
confere "sai com código 0" igual "$codigo" 0
confere "a pilha não rodou de novo" igual "$(rodadas)" 1
confere "diz que já estava gravado" contem "$saida" "não rodou de novo"

caso "3. Outra cópia com o mesmo código usa o mesmo comprovante (a linha de base do implementador)"
pilha
confere "sai com código 0" igual "$codigo" 0
confere "a pilha não rodou" igual "$(rodadas)" 1
confere "continua havendo um comprovante só" igual "$(comprovantes)" 1

caso "4. Código alterado, mesmo sem commit, roda de verdade"
muda "mudança da tarefa"
pilha
confere "sai com código 0" igual "$codigo" 0
confere "a pilha rodou" igual "$(rodadas)" 2
confere "diz que rodou agora" contem "$saida" "rodou agora"

caso "5. O commit do mesmo conteúdo não pede rodada nova (o Gatilho A depois do implementador)"
grava "tarefa: mudança"
pilha
confere "sai com código 0" igual "$codigo" 0
confere "a pilha não rodou" igual "$(rodadas)" 2
confere "diz que já estava gravado" contem "$saida" "não rodou de novo"

caso "6. Arquivo novo que o git não ignora é código novo; arquivo ignorado não é"
echo "def teste(): pass" > "$T/tarefa/teste_novo.py"
pilha
confere "com o arquivo novo, a pilha rodou" igual "$(rodadas)" 3
mkdir -p "$T/tarefa/ignorado" && echo lixo > "$T/tarefa/ignorado/sobra.txt"
pilha
confere "com o arquivo ignorado, a pilha não rodou" igual "$(rodadas)" 3
grava "tarefa: teste novo"

caso "7. A chamada não deixa rastro na cópia nem no repositório"
echo "rascunho" > "$T/tarefa/rascunho.py"
antes_objetos=$(objetos_soltos)
antes_indice=$(cara_do_indice)
pilha
confere "a pilha rodou sobre o arquivo novo" igual "$(rodadas)" 4
confere "o arquivo novo continua fora do índice" contem "$(situacao)" "?? rascunho.py"
confere "o índice da cópia não foi tocado" igual "$(cara_do_indice)" "$antes_indice"
confere "o repositório não ganhou objeto" igual "$(objetos_soltos)" "$antes_objetos"
rm "$T/tarefa/rascunho.py"
pilha
confere "sem o arquivo, o código volta a ser o do comprovante anterior" igual "$(rodadas)" 4

caso "8. Arquivo apagado e mudança só de permissão são código novo"
echo "a = 1" > "$T/tarefa/par_a.py"
echo "b = 1" > "$T/tarefa/par_b.py"
pilha
n=$(rodadas)
chmod +x "$T/tarefa/par_a.py"
pilha
confere "com a permissão trocada, a pilha rodou" igual "$(rodadas)" $((n + 1))
rm "$T/tarefa/par_b.py"
pilha
confere "com um arquivo apagado, a pilha rodou" igual "$(rodadas)" $((n + 2))
rm "$T/tarefa/par_a.py"

caso "9. Merge que não muda o código usa o comprovante da tarefa (a integração)"
n=$(rodadas)
G -C "$T/integracao" merge --quiet --no-ff -m "Integra a tarefa" tarefa
pilha "$T/integracao"
confere "sai com código 0" igual "$codigo" 0
confere "a pilha não rodou" igual "$(rodadas)" "$n"
confere "diz que já estava gravado" contem "$saida" "não rodou de novo"

caso "10. Merge que junta código de outra tarefa roda de verdade"
echo "def outra(): return 1" > "$T/integracao/outra.py"
G -C "$T/integracao" add --all && G -C "$T/integracao" commit --quiet -m "Integra outra tarefa"
pilha "$T/integracao"
confere "a integração com o código da outra tarefa rodou" igual "$(rodadas)" $((n + 1))
muda "segunda mudança da tarefa"
grava "tarefa: segunda mudança"
pilha
confere "a tarefa com a segunda mudança rodou" igual "$(rodadas)" $((n + 2))
G -C "$T/integracao" merge --quiet --no-ff -m "Integra a tarefa de novo" tarefa
pilha "$T/integracao"
confere "o merge juntou as duas e a pilha rodou" igual "$(rodadas)" $((n + 3))
confere "sai com código 0" igual "$codigo" 0
G -C "$T/tarefa" merge --quiet -m "Tarefa recebe a integração" integracao
pilha
confere "a tarefa, depois de receber a integração, tem o mesmo código e não roda" igual "$(rodadas)" $((n + 3))

caso "11. Falha fica gravada e não roda de novo"
n=$(rodadas)
muda "defeito"
pilha
confere "sai com código 1" igual "$codigo" 1
confere "a pilha rodou" igual "$(rodadas)" $((n + 1))
confere "o comprovante diz que falhou" contem "$saida" "resultado: falhou"
confere "mostra o fim do registro, com o teste que falhou" contem "$saida" "FAILED teste_soma"
pilha
confere "na segunda chamada sai com código 1" igual "$codigo" 1
confere "e a pilha não rodou de novo" igual "$(rodadas)" $((n + 1))
confere "diz que já estava gravado" contem "$saida" "não rodou de novo"

caso "12. --de-novo repete a rodada uma vez por código e guarda o comprovante anterior"
pilha "$T/tarefa" --de-novo
confere "a pilha rodou de novo" igual "$(rodadas)" $((n + 2))
confere "sai com código 1, porque o defeito continua lá" igual "$codigo" 1
confere "diz que rodou agora" contem "$saida" "rodou agora"
confere "o comprovante anterior ficou guardado" igual "$(guardados txt)" 1
confere "o registro anterior também" igual "$(guardados log)" 1
pilha
confere "sem --de-novo, vale o comprovante novo e não roda" igual "$(rodadas)" $((n + 2))
pilha "$T/tarefa" --de-novo
confere "o segundo --de-novo no mesmo código não roda" igual "$(rodadas)" $((n + 2))
confere "e avisa que a pilha já foi repetida" contem "$saida" "já foi repetida uma vez"
confere "continua havendo um comprovante guardado só" igual "$(guardados txt)" 1
sed -i '/defeito/d' "$T/tarefa/soma.py"

caso "13. Código que muda durante a rodada não vira comprovante"
muda "correção"
echo "rascunho que já estava ali" > "$T/tarefa/rascunho.py"
cp "$T/tarefa/soma.py" "$T/soma.antes"
n=$(rodadas)
antes=$(comprovantes)
antes_indice=$(cara_do_indice)
touch "$T/mexe"
pilha
confere "sai com código 3" igual "$codigo" 3
confere "a pilha rodou" igual "$(rodadas)" $((n + 1))
confere "avisa que o código mudou" contem "$saida" "mudou enquanto a pilha rodava"
confere "lista o arquivo que mudou durante a rodada" contem "$saida" "M${TAB}soma.py"
confere "não lista o que já estava alterado antes dela" nao_contem "$saida" "rascunho.py"
confere "nenhum comprovante foi gravado" igual "$(comprovantes)" "$antes"
confere "o índice da cópia não foi tocado" igual "$(cara_do_indice)" "$antes_indice"
rm "$T/mexe"
pilha
confere "chamando de novo, roda sobre o código como ficou" igual "$(rodadas)" $((n + 2))
confere "e sai com código 0" igual "$codigo" 0

caso "14. Duas chamadas ao mesmo tempo, uma rodada só, mesmo com o aviso de mudança antigo na pasta"
cp "$T/soma.antes" "$T/tarefa/soma.py"
echo 3 > "$T/demora"
"$SCRIPT" "$P" "$T/tarefa" > "$T/saida-a" 2>&1 &
pid_a=$!
"$SCRIPT" "$P" "$T/tarefa" > "$T/saida-b" 2>&1 &
pid_b=$!
wait "$pid_a"; codigo_a=$?
wait "$pid_b"; codigo_b=$?
confere "a pilha rodou uma vez só" igual "$(rodadas)" $((n + 3))
confere "a primeira chamada sai com código 0" igual "$codigo_a" 0
confere "a segunda chamada sai com código 0" igual "$codigo_b" 0
confere "uma das duas rodou" contem "$(cat "$T/saida-a" "$T/saida-b")" "rodou agora"
confere "a outra esperou pela rodada em curso" contem "$(cat "$T/saida-a" "$T/saida-b")" "esperou uma rodada"
rm "$T/tarefa/rascunho.py"

caso "15. Arquivo novo gravado pela própria pilha: entra em ignorar e deixa de contar como código"
muda "pilha com relatório"
n=$(rodadas)
rm "$T/demora"
touch "$T/gera"
pilha
confere "sai com código 3" igual "$codigo" 3
confere "lista o arquivo que a pilha gravou" contem "$saida" "A${TAB}relatorio.txt"
confere "diz onde anotar o que a pilha grava" contem "$saida" "$P/ignorar"
echo "relatorio.txt" > "$P/ignorar"
pilha
confere "com o arquivo em ignorar, a pilha roda e sai com código 0" igual "$codigo" 0
confere "foram duas rodadas até aqui" igual "$(rodadas)" $((n + 2))
pilha
confere "a chamada seguinte usa o comprovante" igual "$(rodadas)" $((n + 2))
grava "tarefa: mudança com a pilha que gera relatório" soma.py
G -C "$T/integracao" merge --quiet --no-ff -m "Integra a tarefa do relatório" tarefa
pilha "$T/integracao"
confere "a integração, que não tem o relatório, usa o comprovante da tarefa" igual "$(rodadas)" $((n + 2))
confere "diz que já estava gravado" contem "$saida" "não rodou de novo"
confere "o comprovante anota o que ficou de fora" contem "$saida" "ignorados: relatorio.txt"
rm "$T/gera"
echo "relat*" >> "$P/ignorar"
echo "def vendas(): return 1" > "$T/tarefa/relatorio_vendas.py"
pilha
confere "linha com curinga não esconde código novo de nome parecido" igual "$(rodadas)" $((n + 3))
mkdir "$T/tarefa/pacote" && echo "cobertura: 100%" > "$T/tarefa/pacote/relatorio.txt"
pilha
confere "o caminho vale da raiz: arquivo de mesmo nome em outra pasta conta como código" igual "$(rodadas)" $((n + 4))
rm -r "$T/tarefa/relatorio.txt" "$T/tarefa/relatorio_vendas.py" "$T/tarefa/pacote"
echo "relatorio.txt" > "$P/ignorar"

caso "16. Quem chamou é interrompido e a rodada segue sozinha"
muda "chamada interrompida"
n=$(rodadas)
echo 4 > "$T/demora"
setsid "$SCRIPT" "$P" "$T/tarefa" > /dev/null 2>&1 &
pid_c=$!
espera_rodadas $((n + 1))
kill -TERM -- "-$pid_c" 2> /dev/null
wait "$pid_c"; codigo_c=$?
confere "a chamada morreu no meio, com o grupo de processos dela" igual "$codigo_c" 143
pilha
confere "a chamada seguinte sai com código 0" igual "$codigo" 0
confere "e esperou a rodada em curso, sem começar outra" igual "$(rodadas)" $((n + 1))
confere "diz que esperou" contem "$saida" "esperou uma rodada"

caso "17. kill no processo da rodada encerra a pilha inteira e não deixa comprovante"
muda "rodada encerrada"
cp "$T/tarefa/soma.py" "$T/soma.antes"
touch "$T/mexe"
pilha
rm "$T/mexe"
cp "$T/soma.antes" "$T/tarefa/soma.py"
confere "antes, uma rodada deste mesmo código saiu com 3 e deixou o aviso de mudança na pasta" igual "$codigo" 3
n=$(rodadas)
echo 60 > "$T/demora"
"$SCRIPT" "$P" "$T/tarefa" > "$T/saida-d" 2>&1 &
pid_d=$!
espera_rodadas $((n + 1))
processo=$(cat "$P"/*.rodando | cut -d, -f1)
kill "$processo"
wait "$pid_d"; codigo_d=$?
confere "quem esperava sai com código 4" igual "$codigo_d" 4
confere "avisa que a rodada foi interrompida" contem "$(cat "$T/saida-d")" "interrompida antes de gravar"
confere "o comando da pilha e os filhos dele morreram junto" sessao_vazia "$processo"
rm "$T/demora"
pilha
confere "chamando de novo, a pilha roda" igual "$(rodadas)" $((n + 2))
confere "e sai com código 0" igual "$codigo" 0

caso "18. Processo que a pilha deixa para trás não segura a trava"
muda "pilha que deixa processo"
n=$(rodadas)
touch "$T/sobra"
pilha
confere "sai com código 0" igual "$codigo" 0
rm "$T/sobra"
confere "o processo deixado para trás continua vivo" kill -0 "$(cat "$T/sobra.pid")"
inicio=$(date +%s)
pilha "$T/tarefa" --de-novo
fim=$(date +%s)
confere "a repetição rodou" igual "$(rodadas)" $((n + 2))
confere "sem esperar o processo deixado para trás" menor $((fim - inicio)) 10
kill -KILL "$(cat "$T/sobra.pid")" 2> /dev/null

caso "19. Tempo máximo: a pilha que passa do limite é encerrada e a falha fica gravada"
muda "tempo máximo"
n=$(rodadas)
echo 2 > "$P/limite"
echo 30 > "$T/demora"
inicio=$(date +%s)
pilha
fim=$(date +%s)
confere "sai com código 1" igual "$codigo" 1
confere "o comprovante registra a saída 124" contem "$saida" "saida: 124"
confere "e diz que passou do tempo máximo" contem "$saida" "tempo máximo de 2 s"
confere "sem esperar a pilha inteira" menor $((fim - inicio)) 20
rm "$P/limite" "$T/demora"

caso "20. Alteração no mesmo segundo de um git add, sem mudar o tamanho, não engana"
printf 'x = "aaaa"\n' > "$T/tarefa/corrida.py"
grava "tarefa: arquivo da corrida"
pilha
n=$(rodadas)
voltas=0
while :; do
  printf 'x = "aaaa"\n' > "$T/tarefa/corrida.py"
  G -C "$T/tarefa" add corrida.py
  printf 'x = "bbbb"\n' > "$T/tarefa/corrida.py"
  [ "$(stat -c %Y "$T/tarefa/corrida.py")" = "$(stat -c %Y "$(indice)")" ] && break
  voltas=$((voltas + 1))
  [ "$voltas" -lt 50 ] || break
done
sleep 1.1
pilha
confere "o arquivo e o índice ficaram com a mesma data" menor "$voltas" 50
confere "a pilha rodou sobre o conteúdo novo" igual "$(rodadas)" $((n + 1))
grava "tarefa: corrida"

caso "21. Sem conseguir copiar o índice da cópia, a impressão digital sai a mesma"
n=$(rodadas)
chmod 000 "$(indice)"
pilha
chmod 644 "$(indice)"
confere "sai com código 0" igual "$codigo" 0
confere "a pilha não rodou" igual "$(rodadas)" "$n"
confere "diz que já estava gravado" contem "$saida" "não rodou de novo"

caso "22. Repositório aninhado: sem impressão digital, a pilha roda toda vez"
mkdir "$T/tarefa/aninhado"
G -C "$T/tarefa/aninhado" init --quiet
echo "y = 1" > "$T/tarefa/aninhado/lib.py"
G -C "$T/tarefa/aninhado" add --all && G -C "$T/tarefa/aninhado" commit --quiet -m "aninhado"
n=$(rodadas)
pilha
confere "sai com código 0" igual "$codigo" 0
confere "a pilha rodou" igual "$(rodadas)" $((n + 1))
confere "avisa que não há impressão digital" contem "$saida" "Sem impressão digital"
confere "e diz por quê" contem "$saida" "repositório aninhado"
echo "y = 2  # defeito escondido" > "$T/tarefa/aninhado/lib.py"
pilha
confere "com o código de dentro alterado, roda de novo em vez de usar comprovante" igual "$(rodadas)" $((n + 2))
rm -rf "$T/tarefa/aninhado"

caso "23. Pedido sobre código novo com outra rodada em curso na mesma cópia espera a vez"
muda "primeira das duas"
n=$(rodadas)
echo 3 > "$T/demora"
"$SCRIPT" "$P" "$T/tarefa" > "$T/saida-e" 2>&1 &
pid_e=$!
espera_rodadas $((n + 1))
muda "segunda das duas"
pilha
wait "$pid_e"; codigo_e=$?
confere "a primeira sai com código 3, porque o código mudou no meio dela" igual "$codigo_e" 3
confere "a segunda sai com código 0" igual "$codigo" 0
confere "foram duas rodadas" igual "$(rodadas)" $((n + 2))
confere "uma depois da outra, nunca ao mesmo tempo" test ! -e "$T/simultaneas"
rm "$T/demora"

caso "24. Pedido que fica velho na fila não roda"
muda "primeira da fila"
n=$(rodadas)
echo 4 > "$T/demora"
"$SCRIPT" "$P" "$T/tarefa" > "$T/saida-g" 2>&1 &
pid_g=$!
espera_rodadas $((n + 1))
muda "segunda da fila"
"$SCRIPT" "$P" "$T/tarefa" > "$T/saida-h" 2>&1 &
pid_h=$!
sleep 1
muda "terceira da fila"
wait "$pid_g"; codigo_g=$?
wait "$pid_h"; codigo_h=$?
confere "a primeira sai com código 3" igual "$codigo_g" 3
confere "a segunda sai com código 3" igual "$codigo_h" 3
confere "e diz que nada rodou, porque o código já era outro quando chegou a vez dela" contem "$(cat "$T/saida-h")" "nada rodou"
confere "só a primeira rodou" igual "$(rodadas)" $((n + 1))
rm "$T/demora"
pilha
confere "o pedido seguinte roda sobre o código como ficou" igual "$(rodadas)" $((n + 2))
confere "e sai com código 0" igual "$codigo" 0

caso "25. Comando alterado durante a rodada não vira comprovante"
muda "comando no meio"
n=$(rodadas)
echo 3 > "$T/demora"
"$SCRIPT" "$P" "$T/tarefa" > "$T/saida-f" 2>&1 &
pid_f=$!
espera_rodadas $((n + 1))
echo "# comando mexido no meio" >> "$P/comando"
wait "$pid_f"; codigo_f=$?
confere "sai com código 3" igual "$codigo_f" 3
confere "diz que o comando foi alterado" contem "$(cat "$T/saida-f")" "O comando da pilha foi alterado"
rm "$T/demora"

caso "26. Comprovante de um comando não vale para outro"
pilha
n=$(rodadas)
pilha
confere "antes de mexer no comando, não roda" igual "$(rodadas)" "$n"
echo "# outro comando" >> "$P/comando"
pilha
confere "com o comando alterado, a pilha rodou" igual "$(rodadas)" $((n + 1))
confere "sai com código 0" igual "$codigo" 0

caso "27. Uso errado"
n=$(rodadas)
saida=$("$SCRIPT" 2>&1); codigo=$?
confere "sem argumentos sai com código 2" igual "$codigo" 2
confere "e mostra o uso" contem "$saida" "Uso: pilha.sh"
pilha "$T/tarefa" --inventada
confere "opção desconhecida sai com código 2" igual "$codigo" 2
saida=$("$SCRIPT" "$T/nao-existe" "$T/tarefa" 2>&1); codigo=$?
confere "pasta dos comprovantes inexistente sai com código 2" igual "$codigo" 2
mkdir "$T/vazia"
saida=$("$SCRIPT" "$T/vazia" "$T/tarefa" 2>&1); codigo=$?
confere "pasta sem o arquivo do comando sai com código 2" igual "$codigo" 2
confere "e diz o que falta" contem "$saida" "Falta o comando da pilha"
: > "$T/vazia/comando"
saida=$("$SCRIPT" "$T/vazia" "$T/tarefa" 2>&1); codigo=$?
confere "arquivo do comando vazio sai com código 2" igual "$codigo" 2
pilha "$T/vazia"
confere "cópia que não é do git sai com código 2" igual "$codigo" 2
for valor in abc 0 "1 5"; do
  echo "$valor" > "$P/limite"
  pilha
  confere "limite \"$valor\" sai com código 2" igual "$codigo" 2
done
rm "$P/limite"
mkdir "$T/tarefa/subpasta"
pilha "$T/tarefa/subpasta"
confere "subpasta da cópia sai com código 2" igual "$codigo" 2
confere "e diz que a pilha roda da raiz" contem "$saida" "raiz da cópia"
rmdir "$T/tarefa/subpasta"
chmod a-w "$T/vazia" && echo "true" > "$T/comando-pronto"
mkdir "$T/trancada" && cp "$T/comando-pronto" "$T/trancada/comando" && chmod a-w "$T/trancada"
saida=$(timeout 10 "$SCRIPT" "$T/trancada" "$T/tarefa" 2>&1); codigo=$?
confere "pasta dos comprovantes sem permissão de escrita sai com código 2, sem ficar esperando" igual "$codigo" 2
chmod u+w "$T/vazia" "$T/trancada"
confere "nenhuma dessas chamadas rodou a pilha" igual "$(rodadas)" "$n"

caso "28. Chamado por caminho relativo e pelo bash"
n=$(rodadas)
muda "caminho relativo"
saida=$(cd "$(dirname "$SCRIPT")" && bash "$(basename "$SCRIPT")" "$P" "$T/tarefa" 2>&1); codigo=$?
confere "sai com código 0" igual "$codigo" 0
confere "a pilha rodou" igual "$(rodadas)" $((n + 1))

caso "29. No fim, a pasta dos comprovantes não tem sobra e nenhuma rodada se sobrepôs a outra"
confere "nenhuma pasta temporária, rodada em curso ou comprovante pela metade" igual "$(sobras_na_pasta)" 0
confere "em nenhum cenário duas rodadas usaram a mesma cópia ao mesmo tempo" test ! -e "$T/simultaneas"

# ---------------------------------------------------------------- resultado

echo
if [ "$falhas" -eq 0 ]; then
  echo "Resultado: $feitos conferências, todas passaram."
  exit 0
fi
echo "Resultado: $feitos conferências, $falhas falharam."
exit 1
