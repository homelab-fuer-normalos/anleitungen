# Offline-Wikipedia mit Kiwix im Proxmox-Container

Anleitung zum Video „Die ganze Wikipedia zu Hause – auch ohne Internet“ (Homelab für Normalos).
Getestet am 26.–28.11.2026 mit Proxmox VE 9, Debian 13, kiwix-tools 3.7.0 und `wikipedia_de_all_maxi_2026-10.zim`.
Alle IP-Adressen sind Beispiele (192.168.1.x) – nimm die aus deinem Netz.

Ehrlich vorweg: keine Live-Wikipedia (neue Komplett-Fassungen nur alle paar Monate). Hilft bei Internet-Ausfall, nicht bei Server-Ausfall.

Größen (deutsche Wikipedia, Herbst 2026): mit Bildern „maxi“ ~45 GB · ohne Bilder „nopic“ ~17 GB · nur Artikelanfänge „mini“ ~4,4 GB.
Aktuelle Dateien: https://download.kiwix.org/zim/wikipedia/ (Name enthält das Datum – nimm die neueste und passe die Befehle an).

```
1) CONTAINER ANLEGEN (in der Proxmox-Shell)
Werte anpassen: 134 = eine freie Nummer, IP-Adresse und Gateway aus deinem Netz.

pct create 134 local:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst \
  --hostname wikipedia --cores 2 --memory 1024 --swap 512 \
  --rootfs local-lvm:4 \
  --mp0 local-lvm:100,mp=/srv/zim,backup=0 \
  --net0 name=eth0,bridge=vmbr0,ip=192.168.1.51/24,gw=192.168.1.1,firewall=1 \
  --unprivileged 1 --features nesting=1 --onboot 1 --timezone Europe/Berlin
pct start 134

→ Vorlage zuerst herunterladen (Name/Nummer ändert sich mit der Zeit, Stand 28.11.2026: 13.6-1):
  pveam update
  pveam available --section system | grep debian-13
  pveam download local debian-13-standard_13.6-1_amd64.tar.zst
  (Im Video steht noch 13.1-2 – das war die Vorlage beim Test.)
→ Zweites Laufwerk 100 GB unter /srv/zim: Beim Update liegen kurz alte + neue Fassung da.
→ backup=0: Die nächtliche Sicherung lässt die 45 GB weg (lassen sich jederzeit neu laden). Der Container selbst wird normal gesichert.
→ Tipp: Mit der Proxmox-Firewall nur dein Heimnetz auf Port 8080 lassen. Ins Internet gehört er nicht.

2) KIWIX INSTALLIEREN + WIKIPEDIA LADEN (im Container: pct enter 134)

apt update && apt -y full-upgrade && apt -y install kiwix-tools wget

systemd-run --unit=wiki-download wget -c -q -P /srv/zim \
  https://download.kiwix.org/zim/wikipedia/wikipedia_de_all_maxi_2026-10.zim \
  https://download.kiwix.org/zim/wikipedia/wikipedia_de_all_maxi_2026-10.zim.sha256

→ Läuft im Hintergrund weiter, auch wenn du das Fenster schließt. Bricht er ab: Befehl einfach nochmal starten (wget -c macht weiter).
Läuft er noch?   systemctl is-active wiki-download   („active“ = lädt noch; bei mir ~26 Minuten)
Fertig?          ls -lh /srv/zim
Prüfsumme:       cd /srv/zim && sha256sum -c wikipedia_de_all_maxi_2026-10.zim.sha256   („OK“ = heil angekommen; dauert ein paar Minuten)

3) FESTER NAME („SCHILD“) – hilft beim Update

ln -s wikipedia_de_all_maxi_2026-10.zim /srv/zim/wikipedia_de.zim

4) EIGENE STARTSEITE (sonst landest du in der „Bibliothek“, deren Suchfeld nur Bücher sucht – keine Artikel)

mkdir -p /etc/kiwix
nano /etc/kiwix/start.html
Inhalt:
<!doctype html><html lang=de><head><meta charset=utf-8>
<meta http-equiv=refresh content="0; url=/viewer#wikipedia_de">
<title>Offline-Wikipedia</title></head>
<body><p><a href="/viewer#wikipedia_de">Zur Offline-Wikipedia</a></p></body></html>

5) DIENST – startet Kiwix von selbst, auch nach einem Neustart

nano /etc/systemd/system/kiwix.service
Inhalt:
[Unit]
Description=Offline-Wikipedia (kiwix-serve)
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/bin/kiwix-serve --port=8080 --customIndex=/etc/kiwix/start.html /srv/zim/wikipedia_de.zim
DynamicUser=yes
Restart=on-failure
RestartSec=30

[Install]
WantedBy=multi-user.target

Einschalten:  systemctl enable --now kiwix
Prüfen:       systemctl status kiwix --no-pager
Im Browser:   http://IP-DEINES-CONTAINERS:8080

6) UPDATE JEDEN MONAT (auf dem PROXMOX-HOST, nicht im Container)
Skript: https://github.com/homelab-fuer-normalos/anleitungen/blob/main/offline-wikipedia/wikipedia-update.sh
• Ganz oben in der Datei anpassen: CT = Nummer deines Containers, VARIANTE = maxi / nopic / mini.
• Ablegen als /usr/local/sbin/wikipedia-update.sh, dann: chmod 700 /usr/local/sbin/wikipedia-update.sh
• Dienst + Timer (jeden 15. um 23:15, verpasst → holt er nach) stehen fertig ganz unten in der Datei (Abschnitt „Einrichten“).
• Einschalten: systemctl daemon-reload && systemctl enable --now wikipedia-update.timer
• Einmal von Hand testen: /usr/local/sbin/wikipedia-update.sh → „Nichts Neues: … ist aktuell.“ = alles richtig.
Was es tut: neueste Fassung bei Kiwix nachsehen → gleich? fertig. Neu? laden, Prüfsumme prüfen, Schild umhängen, Kiwix neu starten → läuft? alte Datei löschen + Meldung. Läuft nicht? zurück auf die alte Fassung + Warnung.
Meldung aufs Handy per Telegram ist freiwillig – Anleitung ganz oben in der Datei.
```

Update-Skript: [wikipedia-update.sh](wikipedia-update.sh) (läuft auf dem Proxmox-Host).
