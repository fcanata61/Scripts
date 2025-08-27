#!/bin/sh
# POSIX shell - Infra do Linux From Scratch (sem compilação)
# Cria estrutura, arquivos essenciais, mounts e chroot.
# Uso:
#   LFS=/mnt/lfs sh lfs-setup.sh <comando>
# Comandos:
#   check            - valida pré-requisitos (root, $LFS, montagem)
#   mkfs             - cria árvore de diretórios e permissões
#   etc              - cria /etc básico (passwd, group, hosts, mtab, logs)
#   own              - ajusta ownership padrão (root:root)
#   mounts           - monta dev, devpts, proc, sysfs, run no $LFS
#   umounts          - desmonta na ordem segura
#   chroot           - entra no chroot pronto p/ construir o sistema
#   all              - roda: check mkfs etc own mounts
#   clean-etc        - remove arquivos /etc criados por este script
#   help             - mostra ajuda

set -eu

# ---------- Config ----------
: "${LFS:?Defina LFS=/caminho/para/lfs (ex: /mnt/lfs)}"

# Ajustes finos
ROOT_PERM=0750        # /root
TMP_PERM=1777         # /tmp e /var/tmp
RUN_PERM=0755

# ---------- Helpers ----------
err() { printf "ERRO: %s\n" "$*" >&2; exit 1; }
msg() { printf "==> %s\n" "$*"; }
as_root() { [ "$(id -u)" -eq 0 ] || err "Execute como root."; }
need_dir() { [ -d "$1" ] || err "Diretório não existe: $1"; }

# Pode ajudar quem quiser montar a partição neste script:
mount_lfs_device() {
  # Ex.: mount_lfs_device /dev/sdXN
  dev="${1:-}"
  [ -n "$dev" ] || err "Informe o device. Ex.: mount_lfs_device /dev/sdXN"
  mkdir -p "$LFS"
  mountpoint -q "$LFS" || mount -v "$dev" "$LFS"
}

check() {
  as_root
  [ -n "$LFS" ] || err "Variável LFS não definida."
  mkdir -p "$LFS"
  [ -w "$LFS" ] || err "Sem escrita em $LFS."
  # Não obriga a partição já montada, mas recomenda:
  if ! mountpoint -q "$LFS"; then
    msg "Aviso: $LFS não é um ponto de montagem (continuando mesmo assim)."
  fi
  msg "OK: pré-requisitos básicos atendidos."
}

mkfs_dirs() {
  as_root
  need_dir "$LFS"
  msg "Criando árvore de diretórios no $LFS (FHS / LFS 12.3)..."

  # Raiz e essenciais
  mkdir -pv "$LFS"/{bin,boot,dev,etc,home,lib,media,mnt,opt,proc,root,run,sbin,srv,sys,tmp,usr,var}

  # Evitar /usr/lib64 (conforme LFS). Criar lib64 apenas na raiz se x86_64 (capítulo inicial do LFS).
  case "$(uname -m)" in
    x86_64) mkdir -pv "$LFS/lib64" ;;
  esac

  # Subárvores
  mkdir -pv "$LFS/etc"/{opt,sysconfig}
  mkdir -pv "$LFS/lib/firmware"
  mkdir -pv "$LFS/media"/{floppy,cdrom}
  mkdir -pv "$LFS/usr"/{bin,lib,sbin}
  mkdir -pv "$LFS/usr"/{include,src}
  mkdir -pv "$LFS/usr/lib/locale"
  mkdir -pv "$LFS/usr/local"/{bin,lib,sbin}
  mkdir -pv "$LFS/usr"/share/{color,dict,doc,info,locale,man,misc,terminfo,zoneinfo}
  mkdir -pv "$LFS/usr/local"/share/{color,dict,doc,info,locale,man,misc,terminfo,zoneinfo}
  mkdir -pv "$LFS/usr/share/man/man"{1,2,3,4,5,6,7,8}
  mkdir -pv "$LFS/usr/local/share/man/man"{1,2,3,4,5,6,7,8}
  mkdir -pv "$LFS/var"/{cache,local,log,mail,opt,spool}
  mkdir -pv "$LFS/var/lib"/{color,misc,locate}

  # Links FHS históricos (var->run, lock->run/lock)
  ln -snf /run "$LFS/var/run"
  ln -snf /run/lock "$LFS/var/lock"

  # Permissões especiais
  install -dv -m "$ROOT_PERM" "$LFS/root"
  install -dv -m "$TMP_PERM" "$LFS/tmp" "$LFS/var/tmp"

  # Ajustes básicos em /run
  chmod "$RUN_PERM" "$LFS/run" 2>/dev/null || true

  msg "Diretórios criados."
}

mk_essential_etc() {
  as_root
  need_dir "$LFS"
  mkdir -p "$LFS/etc" "$LFS/var/log"

  msg "Criando /etc/mtab como link para /proc/self/mounts..."
  ln -snf /proc/self/mounts "$LFS/etc/mtab"

  msg "Criando /etc/hosts básico..."
  hname="$(hostname 2>/dev/null || echo lfs)"
  cat > "$LFS/etc/hosts" <<EOF
127.0.0.1  localhost $hname
::1        localhost
EOF

  msg "Criando /etc/passwd mínimo (LFS 12.3)..."
  cat > "$LFS/etc/passwd" <<'EOF'
root:x:0:0:root:/root:/bin/bash
bin:x:1:1:bin:/dev/null:/usr/bin/false
daemon:x:6:6:Daemon User:/dev/null:/usr/bin/false
messagebus:x:18:18:D-Bus Message Daemon User:/run/dbus:/usr/bin/false
uuidd:x:80:80:UUID Generation Daemon User:/dev/null:/usr/bin/false
nobody:x:65534:65534:Unprivileged User:/dev/null:/usr/bin/false
EOF

  msg "Criando /etc/group mínimo (LFS 12.3)..."
  cat > "$LFS/etc/group" <<'EOF'
root:x:0:
bin:x:1:daemon
sys:x:2:
kmem:x:3:
tape:x:4:
tty:x:5:
daemon:x:6:
floppy:x:7:
disk:x:8:
lp:x:9:
dialout:x:10:
audio:x:11:
video:x:12:
utmp:x:13:
cdrom:x:15:
adm:x:16:
messagebus:x:18:
input:x:24:
mail:x:34:
kvm:x:61:
uuidd:x:80:
wheel:x:97:
users:x:999:
nogroup:x:65534:
EOF

  # Logs básicos (permissões conforme nota do LFS)
  msg "Inicializando logs em /var/log..."
  : > "$LFS/var/log/btmp"
  : > "$LFS/var/log/lastlog"
  : > "$LFS/var/log/faillog"
  : > "$LFS/var/log/wtmp"
  chgrp -v utmp "$LFS/var/log/lastlog" 2>/dev/null || true
  chmod -v 664 "$LFS/var/log/lastlog" 2>/dev/null || true
  chmod -v 600 "$LFS/var/log/btmp" 2>/dev/null || true

  msg "/etc básico criado."
}

own_rootroot() {
  as_root
  need_dir "$LFS"
  msg "Ajustando ownership para root:root nos diretórios principais..."
  chown -R root:root "$LFS"/{bin,boot,dev,etc,home,lib,lib64,media,mnt,opt,proc,root,run,sbin,srv,sys,tmp,usr,var} 2>/dev/null || true
  msg "Ownership ajustado."
}

mounts() {
  as_root
  need_dir "$LFS"
  msg "Montando filesystems virtuais no chroot de $LFS..."

  mkdir -pv "$LFS"/{dev,proc,sys,run}

  # /dev: bind
  if ! mountpoint -q "$LFS/dev"; then
    mount -v --bind /dev "$LFS/dev"
  fi

  # devpts (gid=5 grupo tty; mode=620)
  mkdir -pv "$LFS/dev/pts"
  if ! mountpoint -q "$LFS/dev/pts"; then
    mount -vt devpts devpts "$LFS/dev/pts" -o gid=5,mode=620
  fi

  # proc, sysfs, tmpfs(/run)
  if ! mountpoint -q "$LFS/proc"; then
    mount -vt proc proc "$LFS/proc"
  fi
  if ! mountpoint -q "$LFS/sys"; then
    mount -vt sysfs sysfs "$LFS/sys"
  fi
  if ! mountpoint -q "$LFS/run"; then
    mount -vt tmpfs tmpfs "$LFS/run"
  fi

  # /dev/shm pode ser link -> trate como diretório dentro do chroot
  if [ -h "$LFS/dev/shm" ]; then
    rm -f "$LFS/dev/shm"
    mkdir -pv "$LFS/dev/shm"
  fi

  msg "Mounts prontos."
}

umounts() {
  as_root
  need_dir "$LFS"
  msg "Desmontando filesystems virtuais do $LFS..."
  # ordem reversa
  mountpoint -q "$LFS/dev/shm" && umount -v "$LFS/dev/shm" || true
  mountpoint -q "$LFS/dev/pts" && umount -v "$LFS/dev/pts" || true
  mountpoint -q "$LFS/run"     && umount -v "$LFS/run"     || true
  mountpoint -q "$LFS/sys"     && umount -v "$LFS/sys"     || true
  mountpoint -q "$LFS/proc"    && umount -v "$LFS/proc"    || true
  mountpoint -q "$LFS/dev"     && umount -v "$LFS/dev"     || true
  msg "Desmontado."
}

enter_chroot() {
  as_root
  need_dir "$LFS"
  msg "Entrando no chroot do LFS..."
  # PATH mínimo dentro do chroot; ajuste conforme seu toolset
  CHROOT_PATH=/usr/bin:/bin:/usr/sbin:/sbin
  chroot "$LFS" /usr/bin/env -i \
    HOME=/root TERM="${TERM:-xterm-256color}" \
    PS1='(lfs chroot) \u:\w\$ ' \
    PATH="$CHROOT_PATH" \
    /bin/bash --login
}

clean_etc() {
  as_root
  for f in hosts mtab passwd group; do
    [ -e "$LFS/etc/$f" ] && rm -v "$LFS/etc/$f"
  done
  for f in btmp lastlog faillog wtmp; do
    [ -e "$LFS/var/log/$f" ] && rm -v "$LFS/var/log/$f"
  done
  msg "Arquivos de /etc e logs removidos (os criados aqui)."
}

help() {
  sed -n '1,120p' "$0" | sed -n '1,80p' | sed 's/^# \{0,1\}//' | awk 'NR<=40{print}'
  cat <<EOF

Comandos disponíveis:
  check | mkfs | etc | own | mounts | umounts | chroot | all | clean-etc | help

Fluxo típico:
  LFS=/mnt/lfs sh $0 all
  LFS=/mnt/lfs sh $0 chroot
EOF
}

# ---------- Dispatcher ----------
cmd="${1:-help}"
case "$cmd" in
  check)    check ;;
  mkfs)     mkfs_dirs ;;
  etc)      mk_essential_etc ;;
  own)      own_rootroot ;;
  mounts)   mounts ;;
  umounts)  umounts ;;
  chroot)   mounts; enter_chroot ;;
  all)      check; mkfs_dirs; mk_essential_etc; own_rootroot; mounts ;;
  clean-etc) clean_etc ;;
  help|*)   help ;;
esac
