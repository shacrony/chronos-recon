#!/bin/bash

# ──────────────── BANNER ────────────────
echo -e "\033[1;36m"
echo "╔══════════════════════════════════════╗"
echo "║              𝙘𝙝𝙧𝙤𝙣𝙤𝙨                  ║"
echo "║      Subdomain Recon Automation      ║"
echo "╚══════════════════════════════════════╝"
echo -e "\033[0m"

# ──────────────────────────────────────────────────────────
# Script: Recon para Bug Bounty
# Autor: Chronos
# Função: Automatizar enumeração de subdomínios, ativos e fuzz
# ──────────────────────────────────────────────────────────

# ─── CHECK: USO ───────────────────────────────────────────
if [ -z "$1" ]; then
  echo -e "\n[!] Uso: $0 dominio.com\n"
  exit 1
fi

DOMINIO=$1
DATA=$(date +%Y%m%d-%H%M)
PASTA="recon-$DOMINIO-$DATA"
mkdir -p "$PASTA" && cd "$PASTA"

# ─── CHECK: CHAOS API ─────────────────────────────────────
if [ -z "$CHAOS_KEY" ]; then
  echo -e "[!] Variável CHAOS_KEY não está definida!"
  echo -e "    Exporte com: export CHAOS_KEY=\"sua-chave\"\n"
  exit 1
fi

# ─── CHECK: FERRAMENTAS ──────────────────────────────────
for tool in subfinder sublist3r chaos httpx-toolkit dirsearch katana nuclei gf waybackurls python3; do
  if ! command -v "$tool" &> /dev/null; then
    echo -e "[!] Ferramenta não encontrada: $tool"
    MISSING=true
  fi
done
[ "$MISSING" = true ] && exit 1

# ─── 1. ENUMERAÇÃO DE SUBDOMÍNIOS ────────────────────────
echo -e "\n[1] Coletando subdomínios..."
sublist3r -d "$DOMINIO" -o subdomain1.txt
subfinder -d "$DOMINIO" -o subdomain2.txt
chaos -d "$DOMINIO" -v > subdomain3.txt

# ─── 2. UNIÃO E REMOÇÃO DE DUPLICATAS ─────────────────────
cat subdomain1.txt subdomain2.txt subdomain3.txt > subfinal.txt
sort subfinal.txt | uniq > subuniq.txt
cat subuniq.txt | wc -l

# ─── 3. SUBDOMAIN TAKEOVER COM TAKEOVER.PY ───────────────
echo "[2] Verificando possíveis subdomain takeovers com takeover.py..."
if [ ! -f ../takeover.py ]; then
  echo "[!] takeover.py não encontrado. Coloque o script na mesma pasta ou ajuste o caminho."
else
  python3 ../takeover.py -l subuniq.txt --vuln -o takeover-results.json
fi

# ─── 4. VERIFICANDO VIVOS COM HTTPX ───────────────────────
echo "[3] Verificando ativos com httpx..."
cat subuniq.txt | httpx-toolkit -silent > subdomainlive.txt
cat subdomainlive.txt | wc -l

# ─── 5. GITDORKER ─────────────────────────────────────────
echo "[4] Rodando GitDorker..."
python3 GitDorker.py -d Dorks/medium_dorks.txt -tf tokens.txt -q "$DOMINIO" -lb

# ─── 6. KATANA + COLETA DE JS E URLS ──────────────────────
echo "[5] Coletando JS e URLs via Katana..."
katana -list subuniq.txt -jc -silent | grep ".js$" | sort -u > js.txt
katana -u subdomainlive.txt -d 5 -ps waybackarchive,commoncrawl,alienvault \
  -jc -fx -ef woff,css,png,svg,mp3,woff2,jpeg,gif,svg -silent -o allurls.txt

# ─── 7. FILTROS DE ARQUIVOS ──────────────────────────────
echo "[6] Filtrando arquivos sensíveis..."
cat allurls.txt | grep -Ei "\.txt|\.log|\.cache|\.secret|\.db|\.backup|\.yml|\.json|\.gz|\.rar|\.zip|\.config" > arquivos_sensiveis.txt
cat allurls.txt | grep -Ei "\.js$" >> js.txt

# ─── 8. SCAN NUCLEI EM JS ─────────────────────────────────
echo "[7] Rodando nuclei em arquivos JS..."
cat js.txt | nuclei -t ~/.local/nuclei-templates/ -severity 'critical,high,medium' -silent -o nuclei-js.txt

# ─── 9. FUZZING COM GF + NUCLEI ───────────────────────────
echo "[8] Buscando LFI com GF + Nuclei..."
cat allurls.txt | gf lfi | nuclei -tags lfi -silent -o lfi-results.txt

# ─── 10. WAYBACK + GF PARA XSS ───────────────────────────
echo "[9] Coletando com Wayback e buscando XSS com GF..."
waybackurls "$DOMINIO" > wayback.txt
cat wayback.txt | gf xss > xss-candidates.txt

# ─── 11. DIRSEARCH ─────────────────────────────────────────
echo "[10] Rodando Dirsearch..."
while read url; do
  dirsearch -u "$url" -e php,cgi,htm,html,shtml,shtm,js,txt,bak,zip,old,conf,log,asp,aspx,jsp,sql,db,sqlite,md,tar.gz,7z,rar,json,xml,yaml,yml,ini,java,py,rb,php3,php4,php5 --random-agent --recursive -R 3 -t 20 --exclude-status=404 --follow-redirects --timeout=10 -o "dirsearch-${url//[:\/]/_}.txt"
done < subdomainlive.txt

echo -e "\n[✔] Recon finalizado! Resultados em: $(pwd)\n"
