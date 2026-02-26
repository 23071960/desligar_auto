#!/bin/bash

############################################################
# DESLIGAMENTO AUTOMÁTICO - VERSÃO PROFISSIONAL
############################################################

LOG="/var/log/desligar_auto.log"
LIMITE=600000        # 10 minutos (ms)
AVISO=60             # segundos antes de desligar

# usuários que NUNCA serão desligados
WHITELIST=("administrador" "professor")

echo "==== $(date) ====" >> "$LOG"

############################################################
# Detectar sessão ativa
############################################################

SESSION_ID=$(loginctl list-sessions --no-legend | awk '$3!="gdm"{print $1; exit}')

[ -z "$SESSION_ID" ] && exit 0

USER_NAME=$(loginctl show-session "$SESSION_ID" -p Name --value)
USER_ID=$(id -u "$USER_NAME")

echo "Usuário ativo: $USER_NAME" >> "$LOG"

############################################################
# Verificar whitelist
############################################################

for W in "${WHITELIST[@]}"; do
    if [ "$USER_NAME" = "$W" ]; then
        echo "Usuário ignorado (whitelist)" >> "$LOG"
        exit 0
    fi
done

############################################################
# Variáveis gráficas
############################################################

export XDG_RUNTIME_DIR="/run/user/$USER_ID"
export DISPLAY=":0"
export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"

############################################################
# Função executar como usuário gráfico
############################################################

run_user() {
    sudo -u "$USER_NAME" \
    XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR \
    DISPLAY=$DISPLAY \
    DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS \
    "$@"
}

############################################################
# Detectar atividade de áudio
############################################################

if command -v pactl >/dev/null; then
    AUDIO=$(run_user pactl list sink-inputs | grep RUNNING)
    if [ ! -z "$AUDIO" ]; then
        echo "Áudio em reprodução — cancelado" >> "$LOG"
        exit 0
    fi
fi

############################################################
# Detectar fullscreen (vídeo/aula)
############################################################

if command -v xprop >/dev/null; then
    FULL=$(run_user xprop -root _NET_ACTIVE_WINDOW 2>/dev/null)
    if echo "$FULL" | grep -qi fullscreen; then
        echo "Fullscreen detectado — cancelado" >> "$LOG"
        exit 0
    fi
fi

############################################################
# Tempo idle
############################################################

IDLE=$(run_user xprintidle 2>/dev/null)

echo "Idle atual: $IDLE" >> "$LOG"

[ -z "$IDLE" ] && exit 0

############################################################
# Aviso e desligamento
############################################################

if [ "$IDLE" -ge "$LIMITE" ]; then

    run_user notify-send \
        "⚠️ Computador inativo" \
        "Desligando em $AVISO segundos por inatividade..."

    for ((i=$AVISO;i>0;i--)); do
        sleep 1

        NOVO_IDLE=$(run_user xprintidle)

        # usuário voltou
        if [ "$NOVO_IDLE" -lt 5000 ]; then
            echo "Usuário voltou — cancelado" >> "$LOG"
            exit 0
        fi
    done

    echo "Desligamento executado" >> "$LOG"
    /sbin/shutdown -h now
fi
