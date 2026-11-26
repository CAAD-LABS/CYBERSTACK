#!/usr/bin/env bash
# Roda a pilha de testes uma vez por código. O resultado fica gravado como comprovante,
# junto com a impressão digital do código: o hash de árvore do git sobre o conteúdo atual
# da cópia, com os arquivos versionados e os novos que o git não ignora. Quem pedir a
# pilha de novo sobre o mesmo código recebe o comprovante, sem rodar. Commit ou merge
# que não muda o conteúdo não muda a impressão digital.
#
# Uso: pilha.sh <pasta dos comprovantes> <raiz da cópia do código> [--de-novo]
#
# Arquivos da pasta dos comprovantes, escritos por quem chama:
#   comando  o comando da pilha, executado com bash de dentro da cópia, com o ambiente
#            de quem chamou. Comprovante de um comando não vale para outro.
#   ignorar  opcional. Arquivos novos que a própria pilha grava e que não são código: um
#            caminho por linha, contado da raiz da cópia, sem curinga. Só alcança arquivo
#            que não está no git, e a lista fica anotada no comprovante.
#   limite   opcional. Tempo máximo da rodada: um número inteiro de segundos, maior que
#            zero. Sem ele, duas horas.
#
# --de-novo  roda mesmo que já exista comprovante para este código, e guarda o anterior
#            ao lado, com "anterior" no nome. Vale uma vez por código: pedida outra vez,
#            responde com o comprovante que existe.
#
# A rodada acontece desligada de quem chamou: se a chamada for interrompida, a rodada
# segue até gravar o resultado, e chamar de novo espera por ela em vez de começar outra.
# Para encerrar uma rodada em curso, kill no processo que a espera mostra: ele leva junto
# o comando da pilha e o que o comando tiver disparado.
#
# Cópia com submódulo ou repositório aninhado não tem impressão digital confiável: a
# pilha roda toda vez, e a saída avisa.
#
# Saída: 0 a pilha passou | 1 a pilha falhou (o registro completo está no caminho mostrado)
#        2 uso errado, pasta que não é raiz de cópia do git, comando ausente ou vazio
#        3 o código mudou durante a rodada: não há comprovante, e a saída lista o que mudou
#        4 a rodada foi interrompida antes de gravar o resultado: chame de novo
set -uo pipefail

# A impressão digital é da cópia recebida, não de um repositório que o ambiente aponte.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES \
  GIT_COMMON_DIR GIT_NAMESPACE GIT_PREFIX

uso() { sed -n '2,/^set -uo pipefail$/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; }

# ---------------------------------------------------------------- impressão digital

# O git trabalhando sobre uma "foto" da cópia: índice e objetos novos ficam na pasta da
# foto. Nem o índice da cópia nem o repositório ganham nada.
git_da_foto() { # git_da_foto <pasta da foto> <raiz da cópia> <argumentos do git>
  GIT_INDEX_FILE="$1/index" GIT_OBJECT_DIRECTORY="$1/objects" \
    GIT_ALTERNATE_OBJECT_DIRECTORIES="$(cat "$1/objetos-do-repositorio")" \
    git -C "$2" -c core.excludesFile="$1/excluir" "${@:3}"
}

# Hash de árvore do conteúdo atual da cópia. Chamada de novo com a mesma pasta de foto,
# aproveita o índice da vez anterior. Quando falha, o motivo fica em <pasta da foto>/erro.
foto() { # foto <pasta da foto> <raiz da cópia> <pasta dos comprovantes>
  local dir="$1" raiz="$2" pasta="$3" dirgit globais
  if [ ! -d "$dir/objects" ]; then
    mkdir -p "$dir/objects" || return 1
    dirgit=$(git -C "$raiz" rev-parse --absolute-git-dir 2> "$dir/erro") || return 1
    (cd "$raiz" && cd "$(git rev-parse --git-path objects)" && pwd) > "$dir/objetos-do-repositorio" 2> "$dir/erro" || return 1
    # Parte do índice da cópia, com a data preservada, para o git não reler arquivo que
    # não mudou e continuar desconfiando do que foi alterado no mesmo segundo.
    if [ -f "$dirgit/index" ]; then
      cp --preserve=timestamps "$dirgit/index" "$dir/index" 2> /dev/null || rm -f "$dir/index"
    fi
  fi
  # O que fica fora da foto: o que o usuário ignora em todo repositório, mais o que a
  # pasta dos comprovantes manda ignorar. Cada linha de "ignorar" vira um caminho exato,
  # preso à raiz da cópia e sem curinga, para não esconder mais do que foi escrito.
  globais=$(git -C "$raiz" config --type=path --get core.excludesFile 2> /dev/null) \
    || globais="${XDG_CONFIG_HOME:-$HOME/.config}/git/ignore"
  {
    cat "$globais" 2> /dev/null
    echo
    sed -e 's/\r$//' -e '/^[[:space:]]*$/d' -e 's/^\.\///' -e 's/^\/*//' \
      -e 's/[][\\*? ]/\\&/g' -e 's/^/\//' "$pasta/ignorar" 2> /dev/null
  } > "$dir/excluir"
  if ! git_da_foto "$dir" "$raiz" add --all > /dev/null 2> "$dir/erro"; then
    # O git recusou o índice copiado: recomeça de um índice vazio.
    rm -f "$dir/index"
    git_da_foto "$dir" "$raiz" add --all > /dev/null 2> "$dir/erro" || return 1
  fi
  # De um submódulo ou repositório aninhado o git guarda só o commit: o que mudar lá
  # dentro não aparece na árvore.
  if [ "$(git_da_foto "$dir" "$raiz" ls-files --stage | grep -c '^160000 ')" -gt 0 ]; then
    echo "a cópia tem submódulo ou repositório aninhado" > "$dir/erro"
    return 1
  fi
  git_da_foto "$dir" "$raiz" write-tree 2> "$dir/erro"
}

# Chave do comprovante: a impressão digital do código mais a do comando.
chave_de() { # chave_de <pasta da foto> <raiz da cópia> <pasta dos comprovantes>
  local arvore
  arvore=$(foto "$1" "$2" "$3") || return 1
  [ -n "$arvore" ] || return 1
  echo "$arvore-$(sha256sum < "$3/comando" | cut -c1-12)"
}

# ---------------------------------------------------------------- a rodada

# Tempo máximo da rodada, em segundos: o do arquivo "limite", ou duas horas sem ele.
# Falha quando o arquivo existe e não traz um número inteiro maior que zero.
limite_de() { # limite_de <pasta dos comprovantes>
  local valor
  [ -e "$1/limite" ] || { echo 7200; return 0; }
  valor=$(tr -d '\n\r' < "$1/limite" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  case "$valor" in '' | *[!0-9]*) return 1 ;; esac
  [ "$valor" -gt 0 ] || return 1
  echo "$valor"
}

# Modo interno, chamado por este mesmo script já desligado de quem pediu a rodada.
# O descritor 9 chega aberto e com a trava da chave: ela dura enquanto este processo durar.
trabalhador() { # trabalhador <pasta dos comprovantes> <raiz da cópia> <chave> <tem impressão digital: sim|nao>
  local pasta="$1" copia="$2" chave="$3" confiavel="$4"
  local tmp limite inicio fim saida resultado agora

  # A limpeza roda na saída do processo, depois que esta função já terminou: por isso
  # os dois caminhos ficam em variáveis globais.
  RODANDO="$pasta/$chave.rodando"
  echo "$$, desde $(date '+%Y-%m-%d %H:%M:%S')" > "$RODANDO"
  TMP=$(mktemp -d "$pasta/tmp.XXXXXX") || return 1
  tmp="$TMP"
  trap 'rm -rf "$TMP" "$RODANDO"' EXIT
  # kill neste processo encerra a rodada inteira: ele é o líder da sessão em que o
  # comando da pilha e os filhos dele rodam.
  trap 'trap - TERM INT; pkill -TERM -s "$$" 2> /dev/null; kill -TERM -- "-$$" 2> /dev/null; exit 143' TERM INT

  # Uma rodada por cópia de cada vez, mesmo que o código tenha mudado entre um pedido e
  # outro. As esperas vão em segundo plano para o kill não ter de esperar por elas.
  exec 8>> "$pasta/copia-$(printf '%s' "$copia" | sha256sum | cut -c1-12).trava"
  flock 8 &
  wait "$!"

  if [ "$confiavel" = sim ]; then
    agora=$(chave_de "$tmp/foto" "$copia" "$pasta") || agora="?"
    if [ "$agora" != "$chave" ]; then
      echo "O código mudou entre o pedido e o começo da rodada: nada rodou. Chame de novo." > "$pasta/$chave.mudou"
      return 0
    fi
  fi

  limite=$(limite_de "$pasta") || limite=7200
  inicio=$(date +%s)
  # O comando não herda as travas: um processo que ele deixe para trás não as segura.
  (cd "$copia" && exec timeout --kill-after=30 "$limite" bash -o pipefail "$pasta/comando") \
    > "$pasta/$chave.log" 2>&1 < /dev/null 8>&- 9>&- &
  wait "$!"
  saida=$?
  fim=$(date +%s)

  if [ "$confiavel" = sim ]; then
    agora=$(chave_de "$tmp/foto" "$copia" "$pasta") || agora="?"
    if [ "$agora" != "$chave" ]; then
      {
        echo "O código mudou enquanto a pilha rodava: o resultado não vale como comprovante."
        if [ "${agora##*-}" != "${chave##*-}" ]; then
          echo "O comando da pilha foi alterado: $pasta/comando"
        fi
        if [ "$agora" != "?" ] && [ "${agora%-*}" != "${chave%-*}" ]; then
          echo "O que mudou na cópia (A arquivo novo, M alterado, D apagado):"
          git_da_foto "$tmp/foto" "$copia" diff-tree -r --name-status "${chave%-*}" "${agora%-*}" | head -n 40
        fi
        echo "Se foi um agente mexendo na cópia, chame de novo com a cópia parada."
        echo "Se foi a própria pilha que gravou arquivo novo que não é código, quem conduz a"
        echo "execução escreve o caminho em $pasta/ignorar e chama de novo."
      } > "$pasta/$chave.mudou" 2>&1
      return 0
    fi
  fi

  if [ "$saida" -eq 0 ]; then resultado=passou; else resultado=falhou; fi
  {
    echo "resultado: $resultado"
    echo "saida: $saida"
    if [ "$saida" -eq 124 ]; then
      echo "motivo: a pilha passou do tempo máximo de $limite s e foi encerrada"
    fi
    if [ "$confiavel" = sim ]; then
      echo "arvore: ${chave%-*}"
    else
      echo "arvore: sem impressão digital; este resultado não vale para outra chamada"
    fi
    echo "comando: $(tr '\n' ' ' < "$pasta/comando" | sed 's/ *$//')"
    if [ -s "$pasta/ignorar" ]; then
      echo "ignorados: $(grep -v '^[[:space:]]*$' "$pasta/ignorar" | tr '\n' ' ' | sed 's/ *$//')"
    fi
    echo "inicio: $(date -d "@$inicio" '+%Y-%m-%d %H:%M:%S')"
    echo "duracao: $((fim - inicio)) s"
    echo "copia: $copia"
    echo "registro: $pasta/$chave.log"
    echo "resumo: $(grep -v '^[[:space:]]*$' "$pasta/$chave.log" | tail -n 1)"
  } > "$pasta/$chave.txt.parcial"
  mv "$pasta/$chave.txt.parcial" "$pasta/$chave.txt"
}

if [ "${1:-}" = "--trabalhador" ]; then
  trabalhador "$2" "$3" "$4" "$5"
  exit 0
fi

# ---------------------------------------------------------------- quem chama

de_novo=nao
posicionais=()
for argumento in "$@"; do
  case "$argumento" in
    --de-novo) de_novo=sim ;;
    -h | --help | --ajuda) uso; exit 0 ;;
    -*) echo "Opção desconhecida: $argumento" >&2; uso >&2; exit 2 ;;
    *) posicionais+=("$argumento") ;;
  esac
done
[ "${#posicionais[@]}" -eq 2 ] || { uso >&2; exit 2; }

for programa in git flock setsid timeout sha256sum; do
  command -v "$programa" > /dev/null || { echo "Falta o programa $programa." >&2; exit 2; }
done

pasta=$(realpath "${posicionais[0]}" 2> /dev/null)
[ -n "$pasta" ] && [ -d "$pasta" ] || { echo "Pasta dos comprovantes não encontrada: ${posicionais[0]}" >&2; exit 2; }
[ -w "$pasta" ] || { echo "Sem permissão para gravar na pasta dos comprovantes: $pasta" >&2; exit 2; }
copia=$(realpath "${posicionais[1]}" 2> /dev/null)
[ -n "$copia" ] && [ -d "$copia" ] || { echo "Cópia do código não encontrada: ${posicionais[1]}" >&2; exit 2; }
[ -s "$pasta/comando" ] || { echo "Falta o comando da pilha, ou o arquivo está vazio: $pasta/comando" >&2; exit 2; }
limite_de "$pasta" > /dev/null || { echo "O limite tem de ser um número inteiro de segundos, maior que zero: $pasta/limite" >&2; exit 2; }
raiz=$(git -C "$copia" rev-parse --show-toplevel 2> /dev/null) || { echo "Não é uma cópia do git: $copia" >&2; exit 2; }
[ "$(realpath "$raiz")" = "$copia" ] || { echo "A pilha roda da raiz da cópia ($raiz), não de uma subpasta: $copia" >&2; exit 2; }

eu=$(realpath "$0")
# Pasta temporária que uma chamada morta à força deixou para trás, há mais de um dia.
find "$pasta" -maxdepth 1 -name 'tmp.*' -mmin +1440 -exec rm -rf {} + 2> /dev/null
TMP=$(mktemp -d "$pasta/tmp.XXXXXX") || { echo "Não consegui criar pasta temporária em $pasta." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
trap 'exit 143' TERM
trap 'exit 130' INT

confiavel=sim
aviso=""
if ! chave=$(chave_de "$TMP/foto" "$copia" "$pasta"); then
  confiavel=nao
  aviso="Sem impressão digital para esta cópia ($(tr '\n' ' ' < "$TMP/foto/erro" 2> /dev/null | cut -c1-200)): a pilha roda toda vez."
  chave="sem-impressao-$(date +%s)-$$"
fi

comprovante="$pasta/$chave.txt"
registro="$pasta/$chave.log"
trava="$pasta/$chave.trava"
mudou="$pasta/$chave.mudou"

# A regra é uma repetição por código. A segunda, e a chamada repetida depois de uma
# interrupção, recebem o comprovante que existe.
if [ "$de_novo" = sim ] && [ -n "$(find "$pasta" -maxdepth 1 -name "$chave.anterior-*.txt" -print -quit)" ]; then
  de_novo=nao
  aviso="A pilha já foi repetida uma vez para este código: vale o comprovante que existe."
fi

identidade() { stat -c '%i-%Y' "$comprovante" 2> /dev/null || echo nenhum; }
# Com --de-novo, o comprovante que já existia não serve de resposta: só o que vier depois.
antigo=nenhum
if [ "$de_novo" = sim ]; then antigo=$(identidade); fi

# Carrega o comprovante em LIDO, de uma vez só, para não misturar dois resultados se
# outra chamada o trocar no meio da leitura. Falha se não há um que sirva de resposta.
LIDO=""
ler_resultado() {
  local id
  id=$(identidade)
  [ "$id" != nenhum ] && [ "$id" != "$antigo" ] || return 1
  LIDO=$(cat "$comprovante" 2> /dev/null) || return 1
  [ -n "$LIDO" ] && [ "$(identidade)" = "$id" ]
}

pegar_trava() { # 0 pegou a trava | 1 há uma rodada em curso
  local r
  { exec 9>> "$trava"; } 2> /dev/null || { echo "Não consegui abrir a trava: $trava" >&2; exit 2; }
  flock --nonblock 9
  r=$?
  [ "$r" -eq 0 ] && return 0
  exec 9>&-
  [ "$r" -eq 1 ] && return 1
  echo "O flock falhou com código $r em $trava." >&2
  exit 2
}
soltar_trava() { exec 9>&-; }

mostrar() { # mostrar <de onde veio o resultado>
  local saida arquivo linhas=3
  saida=$(sed -n 's/^saida: //p' <<< "$LIDO")
  arquivo=$(sed -n 's/^registro: //p' <<< "$LIDO")
  if [ "$saida" != 0 ]; then linhas=60; fi
  echo "COMPROVANTE: $(sed -n 's/^resultado: //p' <<< "$LIDO") | $1"
  if [ -n "$aviso" ]; then echo "$aviso"; fi
  echo "$LIDO"
  echo "--- fim do registro ---"
  tail -n "$linhas" "$arquivo" 2> /dev/null
  if [ "$saida" = 0 ]; then exit 0; fi
  exit 1
}

if [ "$confiavel" = sim ] && ler_resultado; then
  mostrar "já gravado para este código, não rodou de novo"
fi

if pegar_trava; then
  # Com a trava na mão, ninguém está rodando este código.
  if [ "$confiavel" = sim ] && ler_resultado; then
    soltar_trava
    mostrar "já gravado para este código, não rodou de novo"
  fi
  if [ -f "$comprovante" ]; then
    guardado="$pasta/$chave.anterior-$(date +%s)"
    mv "$comprovante" "$guardado.txt"
    if [ -f "$registro" ]; then mv "$registro" "$guardado.log"; fi
    antigo=nenhum
  fi
  rm -f "$mudou"
  # O subshell termina logo e deixa o trabalhador sem pai e em sessão própria: ele não
  # morre com quem chamou. O trabalhador herda o descritor 9 e, com ele, a trava.
  (setsid bash "$eu" --trabalhador "$pasta" "$copia" "$chave" "$confiavel" < /dev/null > /dev/null 2>&1 &)
  soltar_trava
  origem="rodou agora"
  echo "Rodando a pilha sobre este código. Registro: $registro"
else
  origem="esperou uma rodada que já estava em curso sobre este código"
  echo "Já existe uma rodada em curso sobre este código. Esperando por ela."
  if [ -f "$pasta/$chave.rodando" ]; then echo "Processo da rodada: $(cat "$pasta/$chave.rodando" 2> /dev/null)"; fi
fi

until ler_resultado; do
  if pegar_trava; then
    # A trava está livre: o trabalhador terminou. Ou gravou algo, ou foi interrompido.
    if ler_resultado; then
      soltar_trava
      break
    fi
    if [ -f "$mudou" ]; then
      texto=$(cat "$mudou")
      soltar_trava
      echo "$texto" >&2
      exit 3
    fi
    soltar_trava
    echo "A rodada foi interrompida antes de gravar o resultado. Chame de novo." >&2
    exit 4
  fi
  sleep 1
done
mostrar "$origem"
