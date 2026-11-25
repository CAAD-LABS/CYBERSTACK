#!/usr/bin/env bash
# Instala a CyberStack: copia os perfis e os comandos para a pasta .claude de um
# projeto, ou da pasta pessoal, e confere cada arquivo pelo SHA-256.
#
# Uso: ./instalar.sh <pasta do projeto>   instala em <pasta>/.claude
#      ./instalar.sh --global             instala em ~/.claude, para todos os projetos
#      ./instalar.sh --conferir [pasta]   só confere; sem pasta, confere este repositório
#      ./instalar.sh --somas              regrava o SHA256SUMS a partir dos arquivos daqui
#
# Opção: --sobrescrever   troca também o arquivo que já existe no destino e está diferente.
#                         Sem ela, arquivo que você alterou no destino é mantido.
#
# Não cria AGENTS.md, CLAUDE.md nem .cyberstack/projeto.md: eles nascem no /preparar.
# Não faz commit.
# Saída: 0 tudo instalado e conferido | 1 erro | 2 instalado, mas ficou arquivo diferente no destino
set -euo pipefail

AQUI=$(cd "$(dirname "$0")" && pwd)
SOMAS="$AQUI/SHA256SUMS"

uso() { sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; }

arquivos() { sed 's/^[0-9a-f]\{64\}  //' "$SOMAS"; }

conferir() { # conferir <raiz>: 0 se todos os arquivos da stack em <raiz> batem com o SHA256SUMS
  (cd "$1" && sha256sum --check --quiet "$SOMAS")
}

sobrescrever=nao
modo=instalar
destino=""
while [ $# -gt 0 ]; do
  case "$1" in
    --global) destino="$HOME" ;;
    --conferir) modo=conferir ;;
    --somas) modo=somas ;;
    --sobrescrever) sobrescrever=sim ;;
    -h|--help|--ajuda) uso; exit 0 ;;
    -*) echo "Opção desconhecida: $1" >&2; uso >&2; exit 1 ;;
    *) destino="$1" ;;
  esac
  shift
done

if [ "$modo" = "somas" ]; then
  (cd "$AQUI" && find .claude -type f | LC_ALL=C sort | sed 's|^\./||' | xargs -d '\n' sha256sum) > "$SOMAS.novo"
  mv "$SOMAS.novo" "$SOMAS"
  echo "SHA256SUMS regravado: $(wc -l < "$SOMAS") arquivos."
  exit 0
fi

[ -f "$SOMAS" ] || { echo "Não achei $SOMAS." >&2; exit 1; }

if [ "$modo" = "conferir" ]; then
  raiz="${destino:-$AQUI}"
  [ -d "$raiz" ] || { echo "Pasta não encontrada: $raiz" >&2; exit 1; }
  if conferir "$raiz"; then
    echo "Conferido: os $(wc -l < "$SOMAS") arquivos da stack em $raiz batem com o SHA256SUMS."
    exit 0
  fi
  echo "Há arquivo da stack faltando ou diferente em $raiz (lista acima)." >&2
  exit 1
fi

[ -n "$destino" ] || { uso >&2; exit 1; }
[ -d "$destino" ] || { echo "Pasta não encontrada: $destino" >&2; exit 1; }
destino=$(cd "$destino" && pwd)

if ! conferir "$AQUI"; then
  echo "Os arquivos deste repositório não batem com o SHA256SUMS (lista acima)." >&2
  echo "Se a mudança é sua, rode ./instalar.sh --somas e tente de novo." >&2
  exit 1
fi

criados=0; iguais=0; trocados=0; mantidos=0
while IFS= read -r caminho; do
  origem="$AQUI/$caminho"
  alvo="$destino/$caminho"
  if [ ! -e "$alvo" ]; then
    mkdir -p "$(dirname "$alvo")"
    cp --preserve=mode "$origem" "$alvo"
    criados=$((criados + 1))
  elif cmp --silent "$origem" "$alvo"; then
    chmod --reference="$origem" "$alvo"
    iguais=$((iguais + 1))
  elif [ "$sobrescrever" = "sim" ]; then
    cp --preserve=mode "$origem" "$alvo"
    trocados=$((trocados + 1))
    echo "trocado:  $caminho"
  else
    mantidos=$((mantidos + 1))
    echo "mantido (já existia e está diferente): $caminho"
  fi
done < <(arquivos)

echo "Destino: $destino/.claude"
echo "Criados: $criados | já iguais: $iguais | trocados: $trocados | mantidos diferentes: $mantidos"

if [ "$mantidos" -gt 0 ]; then
  echo
  echo "Os arquivos mantidos são do destino, não desta versão da stack."
  echo "Para trocá-los pelos daqui: ./instalar.sh --sobrescrever $destino"
  exit 2
fi

conferir "$destino"
echo "Conferido pelo SHA-256."
echo
echo "Próximo passo: abra uma sessão nova do Claude Code na raiz do projeto e rode /preparar."
