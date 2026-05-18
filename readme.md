# DIY Docker Engine Tutorial 

- [DIY Docker Engine Tutorial](#diy-docker-engine-tutorial)
  - [Einleitung](#einleitung)
  - [Voraussetzungen](#voraussetzungen)
  - [Was ist Docker](#was-ist-docker)
  - [Vorbereitung](#vorbereitung)
    - [Terminal färben](#terminal-färben)
    - [Platzhalterprozesse](#platzhalterprozesse)
    - [Prozesse beenden](#prozesse-beenden)
    - [Docker Container](#docker-container)
  - [Namespaces - Isolation](#namespaces---isolation)
    - [PID eigener Prozessbaum](#pid-eigener-prozessbaum)
  - [MNT eigenes Dateisystem](#mnt-eigenes-dateisystem)
    - [Einleitung](#einleitung-1)
    - [Was ist ein Mount](#was-ist-ein-mount)
    - [chroot der Blickwinkel eines Prozesses](#chroot-der-blickwinkel-eines-prozesses)
    - [Alles zusammenführen](#alles-zusammenführen)
  - [overlayfs Dateisystem in Schichten](#overlayfs-dateisystem-in-schichten)
    - [Tests des Dateisystems](#tests-des-dateisystems)
  - [NET eigenes Netztwerkinterface](#net-eigenes-netztwerkinterface)
    - [Einleitung](#einleitung-2)
    - [Vorbereitung](#vorbereitung-1)
    - [Das Netz](#das-netz)
    - [Erstellen eines Interfaces](#erstellen-eines-interfaces)
    - [Namespace erstellen und Link verschieben](#namespace-erstellen-und-link-verschieben)
    - [Verbindung aufbauen und testen](#verbindung-aufbauen-und-testen)
    - [Mehrere Container über Bridge verbinden](#mehrere-container-über-bridge-verbinden)
    - [Aufräumen](#aufräumen)
  - [UTS eigener Hostname](#uts-eigener-hostname)
    - [USER Namespace - rootless Container](#user-namespace---rootless-container)
  - [cgroups - Ressourcenlimits](#cgroups---ressourcenlimits)
    - [Docker Container Konfiguration](#docker-container-konfiguration)
    - [Shell in Leaf-cgroup verschieben](#shell-in-leaf-cgroup-verschieben)
    - [Limits für unseren Container definieren](#limits-für-unseren-container-definieren)
    - [Limits testen](#limits-testen)
    - [Aufräumen](#aufräumen-1)
  - [IPC Namespace - Shared Memory Isolation](#ipc-namespace---shared-memory-isolation)
  - [Quellen](#quellen)


## Einleitung
In diesem Tutorial bauen wir unsere eigene Container-Runtime, um zu verstehen,
wie Docker unter der Haube funktioniert.

Docker ist kein Magie - es sind Linux-Kernel-Features: Namespaces für Isolation,
cgroups für Ressourcenlimits und overlayfs für Images. Wer diese Primitives versteht,
versteht Docker.


## Voraussetzungen
- eine VM oder Docker
- einfache Dockerkentnisse
- einfache Linuxkentnisse
- einfache Netzwerkkentnisse

## Was ist Docker

Docker ist eine Container-Runtime die auf Linux-Kernel-Features aufbaut, um Prozesse 
zu isolieren und zu verwalten. Drei Bausteine machen das möglich:

- **Namespaces** - isolieren was ein Prozess sehen kann (Prozesse, Netzwerk, Dateisystem)
  - **pid** - Prozessisolation
  - **mount** - einhängen von Dateisystemen in einen isolierten Verzeichnisbaum
  - **net** - ermöglichen die Netzwerkkommunikation zwischen den Containern und dem Host
  - **user** - Isoliert die Benutzer
  - **uts** - Unix Time Sharing Isolation des Hostnamens
  - **ipc** - shared memory Isolation
- **overlayfs** - ermöglichen schichtweise Images ohne Dateiduplizierung
- **cgroups** - begrenzen was ein Prozess verbrauchen darf (CPU, RAM, IO)

Ein `docker run`-Befehl erstellt letztendlich einen Linux-Prozess mit diesen drei 
Einschränkungen. Genau das werden wir in diesem Tutorial selbst nachbauen.

## Vorbereitung
Das Tutorial machen wir innerhalb eines Docker Containers um unseren Host nicht zu beeinträchtigen. Der Container muss im `--privileged` mode laufen, damit wir die kernel Aufrufe ausführen können.
```bash
docker run -it --privileged ubuntu:24.04 /bin/bash
```
Ihr könnt das Tutorial auch in einer Linux VM bearbeiten.

### Terminal färben
Da wir innerhalb mehrerer Terminal Instanzen arbeiten werden, werden wir den Prompt String des Terminals umbenennen und färben. Dies geschieht mit folgenden Befehlen, die führen wir beim betreten des entsprechenden Terminals aus.

```bash
# Terminal 1 - immer der "Host"
export PS1="\[\e[32m\][HOST]\[\e[0m\] \$ "

# Terminal 2 - immer der "Container/Namespace"
export PS1="\[\e[31m\][CONTAINER]\[\e[0m\] \$ "
```
### Platzhalterprozesse
Um die Isolation besser zu verdeutlichen werden wir zusätzliche Prozesse im Host starten.
```bash
sleep 1000 &
sleep 2000 &
sleep 3000 &
cat /dev/zero > /dev/null &
yes > /dev/null &
```

### Prozesse beenden
Diese können wir mit folgenden befehlen beenden.
```bash
jobs
kill $(jobs -p)
```

Wenn ein Prozess sich nicht beenden lässt hilft
```bash
sudo kill -9 <pid>
```
Es gibt folgende Signale SIGTERM | -15 (Bitte beende dich) und SIGKILL | -9 (Sofort beenden) . 


### Docker Container
Ich empfehle dieses Tutorial in einem Container oder einer VM zu machen. Sonst könnte man sich sein OS kaputt machen.  
Meine empfehlung ist das [Image](./DOcker/Dockerfile) zu verwenden weil dieser bereits die wichtigsten Tools vorinstalliert hat.
```bash
#baut das image
docker build -f ./Docker/Dockerfile --label cdev -t developer-image/ubuntu:cdev .

#startet den container
docker run -i --rm --privileged --name cdev -t developer-image/ubuntu:cdev

#gibt die laufenden container aus
docker ps 
#startet ein neues Terminal im container
docker exec -it <container-name> bash 
```

## Namespaces - Isolation
Wir verbinden uns mit unserem Docker Container und [färben](#terminal-färben) diesen erstmal als HOST um die Übersicht besser zu gestalten.
Danach starten wir erstmal ein Paar [Platzhalterprozesse](#platzhalterprozesse).
Nun listen wir unsere Prozesse auf mit `ps awx`. Wir sollten mehrere Prozesse angezeigt bekommen.
```bash
[HOST] $ ps awx
  PID TTY      STAT   TIME COMMAND
    1 pts/1    S      0:00 /bin/bash
   16 pts/1    S      0:00 sleep 1000
   17 pts/1    S      0:00 sleep 2000
   18 pts/1    S      0:00 sleep 3000
   19 pts/1    R      3:34 cat /dev/zero
   20 pts/1    R      3:34 yes
   22 pts/1    R+     0:00 ps awx
```
Wir sehen unsere Platzhalter und unsere bash mit der `PID1`.
Mit `pstree -p` können wir uns einen Baum unserer Prozesse anzeigen.
```bash
[HOST] $ pstree -p
bash(1)-+-cat(19)
        |-pstree(23)
        |-sleep(16)
        |-sleep(17)
        |-sleep(18)
```

### PID eigener Prozessbaum
Alle unsere Prozesse sind aktuell von unserer bash abhängig, das heißt sie hat diese Prozesse gestartet.
Nun erstellen wir unseren ersten Teil der Isolation.
Dafür verwenden wir den [unshare](https://www.kernel.org/doc/Documentation/unshare.txt) Befehl.
```bash
sudo unshare --pid --fork --mount-proc /bin/bash
```
Direkt danach [färben](#terminal-färben) wir unseren Terminal als CONTAINER, denn wir haben jetzt einen neuen `bash` Prozess gestartet der sich in einem eigenen Namespace befindet. Dies können wir mit `ps aux` beweisen.
```bash
[CONTAINER] $ ps aux
USER       PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
root         1  0.0  0.0   4144  3328 pts/1    S    20:46   0:00 /bin/bash
root         8  0.0  0.0   6444  2448 pts/1    R+   20:50   0:00 ps aux
```
Wir sehen nur zwei Prozesse und unsere Bash hat die `PID1`. Die Platzhalterprozesse die wir vorher gestartet haben sind nicht mehr sichtbar.

Da wir uns nicht mehr in dem HOST befinden, verbinden wir uns in einer neuen Terminal Session mit unserem Docker Container, und [färben](#terminal-färben) diese als HOST.
```bash
docker exec -it <container-name> bash
export PS1="\[\e[32m\][HOST]\[\e[0m\] \$ "
```
Wir führen `ps aux` aus um die Prozesse anzuzeigen. Jetzt sehen wir alle unsere Platzhalterprozesse und die Prozesse die wir unshared haben. Also unsere bash in unserem eigenen "container". 
```bash
[HOST] $ ps aux
USER       PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
develop+     1  0.0  0.0   4660  3848 pts/0    Ss   17:40   0:00 /bin/bash
develop+   563 99.9  0.0   2368  1012 pts/0    R    19:29  84:55 cat /dev/zero
develop+   564 99.9  0.0   2228   924 pts/0    R    19:29  84:55 yes
develop+   614  0.0  0.0   4660  3856 pts/2    Ss   19:32   0:00 bash
root       687  0.0  0.0   8384  4168 pts/2    S+   20:46   0:00 sudo unshare --pid --fork --mount-proc /bin/bash
root       688  0.0  0.0   8384  1732 pts/1    Ss   20:46   0:00 sudo unshare --pid --fork --mount-proc /bin/bash
root       689  0.0  0.0   2232   980 pts/1    S    20:46   0:00 unshare --pid --fork --mount-proc /bin/bash
root       690  0.0  0.0   4144  3328 pts/1    S+   20:46   0:00 /bin/bash
develop+   699  0.0  0.0   6444  2456 pts/0    R+   20:54   0:00 ps aux
```
In dem Beispiel ist es die PID690, weil es noch zwei `root` Prozesse gibt die diesen Kontrollieren. Wir können den Baum mit `pstree -p 687` anzeigen.
```bash
[HOST] $ pstree -p 687
sudo(687)---sudo(688)---unshare(689)---bash(690)
```
Nun müssen wir aufreumen also beenden wir die Platzhalter Prozesse mit `kill -9 $(jobs -p)`. Das muss im Host und Container gemacht werden, sonst ist unsere CPU sehr stark ausgelastet.

Den container können wir mit `exit` verlassen. Der Terminal sollte erneut `[HOST]` anzeigen. 
Lasst uns mit unshare spielen und folgenden Befehl ausführen `sudo unshare --pid /bin/bash`.
Wir sind jetzt wieder in unserem neuen Container. Gib mit `echo $$` die eigene PID aus und zeige die laufenden Prozesse mit `ps aux`an. Was siehst du jetzt im vergleich zum vorherigen Container?

```bash
[HOST] $ sudo unshare --pid /bin/bash
[sudo] password for developer: 
bash: fork: Cannot allocate memory
root@f805d9b6708b:/home/developer/source-code# echo $$
721
root@f805d9b6708b:/home/developer/source-code# ps aux
bash: fork: Cannot allocate memory
root@f805d9b6708b:/home/developer/source-code# exit
exit
[HOST]
```
Wir sind im `CONTAINER`. Können wegen einem Fehler keine eigenen Prozesse ausführen. Dies kommt daher das wir den Prozess zwar isoliert haben aber weder ein `fork` noch ein `--mount-proc` gemacht haben. Die PID des neuen `bash` Prozesses ist nicht 1 sondern 721. Das heist das unsere bash noch immer im Namespace des `HOSTS` lauft. Das ist auch der Grund warum wir keine eigenen Prozesse starten können. Fork sorgt dafür das die Anwendung die wir mit `unshare` in einen eigenen Namespace verschieben, dort neu gestartet wird. Da dies nicht geschehen ist, können wir auch nichts starten. Wir verlassen die `namespace` mit `exit`.

Lasst uns den `fork` Befehl hinzu nehmen `sudo unshare --pid --fork /bin/bash` und erneut die eigene PID sowie die laufenden Prozesse ausgeben. Was seht ihr jetzt? Wie unterscheidet sich die Ausgabe zu den vorherigen Aufrufen?

```bash
[HOST] $ sudo unshare --pid --fork /bin/bash
root@f805d9b6708b:/home/developer/source-code# ps aux
USER       PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
develop+     1  0.0  0.0   4660  3848 pts/0    Ss+  17:40   0:00 /bin/bash
develop+   614  0.0  0.0   4660  3856 pts/2    Ss   19:32   0:00 bash
root       728  0.0  0.0   8388  4036 pts/2    R+   21:11   0:00 sudo unshare --pid --fork /bin/bash
root       729  0.0  0.0   8388  1712 pts/1    Ss   21:11   0:00 sudo unshare --pid --fork /bin/bash
root       730  0.0  0.0   2232   984 pts/1    S    21:11   0:00 unshare --pid --fork /bin/bash
root       731  0.0  0.0   4144  3328 pts/1    S    21:11   0:00 /bin/bash
root       737  0.0  0.0   6444  2456 pts/1    R+   21:11   0:00 ps aux
root@f805d9b6708b:/home/developer/source-code#  echo $$
1
```
Das sieht schon besser aus. Wir sehen das unsere PID jetzt 1 ist, können aber noch weiterhin die Prozesse des hosts sehen. Warum? Wir haben das `/proc` Verzeichniss nicht neu gemountet. Linux arbeitet sehr stark mit Dateien und unsere laufenden Prozesse sind Dateien im `/proc` Verzeichnis auf dem RAM. Lasst uns jetzt das `proc` Dateisystem mounten und dadurch das `/proc` Verzeichnis des `HOST` verdecken. Führen wir den Befehl aus `mount -t proc proc /proc` und zeigen dann die laufenden Prozesse an. Was seht ihr jetzt?

```bash
root@f805d9b6708b:/home/developer/source-code# mount -t proc proc /proc
root@f805d9b6708b:/home/developer/source-code# ps aux
USER       PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
root         1  0.0  0.0   4144  3336 pts/1    S    21:11   0:00 /bin/bash
root        12  0.0  0.0   6444  2448 pts/1    R+   21:13   0:00 ps aux
```
Jetzt sieht es richtig aus, wir sehen nur noch unsere bash mit der PID 1 und ps.

Zusammengefasst erstellt `sudo unshare --pid --fork --mount-proc /bin/bash` einen neuen `namespace`, startet die `/bin/bash` in diesem `namespace` neu und überdeckt das `/proc` Verzeichnis damit man aus dem Namespace nicht mehr die `HOST` Prozesse einsehen kann. Der Kernel befüllt dieses Verzeichnis automatisch, wir müssen es nur mounten.
Mounten wird in den nächsten Schritten immer wieder verwendet um bestimmte Verzeichnisse zu verbergen und mit den Dateien die der Container benötigt zu füllen.



## MNT eigenes Dateisystem

### Einleitung
Linux repräsentiert alles als Dateien. Dazu gehören Prozesse (`/proc`), Geräte (`/dev`), Netzwerk (`/sys/net`) und das eigentliche Dateisystem. Der `MNT`-Namespace isoliert die *Mounttabelle*, die liste aller eingehängten Dateisysteme. Dadurch hat ein Prozess seine eigene Private Tabelle. 
Ein Container soll sein eigenes Root-Verzeichnis `/` haben.
Dafür verwenden wir zwei Werkzeuge: `chroot` (tauscht das Root-Verzeichnis) und
`unshare --mount` (isoliert Mounts damit sie den Host nicht beeinflussen).

### Was ist ein Mount
Linux arbeitet mit einem einzigen Verzeichnisbaum, deswegen müssen zusätzliche Dateisysteme wie z.B.: USB Massenspeicher an diesen Baum angehängt werden. Das nennt man Mounten. 

Der Baum beginnt bei `/`. Hier ist ein typischer Linux Baum.
```
/
├── bin/
├── home/
├── proc/
├── dev/
└── mnt/
```

Gemacht wird das mit dem Befehl `mount <was> <wo>`. EIn USB Massenspeicher würde man so mounten `mount /dev/sdb1 /mnt/usb`. Dabei ist das Verzechnis `/mnt/usb` der Mountpunkt an den das Gerät `/dev/sdb1` gehängt wird.

Weiterhin gibt es virtuelle Dateisysteme, wie z.B.: `/proc` dieses wird vom Kernel im RAM, live und dynamisch generiert. Es enthällt die aktuell laufenden Prozesse. Diese habt ihr im vorherigen Kapitel gesehen `mount -t proc proc /proc`. Hier wurde das Virtuelle `proc`-Dateisystem bei `/proc` im Baum gehängt, das Dateisystem hat den Typen `-t proc`. Danach bfüllt der Kernel es automatisch.

### chroot der Blickwinkel eines Prozesses

Jezt geht es darum dafür zu sorgen das unser Prozess nicht nur die entsprechenden virtuellen Dateisysteme gemountet hat, sondern auch um den Blickwinkel. Wir wollen dafür sorgen das der Prozess sich in einem eigenen Linux Baum bewegt. Weiterhin soll der Prozess nicht in der Lage sein den Baum des Hosts zu betreten. Dies erreichen wir mit `chroot <new_root> [command]`.

Dies sorgt dafür das die ausgeführte Command in dem neuen Verzeichniss ausgeführt wird.

Wenn wir `chroot /home/new/root /bin/bash` ausführen würde es den Blickwinckel der Bash Anwendung von
```
/
├── bin/
├── home/
|    └── new/root
├── proc/
├── dev/
└── mnt/
```
nach `new/root/...` umbiegen wobei dieses Verzeichnis von jetzt an als `/` definiert ist und der Prozess die oberen Verzeichnisse nicht mehr erreichen kann.

### Alles zusammenführen

Jetzt führen wir das was wir in dem Abschnitt gelernt haben zusammen.
Dafür benötigen wir erstmal eine weitere Linux Distribution. Wir verwenden Alpine. Diese wird für unseren Container als der Root definiert.

Als erstes gehen wir zurück in unseren Docker Container den wir für die Aufgaben verwendet haben und machen zwei Terminals auf. Ein Terminal wird der Host sein und einen machen wir zum Container.
```bash
#Terminal 1 -> wird unser Host sein
docker run -i --rm --name cdev --privileged -t <image>
export PS1="\[\e[32m\][HOST]\[\e[0m\] \$ "
#Terminal 2 -> wird unser Container 1 sein
docker exec -it <container> bash 
export PS1="\[\e[32m\][HOST]\[\e[0m\] \$ "
```
 Wir betreten den zweiten Terminal und führen die nachfolgenden Befehle darin aus.
Wir laden es mit `wget` herunter und extrahieren den Inhalt des TARs in `/tmp/alpine`. Dies wird unser neuer root sein.
```sh
wget https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/x86_64/alpine-minirootfs-3.19.0-x86_64.tar.gz
mkdir -p /tmp/alpine
tar xf alpine-minirootfs-*.tar.gz -C /tmp/alpine
ls /tmp/alpine 
```
Als nächstes starten wir die bash im eigenen `--mount` Namespace mit unshare und benennen diese als `CONTAINER`.
```bash
sudo unshare --mount /bin/bash
export PS1="\[\e[31m\][CONTAINER]\[\e[0m\] \$ "
```
Jetzt mounten wir drei Dateisysteme in unserem neuen Root. `proc` für die laufenden Prozesse und `sysfs` für Systemdienste die Linux benötigt. Die letzte Zeile bindet die Geräte die mit dem Host verbunden sind und sich standartmäßig in `/dev` befinden an den `/tmp/alpine/dev` Zweig ohne ein neues Dateisystem zu erstellen. Wir spiegeln sie sozusagen. 
```sh
mount -t proc proc /tmp/alpine/proc
mount -t sysfs sysfs /tmp/alpine/sys
mount -o bind /dev /tmp/alpine/dev
```

Jetzt müssen wir nur noch den neuen Root für die Shell des Containers definieren.
```sh
chroot /tmp/alpine /bin/sh
```
Jetzt sind wir mit der Shell im `alpine` Verzeichniss und sehen nur noch was unten drunter ist aber können nicht mehr raus.

Lasst uns testen ob es funktioniert hat.
```sh
cat /etc/os-release   # Alpine Linux
ls /proc              # Prozesse sichtbar
ps aux               # laufende Prozesse
echo "geheim" > /secret.txt  # Datei nur im Container
exit                  # zurück in unshare-Shell
```

Jetzt nur noch aufraumen.
```sh
umount /tmp/alpine/proc
umount /tmp/alpine/sys
umount /tmp/alpine/dev
exit   # Mount-Namespace verlassen - Mounts verschwinden automatisch
```

Damit haben wir ein eigenes Dateisystem für unseren Container erstellt und es isoliert.

## overlayfs Dateisystem in Schichten

Unser Dateisystem hat ein großes Problem. Es wird beim Erstellen des Containers verändert und muss bei jedem neuen Container neu heruntergeladen werden. Dies ist umständlich und verbraucht viel Speicher. Das geht besser mit `overlayfs`

Wir benötigen erstmal vier Verzeichnisse und unsere `alpine` image die wir direkt in den `alpine/diff` Verzeichnis exportieren.
```sh
mkdir -p /tmp/containers/alpine/diff
mkdir -p /tmp/containers/c1/upper
mkdir -p /tmp/containers/c1/work
mkdir -p /tmp/containers/c1/merged

tar xf alpine-minirootfs-*.tar.gz -C /tmp/containers/alpine/diff
```

`overlayfs` ist Teil des Linux Kernels und ermöglicht es uns ein Verzeichnis als `lower` zu definieren. Dies sorgt dafür das dieses Verzeichnis `readonly` wird. 

Dann geben wir noch drei weitere Verzeichnisse an `upper`, `work` und `merged`.  
Wenn wir eine neue Datei in `lower` erstellen, dann wird diese stattdessen automatisch in `upper` abgelegt. Wenn wir eine Datei löschen dann wird in `upper` eine `whiteout` Datei erstellt, die die Originaldatei in `lower` versteckt.  
`work` ist für uns egal, `overlayfs` verwendet es für Laufzeitdaten.  
`merged` ist das Verzeichnis das wir mit `chroot` mounten müssen, dies ist die Gesamtansicht für unseren Container.

Also mounten wir jetzt unser Container Dateisystem.
```sh
mount -t overlay overlay \
  -o lowerdir=/tmp/containers/alpine/diff,\
     upperdir=/tmp/containers/c1/upper,\
     workdir=/tmp/containers/c1/work \
  /tmp/containers/c1/merged
```

### Tests des Dateisystems
Lasst es uns jetzt ausprobieren. Wir ändern eine Datei in unserem Container und schauen dann nach ob diese sich im `lower` verändert hat. Dies sollte nicht passieren, es sollte eine neue Datei im `upper` entstanden sein
```sh
# Datei im Container ändern
echo "verändert" > /tmp/containers/c1/merged/etc/hostname

# lower ist unberührt
cat /tmp/containers/alpine/diff/etc/hostname   # original

# Änderung nur im upper
cat /tmp/containers/c1/upper/etc/hostname      # "verändert"
ls /tmp/containers/c1/upper/etc/               # nur geänderte Dateien
```
Lasst uns einen weiteren Container anlegen. `C1` und `C2` teilen sich jetzt den selben `lower` und haben eigene Verzeichnisse für die Änderungen.
```sh
mkdir -p /tmp/containers/c2/upper /tmp/containers/c2/work /tmp/containers/c2/merged

mount -t overlay overlay \
  -o lowerdir=/tmp/containers/alpine/diff,\
     upperdir=/tmp/containers/c2/upper,\
     workdir=/tmp/containers/c2/work \
  /tmp/containers/c2/merged
```

Zuletzt müsste man noch `unshare` und `chroot` in den entsprechenden `merged` machen und man hat ein eigenes Container Dateisystem das die originale Image nicht mehr verändert. Docker macht es genauso, nur das es anstatt `c1`, hashwerte als Containernamen und `overlayfs` Verzeichnisse verwendet.

## NET eigenes Netztwerkinterface

### Einleitung
In diesem Teil werden wir uns mit Netzwerken beschäftigen. Wir werden lernen wie man eine Verbindung zwischen dem Container und Host herstellt über die beide mit einander kommunizieren können. Danach konfigurieren wir unser Netzwerk so das auch das Internet von innerhalb des Containers erreichbar ist. Zuletzt erstellen wir eine Bridge über die Container miteinander, mit dem Host und dem Internet kommunizieren können.

### Vorbereitung
Beendet und löscht den Docker Container in dem ihr die vorherigen Aufgaben bearbeitet habt. Dadurch raumen wir alles auf und können für die nächsten Aufgaben auf einer sauberen Umgebung starten.

Startet den Docker Container neu und verbintet zwei weitere Terminals, damit wir drei Terminals innerhalb des Containers haben.
Da wir uns mit dem Docker Netzwerk beschäftigen werden, werden wir ein Host und zwei Container simulieren. Diese [färben](#terminal-färben) wir direkt ein.

```bash
#Terminal 1 -> wird unser Host sein
docker run -i --rm --name cdev --privileged -t <image>
export PS1="\[\e[32m\][HOST]\[\e[0m\] \$ "
#Terminal 2 -> wird unser Container 1 sein
docker exec -it <container> bash 
export PS1="\[\e[32m\][HOST]\[\e[0m\] \$ "
#Terminal 3 -> wird unser Container 2 sein
docker exec -it <container> bash 
export PS1="\[\e[32m\][HOST]\[\e[0m\] \$ "
```
Wir färben erstmal alle drei Terminals als HOST, und werden später dann den `unshare` machen.
Wenn nicht anders genannt arbeiten wir in `Terminal 1`

### Das Netz
Zuerst lassen wir uns die aktuellen Netzwerkschnittstellen unseres HOSTs an.
```bash
ip -brief addr show
```
Dies sollte eine Liste der aktuellen Schnittstellen mit deren IP und Zustand anzeigen.
```bash
[HOST] $ ip -brief addr show
lo               UNKNOWN        127.0.0.1/8 ::1/128 
tunl0@NONE       DOWN           
gre0@NONE        DOWN           
gretap0@NONE     DOWN           
erspan0@NONE     DOWN           
ip_vti0@NONE     DOWN           
ip6_vti0@NONE    DOWN           
sit0@NONE        DOWN           
ip6tnl0@NONE     DOWN           
ip6gre0@NONE     DOWN           
eth0@if27        UP             172.17.0.2/16 
```
Die meisten Interfaces werden vom Kernel automatisch erstellt und können ignoriert werden. Wichtig sind `lo` (localhost) welche auf `127.0.0.1/8` zeigt und `eth0@if25` (docker-bridge) welche auf `172.17.0.2/16` zeigt. Dies ist unser Tunnel in die Außenwelt und zu den anderen Containern.
Dabei bedeutet `eth0@if25` das es teil eines Paares ist. Das Interface `eth0` hat das Gegenstück mit der ID `25` in möglicherweise einem anderen Namespace. In dem Fall dem HOST unseres aktuellen Docker Containers.
Die IDs können wir mit `ip link show` sehen.

### Erstellen eines Interfaces
Lasst uns die Anzahl der Interfaces zählen `ip -brief link show | wc -l ` merkt euch die Zahl.

Jetzt erstellen wir ein neues Interface vom Typ `veth` (virtual-ether) mit dem Namen `veth0` und dem Gegenstück dessen Name `veth1` ist. Also ein Kabel mit zwei Steckern.
```bash
sudo ip link add veth0 type veth peer name veth1
```

Führt jetz folgende Befehle aus um das erstellte Interface zu sehen.
```bash
ip -brief link show             
ip -brief link show veth0       
ip -brief link show veth1       
```
Dadurch bekommen wir folgende ausgabe. Wir sehen die zwei Interfaces einerseits aus der Sicht von `veth0` und andererseits aus der Sicht von `veth1`
```bash
[HOST] $ sudo ip link add veth0 type veth peer name veth1
[HOST] $ ip -brief link show  
lo               UNKNOWN        00:00:00:00:00:00 <LOOPBACK,UP,LOWER_UP> 
# default interfaces gelöscht
eth0@if27        UP             76:3d:3c:93:f3:ee <BROADCAST,MULTICAST,UP,LOWER_UP> 
veth1@veth0      DOWN           5e:21:f8:80:dc:9d <BROADCAST,MULTICAST,M-DOWN> 
veth0@veth1      DOWN           ea:43:fb:77:be:f3 <BROADCAST,MULTICAST,M-DOWN> 
[HOST] $ ip -brief link show veth0  
veth0@veth1      DOWN           ea:43:fb:77:be:f3 <BROADCAST,MULTICAST,M-DOWN> 
[HOST] $ ip -brief link show veth1  
veth1@veth0      DOWN           5e:21:f8:80:dc:9d <BROADCAST,MULTICAST,M-DOWN> 
```

Was passiert wenn wir den `veth0` löschen?
```bash
sudo ip link delete veth0
ip -brief link show
```
Warum ist `veth1` auch weg?

### Namespace erstellen und Link verschieben
Wir wechseln jetzt in `Terminal 2` und führen `sudo unshare --net /bin/bash` aus, dadurch wechseln wir aus dem `HOST` in ein eigenes Namespace. Wir [färben](#terminal-färben) es direkt ein um es unterscheiden zu können. Dann geben wir die PID `echo $$` des Prozesses aus.

```bash
sudo unshare --net /bin/bash
export PS1="\[\e[31m\][CONTAINER-1]\[\e[0m\] \$ "
echo $$
```
Somit bekommen wir folgende Ausgabe:
```bash
[HOST] $ sudo unshare --net /bin/bash
[sudo] password for developer: 
root@7d696a35a6d9:/home/developer/source-code# export PS1="\[\e[31m\][CONTAINER-1]\[\e[0m\] \$ "
[CONTAINER-1] $ echo $$
531
```
Die `PID` in meinem Fall 531 merken wir uns und wechseln zurück in den `Terminal 1` unseren HOST.

Wir erstellen erneut unser Interface und schieben den `veth1` Teil des Kabels es in das `namespace` unseres `CONTAINER-1` mit der PID die wir uns vorher gemerkt haben.
```bash
sudo ip link add veth0 type veth peer name veth1
sudo ip link set veth1 netns 531
```
Führt `ip -brief link show` im `HOST` aus, `veth1` sollte verschwunden sein. Wechselt in den `CONTAINER-1` und führt den Befehl erneut aus, ihr solltet jetzt `veth1` dort sehen.
Somit haben wir unseren `HOST` mit unserem `CONTAINER-1` mit einem `Kabel` verbunden.

### Verbindung aufbauen und testen
Was wir jetzt noch machen müssen ist den zwei Enden je eine IP zuzuweisen. Wir nehmen das `10.0.0.0/24` Netz.
Im `HOST` führen wir folgende Befehle aus.
```bash
sudo ip addr add 10.0.0.1/24 dev veth0
sudo ip link set veth0 up
```
Im `TERMINAL-1` führen wir folgende Befehle aus.
```bash
ip addr add 10.0.0.2/24 dev veth1
ip link set veth1 up
ip link set lo up
```

Jetzt sollten wir sie gegenseitig anpingen können. Aus dem `HOST` den `CONTAINER-1` anpingen `ping -c 2 10.0.0.2` und umgekehrt `ping -c 2 10.0.0.1`.
Die Pings sollten ankommen. Im `CONTAINER-1` möchten wir noch das Internet `ping -c 3 8.8.8.8 ` anpingen.
Das ist aktuell noch nicht möglich. Lasst uns die Routen `ip route show` anschauen.

```bash
[CONTAINER-1] $ ping -c 3 8.8.8.8 
ping: connect: Network is unreachable
[CONTAINER-1] $ ip route show  
10.0.0.0/24 dev veth1 proto kernel scope link src 10.0.0.2 
```
Wir sehen nur eine Route zum `HOST` aber keine `default` Route die der Kernel verwenden kann um Pakete zu senden deren Ziel er nicht kenn. Erstellen wir die Route `ip route add default via 10.0.0.1`. Indem wir ihm sagen das er alles an den Host senden soll was er nicht zuweisen kann.
Schaut euch die Routen an und Pingt das Internet erneut an, so wie es aussieht funktioniert es immer noch nicht.

```bash
[CONTAINER-1] $ ip route add default via 10.0.0.1
[CONTAINER-1] $ ip route show 
default via 10.0.0.1 dev veth1 
10.0.0.0/24 dev veth1 proto kernel scope link src 10.0.0.2 
[CONTAINER-1] $ ping -c 3 8.8.8.8
PING 8.8.8.8 (8.8.8.8) 56(84) bytes of data.
--- 8.8.8.8 ping statistics ---
3 packets transmitted, 0 received, 100% packet loss, time 2064ms
```
Unser `HOST` muss noch als Router konfiguriert werden. Deshalb wechseln wir zurück in den `HOST` Terminal und prüfen ob `ip-forwarding` aktiviert ist mit `cat /proc/sys/net/ipv4/ip_forward`. Es sollte `1` ausgegeben werden. Es sollte von Docker bereits aktiviert sein. Wenn nicht dann `sudo sh -c 'echo 1 > /proc/sys/net/ipv4/ip_forward'` ausführen. 

Erstellen unsere erste NAT-Regel die den Paketen vom `Container-1`die `HOST-IP` zuweist.
```bash
sudo iptables -t nat -A POSTROUTING -s 10.0.0.0/24 -j MASQUERADE
```
Wir aktivieren `MASQUERADE`, dies ersetzt die IP Adresse unseres `CONTAINER-1` mit der des `HOST` bevor es die Nachricht ins Internet weiter leitet.

Welchese in den `CONTAINER-1` und führe `ping -c 3 8.8.8.8` jetzt sollte es erreichbar sein. Zeige die Route die unsere Pakete nehmen mit `traceroute 8.8.8.8`.

```bash
[CONTAINER-1] $ traceroute 8.8.8.8
traceroute to 8.8.8.8 (8.8.8.8), 30 hops max, 60 byte packets
 1  localhost (10.0.0.1)  0.060 ms  0.015 ms  0.016 ms
 2  localhost (172.17.0.1)  0.095 ms  0.027 ms  0.021 ms
 3  * * *
 4  * * *
```
Wir sehen das wir an unseren Host `10.0.0.1` weitergeleitet werden, dieser leitet uns an den Docker Container Bridge weiter in dem wir unere Terminals gestartet haben. Die Sterne sind HOPs die sich aus Sicherheitsgründen nicht zurück melden.

Lasst uns die Pakete beobachten. Wechseln wir in den `HOST` und führen `sudo tcpdump -i veth0 -n icmp &` aus. Danach gehen wir zum `CONTAINER-1` zurück und machen den Ping erneut `ping -c 3 8.8.8.8`.

```bash
[HOST] $ tcpdump: verbose output suppressed, use -v[v]... for full protocol decode
listening on veth0, link-type EN10MB (Ethernet), snapshot length 262144 bytes
20:59:38.966178 IP localhost > dns.google: ICMP echo request, id 53251, seq 1, length 64
20:59:39.013826 IP dns.google > localhost: ICMP echo reply, id 53251, seq 1, length 64
20:59:38.966175 IP 10.0.0.2 > 8.8.8.8: ICMP echo request, id 53251, seq 1, length 64
20:59:39.013826 IP 8.8.8.8 > 10.0.0.2: ICMP echo reply, id 53251, seq 1, length 64
20:59:39.973053 IP 10.0.0.2 > 8.8.8.8: ICMP echo request, id 53251, seq 2, length 64
20:59:39.973053 IP localhost > dns.google: ICMP echo request, id 53251, seq 2, length 64
20:59:39.995501 IP 8.8.8.8 > 10.0.0.2: ICMP echo reply, id 53251, seq 2, length 64
20:59:39.995501 IP dns.google > localhost: ICMP echo reply, id 53251, seq 2, length 64
20:59:40.980698 IP localhost > dns.google: ICMP echo request, id 53251, seq 3, length 64
20:59:41.003237 IP dns.google > localhost: ICMP echo reply, id 53251, seq 3, length 64
```
Wir sehen wie die Pakete hin und her geschickt werden.

### Mehrere Container über Bridge verbinden
In diesem Schritt werden wir ein Bridge Netzwerk erstellen, genau so wie es auch Docker normalerweise aufbaut damit die Container untereinander kommunizieren können.

Dazu wechseln wir jetzt in den bisher ungenutzten `Terminal-3` und verschieben den in ein neues `namespace`, [färben](#terminal-färben) den Terminal und nennen ihn `CONTAINER-2`. Geben uns die PID aus und merken uns diese.
```bash
sudo unshare --net /bin/bash
export PS1="\[\e[31m\][CONTAINER-2]\[\e[0m\] \$ "
echo $$   
```
So sollte es aussehen:
```bash
[HOST] $ sudo unshare --net /bin/bash
[sudo] password for developer: 
root@7d696a35a6d9:/home/developer/source-code# export PS1="\[\e[31m\][CONTAINER-2]\[\e[0m\] \$ "
[CONTAINER-2] $ echo $$   
1298
```

Wir wechseln in den `HOST` und erstellen eine Bridge, weisen ihr die IP des Containers zu in dem wir unsre Aufgaben machen. Dann erstellen wir zwei ethernet Kabel die wir mit der einen Seite mit der `bridge` verbinden und mit der anderen in unsere zwei Container einbinden. Wechselt wenn nötig in die entsprechenden Terminal und gebt euch die `PID` der container aus.
```bash
sudo ip link add docker-bridge type bridge
sudo ip addr add 10.0.0.5/24 dev docker-bridge

# Interface erstellen mit zwei Steckern 
sudo ip link add veth-c1-host type veth peer name veth-c1
# Eine Seite in die Bridge anschließen
sudo ip link set veth-c1-host master docker-bridge 

# Interface erstellen mit zwei Steckern 
sudo ip link add veth-c2-host type veth peer name veth-c2
# Eine Seite in die Bridge anschließen
sudo ip link set veth-c2-host master docker-bridge

# Kabel in Container verschieben
sudo ip link set veth-c1 netns <CONTAINER-1-PID>
sudo ip link set veth-c2 netns <CONTAINER-2-PID>

# Host interfaces hoch fahren
sudo ip link set docker-bridge up
sudo ip link set veth-c1-host up
sudo ip link set veth-c2-host up

# Alte direkte Route löschen
sudo ip route del 10.0.0.0/24 dev veth0

#sudo iptables -P FORWARD ACCEPT
```

Danach wechseln wir in `CONTAINER-1`, weisen dem Kabel eine IP zu und starten das Interface.
```bash
ip addr add 10.0.0.4/24 dev veth-c1
ip route add default via 10.0.0.5
ip link set veth-c1 up
```
Dann wechseln wir in `CONTAINER-2`, weisen dem Kabel eine IP zu und starten das Interface.
```bash
ip addr add 10.0.0.3/24 dev veth-c2
ip route add default via 10.0.0.5
ip link set veth-c2 up
ip link set lo up
```

Jetzt sollte alles konfiguriert sein. Testet ob die Pings funktionierten von den zwei Containern zu einander und zum Host sowie inst Internet. Wenn alles funktioniert haben wir ein Bridge Netzwerk gebaut das auch Docker normallerweise für seine Container verwendet.

### Aufräumen
Wir verlassen die zwei Container Terminals mit exit. Dadurch werden die veth Interfaces in den Namespaces automatisch vom Kernel entfernt, da der Namespace nicht mehr existiert.

Zurück im HOST löschen wir die Bridge und entfernen die iptables Regel.
```sh
sudo ip link delete docker-bridge
sudo iptables -t nat -D POSTROUTING -s 10.0.0.0/24 -j MASQUERADE
```
Prüfen ob alles sauber ist.
```sh
ip -brief link show           # docker-bridge und veth Interfaces sollten weg sein
sudo iptables -t nat -L POSTROUTING --line-numbers   # Regel sollte nicht mehr auftauchen
```


## UTS eigener Hostname
Der `UTS` Namespace (Unix Time-Sharing) isoliert den **Hostnamen** des Systems.
Ohne ihn sehen alle Container denselben Hostnamen des Hosts. Das macht Logs unlesbar
und Anwendungen die sich mit dem Hostnamen im Netzwerk registrieren (z.B. Datenbanken)
würden sich gegenseitig überschreiben.

`docker run --name myapp nginx` setzt intern den UTS Hostnamen auf `myapp`.
Jedes `[myapp] ERROR` im Log ist damit sofort dem richtigen Container zuzuordnen.

Wir starten zwei Terminals und färben diese als `HOST` und `CONTAINER`.
Im `HOST` schauen wir uns erstmal den aktuellen Hostnamen an.

```sh
[HOST] $ hostname
ubuntu
```
Dann wechseln wir in den CONTAINER Terminal und erstellen einen UTS-Namespace.
```sh
sudo unshare --uts /bin/bash
export PS1="\[\e[31m\][CONTAINER]\[\e[0m\] \$ "
```
Jetzt setzen wir einen eigenen Hostnamen im Container und überprüfen ihn.
```sh
[CONTAINER] $ hostname mycontainer
[CONTAINER] $ hostname
mycontainer
```
Wechseln wir zurück in den HOST und prüfen ob sich etwas verändert hat.

```sh
[HOST] $ hostname
ubuntu
```
Der Hostname des Hosts ist unverändert. Der Container hat seinen eigenen Hostnamen
der nach außen nicht sichtbar ist. Mit `exit` verlassen wir den Namespace wieder.


### USER Namespace - rootless Container  

Der `USER` Namespace isoliert die Benutzer- und Gruppen-IDs eines Prozesses. Ohne ihn läuft ein Container-Prozess der root sein will als echter root auf dem Host. Ein Container-Ausbruch würde sofort volle Host-Root-Rechte geben. Ein Sicherheitsproblem.

Mit dem `USER` Namespace wird eine UID-Mapping Tabelle angelegt. Ein Prozess ist innerhalb des Containers `root` (UID 0), auf dem Host aber nur ein unprivilegierter Nutzer. Das ist die Grundlage von rootless Containern. `docker run --user` und der rootless Docker Modus bauen genau darauf auf.

Wir starten zwei Terminals und färben diese als `HOST` und `CONTAINER`.
Im `HOST` schauen wir uns erstmal unseren aktuellen Benutzer an.
```sh
[HOST] $ id
uid=1000(developer) gid=1000(developer) groups=1000(developer)
```
Dann wechseln wir in den `CONTAINER` Terminal. Diesmal brauchen wir kein sudo, das ist der Punkt des USER Namespace, er ist der einzige Namespace den unprivilegierte Nutzer ohne root-Rechte erstellen dürfen.
```sh
unshare --user --map-root-user /bin/bash
export PS1="\[\e[31m\][CONTAINER]\[\e[0m\] \$ "
```
Jetzt prüfen wir wer wir innerhalb des Containers sind.
```sh
[CONTAINER] $ whoami
root
[CONTAINER] $ id
uid=0(root) gid=0(root) groups=0(root)
```
Wir sind root. Lasst uns die UID-Mapping Tabelle anschauen die der Kernel für uns angelegt hat.
```sh
[CONTAINER] $ cat /proc/self/uid_map
         0       1000          1
```
Die drei Spalten bedeuten: UID 0 im Container entspricht UID 1000 auf dem Host, und das gilt für 1 Benutzer. Unser Container-root ist auf dem Host also nur der developer Benutzer.
Wechseln wir zurück in den HOST und schauen wie der Prozess von außen aussieht.

```sh
[HOST] $ ps aux | grep bash
develop+  1423  0.0  0.0   4144  3328 pts/1    S    21:00   0:00 /bin/bash
```
Der Prozess gehört dem developer Benutzer, nicht root. Erstellen wir eine Datei im Container und prüfen wie diese auf dem Host aussieht.
```sh
[CONTAINER] $ echo "geheim" > /tmp/container-datei.txt
```
Im HOST.
```sh
[HOST] $ ls -la /tmp/container-datei.txt
-rw-r--r-- 1 developer developer 7 Mai 18 21:01 /tmp/container-datei.txt
```
Die Datei gehört dem developer Benutzer, nicht root. Egal was wir innerhalb des Containers als root machen, auf dem Host bleiben wir ein unprivilegierter Benutzer.

Mit exit verlassen wir den Namespace wieder.

In diesem Tutorial verwenden wir `--privileged` für unseren Docker Container, da die anderen Demos wie `mount, cgroups oder veth` echte Kernel-Privilegien auf dem Host benötigen. Der `USER` Namespace alleine reicht dafür nicht aus. Er schützt die BenutzerIDs, ersetzt aber keine echten `root` Rechte für Kernel-Features.


## cgroups - Ressourcenlimits 
[`cgroups`](https://manpages.ubuntu.com/manpages/bionic/man7/cgroups.7.html) sind ein Linux Kernel Feature das Ressourcenlimits für Prozesse und deren Kindprozesse erzwingt. Während Namespaces isolieren was Prozesse sehen, begrenzen `cgroups` was dieser verbrauchen darf.
Da Linux alles in Dateien verwaltet, ist ein `cgroup` einfach ein Verzeichnis `/sys/fs/cgroup/` mit dateien in denen Limits definiert werden.
Mit `ls /sys/fs/cgroup/` könnt ihr die Limits anschauen und mit `mount | grep cgroup` die Version. Wir verwenden `V2` für unser Tutorial.

### Docker Container Konfiguration 
Damit wir das innerhalb unseres dev Containers nutzen können, müssen wir diesen mit dem Flag `--cgroupns=host` starten. Wenn ihr das Tutorial in einer Linux VM macht dann ist dies nicht nötig.  

Durch das Flag leiten wir die `cgroups` des Hostsystems an den `DEV Container` weiter. Sonst können wir die `cgroup` innerhalb des Containers nicht verändern.

```sh
docker run -i --rm --privileged --cgroupns=host --name cdev -t developer-image/ubuntu:cdev
export PS1="\[\e[32m\][HOST]\[\e[0m\] \$ "
```

Wir testen ob es funktioniert hat. Es sollte ein Verzeichnis innerhalb des Docker Hosts ausgegeben werden.
```sh
[HOST] $ cat /proc/self/cgroup
0::/docker/70a2e43871971232b79b2d18f9c39867ad0ef347f3e3e98cf76e141b8d73dcbf
```

Schauen wir uns die aktiven Controller an.
```sh
[HOST] $ cat /sys/fs/cgroup/cgroup.controllers
cpuset cpu io memory hugetlb pids rdma

[HOST] $ cat /sys/fs/cgroup/cgroup.subtree_control
cpuset cpu io memory hugetlb pids rdma
```
Beide Dateien enthalten die selben Controller. `cgroup.controllers` zeigt was verfügbar ist, `cgroup.subtree_control` zeigt was an child-cgroups weitergegeben wird. Da beide identisch sind, sind alle Controller bereits aktiv und wir können direkt loslegen.

Wenn die Ausgabe leer ist, müssen wir die Controller noch aktivieren.
Wir benötigen für diesen Schritt nur `memor, cpu und pids` Dafür müssen wir einfach die Werte in eine Datei schreiben.
```sh
[HOST] $ echo "+memory +cpu +pids" > /sys/fs/cgroup/cgroup.subtree_control
```


### Shell in Leaf-cgroup verschieben
cgroups v2 hat eine wichtige Einschränkung: ein Verzeichnis kann entweder eigene Prozesse oder child-cgroups haben, aber nicht beides gleichzeitig. Das nennt sich "no internal processes" Regel.

Der Root-cgroup hat bereits Prozesse drin. Deshalb müssen wir unsere Shell zuerst in ein eigenes Verzeichnis verschieben bevor wir `mycontainer` anlegen können. Wir wechseln in eine Root-Shell da wir direkt in cgroup-Dateien schreiben.

```sh
sudo -s
mkdir /sys/fs/cgroup/init
echo $$ > /sys/fs/cgroup/init/cgroup.procs
```
Wir prüfen ob unsere Shell jetzt in init liegt.

```sh
[HOST] $ cat /proc/self/cgroup
0::/init
```

### Limits für unseren Container definieren
Für unseren Container müssen wir ein neues Verzeichnis erstellen `mkdir /sys/fs/cgroup/mycontainer`. Lasst euch den Inhalt davon mit `ls` ausgeben. 
```sh
[HOST] $ ls /sys/fs/cgroup/mycontainer
cgroup.controllers  cgroup.kill             cgroup.pressure  cgroup.subtree_control  cpu.pressure    io.pressure
cgroup.events       cgroup.max.depth        cgroup.procs     cgroup.threads          cpu.stat        memory.pressure
cgroup.freeze       cgroup.max.descendants  cgroup.stat      cgroup.type             cpu.stat.local
```
Ihr seht das dieses bereits mehrere Dateien enthällt. Der Kernel erstellt diese automatisch.

Jetzt setzen wir die Limits. Wir begrenzen den Arbeitsspeicher auf 100MB, die CPU auf 50% und die maximale Anzahl an Prozessen auf 20.
```sh
[HOST] $ echo "104857600" > /sys/fs/cgroup/mycontainer/memory.max   # 100 MB
[HOST] $ echo "50000 100000" > /sys/fs/cgroup/mycontainer/cpu.max   # 50% CPU (50ms von 100ms)
[HOST] $ echo "20" > /sys/fs/cgroup/mycontainer/pids.max
```

### Limits testen
Wir verschieben unsere Shell in die neue cgroup und testen die Limits.
```sh
[HOST] $ echo $$ > /sys/fs/cgroup/mycontainer/cgroup.procs
[HOST] $ cat /proc/self/cgroup   # sollte 0::/mycontainer ausgeben
```
Memory-Limit testen - wir allokieren mehr RAM als erlaubt. Der Kernel soll den Prozess mit einem OOM-Kill beenden.
```sh
[HOST] $ python3 -c "x = bytearray(200 * 1024 * 1024)"
Killed
```
Der Prozess wurde beendet weil er das 100MB Limit überschritten hat.

CPU-Limit testen - wir starten einen Prozess der dauerhaft 100% CPU versucht zu nutzen.
```sh
[HOST] # dd if=/dev/zero of=/dev/null &
[1] 49
```
Mit htop überprüfen: der dd Prozess sollte bei ~50% CPU gedeckelt sein obwohl er alles nehmen würde.
Das `cpu.max 50000 100000` bedeutet: 50ms CPU-Zeit pro 100ms Periode - also 50%.

Den Hintergrundprozess beenden `kill %1`.

### Aufräumen
Wir verlassen mycontainer indem wir die Shell zurück in init verschieben und löschen dann das Verzeichnis.
```sh
[HOST] echo $$ > /sys/fs/cgroup/init/cgroup.procs
[HOST] rmdir /sys/fs/cgroup/mycontainer
[HOST] exit   # Root-Shell verlassen
```
Damit haben wir mit reinen Dateizugriffen Ressourcenlimits für einen Prozess gesetzt - genau das macht Docker intern wenn ihr `--memory` oder `--cpus` als Flags übergebt.

## IPC Namespace - Shared Memory Isolation
Der `IPC` Namespace isoliert drei Kernel-Mechanismen: Shared Memory, Message Queues und Semaphoren.
Ohne ihn können Prozesse in verschiedenen Containern denselben Shared Memory Bereich lesen und schreiben - ein direktes Sicherheitsproblem.

Wir starten zwei Terminals und färben diese als `HOST` und `CONTAINER`.

Im `HOST` legen wir ein Shared Memory Segment an und schauen es uns an.
```sh
[HOST] $ ipcmk -M 1024          # legt ein neues Segment an (1024 Bytes)
Shared memory id: 5
[HOST] $ ipcs -m                 # listet alle Shared Memory Segmente
------ Shared Memory Segments --------
key        shmid      owner      perms      bytes      nattch     status      
0x4e5e7b24 5          root       644        1024       0
```

Wir wechseln in den `CONTAINER` Terminal und starten einen Prozess **ohne** IPC-Isolation.
```sh
sudo unshare --pid --fork --mount-proc /bin/bash
export PS1="\[\e[31m\][CONTAINER]\[\e[0m\] \$ "
```

Schauen wir nach ob wir das Segment des Hosts sehen können.
```sh
[CONTAINER] $ ipcs -m
------ Shared Memory Segments --------
key        shmid      owner      perms      bytes      nattch     status      
0x4e5e7b24 5          root       644        1024       0
```
Wir sehen das Segment des Hosts. Das heißt ein Prozess in diesem Container könnte theoretisch darauf zugreifen. Verlassen wir den Namespace mit `exit`.

Jetzt starten wir den Container **mit** IPC-Isolation.
```sh
sudo unshare --ipc --pid --fork --mount-proc /bin/bash
export PS1="\[\e[31m\][CONTAINER]\[\e[0m\] \$ "
```

```sh
[CONTAINER] $ ipcs -m
------ Shared Memory Segments --------
key        shmid      owner      perms      bytes      nattch     status
```
Leer. Der Container hat jetzt seinen eigenen IPC-Namespace und sieht das Segment des Hosts nicht mehr.

Erstellen wir jetzt ein eigenes Segment innerhalb des Containers.
```sh
[CONTAINER] $ ipcmk -M 512
Shared memory id: 0
[CONTAINER] $ ipcs -m
------ Shared Memory Segments --------
key        shmid      owner      perms      bytes      nattch     status      
0x...      0          root       644        512        0
```
Wechseln wir zurück in den `HOST` und prüfen ob das Segment des Containers sichtbar ist.
```sh
[HOST] $ ipcs -m
------ Shared Memory Segments --------
key        shmid      owner      perms      bytes      nattch     status      
0x4e5e7b24 5          root       644        1024       0
```
Nur unser ursprüngliches Segment. Das Segment aus dem Container bleibt vollständig isoliert. Mit `exit` verlassen wir den Namespace wieder, das Segment wird automatisch vom Kernel aufgeräumt.


## Quellen

- https://www.kernel.org
- https://www.kernel.org/doc/Documentation/unshare.txt
- https://www.kernel.org/doc/Documentation/filesystems/proc.txt
- https://github.com/opencontainers/runtime-spec/blob/main/config-linux.md#namespaces
- https://manpages.ubuntu.com/manpages/jammy/de/man1/unshare.1.html
- https://manpages.ubuntu.com/manpages/stonking/man8/ip-route.8.html
- https://manpages.ubuntu.com/manpages/stonking/man1/chroot.1.html
- https://manpages.ubuntu.com/manpages/bionic/man7/cgroups.7.html
- https://github.com/opencontainers

