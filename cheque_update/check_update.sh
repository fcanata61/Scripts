#!/bin/bash
#
# Script genérico para verificar e baixar atualizações de pacotes no LFS
# Suporta grupos (BASE, X11, DESKTOP, EXTRAS...)
# Agora com filtro por grupo e opção --list
#

# Pasta base do repositório local
REPO="$HOME/lfs_repo"
PKG_FILE="packages.txt"

# Relatórios
REPORT="$REPO/update_report.txt"
HISTORY="$REPO/history.log"

# Extensões comuns de pacotes-fonte
EXTENSIONS="tar.gz tar.xz tar.bz2 zip tgz txz tbz2"

# 🎨 Cores
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m'

# ⏳ Função de spinner
spinner() {
    local pid=$!
    local delay=0.15
    local spin='|/-\'
    while kill -0 $pid 2>/dev/null; do
        for i in $(seq 0 3); do
            printf "\r${YELLOW}... %s${NC}" "${spin:$i:1}"
            sleep $delay
        done
    done
    printf "\r"
}

# Função para extrair versão
extract_version() {
    local pkg="$1"
    local file="$2"
    echo "$file" | sed -E "s/^${pkg}-([0-9][0-9\.]*)\..*/\1/"
}

# =======================
# Opção --list
# =======================
if [[ "$1" == "--list" ]]; then
    echo -e "${BLUE}=== Grupos disponíveis em $PKG_FILE ===${NC}"
    cut -d' ' -f1 "$PKG_FILE" | grep -v '^#' | sort -u
    exit 0
fi

# Argumento opcional: grupo a filtrar
FILTER_GROUP="$1"

if [[ -n "$FILTER_GROUP" ]]; then
    echo -e "${BLUE}=== Verificando apenas o grupo: $FILTER_GROUP ===${NC}"
else
    echo -e "${BLUE}=== Verificação de atualizações para todos os grupos ===${NC}"
fi

echo "=== Relatório de Atualizações ($(date)) ===" > "$REPORT"
tmpfile=$(mktemp)

while read -r group pkg installed url; do
    [[ -z "$pkg" || "$pkg" =~ ^# ]] && echo "$group $pkg $installed $url" >> "$tmpfile" && continue

    # aplica filtro por grupo se informado
    if [[ -n "$FILTER_GROUP" && "$group" != "$FILTER_GROUP" ]]; then
        echo "$group $pkg $installed $url" >> "$tmpfile"
        continue
    fi

    echo
    echo -e "🔎 Grupo: ${BLUE}$group${NC} | Pacote: ${YELLOW}$pkg${NC}"

    # Pasta de updates específica para o grupo
    UPDATE_DIR="$REPO/updates/$group"
    mkdir -p "$UPDATE_DIR"

    # baixa a página com spinner
    (curl -s "$url" > /tmp/page.$$) & spinner
    page=$(cat /tmp/page.$$)
    rm -f /tmp/page.$$

    versions=()
    files=()
    for ext in $EXTENSIONS; do
        matches=$(echo "$page" | grep -oP "${pkg}-[0-9][0-9\.]*\.${ext}" | sort -u)
        for m in $matches; do
            ver=$(extract_version "$pkg" "$m")
            versions+=("$ver")
            files+=("$m")
        done
    done

    if [[ ${#versions[@]} -eq 0 ]]; then
        echo -e " ${RED}⚠ Nenhuma versão encontrada!${NC}"
        echo "$group $pkg - ERRO: Nenhuma versão encontrada!" >> "$REPORT"
        echo "$group $pkg $installed $url" >> "$tmpfile"
        continue
    fi

    latest=$(printf "%s\n" "${versions[@]}" | sort -V | tail -1)

    echo -e " -> Versão instalada: ${YELLOW}$installed${NC}"
    echo -e " -> Última versão:    ${GREEN}$latest${NC}"

    if [[ "$installed" != "$latest" ]]; then
        echo -e " ${GREEN}✅ ATUALIZAÇÃO DISPONÍVEL para $pkg!${NC}"
        echo "$group $pkg - Atualizado de $installed para $latest" >> "$REPORT"
        echo "$(date) - [$group] $pkg atualizado de $installed para $latest" >> "$HISTORY"

        # Descobre o arquivo correspondente à versão mais nova
        new_file=""
        for f in "${files[@]}"; do
            ver=$(extract_version "$pkg" "$f")
            if [[ "$ver" == "$latest" ]]; then
                new_file="$f"
                break
            fi
        done

        if [[ -n "$new_file" ]]; then
            echo -e " ⬇ Baixando ${BLUE}$new_file${NC} ..."
            (wget -q -c "$url/$new_file" -P "$UPDATE_DIR") & spinner
            echo -e " ${GREEN}✔ Download concluído em $UPDATE_DIR${NC}"
        fi

        # Atualiza o packages.txt
        echo "$group $pkg $latest $url" >> "$tmpfile"
    else
        echo -e " ${GREEN}✔ Já está atualizado.${NC}"
        echo "$group $pkg - Já está atualizado ($installed)" >> "$REPORT"
        echo "$group $pkg $installed $url" >> "$tmpfile"
    fi
done < "$PKG_FILE"

# Substitui o arquivo original pelo atualizado
mv "$tmpfile" "$PKG_FILE"

echo
echo -e "${BLUE}=== Relatório salvo em $REPORT ===${NC}"
echo -e "${BLUE}=== Histórico acumulado em $HISTORY ===${NC}"
echo -e "${BLUE}=== packages.txt atualizado com as novas versões ===${NC}"
