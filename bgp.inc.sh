#!/bin/bash

#**
#
# Management of BGP peering in the AS (add/delete network routes via quagga/vtysh) 
# @date 2012
# @author pcheynier
#
#**

# --------- CONFIGURATION

# VTYSH Path
VTYSH="/usr/bin/vtysh"
# Quagga Configuration Path
QUAGGA_CONF="/etc/quagga/bgpd.conf"

# Default local AS number
BGP_LOCAL_AS="64699"

# --------- END OF CONF

# Send a message to logger and logged in users
bgp_message () {
        /usr/bin/logger -s -t 'bgp_mgt' "$1"
}

# Set an AS number diferent than the default one
# @param    AS number
#
set_AS () {
    BGP_LOCAL_AS="$1"
}

# Check if a route/an address looks like IPv6 one
# @param    IP route/address
# 
is_v6 () {
    # Match colons, simpler than using IPv6 regex as we do not need validation... 
    if [[ -n `echo $1 | egrep ":"` ]]; then 
        return 0
    else 
        return 1
    fi
}

# Check if a route is announced
# @param    Network route
# 
check_route () {
        # Get the right network type to use in "sh bgp .." command
        if is_v6 $1; then 
            net_type="ipv6"
        else 
            net_type="ipv4"
        fi
        # Return the state of the route
        if [[ -z `$VTYSH -c "sh bgp $net_type unicast $1" | grep "Network not in table"` ]]; then
            return 0
        else 
            return 1
        fi
}

# Add/Restore a route
# @param    Network route
# 
add_route () {
        bgp_message "Adding route to $1"
        # Be sure the route exists in the initial configuration to avoid some big fails if your peer is too permissive (..)
        NETWORK_ROUTEMAP_CMD=`cat $QUAGGA_CONF | grep "$1" | head -1`
        if [[ -n $NETWORK_ROUTEMAP_CMD ]]; then 
            if is_v6 $1; then 
                $VTYSH -c "conf t" -c "router bgp $BGP_LOCAL_AS" -c "address-family ipv6" -c "$NETWORK_ROUTEMAP_CMD"
            else
                $VTYSH -c "conf t" -c "router bgp $BGP_LOCAL_AS" -c "$NETWORK_ROUTEMAP_CMD"
            fi
            sleep 1
        fi
}

# Delete a route
# @param    Network route
# 
remove_route () {
        bgp_message "Deleting route to $1"
        if is_v6 $1; then
            $VTYSH -c "conf t" -c "router bgp $BGP_LOCAL_AS" -c "address-family ipv6" -c "no network $1"
        else 
            $VTYSH -c "conf t" -c "router bgp $BGP_LOCAL_AS" -c "no network $1"
        fi
        sleep 1
}


