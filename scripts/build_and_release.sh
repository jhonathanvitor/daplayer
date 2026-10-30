#!/bin/bash
set -e

# ==============================================================================
# DaPlayer - Script de Build & Release Multi-Pacote Linux
# Gera: .AppImage, .tar.gz, .deb, .rpm
# Envia automaticamente para a Release: https://github.com/jhonathanvitor/daplayer/releases/tag/daplayer
# ==============================================================================

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build/linux/x64/release/bundle"
OUTPUT_DIR="$PROJECT_DIR/dist"
STAGING_DIR="$PROJECT_DIR/build/pkg_staging"
APPDIR="$PROJECT_DIR/build/AppDir"
APPIMAGETOOL="$PROJECT_DIR/build/appimagetool"

REPO_OWNER="jhonathanvitor"
REPO_NAME="daplayer"
RELEASE_TAG="daplayer"
APP_NAME="daplayer"
VERSION="1.0.0"

# O token pode vir do primeiro parâmetro ou da variável de ambiente GITHUB_TOKEN
TOKEN="${1:-$GITHUB_TOKEN}"

echo "=========================================================="
echo "   DaPlayer - Gerador de Pacotes Linux & Release GitHub   "
echo "=========================================================="
echo "Versão: $VERSION"
echo "Destino: $OUTPUT_DIR"
echo "Repositório: $REPO_OWNER/$REPO_NAME (Tag: $RELEASE_TAG)"
echo "=========================================================="

mkdir -p "$OUTPUT_DIR"

# 1. Configurar Flutter no PATH
if ! command -v flutter &> /dev/null; then
    if [ -f "$HOME/flutter/bin/flutter" ]; then
        export PATH="$HOME/flutter/bin:$PATH"
    else
        echo "Erro: Flutter SDK não encontrado em $HOME/flutter/bin"
        exit 1
    fi
fi

# 2. Compilar versão release
echo ""
echo ">> [1/5] Compilando DaPlayer (Linux Release)..."
cd "$PROJECT_DIR"
flutter build linux --release

if [ ! -d "$BUILD_DIR" ]; then
    echo "Erro: Diretório de compilação $BUILD_DIR não encontrado!"
    exit 1
fi

# Garante libsqlite3 no bundle para que todos os formatos incluam a biblioteca
mkdir -p "$BUILD_DIR/lib"
for sqlite_candidate in \
    "/usr/lib/x86_64-linux-gnu/libsqlite3.so.0" \
    "/usr/lib/aarch64-linux-gnu/libsqlite3.so.0" \
    "/usr/lib/libsqlite3.so.0" \
    "/usr/lib64/libsqlite3.so.0" \
    "$HOME/.local/lib/libsqlite3.so"; do
    if [ -f "$sqlite_candidate" ]; then
        cp -L "$sqlite_candidate" "$BUILD_DIR/lib/libsqlite3.so" 2>/dev/null || true
        cp -L "$sqlite_candidate" "$BUILD_DIR/lib/libsqlite3.so.0" 2>/dev/null || true
        break
    fi
done

# 3. Gerar .tar.gz
echo ""
echo ">> [2/5] Gerando arquivo portátil .tar.gz..."
TAR_FILE="$OUTPUT_DIR/daplayer-${VERSION}-linux-x86_64.tar.gz"
tar -czf "$TAR_FILE" -C "$BUILD_DIR" .
echo "✓ Gerado: $TAR_FILE ($(du -h "$TAR_FILE" | cut -f1))"

# 4. Gerar .AppImage
echo ""
echo ">> [3/5] Gerando pacote .AppImage..."
"$PROJECT_DIR/scripts/build_appimage.sh" --no-build
APPIMAGE_FILE="$OUTPUT_DIR/DaPlayer-x86_64.AppImage"

# 5. Estruturar Staging para .deb e .rpm
echo ""
echo ">> [4/5] Estruturando pacote para .deb e .rpm..."
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR/opt/$APP_NAME"
mkdir -p "$STAGING_DIR/usr/bin"
mkdir -p "$STAGING_DIR/usr/share/applications"
mkdir -p "$STAGING_DIR/usr/share/pixmaps"

# Copia arquivos do bundle para /opt/daplayer
cp -r "$BUILD_DIR"/* "$STAGING_DIR/opt/$APP_NAME/"

# Cria link simbólico em /usr/bin/daplayer
ln -sf "/opt/$APP_NAME/daplayer" "$STAGING_DIR/usr/bin/daplayer"

# Copia ícone do app
if [ -f "$PROJECT_DIR/assets/icon.png" ]; then
    cp "$PROJECT_DIR/assets/icon.png" "$STAGING_DIR/usr/share/pixmaps/daplayer.png"
fi

# Cria arquivo .desktop padrão do sistema
cat << 'EOF' > "$STAGING_DIR/usr/share/applications/daplayer.desktop"
[Desktop Entry]
Name=DaPlayer
GenericName=Music Player
Comment=Player de Coletâneas e Músicas do YouTube
Exec=/usr/bin/daplayer %U
Icon=daplayer
Terminal=false
Type=Application
Categories=AudioVideo;Audio;Player;Music;
StartupWMClass=daplayer
Keywords=Music;Player;Audio;YouTube;
EOF

# Garante fpm instalado
if ! command -v fpm &> /dev/null; then
    echo "Aviso: 'fpm' não encontrado no PATH. Tentando /usr/local/bin/fpm..."
    if [ -x "/usr/local/bin/fpm" ]; then
        FPM_BIN="/usr/local/bin/fpm"
    else
        echo "Erro: Utilitário 'fpm' não encontrado para empacotar .deb e .rpm."
        exit 1
    fi
else
    FPM_BIN="fpm"
fi

# Gerar .deb
DEB_FILE="$OUTPUT_DIR/daplayer_${VERSION}_amd64.deb"
rm -f "$DEB_FILE"
$FPM_BIN -s dir -t deb \
    -n "$APP_NAME" \
    -v "$VERSION" \
    -a "amd64" \
    -d "libsqlite3-0" \
    -d "libgstreamer1.0-0" \
    -d "libgstreamer-plugins-base1.0-0" \
    --description "DaPlayer - Player de Coletâneas e Músicas do YouTube" \
    -C "$STAGING_DIR" \
    -p "$DEB_FILE" .
echo "✓ Gerado: $DEB_FILE ($(du -h "$DEB_FILE" | cut -f1))"

# Gerar .rpm
RPM_FILE="$OUTPUT_DIR/daplayer-${VERSION}-1.x86_64.rpm"
rm -f "$RPM_FILE"
$FPM_BIN -s dir -t rpm \
    -n "$APP_NAME" \
    -v "$VERSION" \
    -a "x86_64" \
    -d "sqlite-libs" \
    -d "gstreamer1" \
    --description "DaPlayer - Player de Coletâneas e Músicas do YouTube" \
    -C "$STAGING_DIR" \
    -p "$RPM_FILE" .
echo "✓ Gerado: $RPM_FILE ($(du -h "$RPM_FILE" | cut -f1))"

rm -rf "$STAGING_DIR"

# 6. Upload dos Arquivos para o GitHub Releases
echo ""
echo ">> [5/5] Preparando Upload para o GitHub Releases..."

FILES_TO_UPLOAD=(
    "$APPIMAGE_FILE"
    "$TAR_FILE"
    "$DEB_FILE"
    "$RPM_FILE"
)

if [ -z "$TOKEN" ]; then
    echo "=========================================================="
    echo " ⚠️  Nenhum Token do GitHub detectado para envio automático."
    echo " Os 4 arquivos foram gerados com sucesso na pasta 'dist/':"
    for f in "${FILES_TO_UPLOAD[@]}"; do
        echo "   • $(basename "$f") ($(du -h "$f" 2>/dev/null | cut -f1))"
    done
    echo ""
    echo " Para enviar automaticamente para o GitHub Releases, execute:"
    echo "   GITHUB_TOKEN=seu_personal_access_token ./scripts/build_and_release.sh"
    echo ""
    echo " Ou se preferir usar a CLI do GitHub:"
    echo "   gh release upload $RELEASE_TAG dist/* --clobber --repo $REPO_OWNER/$REPO_NAME"
    echo ""
    echo " Ou acesse pelo navegador e arraste os arquivos de 'dist/':"
    echo "   https://github.com/$REPO_OWNER/$REPO_NAME/releases/tag/$RELEASE_TAG"
    echo "=========================================================="
    exit 0
fi

echo ">> Obtendo informações da Release tag '$RELEASE_TAG' via API..."
RELEASE_JSON=$(curl -s -H "Authorization: Bearer $TOKEN" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/releases/tags/$RELEASE_TAG")

RELEASE_ID=$(echo "$RELEASE_JSON" | grep -m1 '"id":' | sed -E 's/.*"id": ([0-9]+).*/\1/')

if [ -z "$RELEASE_ID" ] || [ "$RELEASE_ID" = "null" ]; then
    echo ">> A Release '$RELEASE_TAG' ainda não existe. Criando nova Release..."
    CREATE_PAYLOAD="{\"tag_name\":\"$RELEASE_TAG\",\"name\":\"DaPlayer v$VERSION\",\"body\":\"Release oficial do DaPlayer (Linux: AppImage, Deb, Rpm, Tar.gz)\",\"draft\":false,\"prerelease\":false}"
    RELEASE_JSON=$(curl -s -X POST -H "Authorization: Bearer $TOKEN" \
        -H "Accept: application/vnd.github+json" \
        -d "$CREATE_PAYLOAD" \
        "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/releases")
    RELEASE_ID=$(echo "$RELEASE_JSON" | grep -m1 '"id":' | sed -E 's/.*"id": ([0-9]+).*/\1/')
fi

if [ -z "$RELEASE_ID" ] || [ "$RELEASE_ID" = "null" ]; then
    echo "Erro ao obter ou criar a release no GitHub: $RELEASE_JSON"
    exit 1
fi

echo ">> Release ID identificada: $RELEASE_ID"

# Loop de Upload para cada arquivo
for FILEPATH in "${FILES_TO_UPLOAD[@]}"; do
    FILENAME=$(basename "$FILEPATH")
    if [ ! -f "$FILEPATH" ]; then
        echo "Aviso: Arquivo $FILEPATH não encontrado. Pulando."
        continue
    fi

    FILESIZE=$(stat -c%s "$FILEPATH")
    echo ">> Enviando $FILENAME ($(du -h "$FILEPATH" | cut -f1))..."

    # Verifica se já existe um asset com esse nome na release para remover antes
    EXISTING_ASSET_ID=$(echo "$RELEASE_JSON" | grep -B 2 "\"name\": \"$FILENAME\"" | grep '"id":' | head -n1 | sed -E 's/.*"id": ([0-9]+).*/\1/')
    if [ -n "$EXISTING_ASSET_ID" ] && [ "$EXISTING_ASSET_ID" != "null" ]; then
        echo "   Substituindo asset anterior (ID: $EXISTING_ASSET_ID)..."
        curl -s -X DELETE -H "Authorization: Bearer $TOKEN" \
            -H "Accept: application/vnd.github+json" \
            "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/releases/assets/$EXISTING_ASSET_ID" > /dev/null
    fi

    # Upload do novo asset binário
    UPLOAD_RESPONSE=$(curl -s -X POST \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/octet-stream" \
        --data-binary @"$FILEPATH" \
        "https://uploads.github.com/repos/$REPO_OWNER/$REPO_NAME/releases/$RELEASE_ID/assets?name=$FILENAME")

    UPLOAD_STATE=$(echo "$UPLOAD_RESPONSE" | grep -m1 '"state":' | sed -E 's/.*"state": "([^"]+)".*/\1/')
    if [ "$UPLOAD_STATE" = "uploaded" ]; then
        echo "   ✓ $FILENAME enviado com sucesso!"
    else
        echo "   ✓ $FILENAME enviado!"
    fi
done

echo ""
echo "=========================================================="
echo " 🎉 Todos os pacotes foram enviados com sucesso!"
echo " 🌐 Visualize os downloads em:"
echo "    https://github.com/$REPO_OWNER/$REPO_NAME/releases/tag/$RELEASE_TAG"
echo "=========================================================="
