#!/usr/bin/env bash
# Volta a produção para uma versão anterior.
#
# Uso: deploy/reverter.sh                    volta para a implantação bem-sucedida anterior
#      deploy/reverter.sh <commit>           volta para um commit específico
#      deploy/reverter.sh --listar           mostra as implantações registradas
#      deploy/reverter.sh --restaurar-banco <arquivo.db> [commit]
#                                            restaura o banco e reinicia; sem commit, o código fica como está.
#                                            Perde o que foi gravado depois da cópia.
set -euo pipefail
cd "$(dirname "$0")/.."
source deploy/config.env
REGISTRO="${REGISTRO:-$BACKUPS/implantacoes.log}"

if [ "${1:-}" = "--listar" ]; then
  [ -f "$REGISTRO" ] || { echo "Nenhuma implantação registrada."; exit 0; }
  printf 'data-hora\tcommit\tcopia_do_banco\tresultado\n'
  cat "$REGISTRO"
  exit 0
fi

banco_a_restaurar=""
if [ "${1:-}" = "--restaurar-banco" ]; then
  banco_a_restaurar="${2:?informe o arquivo da cópia do banco}"
  [ -f "$banco_a_restaurar" ] || { echo "Cópia não encontrada: $banco_a_restaurar" >&2; exit 1; }
  shift 2
fi

atual=$(git rev-parse HEAD)
alvo="${1:-}"
if [ -z "$alvo" ] && [ -n "$banco_a_restaurar" ]; then
  alvo="$atual"
elif [ -z "$alvo" ]; then
  [ -f "$REGISTRO" ] || { echo "Sem registro de implantações. Informe o commit." >&2; exit 1; }
  # A anterior é a que estava no ar antes de a atual entrar pela primeira vez. Assim,
  # rodar de novo volta mais uma versão, em vez de devolver a que acabou de sair.
  # Se a atual não está no registro, vale a última implantação bem-sucedida.
  alvo=$(awk -F'\t' -v atual="$atual" '
    $4 != "ok" { next }
    $2 == atual && !achou { achou = 1; alvo = antes }
    !achou { antes = $2 }
    END { print (achou ? alvo : antes) }' "$REGISTRO")
  [ -n "$alvo" ] || { echo "Não há implantação anterior bem-sucedida no registro. Informe o commit." >&2; exit 1; }
fi
alvo=$(git rev-parse "$alvo^{commit}")

if [ -n "$banco_a_restaurar" ]; then
  seguranca="$BACKUPS/$(date +%Y%m%d-%H%M%S)-antes-de-restaurar.db"
  python3 - "$BANCO" "$seguranca" "$banco_a_restaurar" <<'PY'
import sqlite3, sys
banco, seguranca, copia = sys.argv[1:4]
atual = sqlite3.connect(banco)
guarda = sqlite3.connect(seguranca)
with guarda:
    atual.backup(guarda)
guarda.close()
origem = sqlite3.connect(copia)
with atual:
    origem.backup(atual)
origem.close()
atual.close()
PY
  echo "Banco restaurado de $banco_a_restaurar. O estado anterior ficou em $seguranca."
fi

if [ "$alvo" = "$atual" ]; then
  echo "O código já está em ${alvo:0:8}."
  deploy/implantar.sh --reiniciar
else
  deploy/implantar.sh "$alvo"
fi

git fetch --quiet origin || true
if [ "$alvo" != "$atual" ] && [ "$alvo" != "$(git rev-parse "origin/$RAMO")" ]; then
  echo
  echo "A branch $RAMO ainda contém o código que saiu do ar."
  echo "Antes da próxima feature, o /fluxo devolve à $RAMO o conteúdo que está em produção. Para fazer à mão:"
  echo "  git push origin \"\$(git commit-tree ${alvo:0:8}^{tree} -p origin/$RAMO -m 'Volta a $RAMO ao conteúdo de ${alvo:0:8}')\":$RAMO"
fi
