FROM ubuntu:22.04
LABEL org.opencontainers.image.source="SRX26 - L4 VPN"
ENV DEBIAN_FRONTEND=noninteractive

RUN apt update
RUN apt install -y net-tools iptables nftables iputils-ping iproute2 wget \
    netcat-openbsd ssh nano traceroute tcpdump lynx nmap tshark vim snort curl \
    openvpn wireguard strongswan strongswan-pki strongswan-swanctl iperf \
    easy-rsa

COPY root/routing.sh /usr/local/bin

WORKDIR /root

# Add routing
CMD ["/usr/local/bin/routing.sh"]