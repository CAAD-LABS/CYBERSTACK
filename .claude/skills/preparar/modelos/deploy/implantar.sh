#!/usr/bin/env bash
# Implanta um commit na pasta de produção: cópia do banco, código, dependências,
# migração, reinício e verificação. Se a verificação falhar, volta sozinho ao
# commit que estava no ar.
#
# Uso: deploy/implantar.sh [commit]     sem argumento: ponta de origin/$RAMO
#      deploy/implantar.sh --reiniciar  só reinicia o serviço e verifica
# Saída: 0 implantado ou nada a fazer | 2 falhou e voltou ao anterior | 3 fora do ar
# O corpo fica em uma função para o bash ler o arquivo inteiro antes de executar:
# a implantação troca este próprio arquivo no meio do caminho.
set -euo pipefail

principal() {
  cd "$(dirname "$0")/.."
  source deploy/config.env
  REGISTRO="${REGISTRO:-$BACKUPS/implantacoes.log}"
  mkdir -p "$BACKUPS"

  saudavel() {
    local i
    for i in $(seq "${SAUDE_TENTATIVAS:-15}"); do
      if { [ -z "${SAUDE_CMD:-}" ] || eval "$SAUDE_CMD"; } &&
         { [ -z "${SAUDE_URL:-}" ] || curl --silent --fail --max-time 5 --output /dev/null "$SAUDE_URL"; }; then
        return 0
      fi
      sleep "${SAUDE_INTERVALO:-2}"
    done
    return 1
  }

  colocar() {
    git checkout --quiet --detach "$1" &&
    { [ -z "${INSTALAR:-}" ] || eval "$INSTALAR"; } &&
    { [ -z "${MIGRAR:-}" ] || eval "$MIGRAR"; } &&
    eval "$REINICIAR"
  }

  if [ "${1:-}" = "--reiniciar" ]; then
    eval "$REINICIAR"
    if saudavel; then echo "Serviço reiniciado e respondendo."; exit 0; fi
    echo "ATENÇÃO: o serviço não respondeu depois do reinício." >&2
    exit 3
  fi

  git fetch --quiet origin
  anterior=$(git rev-parse HEAD)
  novo=$(git rev-parse "${1:-origin/$RAMO}^{commit}")
  if [ "$anterior" = "$novo" ]; then
    echo "Nada a implantar: a produção já está em ${novo:0:8}."
    exit 0
  fi

  carimbo=$(date +%Y%m%d-%H%M%S)
  copia=""
  if [ -f "$BANCO" ]; then
    copia="$BACKUPS/$carimbo-${anterior:0:8}.db"
    python3 - "$BANCO" "$copia" <<'PY'
import sqlite3, sys
origem = sqlite3.connect(sys.argv[1])
destino = sqlite3.connect(sys.argv[2])
with destino:
    origem.backup(destino)
destino.close()
origem.close()
PY
  fi

  if colocar "$novo" && saudavel; then
    printf '%s\t%s\t%s\tok\n' "$carimbo" "$novo" "$copia" >> "$REGISTRO"
    { ls -1t "$BACKUPS"/*.db 2>/dev/null || true; } | tail -n +"$(( ${MANTER_BACKUPS:-20} + 1 ))" | xargs -r rm --
    echo "Implantado ${novo:0:8}. Anterior: ${anterior:0:8}. Cópia do banco: ${copia:-nenhuma}."
    exit 0
  fi

  printf '%s\t%s\t%s\tfalhou\n' "$carimbo" "$novo" "$copia" >> "$REGISTRO"
  echo "Falha ao implantar ${novo:0:8}. Voltando para ${anterior:0:8}." >&2
  if colocar "$anterior" && saudavel; then
    echo "A produção voltou para ${anterior:0:8}. O banco não foi restaurado; a cópia está em ${copia:-nenhuma}." >&2
    exit 2
  fi
  echo "ATENÇÃO: a volta para ${anterior:0:8} também falhou. A produção está fora do ar." >&2
  exit 3
}

principal "$@"; exit $?
