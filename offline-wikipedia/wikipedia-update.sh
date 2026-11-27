#!/bin/bash
# Offline-Wikipedia (Kiwix) monatlich aktualisieren – läuft auf dem PROXMOX-HOST, nicht im Container.
# Aus dem Video „Offline-Wikipedia mit Kiwix“ (Homelab für Normalos).
#
# Was es tut:
#   1. Schaut bei download.kiwix.org nach der neuesten Fassung.
#   2. Gleich wie deine? -> fertig, nichts passiert.
#   3. Neu? -> laden, Prüfsumme prüfen, Schild (wikipedia_de.zim) umhängen, Kiwix neu starten.
#   4. Läuft Kiwix? -> alte Datei löschen + Meldung.  Läuft nicht? -> zurück auf alte Fassung + Warnung.
#
# Anpassen: CT = Nummer deines Containers, VARIANTE = maxi (mit Bildern) / nopic / mini.
# Meldung aufs Handy (optional): Datei /root/telegram.env mit zwei Zeilen anlegen
#   BOT_TOKEN=123456:ABC...     (vom BotFather)
#   CHAT_ID=123456789
# und mit  chmod 600 /root/telegram.env  schützen. Ohne die Datei landen Meldungen nur im Protokoll:
#   journalctl -u wikipedia-update
set -u
CT=134
VARIANTE=maxi
DIR=/srv/zim
BASE=https://download.kiwix.org/zim/wikipedia

melde() {   # $1 = Titel, $2 = Text
  echo "$1: $2"
  if [ -r /root/telegram.env ]; then
    . /root/telegram.env
    curl -s --max-time 30 "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
      --data-urlencode "chat_id=${CHAT_ID}" --data-urlencode "text=$1: $2" >/dev/null
  fi
}

neu=$(curl -sL --max-time 60 "$BASE/" | grep -o "wikipedia_de_all_${VARIANTE}_[0-9]\{4\}-[0-9]\{2\}\.zim" | sort -u | tail -1)
[ -z "$neu" ] && { melde "Wikipedia-Update WARNUNG" "Kiwix-Liste nicht lesbar - nichts geaendert."; exit 1; }
alt=$(pct exec $CT -- readlink $DIR/wikipedia_de.zim)
[ "$neu" = "$alt" ] && { echo "Nichts Neues: $alt ist aktuell."; exit 0; }

if ! pct exec $CT -- bash -c "cd $DIR && wget -q -c $BASE/$neu $BASE/$neu.sha256 && sha256sum -c --quiet $neu.sha256"; then
  melde "Wikipedia-Update WARNUNG" "Download oder Pruefung von $neu fehlgeschlagen - alte Fassung $alt bleibt."; exit 1
fi
if ! pct exec $CT -- bash -c "ln -sfn $neu $DIR/wikipedia_de.zim && systemctl restart kiwix && sleep 10 && systemctl is-active --quiet kiwix"; then
  pct exec $CT -- bash -c "ln -sfn $alt $DIR/wikipedia_de.zim && systemctl restart kiwix"
  melde "Wikipedia-Update WARNUNG" "$neu startet nicht - zurueck auf $alt."; exit 1
fi
pct exec $CT -- rm -f "$DIR/$alt" "$DIR/$alt.sha256"
melde "Wikipedia aktualisiert" "Neue Fassung $neu ist online (vorher $alt)."

# ---------------------------------------------------------------------------
# Einrichten (einmal, auf dem Proxmox-Host):
#   nano /usr/local/sbin/wikipedia-update.sh      # dieses Skript einfügen
#   chmod 700 /usr/local/sbin/wikipedia-update.sh
#
#   /etc/systemd/system/wikipedia-update.service:
#     [Unit]
#     Description=Offline-Wikipedia monatlich aktualisieren
#     [Service]
#     Type=oneshot
#     ExecStart=/usr/local/sbin/wikipedia-update.sh
#
#   /etc/systemd/system/wikipedia-update.timer:
#     [Unit]
#     Description=Offline-Wikipedia monatlich pruefen
#     [Timer]
#     OnCalendar=*-*-15 23:15:00
#     Persistent=true
#     [Install]
#     WantedBy=timers.target
#
#   systemctl daemon-reload && systemctl enable --now wikipedia-update.timer
#   Einmal von Hand testen:  /usr/local/sbin/wikipedia-update.sh
