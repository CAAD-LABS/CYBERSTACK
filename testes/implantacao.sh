#!/usr/bin/env bash
# Exercita implantar.sh e reverter.sh em um projeto de brinquedo (Python e SQLite),
# sem systemd e sem sudo: o "reinício do serviço" é um script que encerra o processo
# anterior e sobe o novo. Tudo acontece em uma pasta temporária, apagada no fim.
#
# Uso: testes/implantacao.sh [pasta com implantar.sh e reverter.sh]
#      Sem argumento, testa os modelos em .claude/skills/preparar/modelos/deploy.
# Saída: 0 se todas as conferências passam, 1 se alguma falha.
set -uo pipefail

AQUI=$(cd "$(dirname "$0")/.." && pwd)
DEPLOY=$(realpath "${1:-$AQUI/.claude/skills/preparar/modelos/deploy}")
for f in implantar.sh reverter.sh; do
  [ -f "$DEPLOY/$f" ] || { echo "Não achei $DEPLOY/$f" >&2; exit 1; }
done

T=$(mktemp -d "${TMPDIR:-/tmp}/cyberstack-teste.XXXXXX")
PORTA=$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
URL="http://127.0.0.1:$PORTA"
REGISTRO="$T/dados/copias/implantacoes.log"
feitos=0
falhas=0
codigo=0
saida=""

limpar() {
  if [ -f "$T/servico.pid" ]; then kill "$(cat "$T/servico.pid")" 2>/dev/null; fi
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
contem() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac; }
nao_contem() { ! contem "$1" "$2"; }

saude() { curl --silent --max-time 3 "$URL/saude" || true; }
no_ar() { git -C "$T/prod" rev-parse HEAD; }
ultima_linha() { tail -n 1 "$REGISTRO"; }
copias() { find "$T/dados/copias" -name '*.db' | wc -l; }
notas() {
  python3 -c 'import sqlite3, sys; print(sqlite3.connect(sys.argv[1]).execute("select count(*) from notas").fetchone()[0])' "${1:-$T/dados/app.db}"
}
grava_nota() {
  python3 -c 'import sqlite3, sys; c = sqlite3.connect(sys.argv[1]); c.execute("insert into notas (texto) values (?)", (sys.argv[2],)); c.commit()' "$T/dados/app.db" "$1"
}

publica() { # publica "<mensagem>": commit do que estiver alterado em dev, envia e devolve o hash
  (cd "$T/dev" && G add -A && G commit --quiet -m "$1" && G push --quiet origin main && git rev-parse HEAD)
}
versao() { # versao <nome>: muda só o número de versão que o sistema mostra
  sed -i "s/^VERSAO = .*/VERSAO = \"$1\"/" "$T/dev/app.py"
  publica "$1"
}
ajusta_config() { # ajusta_config <CHAVE> <linha nova inteira>
  python3 - "$T/dev/deploy/config.env" "$1" "$2" <<'EOF'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
chave, nova = sys.argv[2], sys.argv[3]
linhas = p.read_text().splitlines()
assert any(l.startswith(chave + "=") for l in linhas), chave
p.write_text("\n".join(nova if l.startswith(chave + "=") else l for l in linhas) + "\n")
EOF
}
implantar() {
  (cd "$T/prod" && deploy/implantar.sh "$@") > "$T/saida" 2>&1
  codigo=$?
  saida=$(cat "$T/saida")
}
reverter() {
  (cd "$T/prod" && deploy/reverter.sh "$@") > "$T/saida" 2>&1
  codigo=$?
  saida=$(cat "$T/saida")
}

# ---------------------------------------------------------------- montagem

montar() {
  mkdir -p "$T/dados"
  G init --quiet --bare "$T/origem.git"
  G init --quiet "$T/dev"
  mkdir -p "$T/dev/deploy"
  cp "$DEPLOY/implantar.sh" "$DEPLOY/reverter.sh" "$T/dev/deploy/"
  chmod +x "$T/dev/deploy/implantar.sh" "$T/dev/deploy/reverter.sh"

  # Faz o papel de "sudo systemctl restart". Fica fora do repositório, como o systemd.
  # O serviço recebe o BANCO daqui, como receberia do Environment= da unidade.
  cat > "$T/reiniciar.sh" <<EOF
#!/usr/bin/env bash
if [ -f "$T/servico.pid" ]; then
  p=\$(cat "$T/servico.pid")
  kill "\$p" 2>/dev/null || true
  for _ in \$(seq 50); do kill -0 "\$p" 2>/dev/null || break; sleep 0.1; done
fi
[ -e "$T/nao-sobe" ] && exit 0
cd "$T/prod"
BANCO="$T/dados/app.db" PORTA=$PORTA setsid nohup python3 app.py >> "$T/servico.log" 2>&1 &
echo \$! > "$T/servico.pid"
EOF
  chmod +x "$T/reiniciar.sh"

  cat > "$T/dev/deploy/config.env" <<EOF
RAMO=main
BANCO="$T/dados/app.db"
BACKUPS="$T/dados/copias"
MANTER_BACKUPS=3
INSTALAR=""
MIGRAR=""
REINICIAR="$T/reiniciar.sh"
SAUDE_CMD=""
SAUDE_URL="$URL/saude"
SAUDE_TENTATIVAS=8
SAUDE_INTERVALO=0.3
EOF

  cat > "$T/dev/app.py" <<'EOF'
import os, sqlite3
from http.server import BaseHTTPRequestHandler, HTTPServer

BANCO = os.environ["BANCO"]
VERSAO = "v1"


class Atende(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/saude":
            con = sqlite3.connect(BANCO)
            total = con.execute("select count(*) from notas").fetchone()[0]
            con.close()
            self.send_response(200)
            self.end_headers()
            self.wfile.write(f"ok {VERSAO} notas={total}\n".encode())
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, *a):
        pass


HTTPServer(("127.0.0.1", int(os.environ["PORTA"])), Atende).serve_forever()
EOF

  (cd "$T/dev" && G add -A && G commit --quiet -m "v1" && G remote add origin "$T/origem.git" && G push --quiet -u origin main)
  G clone --quiet "$T/origem.git" "$T/prod"

  python3 - "$T/dados/app.db" <<'EOF'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
c.execute("pragma journal_mode=wal")
c.execute("create table notas (id integer primary key, texto text)")
c.execute("insert into notas (texto) values ('primeira nota')")
c.commit()
c.close()
EOF
  "$T/reiniciar.sh"
  for _ in $(seq 20); do contem "$(saude)" "ok v1" && return 0; sleep 0.2; done
  echo "O serviço de teste não subiu. Veja $T/servico.log" >&2
  trap - EXIT
  exit 1
}

# ---------------------------------------------------------------- cenários

montar
echo "Testando os scripts de: $DEPLOY"

caso "1. Implantação boa"
V1=$(no_ar)
V2=$(versao v2)
implantar
confere "sai com código 0" igual "$codigo" 0
confere "o sistema responde na versão nova" contem "$(saude)" "ok v2"
confere "a pasta de produção está no commit novo" igual "$(no_ar)" "$V2"
confere "o registro ganha uma linha ok com o commit" contem "$(ultima_linha)" "$V2"
confere "a linha do registro termina em ok" contem "$(ultima_linha)" "	ok"
confere "a cópia do banco feita antes existe e tem os dados" igual "$(notas "$(ultima_linha | cut -f3)")" 1

caso "2. Nada a implantar"
implantar
confere "sai com código 0" igual "$codigo" 0
confere "avisa que não há o que implantar" contem "$saida" "Nada a implantar"

caso "3. A primeira entrega já pode ser desfeita"
confere "o registro começa pelo commit que estava no ar antes da stack" contem "$(head -n 1 "$REGISTRO")" "$V1"
reverter
confere "reverter.sh sai com código 0" igual "$codigo" 0
confere "o sistema volta à versão de antes da primeira entrega" contem "$(saude)" "ok v1"
implantar
confere "e a entrega pode ser refeita" contem "$(saude)" "ok v2"

caso "4. Implantação quebrada volta sozinha"
(cd "$T/dev" && printf 'raise SystemExit("quebrado de propósito")\n' | cat - app.py > app.novo && mv app.novo app.py)
V3=$(publica "v3 quebrada")
implantar
confere "sai com código 2" igual "$codigo" 2
confere "o sistema segue respondendo na versão anterior" contem "$(saude)" "ok v2"
confere "a pasta de produção voltou ao commit anterior" igual "$(no_ar)" "$V2"
confere "o registro marca o commit quebrado como falhou" contem "$(ultima_linha)" "$V3"
confere "a linha do registro termina em falhou" contem "$(ultima_linha)" "	falhou"

caso "5. Reversão manual preserva o banco"
(cd "$T/dev" && sed -i '1d' app.py)
V4=$(versao v4)
implantar
grava_nota "gravada com a v4 no ar"
V5=$(versao v5)
implantar
confere "a v5 está no ar com as duas notas" contem "$(saude)" "ok v5 notas=2"
reverter
confere "sai com código 0" igual "$codigo" 0
confere "volta para a implantação bem-sucedida anterior" contem "$(saude)" "ok v4"
confere "o banco não volta: a nota gravada depois continua lá" igual "$(notas)" 2
confere "avisa que a principal ainda contém o código que saiu do ar" contem "$saida" "ainda contém o código que saiu do ar"

caso "6. Lista das implantações"
reverter --listar
confere "sai com código 0" igual "$codigo" 0
confere "mostra o cabeçalho" contem "$saida" "resultado"
confere "mostra a implantação da v5" contem "$saida" "$V5"

caso "7. Reversão para um commit escolhido"
reverter "$V2"
confere "sai com código 0" igual "$codigo" 0
confere "o sistema responde na versão pedida" contem "$(saude)" "ok v2"

caso "8. Restauração do banco"
grava_nota "terceira nota"
V6=$(versao v6)
implantar
COPIA=$(ultima_linha | cut -f3)
grava_nota "quarta nota, gravada depois da cópia"
confere "antes de restaurar há quatro notas" igual "$(notas)" 4
reverter --restaurar-banco "$COPIA"
confere "sai com código 0" igual "$codigo" 0
confere "o banco volta ao conteúdo da cópia" igual "$(notas)" 3
confere "o código fica como estava" igual "$(no_ar)" "$V6"
confere "o sistema responde depois do reinício" contem "$(saude)" "ok v6 notas=3"
GUARDA=$(find "$T/dados/copias" -name '*-antes-de-restaurar.db' | head -n 1)
confere "o estado de antes da restauração fica guardado" igual "$(notas "$GUARDA")" 4

caso "9. Falha total: nem a nova nem a anterior sobem"
touch "$T/nao-sobe"
V7=$(versao v7)
implantar
confere "sai com código 3" igual "$codigo" 3
confere "avisa que a produção está fora do ar" contem "$saida" "fora do ar"
rm "$T/nao-sobe"
implantar --reiniciar
confere "com a causa resolvida, --reiniciar sai com código 0" igual "$codigo" 0
confere "o sistema volta a responder na versão anterior" contem "$(saude)" "ok v6"

caso "10. Rodízio das cópias do banco"
implantar
confere "a v7 entra depois que o serviço volta a subir" contem "$(saude)" "ok v7"
confere "ficam no máximo as cópias de MANTER_BACKUPS" test "$(copias)" -le 3

caso "11. Rodar a reversão duas vezes volta duas versões"
V8=$(versao v8)
implantar
V9=$(versao v9)
implantar
confere "a v9 está no ar" contem "$(saude)" "ok v9"
reverter
confere "a primeira reversão volta para a v8" contem "$(saude)" "ok v8"
reverter
confere "a segunda volta mais uma, para a v7, e não de novo para a v9" contem "$(saude)" "ok v7"

caso "12. Feature que traz migração, código e configuração no mesmo commit"
cat > "$T/dev/migrar.py" <<'EOF'
import os, sqlite3

# O caminho do banco vem da variável de ambiente BANCO, como manda o AGENTS.md.
pasta = os.path.dirname(os.environ["BANCO"])
if os.path.exists(os.path.join(pasta, "migracao-falha")):
    raise SystemExit("falha de ambiente simulada")
con = sqlite3.connect(os.environ["BANCO"])
colunas = [linha[1] for linha in con.execute("pragma table_info(notas)")]
if "autor" not in colunas:
    con.execute("alter table notas add column autor text default 'sem autor'")
con.commit()
con.close()
EOF
python3 - "$T/dev/app.py" <<'EOF'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
t = p.read_text()
velho = "        else:\n            self.send_response(404)"
novo = """        elif self.path == "/notas":
            con = sqlite3.connect(BANCO)
            linhas = con.execute("select texto, autor from notas").fetchall()
            con.close()
            self.send_response(200)
            self.end_headers()
            self.wfile.write(repr(linhas).encode())
        else:
            self.send_response(404)"""
assert t.count(velho) == 1
p.write_text(t.replace(velho, novo))
EOF
ajusta_config MIGRAR 'MIGRAR="python3 migrar.py"'
V10=$(versao v10)
implantar
confere "sai com código 0" igual "$codigo" 0
confere "o sistema responde na versão nova" contem "$(saude)" "ok v10"
confere "a migração rodou nesta mesma implantação e enxergou o BANCO" contem "$(python3 -c 'import sqlite3, sys; print([l[1] for l in sqlite3.connect(sys.argv[1]).execute("pragma table_info(notas)")])' "$T/dados/app.db")" "autor"
confere "a tela que usa a coluna nova funciona" igual "$(curl --silent --max-time 3 --output /dev/null --write-out '%{http_code}' "$URL/notas")" 200

caso "13. Migração que falha não vira produção fora do ar"
touch "$T/dados/migracao-falha"
V11=$(versao v11)
implantar
confere "sai com código 2, e não 3" igual "$codigo" 2
confere "o sistema segue respondendo na versão anterior" contem "$(saude)" "ok v10"
confere "a pasta de produção voltou ao commit anterior" igual "$(no_ar)" "$V10"
confere "não acusa produção fora do ar" nao_contem "$saida" "fora do ar"
rm "$T/dados/migracao-falha"
implantar
confere "com a causa resolvida, a mesma versão entra" contem "$(saude)" "ok v11"

caso "14. O aviso de sincronizar a principal só aparece quando o código voltou"
V12=$(versao v12)
COPIA=$(ultima_linha | cut -f3)
reverter --restaurar-banco "$COPIA"
confere "restaurar o banco sem trocar o código sai com código 0" igual "$codigo" 0
confere "e não diz que a principal contém código que saiu do ar" nao_contem "$saida" "saiu do ar"
implantar
confere "a v12, que só não tinha sido implantada, entra normalmente" contem "$(saude)" "ok v12"

caso "15. O comando de sincronização indicado funciona em histórico com merge"
(cd "$T/dev" && G checkout --quiet -b tarefa && sed -i 's/^VERSAO = .*/VERSAO = "v13"/' app.py && G commit --quiet -am "v13 em uma branch" \
  && G checkout --quiet main && G merge --quiet --no-ff --no-edit tarefa && G push --quiet origin main)
V13=$(git -C "$T/dev" rev-parse HEAD)
implantar
confere "a v13, que chegou por merge, está no ar" contem "$(saude)" "ok v13"
reverter
confere "a reversão volta para a v12" contem "$(saude)" "ok v12"
confere "o aviso de sincronizar aparece" contem "$saida" "saiu do ar"
COMANDO=$(printf '%s\n' "$saida" | sed -n 's/^  \(git .*\)$/\1/p' | tail -n 1)
confere "o aviso traz o comando para fazer à mão" test -n "$COMANDO"
(cd "$T/prod" && G config user.name teste && G config user.email teste@exemplo.invalid && eval "$COMANDO") > "$T/saida-sinc" 2>&1
confere "o comando indicado roda sem erro" igual "$?" 0
git -C "$T/prod" fetch --quiet origin
confere "a principal fica com o mesmo conteúdo da produção" git -C "$T/prod" diff --quiet HEAD origin/main
confere "sem reescrever o histórico: o commit novo vem depois do merge" igual "$(git -C "$T/prod" rev-parse origin/main^)" "$V13"

(cd "$T/dev" && G pull --quiet origin main)

caso "16. Sem acesso ao remoto, a reversão ainda funciona"
mv "$T/origem.git" "$T/origem.fora"
reverter "$V11"
confere "voltar para um commit que já está na pasta sai com código 0" igual "$codigo" 0
confere "o sistema responde na versão pedida" contem "$(saude)" "ok v11"
implantar 0123456789abcdef0123456789abcdef01234567
confere "implantar um commit que não está na pasta sai com código 1" igual "$codigo" 1
confere "e o sistema segue como estava" contem "$(saude)" "ok v11"
mv "$T/origem.fora" "$T/origem.git"

caso "17. Falha ao gravar o registro não impede a volta"
(cd "$T/dev" && printf 'raise SystemExit("quebrado de propósito")\n' | cat - app.py > app.novo && mv app.novo app.py)
publica "versão quebrada" > /dev/null
chmod a-w "$REGISTRO"
implantar
chmod u+w "$REGISTRO"
confere "sai com código 2" igual "$codigo" 2
confere "o sistema segue respondendo na versão anterior" contem "$(saude)" "ok v11"
(cd "$T/dev" && sed -i '1d' app.py)

caso "18. Serviço que sobe e cai em seguida não passa na verificação"
ajusta_config SAUDE_URL 'SAUDE_URL=""'
ajusta_config SAUDE_CMD "SAUDE_CMD='kill -0 \"\$(cat $T/servico.pid)\" 2> /dev/null'"
V14=$(versao v14)
implantar
confere "a verificação só pelo processo vivo entra junto com a v14" contem "$(saude)" "ok v14"
(cd "$T/dev" && sed -i 's/^HTTPServer.*/import time; time.sleep(0.1); raise SystemExit("morre logo depois de subir")/' app.py)
publica "v15 que morre logo depois de subir" > /dev/null
implantar
confere "sai com código 2, e não 0" igual "$codigo" 2
confere "a pasta de produção voltou ao commit anterior" igual "$(no_ar)" "$V14"
confere "o sistema responde na versão anterior" contem "$(saude)" "ok v14"

caso "19. Configuração sem reinício não vai ao ar"
(cd "$T/dev" && G revert --no-edit HEAD > /dev/null)
ajusta_config REINICIAR 'REINICIAR=""'
publica "configuração sem o comando de reinício" > /dev/null
implantar
confere "sai com código 2" igual "$codigo" 2
confere "diz o motivo" contem "$saida" "sem REINICIAR"
confere "o sistema segue na versão anterior" contem "$(saude)" "ok v14"

caso "20. Duas implantações ao mesmo tempo entram em fila"
ajusta_config REINICIAR "REINICIAR=\"$T/reiniciar.sh\""
ajusta_config INSTALAR "INSTALAR='echo inicio >> \"$T/marcas\"; sleep 1.2; echo fim >> \"$T/marcas\"'"
V20=$(versao v20)
V21=$(versao v21)
(cd "$T/prod" && deploy/implantar.sh "$V20") > "$T/saida-primeira" 2>&1 &
PRIMEIRA=$!
sleep 0.4
implantar "$V21"
wait "$PRIMEIRA"
codigo_primeira=$?
confere "a primeira sai com código 0" igual "$codigo_primeira" 0
confere "a segunda sai com código 0" igual "$codigo" 0
confere "a segunda avisa que esperou a vez" contem "$saida" "Esperando"
confere "uma só começou depois que a outra acabou" igual "$(tr '\n' ' ' < "$T/marcas")" "inicio fim inicio fim "
confere "a segunda partiu do commit que a primeira deixou no ar" contem "$saida" "Anterior: ${V20:0:8}"
confere "no fim está no ar a versão da segunda" contem "$(saude)" "ok v21"

# ---------------------------------------------------------------- resultado

echo
if [ "$falhas" -eq 0 ]; then
  echo "Resultado: $feitos conferências, todas passaram."
  exit 0
fi
echo "Resultado: $feitos conferências, $falhas falharam."
exit 1
