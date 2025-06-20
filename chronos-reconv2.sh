#!/bin/bash
set -e

# ──────────────── BANNER ────────────────
echo -e "\033[1;36m"
echo "╔══════════════════════════════════════╗"
echo "║ 𝙘𝙝𝙧𝙤𝙣𝙤𝙨 ║"
echo "║ Subdomain Recon Automation ║"
echo "╚══════════════════════════════════════╝"
echo -e "\033[0m"

# ──────────────────────────────────────────────────────────
# Script: Recon para Bug Bounty
# Autor: Chronos
# Função: Automatizar enumeração de subdomínios, ativos e fuzz
# ──────────────────────────────────────────────────────────

# ─── VARIÁVEIS CONFIGURÁVEIS ──────────────────────────────
GITDORKER_PATH="${GITDORKER_PATH:-/home/kali/Downloads/GitDorker}"
FEROX_WORDLIST="${FEROX_WORDLIST:-/usr/share/wordlists/dirbuster/directory-list-2.3-medium.txt}"

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
    echo -e " Exporte com: export CHAOS_KEY=\"sua-chave\"\n"
    exit 1
fi

# ─── CHECK: FERRAMENTAS ──────────────────────────────────
MISSING=false
for tool in subfinder sublist3r chaos httpx-toolkit feroxbuster katana nuclei gf waybackurls python3; do
    if ! command -v "$tool" &> /dev/null; then
        echo -e "\033[1;31m[!] Ferramenta não encontrada: $tool\033[0m"
        MISSING=true
    fi
done
[ "$MISSING" = true ] && exit 1

# ─── 1. ENUMERAÇÃO DE SUBDOMÍNIOS (PARALELO) ─────────────
echo -e "\n[1] Coletando subdomínios..."
sublist3r -d "$DOMINIO" -o subdomain1.txt & 
subfinder -d "$DOMINIO" -o subdomain2.txt & 
chaos -d "$DOMINIO" -v > subdomain3.txt & 
wait

# ─── 2. UNIÃO E REMOÇÃO DE DUPLICATAS ────────────────────
cat subdomain1.txt subdomain2.txt subdomain3.txt > subfinal.txt
sort -u subfinal.txt > subuniq.txt
SUBS=$(wc -l < subuniq.txt)
echo -e "\033[1;32m[✔] Subdomínios únicos encontrados: $SUBS\033[0m"

# ─── 3. SUBDOMAIN TAKEOVER COM TAKEOVER.PY ───────────────
echo -e "\n[2] Verificando possíveis subdomain takeovers com takeover.py..."
if [ ! -f ../takeover.py ]; then
    echo -e "\033[1;33m[!] takeover.py não encontrado. Coloque o script na mesma pasta ou ajuste o caminho.\033[0m"
else
    python3 ../takeover.py -l subuniq.txt --vuln -o takeover-results.json || echo -e "\033[1;31m[!] takeover.py falhou\033[0m"
fi

# ─── 4. VERIFICANDO VIVOS COM HTTPX ──────────────────────
echo -e "\n[3] Verificando ativos com httpx..."
httpx-toolkit -silent < subuniq.txt > subdomainlive.txt
LIVES=$(wc -l < subdomainlive.txt)
echo -e "\033[1;32m[✔] Subdomínios ativos: $LIVES\033[0m"

# ─── 5. GitDorker (modo automático) ──────────────────────
echo -e "\n\033[1;34m[4] Executando GitDorker com token global...\033[0m"
DORKS_FILE="$GITDORKER_PATH/Dorks/medium_dorks.txt"
TOKENS_FILE="$GITDORKER_PATH/tokens.txt"
OUTPUT_FILE="gitdorker_$DOMINIO.txt"
if [ -f "$TOKENS_FILE" ] && [ -f "$DORKS_FILE" ]; then
    python3 "$GITDORKER_PATH/GitDorker.py" \
        -d "$DORKS_FILE" \
        -tf "$TOKENS_FILE" \
        -q "$DOMINIO" -lb \
        -o "$OUTPUT_FILE" \
        && echo -e "\033[1;32m[✔] GitDorker finalizado. Resultados em: $OUTPUT_FILE\033[0m"
else
    echo -e "\033[1;31m[!] GitDorker não executado.\033[0m"
    [ ! -f "$TOKENS_FILE" ] && echo " ✘ tokens.txt não encontrado em: $TOKENS_FILE"
    [ ! -f "$DORKS_FILE" ] && echo " ✘ Dorks file não encontrado em: $DORKS_FILE"
fi

# ─── 6. KATANA + COLETA DE JS E URLS ─────────────────────
echo -e "\n[5] Coletando JS e URLs via Katana..."
katana -list subuniq.txt -jc -silent | grep ".js$" | sort -u > js.txt
katana -u subdomainlive.txt -d 5 -ps waybackarchive,commoncrawl,alienvault -jc -fx -ef woff,css,png,svg,mp3,woff2,jpeg,gif,svg -silent -o allurls.txt

# ─── 7. FILTROS DE ARQUIVOS ──────────────────────────────
echo -e "\n[6] Filtrando arquivos sensíveis..."
grep -Ei "\.txt|\.log|\.cache|\.secret|\.db|\.backup|\.yml|\.json|\.gz|\.rar|\.zip|\.config" allurls.txt > arquivos_sensiveis.txt
grep -Ei "\.js$" allurls.txt >> js.txt

# ─── 8. SCAN NUCLEI EM JS ────────────────────────────────
echo -e "\n[7] Rodando nuclei em arquivos JS..."
nuclei -t ~/.local/nuclei-templates/ -severity 'critical,high,medium' -silent -l js.txt -o nuclei-js.txt

# ─── 9. FUZZING COM GF + NUCLEI ──────────────────────────
echo -e "\n[8] Buscando LFI com GF + Nuclei..."
gf lfi < allurls.txt | nuclei -tags lfi -silent -o lfi-results.txt

# ─── 10. WAYBACK + GF PARA XSS ───────────────────────────
echo -e "\n[9] Coletando com Wayback e buscando XSS com GF..."
waybackurls "$DOMINIO" > wayback.txt
gf xss < wayback.txt > xss-candidates.txt

# ─── 11. FUZZING COM FEROXBUSTER ─────────────────────────
echo -e "\n[10] Rodando Feroxbuster..."
while read -r url; do
    OUTFILE="feroxbuster-${url//[:\/]/_}.txt"
    feroxbuster -u "$url" -w "$FEROX_WORDLIST" -t 30 -n -q -d 2 -o "$OUTFILE"
done < subdomainlive.txt

# ─── 12. LIMPEZA OPCIONAL ────────────────────────────────
echo -e "\nDeseja remover arquivos temporários intermediários? (s/n)"
read -r CLEAN
if [[ "$CLEAN" =~ ^[sS]$ ]]; then
    rm -f subdomain1.txt subdomain2.txt subdomain3.txt subfinal.txt
    echo -e "\033[1;32m[✔] Arquivos temporários removidos.\033[0m"
fi

echo -e "\n\033[1;32m[✔] Recon finalizado! Resultados em: $(pwd)\033[0m\n"
