# DIY Docker Engine Tutorial 

## Einleitung
In diesem Tutorial werden wir unser eigenes Docker aufbauen um zu verstehen was Docker ist und wie es funktioniert.

## Voraussetzungen
- eine Programmiersprache, am besten GO
- einfache Linuxkentnisse
- einfache Netzwerkkentnisse

## 0. Was ist Docker
Docker ist ein Prozess der auf dem Linux Betriebssystem aufsetzt und dessen Funktionalitäten nutzt um Anwendungen voneinander mit Hilfe von Namespaces zu isolieren.

### 0.1 Docker Container
Das Tutorial machen wir innerhalb eines Docker Containers um unseren Host nicht zu beeinträchtigen. Der Container muss im `--privileged` mode laufen, damit wir die kernel Aufrufe ausführen können.
```bash
docker run -it --privileged ubuntu:24.04 /bin/bash
```
#### Terminal färben
Da wir innerhalb mehrerer Terminal instanzen arbeiten werden, werden wir den Prompt String des Terminals umbenennen und färben. Dies geschieht mit folgenden Befehlen, die führen wir beim betreten des entsprechenden Terminals aus.

```bash
# Terminal 1 — immer der "Host"
export PS1="\[\e[32m\][HOST]\[\e[0m\] \$ "

# Terminal 2 — immer der "Container/Namespace"
export PS1="\[\e[31m\][CONTAINER]\[\e[0m\] \$ "
```
#### Platzhalterprozesse
Um die Isolation besser zu verdeutlichen werden wir zusätzliche Prozesse im Host starten.
```bash
sleep 1000 &
sleep 2000 &
sleep 3000 &
cat /dev/zero > /dev/null &
yes > /dev/null &
```

#### Prozesse beenden
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


### 0.1 GO Installation

## 1. Namespaces - Isolation
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

### 1.1 PID eigener Prozessbaum
Alle unsere Prozesse sind aktuell von unserer bash abhängig, das heißt sie hat diese Prozesse gestartet.
Nun erstellen wir unseren ersten Teil der Isolation.
Dafür verwenden wir den `UNSHARE` Befehl.
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
Wir sind im `CONTAINER`. Können wegen einem Fehler keine eigenen Prozesse ausführen. Dies kommt daher das wir den Prozess zwar isoliert haben aber weder ein `fork` noch ein `--mount-proc` gemacht haben. Die PID des neuen `bash` Prozesses ist nicht 1 sondern 721. Das heist das unsere bash noch immer im Namespace des `HOSTS` lauft. Das ist auch der Grund warum wir keine eigenen Prozesse starten können. Fork sorgt dafür das die Anwendung die wir mit `unshare` in einen eigenen Namespace verschieben, dort neu gestartet wird. Da dies nicht geschehen nicht, können wir auch nichts starten. Wir verlassen die `namespace` mit `exit`.

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
Das sieht schon besser aus. Wir sehen das unsere PID jetzt 1 ist, können aber noch weiterhin die Prozesse des hosts sehen. Warum? Wir haben das `/proc` Verzeichniss nicht neu gemountet. Linux arbeitet sehr stark mit Dateien und unsere laufenden Prozesse sind Dateien im `/proc` Verzeichnis auf dem RAM. Lasst uns jetzt das `/proc` Verzeichnis mounten und dadurch das Verzeichnis des `HOST` verdecken. Führen wir den Befehl aus `mount -t proc proc /proc` und zeigen dann die laufenden Prozesse an. Was seht ihr jetzt?

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

### 1.2 NET eigenes Netztwerkinterfrace

#### Einleitung
In diesem Teil werden wir uns mit Netzwerken beschäftigen. Wir werden lernen wie man eine Verbindung zwischen dem Container und Host herstellt über die beide mit einander kommunizieren können. Danach konfigurieren wir unser Netzwerk so das auch das Internet von innerhalb des Containers erreichbar ist. Zuletzt erstellen wir eine Bridge über die Container miteinander, mit dem Host und dem Internet kommunizieren können.

#### Vorbereitung
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

#### Das Netz
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

#### Erstellen eines Interfaces
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

#### Namespace erstellen und Link verschieben
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

#### Verbindung aufbauen und testen
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

#### Mehrere Container über Bridge verbinden
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

Jetzt sollte alles konfiguriert sein. Testet ob die Pings funktionierten von den zwei Containern zu einander und zum Host sowie inst Internet.
Wenn alles funktioniert haben wir ein Bridge Netzwerk gebaut das auch Docker normallerweise für seine Container verwendet.
