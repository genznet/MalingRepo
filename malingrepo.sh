#!/usr/bin/env bash

set -e

echo "=== Skrip Auto Jadikan Repo Milik Kamu (v4: auto-fix folder, auto-push, .gitignore, auto-clean secrets) ==="

# --- Cek dependency ---
if ! command -v git >/dev/null 2>&1; then
  echo "Error: git belum terinstall. Tolong install git dulu."
  exit 1
fi

echo

# ==== FUNGSI: auto bersihkan secret di .env, .json, .yaml ====
clean_env_json_yaml() {
  echo
  echo "=== Scan & bersihkan secret di .env / .json / .yaml ==="

  # cari file target
  mapfile -t FILES < <(find . -type f \( -name ".env" -o -name ".env.*" -o -name "*.json" -o -name "*.yaml" -o -name "*.yml" \))

  if [ "${#FILES[@]}" -eq 0 ]; then
    echo "→ Tidak ada file .env / .json / .yaml yang ditemukan. Lewati."
    return
  fi

  for f in "${FILES[@]}"; do
    echo "→ Membersihkan: $f"

    case "$f" in
      *.env* )
        # contoh: API_KEY=xxx / PASSWORD=yyy / JWT_SECRET = zzz
        sed -i -E 's/^([[:space:]]*[A-Za-z0-9_]*(SECRET|TOKEN|PASS(WORD)?|KEY)[A-Za-z0-9_]*[[:space:]]*=[[:space:]]*).*/\1REDACTED_ENV_VALUE/' "$f" 2>/dev/null || true
        ;;
      *.json )
        # contoh: "apiKey": "xxx"
        sed -i -E 's/(".*(secret|token|pass(word)?|key).*"[[:space:]]*:[[:space:]]*").*"/\1"REDACTED_JSON_VALUE"/I' "$f" 2>/dev/null || true
        ;;
      *.yml|*.yaml )
        # contoh: api_secret: xxxx
        sed -i -E 's/^([[:space:]]*.*(secret|token|pass(word)?|key).*:[[:space:]]*).*/\1REDACTED_YAML_VALUE/I' "$f" 2>/dev/null || true
        ;;
    esac
  done
}

# --- Input sumber repo ---
read -rp "Masukkan URL repo sumber (contoh: https://github.com/hokagelegend9999/alpha.v2): " SRC_URL
if [ -z "$SRC_URL" ]; then
  echo "Error: URL sumber tidak boleh kosong."
  exit 1
fi

REPO_NAME_FROM_URL=$(basename -s .git "$(echo "$SRC_URL" | sed 's#/$##')")
DEFAULT_LOCAL_DIR="$REPO_NAME_FROM_URL"

read -rp "Nama folder lokal untuk clone? (default: $DEFAULT_LOCAL_DIR): " LOCAL_DIR
LOCAL_DIR=${LOCAL_DIR:-$DEFAULT_LOCAL_DIR}

USE_EXISTING_DIR=0

# --- Auto-fix folder bentrok ---
while true; do
  if [ -d "$LOCAL_DIR" ]; then
    if [ -z "$(ls -A "$LOCAL_DIR")" ]; then
      break
    else
      echo
      echo "!!! Folder '$LOCAL_DIR' sudah ada dan TIDAK kosong."
      echo "Pilih aksi:"
      echo "  1) Pakai folder itu saja (skip clone, pakai repo yang sudah ada)"
      echo "  2) Hapus folder lalu clone ulang"
      read -rp "Pilih [1/2] (default: 1): " FOLDER_OPTION
      FOLDER_OPTION=${FOLDER_OPTION:-1}

      case "$FOLDER_OPTION" in
        1)
          if [ ! -d "$LOCAL_DIR/.git" ]; then
            echo "Folder '$LOCAL_DIR' bukan repo git (tidak ada .git). Pilih opsi 2."
            continue
          fi
          USE_EXISTING_DIR=1
          break
          ;;
        2)
          echo "Menghapus folder '$LOCAL_DIR'..."
          rm -rf "$LOCAL_DIR"
          break
          ;;
        *)
          echo "Pilihan tidak dikenal, coba lagi."
          ;;
      esac
    fi
  else
    break
  fi
done

echo
echo "→ Clone dari: $SRC_URL"
echo "→ Ke folder: $LOCAL_DIR"
echo

if [ "$USE_EXISTING_DIR" -eq 1 ]; then
  echo "Folder sudah ada, SKIP clone. Memakai repo yang ada di '$LOCAL_DIR'."
else
  git clone "$SRC_URL" "$LOCAL_DIR"
fi

cd "$LOCAL_DIR"

echo
echo "=== Menghapus remote origin lama (kalau ada) ==="
git remote remove origin 2>/dev/null || true

# --- Deteksi branch utama ---
echo
echo "=== Mendeteksi branch utama ==="
if git show-ref -q refs/heads/main; then
  DEFAULT_BRANCH="main"
elif git show-ref -q refs/heads/master; then
  DEFAULT_BRANCH="master"
else
  if git show-ref -q refs/remotes/origin/HEAD; then
    DEFAULT_BRANCH=$(git symbolic-ref --short refs/remotes/origin/HEAD | cut -d'/' -f2)
  else
    DEFAULT_BRANCH=$(git branch --format='%(refname:short)' | head -n 1)
  fi
fi
echo "Branch utama terdeteksi: $DEFAULT_BRANCH"

# --- Input info GitHub ---
echo
read -rp "Masukkan username GitHub kamu (contoh: genznet): " GH_USER
if [ -z "$GH_USER" ]; then
  echo "Error: username GitHub tidak boleh kosong."
  exit 1
fi

read -rp "Nama repo baru di akun kamu? (default: $REPO_NAME_FROM_URL): " NEW_REPO_NAME
NEW_REPO_NAME=${NEW_REPO_NAME:-$REPO_NAME_FROM_URL}

NEW_REPO_URL="https://$GH_USER@github.com/$GH_USER/$NEW_REPO_NAME.git"

echo
echo "=== Menambahkan / mengupdate remote origin ==="
echo "Origin baru: $NEW_REPO_URL"
git remote add origin "$NEW_REPO_URL" 2>/dev/null || git remote set-url origin "$NEW_REPO_URL"

# --- Opsional: bersihkan secret khusus rclone.conf ---
echo
read -rp "Bersihkan secret di config/rclone.conf juga? [y/N]: " CLEAN_RCLONE
if [[ "$CLEAN_RCLONE" =~ ^[Yy]$ ]]; then
  echo
  echo "=== Membersihkan secret di config/rclone.conf ==="
  if [ -f "config/rclone.conf" ]; then
    echo "→ Membersihkan config/rclone.conf ..."
    sed -i 's/\(token *= *\).*/\1YOUR_TOKEN_HERE/' config/rclone.conf 2>/dev/null || true
    sed -i 's/\(refresh_token *= *\).*/\1YOUR_REFRESH_TOKEN_HERE/' config/rclone.conf 2>/dev/null || true
    sed -i 's/\(client_id *= *\).*/\1YOUR_CLIENT_ID_HERE/' config/rclone.conf 2>/dev/null || true
    sed -i 's/\(client_secret *= *\).*/\1YOUR_CLIENT_SECRET_HERE/' config/rclone.conf 2>/dev/null || true
  else
    echo "→ Tidak ada file config/rclone.conf, lewati."
  fi
fi

# --- Auto clean .env / .json / .yaml ---
echo
read -rp "Scan & bersihkan secret di .env / .json / .yaml? [y/N]: " CLEAN_ENVJSON
if [[ "$CLEAN_ENVJSON" =~ ^[Yy]$ ]]; then
  clean_env_json_yaml
fi

# --- .gitignore generator ---
echo
read -rp "Generate .gitignore standar? [y/N]: " GI_ANS
if [[ "$GI_ANS" =~ ^[Yy]$ ]]; then
  echo "=== Membuat / mengupdate .gitignore ==="
  if [ -f ".gitignore" ]; then
    echo "→ .gitignore sudah ada, menambahkan blok standar."
  else
    echo "→ .gitignore belum ada, membuat baru."
  fi

  cat >> .gitignore <<'EOF'

# ==== Generated by malingrepo.sh ====
# Logs & temp
*.log
*.tmp
*.temp
*.bak
*.old
*.swp
*.swo

# OS & editor
.DS_Store
Thumbs.db
.idea/
.vscode/

# Python
__pycache__/
*.py[cod]
*.pyo
*.pyd

# Node / JS
node_modules/
dist/
build/

# Env / credentials
.env
.env.*
*.sqlite3

# Archives
*.tar
*.tar.gz
*.zip
*.7z
EOF

  git add .gitignore
fi

# --- Commit perubahan pembersihan & .gitignore ---
echo
echo "=== Commit perubahan lokal (jika ada) sebelum reset history ==="
git add . || true
git commit -m "apply secret cleanup & gitignore" 2>/dev/null || echo "Tidak ada perubahan baru untuk di-commit."

# --- Orphan branch (reset history) ---
echo
read -rp "Reset history jadi 1 commit bersih (orphan branch)? [y/N]: " ORPHAN_ANS
if [[ "$ORPHAN_ANS" =~ ^[Yy]$ ]]; then
  echo "=== Membuat history baru bersih (orphan branch) ==="
  git checkout --orphan "clean-$DEFAULT_BRANCH"
  git add .
  git commit -m "initial clean commit without secrets"
  git branch -M "$DEFAULT_BRANCH"
fi

echo
echo "=== Push ke repo baru ==="
if [ -n "$GH_TOKEN" ]; then
  echo "GH_TOKEN terdeteksi → push otomatis tanpa prompt password."
  export GH_TOKEN
  ASKPASS_SCRIPT="$(mktemp)"
  cat > "$ASKPASS_SCRIPT" <<'EOF'
#!/usr/bin/env sh
printf '%s\n' "$GH_TOKEN"
EOF
  chmod +x "$ASKPASS_SCRIPT"
  GIT_ASKPASS="$ASKPASS_SCRIPT" git push -u origin "$DEFAULT_BRANCH"
  rm -f "$ASKPASS_SCRIPT"
else
  echo "GH_TOKEN tidak ada."
  echo "Saat diminta password, MASUKKAN TOKEN GitHub (bukan password akun)."
  git push -u origin "$DEFAULT_BRANCH"
fi

echo
echo "=== Selesai! ==="
echo "Repo sekarang ada di akun kamu:"
echo "  → https://github.com/$GH_USER/$NEW_REPO_NAME"
echo
echo "Folder lokal: $(pwd)"
