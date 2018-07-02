# libreswan_setup
Installs and configures Libreswan across X number of servers.

# Usage

Node1:
```
$ /tmp/setup_ipsec.sh -i defaultroute -addrs 10.1.1.1,10.1.1.2,10.1.1.3
```

Node2-X:
```
$ /tmp/setup_ipsec.sh -i defaultroute \
   -addrs 10.1.1.1,10.1.1.2,10.1.1.3 -p <secret from node1's run>
```
