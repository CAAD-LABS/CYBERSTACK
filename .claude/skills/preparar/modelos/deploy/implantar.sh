#!/usr/bin/env bash
# Implanta um commit na pasta de produção: cópia do banco, código, dependências,
# migração, reinício e verificação. Se a verificação falhar, volta sozinho ao
# commit que estava no ar.
#
# Uso: deploy/implantar.sh [commit]     sem argumento: ponta de origin/$RAMO
#      deploy/implantar.sh --reiniciar  só reinicia o serviço e verifica
# Saída: 0 implantado ou nada a fazer | 2 falhou e voltou ao anterior | 3 fora do ar
#        1 parou antes de trocar o código: nada mudou em produção
# O corpo fica em uma função para o bash ler o arquivo inteiro antes de executar:
# a implantação troca este próprio arquivo no meio do caminho.
set -euo pipefail

principal() {
  cd "$(dirname "$0")/.."

  # Lê a configuração do commit que está na pasta e entrega o caminho do banco, como
  # variável de ambiente, aos comandos de instalar, migrar e reiniciar. O ensaio em
  # subshell impede que um erro no arquivo derrube o script no meio da implantação.
  configurar() {
    if ! ( source deploy/config.env ) > /dev/null 2>&1; then
      echo "deploy/config.env tem erro e não pôde ser lido." >&2
      return 1
    fi
    source deploy/config.env
    export BANCO
    if [ -z "${REINICIAR:-}" ] || { [ -z "${SAUDE_CMD:-}" ] && [ -z "${SAUDE_URL:-}" ]; }; then
      echo "deploy/config.env sem REINICIAR ou sem nenhuma verificação (SAUDE_CMD, SAUDE_URL)." >&2
      return 1
    fi
  }
  configurar || exit 1
  REGISTRO="${REGISTRO:-$BACKUPS/implantacoes.log}"
  mkdir -p "$BACKUPS"

  # Uma implantação por vez: a segunda espera a primeira acabar. O flock segura a
  # trava e roda este mesmo script; com --close ela não passa para o serviço que
  # o script reinicia. A variável evita travar duas vezes quando o reverter.sh,
  # que já está com a trava, chama este script.
  trava="$BACKUPS/.trava"
  if [ "${TRAVA_DE_IMPLANTACAO:-}" != "$trava" ]; then
    flock --nonblock "$trava" true || echo "Outra implantação em andamento. Esperando ela terminar." >&2
    TRAVA_DE_IMPLANTACAO="$trava" exec flock --close "$trava" deploy/implantar.sh "$@"
  fi

  # Saudável é passar em duas verificações seguidas: serviço que sobe e cai logo em
  # seguida passa na primeira e não na segunda.
  saudavel() {
    local i seguidas=0 tentativas="${SAUDE_TENTATIVAS:-15}"
    for i in $(seq "$tentativas"); do
      if { [ -z "${SAUDE_CMD:-}" ] || eval "$SAUDE_CMD"; } &&
         { [ -z "${SAUDE_URL:-}" ] || curl --silent --fail --max-time 5 --output /dev/null "$SAUDE_URL"; }; then
        seguidas=$((seguidas + 1))
        if [ "$seguidas" -ge 2 ] || [ "$tentativas" -le 1 ]; then return 0; fi
      else
        seguidas=0
      fi
      sleep "${SAUDE_INTERVALO:-2}"
    done
    return 1
  }

  # colocar <commit> [sem-migrar]: põe o commit na pasta, com a configuração dele, e
  # reinicia. Na volta automática a migração não roda: a do commit anterior já está
  # aplicada, e uma migração que falha não pode impedir a volta.
  colocar() {
    git checkout --quiet --detach "$1" &&
    configurar &&
    { [ -z "${INSTALAR:-}" ] || eval "$INSTALAR"; } &&
    { [ "${2:-}" = "sem-migrar" ] || [ -z "${MIGRAR:-}" ] || eval "$MIGRAR"; } &&
    eval "$REINICIAR"
  }

  if [ "${1:-}" = "--reiniciar" ]; then
    eval "$REINICIAR"
    if saudavel; then echo "Serviço reiniciado e respondendo."; exit 0; fi
    echo "ATENÇÃO: o serviço não respondeu depois do reinício." >&2
    exit 3
  fi

  if ! git fetch --quiet origin 2> /dev/null; then
    # Sem acesso ao remoto ainda dá para pôr no ar um commit que já está na pasta,
    # que é o caso da reversão.
    if [ -z "${1:-}" ] || ! git cat-file -e "$1^{commit}" 2> /dev/null; then
      echo "Não consegui buscar do remoto, e o commit pedido não está na pasta. Nada foi alterado." >&2
      exit 1
    fi
    echo "Aviso: sem acesso ao remoto. Usando o commit que já está na pasta." >&2
  fi
  anterior=$(git rev-parse HEAD)
  novo=$(git rev-parse --quiet --verify "${1:-origin/$RAMO}^{commit}") || {
    echo "Commit não encontrado: ${1:-origin/$RAMO}. Nada foi alterado." >&2
    exit 1
  }
  if [ "$anterior" = "$novo" ]; then
    echo "Nada a implantar: a produção já está em ${novo:0:8}."
    exit 0
  fi

  carimbo=$(date +%Y%m%d-%H%M%S)

  # Na primeira implantação o registro ganha também o commit que já estava no ar,
  # para o reverter.sh ter para onde voltar.
  [ -s "$REGISTRO" ] || printf '%s\t%s\t\tok\n' "$carimbo" "$anterior" >> "$REGISTRO" || true

  copia=""
  if [ -f "$BANCO" ]; then
    copia="$BACKUPS/$carimbo-${anterior:0:8}.db"
    python3 - "$BANCO" "$copia" <<'PY' || { echo "Não consegui copiar o banco. Nada foi alterado." >&2; exit 1; }
import sqlite3, sys
origem = sqlite3.connect(sys.argv[1])
destino = sqlite3.connect(sys.argv[2])
with destino:
    origem.backup(destino)
destino.close()
origem.close()
PY
  else
    echo "Aviso: não achei o banco em $BANCO. Seguindo sem cópia." >&2
  fi

  if colocar "$novo" && saudavel; then
    # O código novo já está no ar: falha ao registrar ou ao limpar cópias não muda o resultado.
    printf '%s\t%s\t%s\tok\n' "$carimbo" "$novo" "$copia" >> "$REGISTRO" ||
      echo "Aviso: não consegui gravar o registro em $REGISTRO." >&2
    { ls -1t "$BACKUPS"/*.db 2>/dev/null || true; } | tail -n +"$(( ${MANTER_BACKUPS:-20} + 1 ))" | xargs -r -d '\n' rm -- || true
    echo "Implantado ${novo:0:8}. Anterior: ${anterior:0:8}. Cópia do banco: ${copia:-nenhuma}."
    exit 0
  fi

  # Falha ao registrar não pode impedir a volta.
  printf '%s\t%s\t%s\tfalhou\n' "$carimbo" "$novo" "$copia" >> "$REGISTRO" || true
  echo "Falha ao implantar ${novo:0:8}. Voltando para ${anterior:0:8}." >&2
  if colocar "$anterior" sem-migrar && saudavel; then
    echo "A produção voltou para ${anterior:0:8}. O banco não foi restaurado; a cópia está em ${copia:-nenhuma}." >&2
    exit 2
  fi
  echo "ATENÇÃO: a volta para ${anterior:0:8} também falhou. A produção está fora do ar." >&2
  exit 3
}

principal "$@"; exit $?
