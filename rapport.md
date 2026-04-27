# Laboratoire n°4 – VPN

# 1 Introduction

`Autheur` : Gabriel Bader, Samuel Dossantos

`Date` : 27 avril 2026

`Note` : Nous nous sommes aidé de l'IA afin de corriger et reformuler le rapport afin de rendre un rapport cohérent, juste et agréable à lire. Nous sommes conscient que cela n'est pas l'idéal mais au vu de la longueur du laboratoire avec les scripts et les manipulations, on a pu gagner du temps. Je précise bien que toute les manipulations et recherches ont été faites par nous, comme le montre toute les copies de nos terminals.

---

## 2 OpenVPN

### Question 1.1 – Route par défaut

**a) Pourquoi vouloir un routage par défaut via le VPN ?**

Faire passer tout le trafic par le VPN garantit que l'ensemble des communications est chiffré, y compris le trafic vers Internet. C'est utile pour un utilisateur distant qui se connecte depuis un réseau non fiable (Wi-Fi public, hôtel, etc.) : tout le trafic sort par le réseau d'entreprise, ce qui permet d'appliquer les politiques de sécurité centrales (filtrage DNS, proxy, etc.).

**b) Faille souvent rencontrée avec le routage par défaut via VPN**

Il s'agit du **VPN split tunneling bypass** ou plus précisément du **DNS leak**. Lorsqu'un client utilise un routage par défaut via VPN, les requêtes DNS peuvent malgré tout être envoyées au serveur DNS local (celui du réseau de l'attaquant) plutôt qu'au DNS du VPN, révélant ainsi les sites visités. Une autre faille classique est la **fuite d'adresse IP locale** (WebRTC leak) qui permet à des sites web de découvrir la vraie adresse IP du client malgré le VPN.

**c) Cas où le routage par défaut n'est pas indiqué**

Le routage par défaut via VPN n'est **pas indiqué en mode site-à-site**. Dans une configuration site-à-site, le but est uniquement d'interconnecter deux réseaux privés. Faire passer tout le trafic Internet des clients du réseau `far` par le VPN vers `main` serait inutile, créerait une charge inutile sur le lien VPN, et dégraderait les performances. Il suffit de router uniquement les préfixes des réseaux distants (`10.0.1.0/24`, `10.0.2.0/24`) via le tunnel.

---

### Question 1.2 – Avantages d'une CA

**Avantage 1 : Gestion centralisée des identités**

Avec une CA, toute machine possédant un certificat signé par cette CA est automatiquement reconnue comme légitime par les autres membres. Pour ajouter une nouvelle machine, il suffit de générer un certificat signé par la CA et de le déployer sur la nouvelle machine. Les autres machines n'ont pas besoin d'être reconfigurées.

**Avantage 2 : Révocation des accès**

Une CA permet de révoquer des certificats via une CRL (Certificate Revocation List). Si une machine est compromise ou qu'un employé quitte l'entreprise, il suffit de révoquer son certificat : il ne pourra plus s'authentifier, sans avoir à modifier la configuration de tous les autres pairs comme ce serait le cas avec des clés pré-partagées.

---

### Question 1.3 – Commandes utilisées pour la CA et les clefs

Toutes les commandes ont été exécutées sur MainS avec `easy-rsa` :

```bash
# Initialisation de la PKI
/usr/share/easy-rsa/easyrsa init-pki
# Crée le répertoire pki/ avec la structure nécessaire

# Création de la CA (sans passphrase pour l'automatisation)
/usr/share/easy-rsa/easyrsa build-ca nopass
# Génère pki/private/ca.key (clé privée CA) et pki/ca.crt (certificat CA auto-signé)
# nopass : pas de mot de passe sur la clé CA (facilite l'automatisation)

# Génération des paramètres Diffie-Hellman (pour la négociation de clé)
/usr/share/easy-rsa/easyrsa gen-dh
# Génère pki/dh.pem, nécessaire côté serveur OpenVPN

# Création du certificat serveur pour MainS
/usr/share/easy-rsa/easyrsa build-server-full main nopass
# Génère pki/issued/main.crt et pki/private/main.key
# build-server-full : génère la clé ET signe le certificat en une seule étape
# nopass : clé privée sans passphrase

# Création des certificats clients
/usr/share/easy-rsa/easyrsa build-client-full far nopass
# Génère pki/issued/far.crt et pki/private/far.key
/usr/share/easy-rsa/easyrsa build-client-full remote nopass
# Génère pki/issued/remote.crt et pki/private/remote.key
```

Les fichiers ont ensuite été copiés dans les répertoires correspondants :
- `ca.crt`, `far.crt`, `far.key` -> `root/far/openvpn/`
- `ca.crt`, `remote.crt`, `remote.key` -> `root/remote/openvpn/`

---

### Question 1.4 – Création de clefs sécurisées

L'erreur courante décrite dans le HOWTO OpenVPN est de **générer les clés et certificats de tous les clients sur le serveur**, puis de les transférer par un canal non sécurisé (copie, mail, etc.). La clé privée d'un client ne devrait jamais quitter la machine sur laquelle elle a été créée.

La bonne pratique est de :
1. Générer la clé privée directement sur la machine cliente
2. Générer une CSR (Certificate Signing Request) sur la machine cliente
3. Envoyer uniquement la CSR au CA (pas la clé privée)
4. Le CA signe le certificat et renvoie uniquement le `.crt`

Dans notre cas, nous avons utilisé `build-client-full` qui génère tout sur MainS pour des raisons pratiques (environnement de test Docker), mais en production c'est à éviter. Quiconque ayant accès à MainS pourrait récupérer les clés privées de `far` et `remote` et usurper leur identité pour se connecter au VPN.

---

### Question 1.5 – Routage avec OpenVPN (site-à-site)

Fichier `root/main/openvpn/server.conf` :

```
server 10.8.0.0 255.255.255.0
```
Définit le pool d'adresses VPN. Les clients reçoivent une adresse dans `10.8.0.0/24`.

```
push "route 10.0.1.0 255.255.255.0"
push "route 10.0.2.0 255.255.255.0"
```
Le serveur **pousse** ces routes vers tous les clients connectés. Ainsi far et remote apprennent automatiquement où se trouvent les réseaux sans configuration manuelle côté client.

```
route 10.0.2.0 255.255.255.0
```
Indique à OpenVPN que le réseau `10.0.2.0/24` est accessible via le tunnel (côté serveur). Sans cette ligne, le serveur ne saurait pas qu'il doit router les paquets vers `10.0.2.0/24` via le tunnel de far.

```
client-config-dir /root/openvpn/ccd
```
Pointe vers le répertoire de configurations par client. Permet d'assigner des paramètres spécifiques à chaque client identifié par son nom de certificat.

Fichier `root/main/openvpn/ccd/far` :
```
iroute 10.0.2.0 255.255.255.0
```
Déclare à OpenVPN qu'**au sein du tunnel**, le réseau `10.0.2.0/24` se trouve derrière le client `far`. C'est la directive interne qui permet au serveur de faire suivre les paquets destinés au réseau far vers la bonne connexion VPN.

---

### Question 1.6 – Configuration remote (remote-to-network)

Fichier `root/remote/openvpn/client.conf` :

```
client
```
Indique qu'il s'agit d'un client OpenVPN (par opposition à un serveur).

```
dev tun
proto udp
remote 10.0.0.2 1194
```
Utilise un tunnel TUN (couche 3), protocole UDP, et se connecte au serveur MainS sur le port 1194.

```
ca   /root/openvpn/ca.crt
cert /root/openvpn/remote.crt
key  /root/openvpn/remote.key
```
Chemin vers les fichiers de la PKI pour l'authentification mutuelle par certificats.

```
resolv-retry infinite
nobind
persist-key
persist-tun
```
- `resolv-retry infinite` : retente la résolution DNS indéfiniment si le serveur est temporairement inaccessible
- `nobind` : n'écoute pas sur un port fixe côté client
- `persist-key/tun` : maintient la clé et l'interface tun en mémoire en cas de reconnexion

Le routage vers `10.0.1.0/24` et `10.0.2.0/24` est assuré par les `push "route"` du serveur, sans avoir besoin d'ajouter des routes manuellement côté client.

---

### Question 1.7 – Résultats du test OpenVPN


```bash
gabriel@gabriel-ThinkPad-P14s-Gen-5:~/hes/srx/srx-lab4$ ./test/runit.sh openvpn
*** Starting docker for openvpn.sh
[+] up 10/10
 ✔ Network net_far  Created                                                                                                                                                         0.1s
 ✔ Network internet Created                                                                                                                                                         0.0s
 ✔ Network net_main Created                                                                                                                                                         0.0s
 ✔ Container MainC1 Healthy                                                                                                                                                         1.0s
 ✔ Container MainS  Healthy                                                                                                                                                         1.0s
 ✔ Container FarC1  Healthy                                                                                                                                                         1.0s
 ✔ Container MainC2 Healthy                                                                                                                                                         1.0s
 ✔ Container FarC2  Healthy                                                                                                                                                         1.0s
 ✔ Container FarS   Healthy                                                                                                                                                         1.0s
 ✔ Container Remote Healthy                                                                                                                                                         1.0s
Ping OK from MainS to 10.0.2.2
Ping OK from MainS to 10.0.2.10
Ping OK from MainS to 10.0.2.11
Ping OK from MainC1 to 10.0.2.2
Ping OK from MainC1 to 10.0.2.10
Ping OK from MainC1 to 10.0.2.11
Ping OK from MainC2 to 10.0.2.2
Ping OK from MainC2 to 10.0.2.10
Ping OK from MainC2 to 10.0.2.11
Ping OK from FarS to 10.0.1.2
Ping OK from FarS to 10.0.1.10
Ping OK from FarS to 10.0.1.11
Ping OK from FarC1 to 10.0.1.2
Ping OK from FarC1 to 10.0.1.10
Ping OK from FarC1 to 10.0.1.11
Ping OK from FarC2 to 10.0.1.2
Ping OK from FarC2 to 10.0.1.10
Ping OK from FarC2 to 10.0.1.11
Ping OK from Remote to 10.0.1.2
Ping OK from Remote to 10.0.1.10
Ping OK from Remote to 10.0.1.11
Ping OK from Remote to 10.0.2.2
Ping OK from Remote to 10.0.2.10
Ping OK from Remote to 10.0.2.11
[+] down 10/10
 ✔ Container FarC1  Removed                                                                                                                                                         1.3s
 ✔ Container FarC2  Removed                                                                                                                                                         1.4s
 ✔ Container MainC1 Removed                                                                                                                                                         1.3s
 ✔ Container MainC2 Removed                                                                                                                                                         1.3s
 ✔ Container Remote Removed                                                                                                                                                         1.4s
 ✔ Container FarS   Removed                                                                                                                                                         1.2s
 ✔ Container MainS  Removed                                                                                                                                                         1.3s
 ✔ Network net_far  Removed                                                                                                                                                         0.2s
 ✔ Network internet Removed                                                                                                                                                         0.4s
 ✔ Network net_main Removed   
```


---

### Question 1.8 – Connexion depuis l'hôte

La configuration `root/host/client.ovpn` permet de se connecter depuis la machine hôte avec OpenVPN Connect Client. Elle utilise les certificats intégrés en inline (voir Q1.9).

La connexion depuis la machine hôte a été établie avec la commande suivante : `sudo openvpn --config root/host/client.ovpn`

OpenVPN se connecte à MainS (10.0.0.2:1194), l'authentification TLS réussit et les routes vers les deux réseaux sont reçues automatiquement :

```
VERIFY OK: depth=0, CN=main
[main] Peer Connection Initiated with [AF_INET]10.0.0.2:1194
net_route_v4_add: 10.0.1.0/24 via 10.8.0.9
net_route_v4_add: 10.0.2.0/24 via 10.8.0.9
Initialization Sequence Completed
```

Et le ping :

```bash
gabriel@gabriel-ThinkPad-P14s-Gen-5:~/hes/srx/srx-lab4$ ping 10.0.1.10
ping 10.0.2.10
PING 10.0.1.10 (10.0.1.10) 56(84) bytes of data.
64 bytes from 10.0.1.10: icmp_seq=1 ttl=63 time=0.510 ms
64 bytes from 10.0.1.10: icmp_seq=2 ttl=63 time=0.731 ms
64 bytes from 10.0.1.10: icmp_seq=3 ttl=63 time=0.244 ms
64 bytes from 10.0.1.10: icmp_seq=4 ttl=63 time=0.250 ms
64 bytes from 10.0.1.10: icmp_seq=5 ttl=63 time=0.572 ms
64 bytes from 10.0.1.10: icmp_seq=6 ttl=63 time=0.527 ms

```

---

### Question 1.9 – Intégration des clefs dans le fichier de configuration

Pour obtenir un seul fichier `.ovpn`, les certificats et clé privée ont été intégrés directement dans le fichier de configuration en utilisant les balises XML d'OpenVPN :

```
<ca>
-----BEGIN CERTIFICATE-----
...contenu du ca.crt...
-----END CERTIFICATE-----
</ca>

<cert>
-----BEGIN CERTIFICATE-----
...contenu du remote.crt...
-----END CERTIFICATE-----
</cert>

<key>
-----BEGIN PRIVATE KEY-----
...contenu du remote.key...
-----END PRIVATE KEY-----
</key>
```

Ainsi, l'utilisateur n'a besoin que d'un seul fichier `client.ovpn` à importer dans OpenVPN Connect, sans fichiers annexes.

---

## 3. WireGuard

### Question 2.1 – Sécuriser la création des clefs

Point 1

Lors de la création d'une clé privée avec `wg genkey`, WireGuard affiche un avertissement si les permissions du fichier de sortie sont trop ouvertes. La clé privée doit être accessible uniquement par son propriétaire (`chmod 600`). Si le fichier est lisible par d'autres utilisateurs, n'importe quel processus sur la même machine pourrait la lire et usurper l'identité du pair.

Point 2

La clé privée doit être générée directement sur la machine qui va l'utiliser et ne jamais quitter cette machine. Pour partager l'identité d'une machine avec ses pairs, on ne partage que la **clé publique** (obtenue via `wg pubkey`). Dans notre configuration, `main_private.key` reste sur main, `far_private.key` sur far, et `remote_private.key` sur remote.

---

### Question 2.2 – Sécurité du fichier wg0.conf

Si le fichier `wg0.conf` est créé sur la machine hôte avec les permissions par défaut (`644`), WireGuard affiche au démarrage :

```
Warning: `/root/wireguard/wg0.conf' is world accessible
```

C'est un problème car `wg0.conf` contient la **clé privée** de l'interface en clair. Avec des permissions `644`, n'importe quel utilisateur du système peut lire ce fichier et donc obtenir la clé privée, ce qui compromet totalement la sécurité du tunnel (un attaquant peut se faire passer pour la machine ou déchiffrer le trafic).

Pour corriger cela, on utilise :
```bash
chmod 600 /root/wireguard/wg0.conf
```

Dans nos scripts `wireguard.sh`, cette commande est exécutée avant le lancement de `wg-quick` :
```bash
chmod 600 /root/wireguard/wg0.conf
wg-quick up /root/wireguard/wg0.conf
```

---

### Question 2.3 – Tableau de routage de MainS

Après établissement des connexions avec FarS et Remote (`ip route` sur MainS) :

```
gabriel@gabriel-ThinkPad-P14s-Gen-5:~/hes/srx/srx-lab4$ docker exec MainS ip route
default via 10.0.0.1 dev eth0 
10.0.0.0/24 dev eth0 proto kernel scope link src 10.0.0.2 
10.0.1.0/24 dev eth1 proto kernel scope link src 10.0.1.2 
10.0.2.0/24 dev wg0 scope link 
10.10.0.0/24 dev wg0 proto kernel scope link src 10.10.0.1 

```
---

### Question 2.4 – Passage des paquets (ping 10.0.2.10 depuis Remote)

Voici les commandes pour analyser le trafic :

```bash
# lance l'infra WireGuard
RUN=wireguard.sh docker-compose up

# tcpdump sur Remote pour voir les interfaces
docker exec Remote tcpdump -i any -n

# ping depuis Remote
docker exec Remote ping 10.0.2.10

# Voir ce qui passe sur MainS
docker exec MainS tcpdump -i any -n

# Voir ce qui passe sur FarS
docker exec FarS tcpdump -i any -n
```

**Chemin aller:**

| Machine | Interface | Chiffré |
|---------|-----------|---------|
| Remote | wg0 Out | Non |
| Remote | eth0 Out | Oui (WireGuard UDP) |
| MainS | eth0 In | Oui (WireGuard UDP) |
| MainS | wg0 In → wg0 Out | Non (déchiffré/rechiffré) |
| MainS | eth0 Out | Oui (WireGuard UDP) |
| FarS | eth0 In | Oui (WireGuard UDP) |
| FarS | wg0 In | Non (déchiffré) |
| FarS | eth1 Out | Non (réseau interne) |

**Chemin retour:**

| Machine | Interface | Chiffré |
|---------|-----------|---------|
| FarS | eth1 In | Non (réseau interne) |
| FarS | wg0 Out | Non (avant chiffrement) |
| FarS | eth0 Out | Oui (WireGuard UDP) |
| MainS | eth0 In | Oui (WireGuard UDP) |
| MainS | wg0 In → wg0 Out | Non (déchiffré/rechiffré) |
| MainS | eth0 Out | Oui (WireGuard UDP) |
| Remote | eth0 In | Oui (WireGuard UDP) |
| Remote | wg0 In | Non (déchiffré) |



---

### Question 2.5 – Résultats du test WireGuard

```bash
gabriel@gabriel-ThinkPad-P14s-Gen-5:~/hes/srx/srx-lab4$ ./test/runit.sh wireguard
*** Starting docker for wireguard.sh
[+] up 10/10
 ✔ Network internet Created                                                                                                                                                                                                                               0.1s
 ✔ Network net_main Created                                                                                                                                                                                                                               0.0s
 ✔ Network net_far  Created                                                                                                                                                                                                                               0.0s
 ✔ Container MainS  Healthy                                                                                                                                                                                                                               1.0s
 ✔ Container MainC2 Healthy                                                                                                                                                                                                                               1.0s
 ✔ Container FarC2  Healthy                                                                                                                                                                                                                               1.0s
 ✔ Container MainC1 Healthy                                                                                                                                                                                                                               1.0s
 ✔ Container FarC1  Healthy                                                                                                                                                                                                                               1.0s
 ✔ Container FarS   Healthy                                                                                                                                                                                                                               0.9s
 ✔ Container Remote Healthy                                                                                                                                                                                                                               0.9s
Ping OK from MainS to 10.0.2.2
Ping OK from MainS to 10.0.2.10
Ping OK from MainS to 10.0.2.11
Ping OK from MainC1 to 10.0.2.2
Ping OK from MainC1 to 10.0.2.10
Ping OK from MainC1 to 10.0.2.11
Ping OK from MainC2 to 10.0.2.2
Ping OK from MainC2 to 10.0.2.10
Ping OK from MainC2 to 10.0.2.11
Ping OK from FarS to 10.0.1.2
Ping OK from FarS to 10.0.1.10
Ping OK from FarS to 10.0.1.11
Ping OK from FarC1 to 10.0.1.2
Ping OK from FarC1 to 10.0.1.10
Ping OK from FarC1 to 10.0.1.11
Ping OK from FarC2 to 10.0.1.2
Ping OK from FarC2 to 10.0.1.10
Ping OK from FarC2 to 10.0.1.11
Ping OK from Remote to 10.0.1.2
Ping OK from Remote to 10.0.1.10
Ping OK from Remote to 10.0.1.11
Ping OK from Remote to 10.0.2.2
Ping OK from Remote to 10.0.2.10
Ping OK from Remote to 10.0.2.11
[+] down 10/10
 ✔ Container Remote Removed                                                                                                                                                                                                                               1.3s
 ✔ Container FarC2  Removed                                                                                                                                                                                                                               1.5s
 ✔ Container MainC1 Removed                                                                                                                                                                                                                               1.4s
 ✔ Container FarC1  Removed                                                                                                                                                                                                                               1.4s
 ✔ Container MainC2 Removed                                                                                                                                                                                                                               1.3s
 ✔ Container FarS   Removed                                                                                                                                                                                                                               1.2s
 ✔ Container MainS  Removed                                                                                                                                                                                                                               1.3s
 ✔ Network net_far  Removed                                                                                                                                                                                                                               0.2s
 ✔ Network net_main Removed                                                                                                                                                                                                                               0.4s
 ✔ Network internet Removed                                                                                                                                                                                                                               0.5s
gabriel@gabriel-ThinkPad-P14s-Gen-5:~/hes/srx/srx-lab4$ 

```
---

### Question 2.6 – Connexion depuis l'hôte (WireGuard Desktop)

La configuration `root/far/wireguard/client.conf` permet à la machine hôte de se connecter :

```bash

# terminal 1
RUN=wireguard.sh docker-compose up

# terminal 2
gabriel@gabriel-ThinkPad-P14s-Gen-5:~/hes/srx/srx-lab4$ sudo wg-quick up root/far/wireguard/client.conf
Warning: `/home/gabriel/hes/srx/srx-lab4/root/far/wireguard/client.conf' is world accessible # Discuté à la Q2.2
[#] ip link add client type wireguard
[#] wg setconf client /dev/fd/63
[#] ip -4 address add 10.10.0.4/24 dev client
[#] ip link set mtu 1420 up dev client
[#] ip -4 route add 10.0.2.0/24 dev client
RTNETLINK answers: File exists
[#] ip link delete dev client
gabriel@gabriel-ThinkPad-P14s-Gen-5:~/hes/srx/srx-lab4$ ping 10.0.1.10
PING 10.0.1.10 (10.0.1.10) 56(84) bytes of data.
64 bytes from 10.0.1.10: icmp_seq=1 ttl=64 time=0.059 ms
64 bytes from 10.0.1.10: icmp_seq=2 ttl=64 time=0.074 ms
64 bytes from 10.0.1.10: icmp_seq=3 ttl=64 time=0.042 ms
^C
--- 10.0.1.10 ping statistics ---
3 packets transmitted, 3 received, 0% packet loss, time 2070ms
rtt min/avg/max/mdev = 0.042/0.058/0.074/0.013 ms
gabriel@gabriel-ThinkPad-P14s-Gen-5:~/hes/srx/srx-lab4$ ping 10.0.1.11
PING 10.0.1.11 (10.0.1.11) 56(84) bytes of data.
64 bytes from 10.0.1.11: icmp_seq=1 ttl=64 time=0.242 ms
64 bytes from 10.0.1.11: icmp_seq=2 ttl=64 time=0.047 ms
64 bytes from 10.0.1.11: icmp_seq=3 ttl=64 time=0.048 ms
^C
--- 10.0.1.11 ping statistics ---
3 packets transmitted, 3 received, 0% packet loss, time 2057ms
rtt min/avg/max/mdev = 0.047/0.112/0.242/0.091 ms
gabriel@gabriel-ThinkPad-P14s-Gen-5:~/hes/srx/srx-lab4$ ping 10.0.2.10
PING 10.0.2.10 (10.0.2.10) 56(84) bytes of data.
64 bytes from 10.0.2.10: icmp_seq=1 ttl=64 time=0.058 ms
64 bytes from 10.0.2.10: icmp_seq=2 ttl=64 time=0.051 ms
^C
--- 10.0.2.10 ping statistics ---
2 packets transmitted, 2 received, 0% packet loss, time 1003ms
rtt min/avg/max/mdev = 0.051/0.054/0.058/0.003 ms
gabriel@gabriel-ThinkPad-P14s-Gen-5:~/hes/srx/srx-lab4$ ping 10.0.2.11
PING 10.0.2.11 (10.0.2.11) 56(84) bytes of data.
64 bytes from 10.0.2.11: icmp_seq=1 ttl=64 time=0.058 ms
64 bytes from 10.0.2.11: icmp_seq=2 ttl=64 time=0.058 ms
64 bytes from 10.0.2.11: icmp_seq=3 ttl=64 time=0.057 ms
^C
--- 10.0.2.11 ping statistics ---
3 packets transmitted, 3 received, 0% packet loss, time 2055ms
rtt min/avg/max/mdev = 0.057/0.057/0.058/0.000 ms
gabriel@gabriel-ThinkPad-P14s-Gen-5:~/hes/srx/srx-lab4$ 





```
---

## 4. IPSec (StrongSwan)

### Question 3.1 – Commandes pour la création des clefs

Les commandes suivantes ont été exécutées dans le conteneur MainS :

```bash
# 1. Génération de la clé privée de la CA (4096 bits pour plus de sécurité)
pki --gen --type rsa --size 4096 --outform pem > /root/ipsec/ca_key.pem

# 2. Création du certificat CA auto-signé (validité 10 ans)
pki --self --ca --lifetime 3650 \
    --in /root/ipsec/ca_key.pem \
    --dn "CN=SRX-lab4 CA, O=HEIG, C=CH" \
    --outform pem > /root/ipsec/ca_cert.pem

# 3. Clé privée de MainS (2048 bits)
pki --gen --type rsa --size 2048 --outform pem > /root/ipsec/main_key.pem

# 4. Certificat de MainS signé par la CA, avec SAN obligatoires
pki --pub --in /root/ipsec/main_key.pem --type rsa \
  | pki --issue --lifetime 1825 \
        --cacert /root/ipsec/ca_cert.pem \
        --cakey  /root/ipsec/ca_key.pem \
        --dn "CN=main.heig.ch, O=HEIG, C=CH" \
        --san main --san 10.0.0.2 \
        --flag serverAuth \
        --outform pem > /root/ipsec/main_cert.pem

# 5. Clé privée et certificat de FarS
pki --gen --type rsa --size 2048 --outform pem > /root/ipsec/far_key.pem
pki --pub --in /root/ipsec/far_key.pem --type rsa \
  | pki --issue --lifetime 1825 \
        --cacert /root/ipsec/ca_cert.pem \
        --cakey  /root/ipsec/ca_key.pem \
        --dn "CN=far.heig.ch, O=HEIG, C=CH" \
        --san far --san 10.0.0.3 \
        --flag serverAuth \
        --outform pem > /root/ipsec/far_cert.pem

# 6. Clé privée et certificat de Remote
pki --gen --type rsa --size 2048 --outform pem > /root/ipsec/remote_key.pem
pki --pub --in /root/ipsec/remote_key.pem --type rsa \
  | pki --issue --lifetime 1825 \
        --cacert /root/ipsec/ca_cert.pem \
        --cakey  /root/ipsec/ca_key.pem \
        --dn "CN=remote.heig.ch, O=HEIG, C=CH" \
        --san remote --san 10.0.0.4 \
        --flag clientAuth \
        --outform pem > /root/ipsec/remote_cert.pem
```
---

### Question 3.2 – Création de clefs hôtes sécurisées

La documentation StrongSwan décrit une méthode où le **CA holder** ne voit jamais la clé privée des hôtes. Voici le déroulement chronologique :

1. **CA holder** génère sa clé CA et son certificat auto-signé. Il garde `ca_key.pem` en lieu sûr.

2. **Host** (ex: FarS) génère sa propre clé privée localement :
   ```bash
   pki --gen --type rsa --size 2048 --outform pem > far_key.pem
   ```

3. **Host** extrait sa clé publique et génère une requête de certification (CSR) :
   ```bash
   pki --pub --in far_key.pem --type rsa --outform pem > far_pub.pem
   ```
   Le host envoie **uniquement** `far_pub.pem` au CA holder. La clé privée `far_key.pem` ne quitte jamais le host.

4. **CA holder** reçoit `far_pub.pem` et signe le certificat :
   ```bash
   pki --issue --cacert ca_cert.pem --cakey ca_key.pem \
       --in far_pub.pem --type pub \
       --dn "CN=far.heig.ch, O=HEIG, C=CH" \
       --san far --san 10.0.0.3 \
       --outform pem > far_cert.pem
   ```
   Il renvoie `far_cert.pem` au host.

5. **Host** possède maintenant `far_key.pem` (privé, jamais partagé) + `far_cert.pem` (public, reçu du CA). Le CA holder n'a jamais vu `far_key.pem`.


---

### Question 3.3 – Fichiers copiés pour MainS et FarS

**Pour MainS** (`root/main/ipsec.sh`) :

| Fichier source | Destination | Utilité |
|----------------|-------------|---------|
| `ca_cert.pem` | `/etc/swanctl/x509ca/` | Certificat de la CA — permet à StrongSwan de vérifier les certificats présentés par les autres machines |
| `main_cert.pem` | `/etc/swanctl/x509/` | Certificat public de MainS — présenté lors de la négociation IKE pour prouver son identité |
| `main_key.pem` | `/etc/swanctl/private/` | Clé privée de MainS — utilisée pour signer les échanges IKE et prouver la possession du certificat |
| `swanctl.conf` | `/etc/swanctl/swanctl.conf` | Configuration des connexions IPSec (politiques, sélecteurs de trafic, authentification) |

**Pour FarS** (`root/far/ipsec.sh`) :

| Fichier source | Destination | Utilité |
|----------------|-------------|---------|
| `ca_cert.pem` | `/etc/swanctl/x509ca/` | Même rôle que pour MainS — vérification des certificats des pairs |
| `far_cert.pem` | `/etc/swanctl/x509/` | Certificat public de FarS |
| `far_key.pem` | `/etc/swanctl/private/` | Clé privée de FarS |
| `swanctl.conf` | `/etc/swanctl/swanctl.conf` | Configuration de la connexion `far-main` |

---

### Question 3.4 – Fichiers pour Remote et ajouts sur MainS

**Pour Remote** (`root/remote/ipsec.sh`) :

| Fichier source | Destination | Utilité |
|----------------|-------------|---------|
| `ca_cert.pem` | `/etc/swanctl/x509ca/` | Vérification du certificat de MainS |
| `remote_cert.pem` | `/etc/swanctl/x509/` | Certificat public de Remote |
| `remote_key.pem` | `/etc/swanctl/private/` | Clé privée de Remote |
| `swanctl.conf` | `/etc/swanctl/swanctl.conf` | Configuration de la connexion `remote-main` avec `start_action = start` |

**Ajouts sur MainS :** La connexion `main-remote` a été ajoutée dans `root/main/ipsec/swanctl.conf`, avec le fichier `remote_cert.pem` déjà présent dans `root/main/ipsec/` pour que MainS puisse vérifier l'identité de Remote.

---

### Question 3.5 – Résultats du test IPSec

``` bash
gabriel@gabriel-ThinkPad-P14s-Gen-5:~/hes/srx/srx-lab4$ ./test/runit.sh ipsec
*** Starting docker for ipsec.sh
[+] up 10/10
 ✔ Network net_main Created                                                                                                                                                                                                                               0.1s
 ✔ Network internet Created                                                                                                                                                                                                                               0.0s
 ✔ Network net_far  Created                                                                                                                                                                                                                               0.0s
 ✔ Container FarC1  Healthy                                                                                                                                                                                                                               0.9s
 ✔ Container FarC2  Healthy                                                                                                                                                                                                                               0.9s
 ✔ Container MainC1 Healthy                                                                                                                                                                                                                               0.9s
 ✔ Container MainC2 Healthy                                                                                                                                                                                                                               0.9s
 ✔ Container MainS  Healthy                                                                                                                                                                                                                               0.9s
 ✔ Container FarS   Healthy                                                                                                                                                                                                                               0.9s
 ✔ Container Remote Healthy                                                                                                                                                                                                                               0.9s
Ping OK from MainS to 10.0.2.2
Ping OK from MainS to 10.0.2.10
Ping OK from MainS to 10.0.2.11
Ping OK from MainC1 to 10.0.2.2
Ping OK from MainC1 to 10.0.2.10
Ping OK from MainC1 to 10.0.2.11
Ping OK from MainC2 to 10.0.2.2
Ping OK from MainC2 to 10.0.2.10
Ping OK from MainC2 to 10.0.2.11
Ping OK from FarS to 10.0.1.2
Ping OK from FarS to 10.0.1.10
Ping OK from FarS to 10.0.1.11
Ping OK from FarC1 to 10.0.1.2
Ping OK from FarC1 to 10.0.1.10
Ping OK from FarC1 to 10.0.1.11
Ping OK from FarC2 to 10.0.1.2
Ping OK from FarC2 to 10.0.1.10
Ping OK from FarC2 to 10.0.1.11
Ping OK from Remote to 10.0.1.2
Ping OK from Remote to 10.0.1.10
Ping OK from Remote to 10.0.1.11
Ping OK from Remote to 10.0.2.2
Ping OK from Remote to 10.0.2.10
Ping OK from Remote to 10.0.2.11
[+] down 10/10
 ✔ Container Remote Removed                                                                                                                                                                                                                               1.3s
 ✔ Container MainC1 Removed                                                                                                                                                                                                                               1.3s
 ✔ Container MainC2 Removed                                                                                                                                                                                                                               1.3s
 ✔ Container FarC2  Removed                                                                                                                                                                                                                               1.3s
 ✔ Container FarC1  Removed                                                                                                                                                                                                                               1.4s
 ✔ Container FarS   Removed                                                                                                                                                                                                                               1.2s
 ✔ Container MainS  Removed                                                                                                                                                                                                                               1.3s
 ✔ Network internet Removed                                                                                                                                                                                                                               0.2s
 ✔ Network net_main Removed                                                                                                                                                                                                                               0.3s
 ✔ Network net_far  Removed         
```
---

## 5. Comparaison

### Question 4.1 – Sécurité de la communication

**OpenVPN**

OpenVPN utilise TLS pour sécuriser le canal de contrôle et négocie une clé de session pour le canal de données. La sécurité maximale disponible inclut AES-256-GCM pour le chiffrement des données, SHA-256 pour l'intégrité, et ECDHE pour l'échange de clés (Perfect Forward Secrecy).

Dans notre configuration, aucun cipher n'est explicitement spécifié dans `server.conf`. OpenVPN 2.5+ utilise par défaut **AES-256-GCM** avec négociation automatique (`--cipher` et `--data-ciphers`). Le canal de contrôle est sécurisé par TLS 1.2/1.3.

**WireGuard**

WireGuard utilise une cryptographie moderne et fixe, sans négociation d'algorithmes :
- **ChaCha20-Poly1305** pour le chiffrement authentifié des données
- **Curve25519** pour l'échange de clés Diffie-Hellman
- **BLAKE2s** pour le hachage
- **SipHash24** pour les tables de hachage

Ces algorithmes sont fixés dans le code (pas de "crypto-agility") ce qui élimine les attaques de downgrade. La PFS est assurée par une rotation des clés de session.

**IPSec (StrongSwan)**

IPSec supporte de nombreux algorithmes. Dans notre configuration sans proposal explicite, StrongSwan utilise ses valeurs par défaut qui incluent **AES-256-GCM** ou **AES-CBC** avec **SHA-256/384** pour ESP, et **IKEv2** avec **ECDHE** ou **DH group 14+** pour la négociation. La PFS est supportée.

---

### Question 4.2 – Sécurité de l'authentification

**OpenVPN**

Authentification par certificats X.509 signés par easy-rsa. L'algorithme de signature est **SHA-256 avec RSA 2048 bits** (sha256WithRSAEncryption) pour les certificats hôtes, et la CA est en RSA 2048 bits également. SHA-256 est actuellement considéré comme sûr (pas de collision connue), et RSA 2048 bits est au minimum acceptable mais RSA 4096 serait préférable pour une longue durée de vie.

**WireGuard**

Authentification par clés statiques **Curve25519** (clés de 256 bits). Curve25519 est considéré comme très sûr et résistant aux attaques connues. Il n'y a pas de certificats, donc pas de PKI à gérer, mais aussi pas de mécanisme de révocation natif.

**IPSec**

Authentification par certificats X.509 signés par StrongSwan `pki`. L'algorithme de signature est **SHA-384 avec RSA 2048 bits** (sha384WithRSAEncryption) pour les certificats hôtes, et la CA est en RSA 4096 bits. SHA-384 est très sûr. La CA en 4096 bits est un bon choix pour une durée de vie longue (10 ans). Les certificats hôtes en 2048 bits sont acceptables mais RSA 3072 ou 4096 serait préférable pour de nouveaux déploiements.

---

### Question 4.3 – Facilité de configuration (ordre croissant de complexité)

1. **WireGuard** (le plus simple) — Configuration minimaliste en quelques lignes dans `wg0.conf`. Pas de daemon complexe, pas de PKI, pas de négociation. La génération de clés est triviale (`wg genkey | wg pubkey`). L'interface se monte avec `wg-quick up`.

2. **OpenVPN** — Nécessite la mise en place d'une PKI complète (easy-rsa), la gestion des certificats, et une configuration serveur/client avec plusieurs paramètres. Reste bien documenté et relativement accessible grâce à easy-rsa.

3. **IPSec/StrongSwan** (le plus complexe) — Nécessite une PKI, une compréhension des concepts IKEv2, la configuration des sélecteurs de trafic (`local_ts`, `remote_ts`), le démarrage manuel du daemon `charon`, et la copie des fichiers dans des emplacements spécifiques. La documentation est plus technique et les erreurs de configuration sont moins explicites.

---

### Question 4.4 – Performance (iperf, ordre décroissant)


**iperf résultat:**

```bash
# OPENVPN
gabriel@gabriel-ThinkPad-P14s-Gen-5:~/hes/srx/srx-lab4$ docker exec MainS iperf -c 10.0.2.2 -t 5
------------------------------------------------------------
Client connecting to 10.0.2.2, TCP port 5001
TCP window size: 45.0 KByte (default)
------------------------------------------------------------
[  1] local 10.8.0.1 port 38892 connected with 10.0.2.2 port 5001
[ ID] Interval       Transfer     Bandwidth
[  1] 0.0000-5.0114 sec  1.17 GBytes  2.01 Gbits/sec
gabriel@gabriel-ThinkPad-P14s-Gen-5:~/hes/srx/srx-lab4$ docker exec MainC1 iperf -c 10.0.2.10 -t 5
------------------------------------------------------------
Client connecting to 10.0.2.10, TCP port 5001
TCP window size: 45.0 KByte (default)
------------------------------------------------------------
[  1] local 10.0.1.10 port 34138 connected with 10.0.2.10 port 5001
[ ID] Interval       Transfer     Bandwidth
[  1] 0.0000-5.0076 sec   758 MBytes  1.27 Gbits/sec
gabriel@gabriel-ThinkPad-P14s-Gen-5:~/hes/srx/srx-lab4$ docker exec Remote iperf -c 10.0.2.11 -t 5
------------------------------------------------------------
Client connecting to 10.0.2.11, TCP port 5001
TCP window size: 45.0 KByte (default)
------------------------------------------------------------
[  1] local 10.8.0.10 port 49528 connected with 10.0.2.11 port 5001
[ ID] Interval       Transfer     Bandwidth
[  1] 0.0000-5.0227 sec   680 MBytes  1.14 Gbits/sec
gabriel@gabriel-ThinkPad-P14s-Gen-5:~/hes/srx/srx-lab4$ 

#WIREGUARD
gabriel@gabriel-ThinkPad-P14s-Gen-5:~/hes/srx/srx-lab4$ docker exec MainS iperf -c 10.0.2.2 -t 5
------------------------------------------------------------
Client connecting to 10.0.2.2, TCP port 5001
TCP window size: 45.0 KByte (default)
------------------------------------------------------------
[  1] local 10.10.0.1 port 38886 connected with 10.0.2.2 port 5001
[ ID] Interval       Transfer     Bandwidth
[  1] 0.0000-5.0184 sec  1.46 GBytes  2.50 Gbits/sec
gabriel@gabriel-ThinkPad-P14s-Gen-5:~/hes/srx/srx-lab4$ docker exec MainC1 iperf -c 10.0.2.10 -t 5
------------------------------------------------------------
Client connecting to 10.0.2.10, TCP port 5001
TCP window size: 85.0 KByte (default)
------------------------------------------------------------
[  1] local 10.0.1.10 port 46706 connected with 10.0.2.10 port 5001
[ ID] Interval       Transfer     Bandwidth
[  1] 0.0000-5.0363 sec  1.10 GBytes  1.87 Gbits/sec
gabriel@gabriel-ThinkPad-P14s-Gen-5:~/hes/srx/srx-lab4$ docker exec Remote iperf -c 10.0.2.11 -t 5
------------------------------------------------------------
Client connecting to 10.0.2.11, TCP port 5001
TCP window size: 85.0 KByte (default)
------------------------------------------------------------
[  1] local 10.10.0.3 port 46760 connected with 10.0.2.11 port 5001
[ ID] Interval       Transfer     Bandwidth
[  1] 0.0000-5.0330 sec   942 MBytes  1.57 Gbits/sec


#IPSEC
gabriel@gabriel-ThinkPad-P14s-Gen-5:~/hes/srx/srx-lab4$ docker exec MainS iperf -c 10.0.2.2 -t 5
------------------------------------------------------------
Client connecting to 10.0.2.2, TCP port 5001
TCP window size: 85.0 KByte (default)
------------------------------------------------------------
[  1] local 10.0.1.2 port 52570 connected with 10.0.2.2 port 5001
[ ID] Interval       Transfer     Bandwidth
[  1] 0.0000-5.0112 sec  1.36 GBytes  2.34 Gbits/sec
gabriel@gabriel-ThinkPad-P14s-Gen-5:~/hes/srx/srx-lab4$ docker exec MainC1 iperf -c 10.0.2.10 -t 5
------------------------------------------------------------
Client connecting to 10.0.2.10, TCP port 5001
TCP window size: 85.0 KByte (default)
------------------------------------------------------------
[  1] local 10.0.1.10 port 50430 connected with 10.0.2.10 port 5001
[ ID] Interval       Transfer     Bandwidth
[  1] 0.0000-5.0122 sec  1.80 GBytes  3.08 Gbits/sec
gabriel@gabriel-ThinkPad-P14s-Gen-5:~/hes/srx/srx-lab4$ docker exec Remote iperf -c 10.0.2.11 -t 5
------------------------------------------------------------
Client connecting to 10.0.2.11, TCP port 5001
TCP window size: 85.0 KByte (default)
------------------------------------------------------------
[  1] local 10.0.0.4 port 57274 connected with 10.0.2.11 port 5001
[ ID] Interval       Transfer     Bandwidth
[  1] 0.0000-5.0045 sec   732 MBytes  1.23 Gbits/sec


```
**Résumé**

| Protocole | MainS <-> FarS | MainC1 <-> FarC1 | Remote <-> FarC2 |
|-----------|----------------|----------------|------------------|
| WireGuard | 2.50 Gbits/s   | 1.87 Gbits/s | 1.57 Gbits/s     |
| IPSec     | 2.34 Gbits/s   | 3.08 Gbits/s | 1.23 Gbits/s     |
| OpenVPN   | 2.01 Gbits/s   | 1.27 Gbits/s | 1.14 Gbits/s     |

Les résultats montrent que les trois protocoles atteignent des débits similaires (entre 1 et 3 Gbits/s), ce qui s'explique par le fait que tous les conteneurs tournent sur la même machine physique et partagent le même réseau virtuel Docker


On constate tout de même que OpenVPN est le plus lent. Contrairement aux deux autres, il tourne en userspace, ce qui signifie que chaque paquet doit faire un aller-retour supplémentaire entre le kernel et l'espace utilisateur avant d'être envoyé.

Donc WireGuard est le plus rapide en moyenne, sa conception minimaliste et son implémentation dans le kernel Linux lui donnent un avantage.


À noter que ces tests sont fait sur un environnement virtuel, et donc à prendre avec du recul. 


