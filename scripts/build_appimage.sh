#!/bin/bash
set -e

# DaPlayer AppImage Build Script
# Compila o projeto Flutter para Linux e gera um pacote standalone .AppImage

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build/linux/x64/release/bundle"
APPDIR="$PROJECT_DIR/build/AppDir"
OUTPUT_DIR="$PROJECT_DIR/dist"
APPIMAGETOOL="$PROJECT_DIR/build/appimagetool"

echo "=========================================="
echo "       Iniciando Build do DaPlayer       "
echo "=========================================="

# 1. Configura Flutter SDK
if ! command -v flutter &> /dev/null; then
    if [ -f "$HOME/flutter/bin/flutter" ]; then
        export PATH="$HOME/flutter/bin:$PATH"
    else
        echo "Erro: Flutter SDK não encontrado no PATH nem em $HOME/flutter/bin"
        exit 1
    fi
fi

# Verifica ferramentas de compilação C++/GTK e bibliotecas do Linux
MISSING_PKGS=""
for tool in cmake clang ninja pkg-config; do
    if ! command -v "$tool" &> /dev/null; then
        MISSING_PKGS="$MISSING_PKGS $tool"
    fi
done

if ! pkg-config --exists ayatana-appindicator3-0.1 2>/dev/null && ! pkg-config --exists appindicator3-0.1 2>/dev/null; then
    MISSING_PKGS="$MISSING_PKGS libayatana-appindicator3-dev"
fi

if [ -n "$MISSING_PKGS" ]; then
    echo "=========================================================="
    echo " Faltando dependências para a Bandeja do Sistema (Tray):"
    echo " $MISSING_PKGS"
    echo ""
    echo " Execute este comando no terminal para instalar:"
    echo " sudo apt install -y libayatana-appindicator3-dev"
    echo "=========================================================="
    exit 1
fi

echo ">> Flutter detectado: $(flutter --version | head -n 1)"

# 2. Obter dependências do Flutter
echo ">> Baixando dependências pubspec.yaml..."
cd "$PROJECT_DIR"
flutter pub get

# 3. Compilar versão release para Linux (se não tiver flag --no-build)
if [ "$1" != "--no-build" ]; then
    echo ">> Compilando DaPlayer para Linux (Release)..."
    flutter build linux --release
fi

if [ ! -d "$BUILD_DIR" ]; then
    echo "Erro: Falha na compilação do bundle Linux em $BUILD_DIR"
    exit 1
fi

# 4. Estruturar o AppDir
echo ">> Estruturando AppDir..."
rm -rf "$APPDIR"
mkdir -p "$APPDIR"
mkdir -p "$OUTPUT_DIR"

# Copia todo o bundle do Flutter (executável + data + lib) para a raiz do AppDir
cp -r "$BUILD_DIR"/* "$APPDIR/"

# Garante a biblioteca sqlite3 embutida no pacote AppImage
mkdir -p "$APPDIR/lib"
for sqlite_candidate in \
    "/usr/lib/x86_64-linux-gnu/libsqlite3.so.0" \
    "/usr/lib/aarch64-linux-gnu/libsqlite3.so.0" \
    "/usr/lib/libsqlite3.so.0" \
    "/usr/lib64/libsqlite3.so.0" \
    "$HOME/.local/lib/libsqlite3.so"; do
    if [ -f "$sqlite_candidate" ]; then
        cp -L "$sqlite_candidate" "$APPDIR/lib/libsqlite3.so" 2>/dev/null || true
        cp -L "$sqlite_candidate" "$APPDIR/lib/libsqlite3.so.0" 2>/dev/null || true
        break
    fi
done

# Copia ícones
if [ -f "$PROJECT_DIR/assets/icon.png" ]; then
    cp "$PROJECT_DIR/assets/icon.png" "$APPDIR/daplayer.png"
    cp "$PROJECT_DIR/assets/icon.png" "$APPDIR/.DirIcon"
fi

# Gera arquivo Desktop
cat << 'EOF' > "$APPDIR/daplayer.desktop"
[Desktop Entry]
Name=DaPlayer
GenericName=Music Player
Comment=Player de Coletâneas e Músicas do YouTube
Exec=daplayer %U
Icon=daplayer
Terminal=false
Type=Application
Categories=AudioVideo;Audio;Player;Music;
StartupWMClass=daplayer
Keywords=Music;Player;Audio;YouTube;
EOF

# Gera script AppRun
cat << 'EOF' > "$APPDIR/AppRun"
#!/bin/bash
HERE="$(dirname "$(readlink -f "${0}")")"
export PATH="${HERE}:${PATH}"
export LD_LIBRARY_PATH="${HERE}/lib:${LD_LIBRARY_PATH}"
cd "${HERE}"
exec "${HERE}/daplayer" "$@"
EOF
chmod +x "$APPDIR/AppRun"

# 5. Baixar appimagetool se não estiver presente
mkdir -p "$PROJECT_DIR/build"
if [ ! -f "$APPIMAGETOOL" ]; then
    echo ">> Baixando appimagetool..."
    curl -L -o "$APPIMAGETOOL" "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage"
    chmod +x "$APPIMAGETOOL"
fi

# 6. Empacotar o AppImage
echo ">> Gerando DaPlayer-x86_64.AppImage..."
export ARCH=x86_64
rm -f "$OUTPUT_DIR/DaPlayer-x86_64.AppImage"
"$APPIMAGETOOL" --appimage-extract-and-run "$APPDIR" "$OUTPUT_DIR/DaPlayer-x86_64.AppImage"

echo "=========================================="
echo " 🎉 Build concluído com sucesso!"
echo " 📦 Arquivo AppImage gerado em:"
echo "    $OUTPUT_DIR/DaPlayer-x86_64.AppImage"
echo "=========================================="
