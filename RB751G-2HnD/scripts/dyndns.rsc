# Main variables - you should change it to your login/pass and desired hostname from Dyn
:local DDNSuser "user"
:local DDNSpass "password"
:local DDNShost "my.host.my.domain"

# Note, one of it is a global variable. It is used to avoid repeats of the same HTTP request to Dyn.
:global CurrentIPonDyn
:local CurrentIP

# If our Mikrotik forgot it, let we get it back
:if ( [:typeof $CurrentIPonDyn] = nil ) do={ 
    :set CurrentIPonDyn [:resolve $DDNShost]
}

# WAN/public IP interfaces
:local WANs { 
    "WAN-L2TP-BeeLine";
    "WAN-PPPoE-MGTS"
}

# Loop through WAN interfaces and look for ones containing an IP
:foreach ifname in=$WANs do={
    :local iface [:ip address find interface=$ifname]
    if ( "" != $iface ) do={
        :local IP [:ip address get [:ip address find interface=$ifname] address]
        :for i from=( [:len $IP] - 1) to=0 do={ 
            :if ( [:pick $IP $i] = "/") do={ 
                :set CurrentIP [:pick $IP 0 $i]
            }
        }
    }
}

# Did we get an IP address to compare
:if ([ :typeof $CurrentIP ] = nil ) do={
   :log info ("No WAN ip addresses found.")
} else={
  :if ($CurrentIPonDyn != $CurrentIP) do={
    :log info "DynDNS: Sending UPDATE!"
    :local str "/nic/update?hostname=$DDNShost&myip=$CurrentIPonDyn&wildcard=NOCHG&mx=NOCHG&backmx=NOCHG"
    :tool fetch address=members.dyndns.org src-path=$str mode=http user=$DDNSuser \
        password=$DDNSpass dst-path=("/DynDNS.".$DDNShost)
    :delay 1
    :local str [:file find name="DynDNS.$DDNShost"];
    :file remove $str
    :set CurrentIPonDyn $CurrentIP
  }
}