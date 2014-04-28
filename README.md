multihoming-quagga-bgp-mgt
===============================================================================

A simple toolkit we use to manage multihomed services operations, scaling, and so on. 

## Context : 

Multihoming allows redundancy, failover, easy scaling, simplification of network/systems/services operations. 

This is a good point for business critical applications requiring 99,99+% availability. 

Being hosted in N DCs is a cool thing, but remember that you need to anticipate the underlying complexity at some points - first of all, on the data tier.  

## Description : 

- vip_mgmt : a script used to add/remove a set of VIP, based on the DNS name, from the local DC 

- vip_watchdog : a scheduled script used to automatically add/remove VIPs announces from the local DC if the number of realservers hosting the services is too low/sufficiently high. 

## Prerequisites : 

These small tools relies on a quagga/ipvs/keepalived setup : 

### Quagga

- Used to announce BGP routes (of the VIPs) from an AS to the neighbors. 

- Only a subpart of the VIP prefix is announced from one DC with the shortest AS-Path. The others announce the prefix too, but with a longer AS-Path. 

- Global repartition between the sites (aka. anycast) could be done with "Geographic DNS", ISIS (internally) or other methods. 

- When one DC is down/unreachable, route convergence is done by the network. 

### IPVS

- Used to manage L4 load-balancing inside the Linux kernel

- 3 avalaible modes to fit your needs (we use & recommend IPVS-TUN). 

### Keepalived

- Keepalived is the healthchecker component. It performs checks and add/remove realservers from the LOCAL pool of resources using ipvs. 

### Some (best-)practices around DNS naming schemes : 

- service.tld > CNAME vip.tld

- vip.tld > A entry(ies) + AAAA if you're dual-stack (you should !)

```bash
user@lvs:~$ dig +short service.tld ANY
service.tld.   <TTL>   IN      CNAME   vip-1.tld.
vip-1.tld.     <TTL>   IN      AAAA    2001:db8::1
vip-1.tld.     <TTL>   IN      AAAA    2001:db8::2
vip-1.tld. 	   <TTL>   IN      A       192.0.2.1
vip-1.tld. 	   <TTL>   IN      A       192.0.2.2
```

## Run :

### Clone 

```bash
    git clone https://github.com/sfr-network-service-platforms/multihoming-quagga-bgp-mgt.git
    chmod +x vip_mgt vip_watchdog
```

### Configure
 
#### Quagga : 

You should include this in your main configuration file 
```bash
    vtysh_enable=yes
```

A sample configuration block used to set different AS Path (reverse the route-maps for the others DC)

```bash
router bgp <AS_NUMBER>
! (...)
 network 192.0.2.1/32 route-map BGP1
 network 192.0.2.2/32 route-map BGP2
!
 address-family ipv6
  network 2001:db8::1/128 route-map BGP1
  network 2001:db8::2/128 route-map BGP2
! (...)
route-map BGP1 permit <ORDER>
 set as-path prepend <AS_NUMBER>
! (...)
route-map BGP2 permit <ORDER>
 set as-path prepend <AS_NUMBER> <AS_NUMBER>
! (...)
```

#### bgp.inc.sh / vip_mgt / vip_watchdog

Replace the configuration parameters by your own (see variables between CONFIGURATION and END OF CONF)

### Enjoy : 

* vip_mgmt : 

```bash
# Service downtime on the local DC (operations on sensitive hardware/networks/systems/applications ?)
user@lvs:~$ vip_mgmt -d vip-1.tld
bgp_mgt: Deleting route to 192.0.2.1/32
bgp_mgt: Deleting route to 192.0.2.2/32
bgp_mgt: Deleting route to 2001:db8::1/128
bgp_mgt: Deleting route to 2001:db8::2/128

# Let's see if it's really OK for one of the VIPs
user@lvs:~$ watch -n1 "ipvsadm -L -n  --rate --exact -t [2001:db8::1]:80"
Prot LocalAddress:Port                 CPS    InPPS   OutPPS    InBPS   OutBPS
  -> RemoteAddress:Port
TCP  [2001:db8::1]:80                    0        0        0        0        0
  -> [2001:db8:42::1]:80                 0        0        0        0        0
  -> [2001:db8:42::2]:80                 0        0        0        0        0
  -> [2001:db8:42::3]:80                 0        0        0        0        0
(...)

ROUTER1# sh bgp ipv6 uni 2001:db8::1/128 | inc Paths
Paths: (1 available, best #1, table default)

# Good ! we have no more trafic on this DC

# (N minutes/hours/days later...) End of the operations 
user@lvs:~$ vip_mgmt -a vip-1.tld
bgp_mgt: Adding route to 192.0.2.1/32
bgp_mgt: Adding route to 192.0.2.2/32
bgp_mgt: Adding route to 2001:db8::1/128
bgp_mgt: Adding route to 2001:db8::2/128

# Let's see if it's realy OK for one of the VIPs
user@lvs:~$ watch -n1 "ipvsadm -L -n  --rate --exact -t [2001:db8::1]:80"
Prot LocalAddress:Port                 CPS    InPPS   OutPPS    InBPS   OutBPS
  -> RemoteAddress:Port
TCP  [2001:db8::1]:80                 1074     5515        0   711394        0
  -> [2001:db8:42::1]:80               359     1844        0   238544        0
  -> [2001:db8:42::2]:80               358     1836        0   236924        0
  -> [2001:db8:42::3]:80               357     1835        0   235926        0
(...)

ROUTER1# sh bgp ipv6 uni 2001:db8::1/128 | inc Paths
Paths: (2 available, best #2, table default)

# We are back in nominal mode. 
```

* vip_watchdog

```bash
# Install the script as crontab every minute
user@lvs:~$ echo "* * * * *   user    /path/vip_watchdog 2>&1 > /dev/null"

# Control activity of the script
user@lvs:~$ tail -f /var/log/syslog | egrep "bgp|vip"
Apr 25 11:38:00 lvs vip_watchdog: 0 realservers available behind 192.0.2.1 > delete route
Apr 25 11:38:00 lvs bgp_mgt: Deleting route to 192.0.2.1/32
Apr 25 11:38:01 lvs vip_watchdog: 0 realservers available behind 192.0.2.2 > delete route
Apr 25 11:38:01 lvs bgp_mgt: Deleting route to 192.0.2.2/32
Apr 25 11:38:02 lvs vip_watchdog: 0 realservers available behind 2001:db8:42::1 > delete route
Apr 25 11:38:02 lvs bgp_mgt: Deleting route to 2001:db8:42::1/128
Apr 25 11:38:03 lvs vip_watchdog: 0 realservers available behind 2001:db8:42::2 > delete route
Apr 25 11:38:03 lvs bgp_mgt: Deleting route to 2001:db8:42::2/128

Apr 25 11:50:00 lvs vip_watchdog: more than 1 realservers available behind 192.0.2.1 > add route
Apr 25 11:50:00 lvs bgp_mgt: Adding route to 192.0.2.1/32
Apr 25 11:50:01 lvs vip_watchdog: more than 1 realservers available behind 192.0.2.2 > add route
Apr 25 11:50:01 lvs bgp_mgt: Adding route to 192.0.2.2/32
Apr 25 11:50:02 lvs vip_watchdog: more than 1 realservers available behind 2001:db8:42::1 > add route
Apr 25 11:50:02 lvs bgp_mgt: Adding route to 2001:db8:42::1/128
Apr 25 11:50:03 lvs vip_watchdog: more than 1 realservers available behind 2001:db8:42::2 > add route
Apr 25 11:50:03 lvs bgp_mgt: Adding route to 2001:db8:42::2/128
```

## Enhance

- With more tests/error handling/...

- With webservice coupling and application rulesets 
(if you're not afraid of possible consequences of higher exposure)

- With your contribution to Quagga 


